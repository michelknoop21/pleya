import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/seerr/seerr_account_store.dart';
import '../services/seerr/seerr_client.dart';
import '../services/seerr/seerr_constants.dart';
import '../services/seerr/seerr_session.dart';

/// Result of a successful connection test, shown in settings before saving.
typedef SeerrTestResult = ({String version, String? displayName, int permissions, SeerrSession session});

/// Owns the active Jellyseerr / Overseerr session for the current Plex profile.
///
/// Runtime-gated (no build-time secret): [isConfigured] is simply "a session
/// exists". Mirrors [TrackersProvider]'s single rebind seam
/// ([onActiveProfileChanged]) and generation guard so a late store load can't
/// clobber a newer profile.
class SeerrProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  final SeerrAccountStore _store = SeerrAccountStore.instance;

  SeerrSession? _session;
  SeerrClient? _client;
  String _activeUserUuid = '';
  int _generation = 0;

  // Bumped on every client swap. Captured into each client's onSessionUpdated
  // closure so a late emit from a disposed/superseded client (a cookie refresh
  // resolving after a profile switch or disconnect) can't persist a stale
  // session under the wrong profile. Mirrors TrackersProvider's rebind guard.
  int _clientGeneration = 0;

  /// Resolves the active profile's Plex token for one-tap login + silent
  /// re-auth. Wired from the widget tree (UserProfileProvider).
  Future<String?> Function()? _plexTokenResolver;

  SeerrSession? get session => _session;
  SeerrClient? get client => _client;

  bool get isConfigured => _session != null;

  String? get host {
    final s = _session;
    if (s == null) return null;
    return Uri.tryParse(s.baseUrl)?.host ?? s.baseUrl;
  }

  bool get canRequest => _hasPerm(SeerrPermission.request);
  bool get canManageRequests => _hasPerm(SeerrPermission.manageRequests);
  bool get canRequest4k => _hasPerm(SeerrPermission.anyRequest4k);
  bool get isAdmin => _session != null && SeerrPermission.has(_session!.permissions, SeerrPermission.admin);

  bool _hasPerm(int flag) => _session != null && SeerrPermission.has(_session!.permissions, flag);

  void attachPlexTokenResolver(Future<String?> Function()? resolver) => _plexTokenResolver = resolver;

  Future<String?> _resolvePlexToken() => _plexTokenResolver?.call() ?? Future<String?>.value(null);

  /// Single rebind seam: load this profile's session and swap the client.
  Future<void> onActiveProfileChanged(String? newUserUuid) async {
    final uuid = newUserUuid ?? '';
    final generation = ++_generation;
    _activeUserUuid = uuid;
    final loaded = await _store.load(uuid);
    if (isDisposed || generation != _generation || uuid != _activeUserUuid) return;
    _setSession(loaded);
    safeNotifyListeners();
  }

  /// Test a connection without persisting. Throws [SeerrException] on failure.
  Future<SeerrTestResult> test({
    required String baseUrl,
    required SeerrAuthMode mode,
    String? apiKey,
    String? email,
    String? password,
    String? plexToken,
  }) async {
    final provisional = SeerrSession(baseUrl: SeerrConstants.normalizeBaseUrl(baseUrl), authMode: mode, apiKey: apiKey);
    final client = SeerrClient(provisional, plexTokenProvider: _resolvePlexToken);
    try {
      final status = await client.getStatus(force: true);
      switch (mode) {
        case SeerrAuthMode.plex:
          if (plexToken == null || plexToken.isEmpty) throw SeerrException.auth();
          await client.loginWithPlexToken(plexToken);
        case SeerrAuthMode.local:
          if (email == null || password == null) throw SeerrException.auth();
          await client.loginLocal(email, password);
        case SeerrAuthMode.apiKey:
          await client.getMe();
      }
      final tested = client.session;
      return (
        version: (status['version'] ?? '?').toString(),
        displayName: tested.displayName,
        permissions: tested.permissions,
        session: tested,
      );
    } finally {
      client.dispose();
    }
  }

  /// Persist a tested session and make it active.
  Future<void> commit(SeerrSession session) async {
    await _store.save(_activeUserUuid, session);
    _setSession(session);
    safeNotifyListeners();
  }

  Future<void> disconnect() async {
    final uuid = _activeUserUuid;
    _setSession(null);
    safeNotifyListeners();
    await _store.clear(uuid);
  }

  void _setSession(SeerrSession? session) {
    _client?.dispose();
    final generation = ++_clientGeneration;
    final boundUuid = _activeUserUuid;
    _session = session;
    _client = session == null
        ? null
        : SeerrClient(
            session,
            plexTokenProvider: _resolvePlexToken,
            onSessionUpdated: (s) => _onSessionUpdated(generation, boundUuid, s),
          );
  }

  void _onSessionUpdated(int generation, String boundUuid, SeerrSession session) {
    // Reject a late emit from a superseded client: it would otherwise save the
    // old profile's session under whatever profile is active now, or resurrect
    // a session that disconnect() just cleared.
    if (isDisposed || generation != _clientGeneration || boundUuid != _activeUserUuid) return;
    _session = session;
    unawaited(_store.save(boundUuid, session));
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}
