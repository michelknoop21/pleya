import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/trackers/device_code.dart';
import '../services/trackers/tracker_account_store.dart';
import '../services/trackers/tracker_connect_runner.dart';
import '../services/trackers/tracker_constants.dart';
import '../services/trackers/tracker_session.dart';
import '../services/trakt/trakt_auth_service.dart';
import '../services/trakt/trakt_client.dart';
import '../services/trakt/trakt_scrobble_service.dart';
import '../services/trakt/trakt_sync_service.dart';
import '../utils/app_logger.dart';

/// Owns the active Trakt session for the currently-selected Plex profile.
///
/// Single rebind seam: `onActiveProfileChanged` loads the new profile's
/// session and pushes it to both `TraktScrobbleService` and `TraktSyncService`.
class TraktAccountProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  /// [kidsProfileCheck] answers "is the active profile a children's profile".
  /// It is required so a provider can never be built without the shield.
  TraktAccountProvider({required Future<bool> Function() kidsProfileCheck}) : _kidsCheck = kidsProfileCheck;

  /// The provider whose binding the Trakt services currently carry, so a
  /// disposed provider only unbinds what is still its own.
  static TraktAccountProvider? _boundOwner;

  final TraktAuthService _auth = TraktAuthService();
  final TrackerAccountStore _store = trackerAccountStore(TrackerService.trakt);

  Future<bool> Function() _kidsCheck;
  int _rebindRun = 0;
  bool _isKidsProfile = false;

  TrackerSession? _session;
  String _activeUserUuid = '';
  int _bindingGeneration = 0;
  bool _isConnecting = false;
  Completer<void>? _cancelCompleter;

  TrackerSession? get session => _session;
  bool get isConnected => _session != null;
  String? get username => _session?.username;
  bool get isConnecting => _isConnecting;

  /// The profile the current binding belongs to; a read that outlives a
  /// profile switch compares it with the one it started for.
  String get activeUserUuid => _activeUserUuid;

  /// Whether the active profile is a children's profile: no Trakt login, no
  /// scrobble and no sync. A stored session is neither loaded nor removed.
  bool get isKidsProfile => _isKidsProfile;

  @visibleForTesting
  void debugSetKidsProfileCheckForTesting(Future<bool> Function() check) => _kidsCheck = check;

  /// Fails closed: a check that throws counts as a children's profile.
  Future<bool> _readKidsProfile() async {
    try {
      return await _kidsCheck();
    } catch (e) {
      appLogger.w('Trakt: kids profile check failed, treating as kids profile', error: e);
      return true;
    }
  }

  /// The shield as it stands now, for what talks to Trakt without a session:
  /// [isKidsProfile] only changes on a rebind, and fails open until the first.
  Future<bool> checkKidsProfile() => _readKidsProfile();

  /// Re-reads the children's profile switch for the active profile, from the
  /// settings screen that changes it.
  /// Does not invalidate the binding generation: a refreshed token pair that
  /// is still on its way for this user must be written, never dropped.
  Future<void> reevaluateKidsGate() => _rebind(_activeUserUuid, bumpGeneration: false);

  /// Cancel an in-flight `connect()` (e.g. user dismissed the device-code
  /// dialog). Completing the completer both wakes the blocking `Future.any`
  /// race and flips `isCompleted` for the next sync check.
  void cancelConnect() {
    final c = _cancelCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Called whenever the active Plex profile changes (or on initial load).
  Future<void> onActiveProfileChanged(String? newUserUuid) => _rebind(newUserUuid ?? '', bumpGeneration: true);

  Future<void> _rebind(String userUuid, {required bool bumpGeneration}) async {
    if (isDisposed) return;
    if (bumpGeneration) _bindingGeneration++;
    // A disconnect, an invalidation or a finished connect bumps the generation
    // and cancels the bind this run would do after its awaits.
    final generation = _bindingGeneration;
    final run = ++_rebindRun;
    _activeUserUuid = userUuid;
    // Nothing of the previous profile may keep scrobbling while the next one
    // is being read: unbind before the first await.
    _unbindServices(userUuid);
    final kids = await _readKidsProfile();
    if (isDisposed || run != _rebindRun) return;
    _isKidsProfile = kids;
    if (kids) {
      // The shield wins over any bind that happened while the check ran.
      _setSessionAndRebind(userUuid, _bindingGeneration, null);
      return;
    }
    final loaded = await _store.load(userUuid);
    if (isDisposed || run != _rebindRun || _isKidsProfile || generation != _bindingGeneration) return;
    // A refreshed pair can be newer than what the store returned a moment ago.
    final current = _session;
    final latest = current != null && loaded != null && (current.expiresAt ?? 0) > (loaded.expiresAt ?? 0)
        ? current
        : loaded;
    _setSessionAndRebind(userUuid, generation, latest);
  }

  /// Run the device-code OAuth flow.
  ///
  /// [onCodeReady] is invoked once with the user code + verification URL so
  /// the UI can render the dialog.
  Future<bool> connect({required void Function(DeviceCode code) onCodeReady}) async {
    if (_isConnecting || isConnected || _isKidsProfile) return false;
    if (await _readKidsProfile()) {
      _isKidsProfile = true;
      safeNotifyListeners();
      return false;
    }
    _isConnecting = true;
    _cancelCompleter = Completer<void>();
    notifyListeners();
    try {
      return await runConnectPipeline<TrackerSession>(
        logLabel: 'Trakt',
        authorize: () => _auth.authorize(
          onCodeReady: onCodeReady,
          shouldCancel: () => _cancelCompleter?.isCompleted ?? false,
          onCancel: _cancelCompleter!.future,
        ),
        enrich: _enrichUsername,
        save: (s) async {
          // The switch can change during the device-code window.
          if (await _readKidsProfile()) throw StateError('Trakt login refused: kids profile');
          await _store.save(_activeUserUuid, s);
        },
        assign: _bindCurrentSession,
      );
    } finally {
      final c = _cancelCompleter;
      if (c != null && !c.isCompleted) c.complete();
      _cancelCompleter = null;
      _isConnecting = false;
      safeNotifyListeners();
    }
  }

  Future<TrackerSession> _enrichUsername(TrackerSession raw) async {
    TraktClient? tmp;
    try {
      tmp = TraktClient(raw, onSessionInvalidated: () {});
      final user = await tmp.getUserSettings();
      return raw.copyWith(username: user.username);
    } catch (e) {
      appLogger.d('Trakt: getUserSettings failed (non-fatal)', error: e);
      return raw;
    } finally {
      tmp?.dispose();
    }
  }

  /// Revoke the access token and clear local state.
  Future<void> disconnect() async {
    final userUuid = _activeUserUuid;
    final generation = ++_bindingGeneration;
    final session = _session;
    _setSessionAndRebind(userUuid, generation, null);
    if (session != null) {
      final client = TraktClient(session, onSessionInvalidated: () {});
      try {
        await client.revoke();
      } finally {
        client.dispose();
      }
    }
    await _store.clear(userUuid);
  }

  void _bindCurrentSession(TrackerSession? session) {
    // The switch may have gone on while the device-code flow was saving.
    if (session != null && _isKidsProfile) throw StateError('Trakt login refused: kids profile');
    _setSessionAndRebind(_activeUserUuid, ++_bindingGeneration, session);
  }

  void _unbindServices(String userUuid) {
    _boundOwner = this;
    TraktScrobbleService.instance.rebindToProfile(null, onSessionInvalidated: () {});
    TraktSyncService.instance.rebindToProfile(userUuid, null, onSessionInvalidated: () {});
  }

  void _setSessionAndRebind(String userUuid, int generation, TrackerSession? session) {
    if (!_isCurrentBinding(userUuid, generation)) return;
    _boundOwner = this;
    _session = session;

    void handleInvalidated() => _handleSessionInvalidated(userUuid, generation);
    void handleUpdated(TrackerSession next) => unawaited(_handleSessionUpdated(userUuid, generation, next));

    TraktScrobbleService.instance.rebindToProfile(
      session,
      onSessionInvalidated: handleInvalidated,
      onSessionUpdated: handleUpdated,
    );
    TraktSyncService.instance.rebindToProfile(
      userUuid,
      session,
      onSessionInvalidated: handleInvalidated,
      onSessionUpdated: handleUpdated,
    );
    safeNotifyListeners();
  }

  bool _isCurrentBinding(String userUuid, int generation) {
    return !isDisposed && userUuid == _activeUserUuid && generation == _bindingGeneration;
  }

  /// Trakt rotates the refresh token, so the old one is dead the moment the
  /// new pair is issued: the pair is written before anything else uses it.
  Future<void> _handleSessionUpdated(String userUuid, int generation, TrackerSession session) async {
    if (!_isCurrentBinding(userUuid, generation)) return;
    if (!_isKidsProfile) _session = session;
    try {
      await _store.save(userUuid, session);
    } catch (e) {
      appLogger.w('Trakt: saving the refreshed session failed', error: e);
    }
    if (!_isCurrentBinding(userUuid, generation)) return;
    TraktScrobbleService.instance.updateSession(session);
    TraktSyncService.instance.updateSession(session);
    safeNotifyListeners();
  }

  /// Called by [TraktClient] when refresh fails permanently. Clears local state
  /// so the UI shows "not connected" and the user can re-link.
  void _handleSessionInvalidated(String userUuid, int generation) {
    if (!_isCurrentBinding(userUuid, generation)) return;
    final nextGeneration = ++_bindingGeneration;
    unawaited(_store.clear(userUuid));
    _setSessionAndRebind(userUuid, nextGeneration, null);
  }

  @visibleForTesting
  void debugBumpGenerationForTesting() => _bindingGeneration++;

  @visibleForTesting
  int get debugBindingGenerationForTesting => _bindingGeneration;

  @visibleForTesting
  Future<void> debugHandleSessionUpdatedForTesting(String userUuid, int generation, TrackerSession session) {
    return _handleSessionUpdated(userUuid, generation, session);
  }

  @visibleForTesting
  void debugHandleSessionInvalidatedForTesting(String userUuid, int generation) {
    _handleSessionInvalidated(userUuid, generation);
  }

  @override
  void dispose() {
    if (identical(_boundOwner, this)) {
      _boundOwner = null;
      TraktScrobbleService.instance.rebindToProfile(null, onSessionInvalidated: () {});
      TraktSyncService.instance.rebindToProfile('', null, onSessionInvalidated: () {});
    }
    _auth.dispose();
    super.dispose();
  }
}
