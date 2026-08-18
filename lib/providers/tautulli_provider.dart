import 'package:flutter/foundation.dart';

import '../mixins/disposable_change_notifier_mixin.dart';
import '../utils/app_logger.dart';
import '../services/tautulli/tautulli_account_store.dart';
import '../services/tautulli/tautulli_client.dart';
import '../services/tautulli/tautulli_constants.dart';
import '../services/tautulli/tautulli_session.dart';

/// What a successful connection test found, shown before anything is saved.
typedef TautulliTestResult = ({String? serverName, String? version, TautulliSession session});

/// Owns the Tautulli session for the current Plex profile.
///
/// Simpler than [SeerrProvider] on purpose: a Tautulli session never mutates
/// after pairing (no cookie to refresh, no permissions to re-read), so there is
/// no late-emit seam to guard. What is left is the same rebind guard, so a slow
/// store load cannot land on a profile the user already switched away from.
///
/// [isConfigured] says only that a session exists. Whether the *surfaces* are
/// allowed to appear is a separate question answered by
/// `MultiServerManager.isOwnerOrAdmin`: Tautulli has a single admin key, so
/// everything it can tell us is admin data.
class TautulliProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  final TautulliAccountStore _store = TautulliAccountStore.instance;

  TautulliSession? _session;
  TautulliClient? _client;
  String _activeUserUuid = '';
  int _generation = 0;

  TautulliSession? get session => _session;
  TautulliClient? get client => _client;

  bool get isConfigured => _session != null;

  /// Host only, for a settings subtitle. Never the token.
  String? get host {
    final s = _session;
    if (s == null) return null;
    return Uri.tryParse(s.baseUrl)?.host ?? s.baseUrl;
  }

  String? get serverName => _session?.serverName;

  /// Machine identifier of the Plex server this instance monitors, which is how
  /// the presence surfaces pick the client that can resolve its rating keys.
  String? get machineIdentifier => _session?.machineIdentifier;

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

  /// Try a URL and token without persisting anything.
  ///
  /// For [TautulliAuthMode.device] the token is the five-minute one the admin
  /// generated in Tautulli; this call spends it on `register_device`, after
  /// which Tautulli keeps the same string as a permanent per-device token.
  /// Throws [TautulliException] on failure.
  Future<TautulliTestResult> test({
    required String baseUrl,
    required TautulliAuthMode mode,
    required String token,
    required String deviceId,
    required String deviceName,
  }) async {
    final provisional = TautulliSession(
      baseUrl: TautulliConstants.normalizeBaseUrl(baseUrl),
      authMode: mode,
      token: token,
      deviceId: mode == TautulliAuthMode.device ? deviceId : null,
    );
    final client = TautulliClient(provisional);
    try {
      String? serverName;
      String? version;
      String? machineIdentifier;

      if (mode == TautulliAuthMode.device) {
        final info = await client.registerDevice(deviceId: deviceId, deviceName: deviceName);
        // register_device answers with the server details, so pairing can show
        // which Tautulli was reached without a second round-trip.
        serverName = info['pms_name']?.toString();
        machineIdentifier = info['pms_identifier']?.toString();
        version = info['tautulli_version']?.toString();
      }

      if (machineIdentifier == null || machineIdentifier.isEmpty) {
        // Which Plex server this instance watches decides which client can
        // resolve the rating keys it reports, so it is worth the extra call
        // rather than something to fill in later. Not worth failing a pairing
        // over, though: without it the presence surfaces fall back to the
        // single-owned-server case, which is what every profile with one server
        // already is.
        try {
          machineIdentifier = (await client.serverInfo())['pms_identifier']?.toString();
        } on TautulliException catch (e) {
          appLogger.d('Tautulli did not report which Plex server it monitors', error: e);
        }
      }
      serverName ??= await client.serverFriendlyName();
      version ??= await client.version();

      return (
        serverName: serverName,
        version: version,
        session: provisional.copyWith(serverName: serverName, machineIdentifier: machineIdentifier, version: version),
      );
    } finally {
      client.dispose();
    }
  }

  /// Persist a tested session and make it active.
  Future<void> commit(TautulliSession session) async {
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

  void _setSession(TautulliSession? session) {
    _client?.dispose();
    _session = session;
    _client = session == null ? null : TautulliClient(session);
  }

  @override
  void dispose() {
    _client?.dispose();
    _client = null;
    super.dispose();
  }
}
