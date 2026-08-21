import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/ids.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/tautulli/tautulli_models.dart';
import '../utils/app_logger.dart';
import '../services/tautulli/tautulli_client.dart';
import '../services/tautulli/tautulli_constants.dart';
import '../services/tautulli/tautulli_import_access.dart';
import '../services/tautulli/tautulli_integration_status.dart';
import '../services/tautulli/tautulli_integration_store.dart';
import '../services/tautulli/tautulli_server_integration.dart';
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
class TautulliProvider extends ChangeNotifier with DisposableChangeNotifierMixin implements TautulliImportAccess {
  final TautulliIntegrationStore _store = TautulliIntegrationStore.instance;

  /// Every integration on this device, keyed by machine identifier. Device-wide
  /// on purpose: one admin pairing serves every local profile that has the
  /// server, which is the whole point of the record being server-scoped.
  Map<String, TautulliServerIntegration> _integrations = const {};

  /// A pairing from before `pms_identifier` was recorded. It cannot be keyed by
  /// server, so it stays profile-scoped and never feeds an import.
  TautulliSession? _legacySession;

  TautulliSession? _session;
  TautulliClient? _client;
  String _activeUserUuid = '';
  int _generation = 0;

  /// Injected so the provider can tell which server a record belongs to and
  /// whether this profile administers it. Closures rather than a stored
  /// snapshot, because servers can still register after the profile binds.
  List<String> Function() _serverIds = () => const [];
  bool Function(ServerId) _isOwnerOrAdmin = (_) => false;

  /// The plex.tv account id of a local profile, or null when it cannot be
  /// resolved exactly. Injected rather than passed per call, because whose
  /// history the admin's credential is aimed at is not the caller's decision to
  /// make; see [TautulliImportAccess].
  int? Function(String profileId) _selfAccountId = (_) => null;

  Listenable? _registryChanges;

  /// Completes once the device's integrations have been read from disk for the
  /// profile that is active now.
  ///
  /// Explicit readiness rather than a "did anyone notify yet" guess, because
  /// the two consumers need opposite things from the same load. The surfaces
  /// want whatever is known *now* and re-render when it changes; the background
  /// import wants the answer to "is there a saved, enabled integration", and an
  /// empty map before hydration is indistinguishable from a real "no". Without
  /// this, a cold start where Discover ran first simply never imported until
  /// something else forced a reload.
  Completer<void> _hydration = Completer<void>();

  /// Whether the authority questions have been wired. Once is all it takes.
  bool _resolversAttached = false;

  /// Wire the multi-server questions.
  ///
  /// [registryChanges] is watched so a server that registers *after* the
  /// profile bound still re-resolves; the listener is dropped in [dispose].
  ///
  /// **One-shot on purpose.** These three closures *are* the authority: which
  /// servers exist, which of them this profile administers, and which Plex
  /// account this profile is. A second call could replace all three, and then
  /// any code that can reach the provider could declare itself an admin of an
  /// arbitrary server and point the credential at an arbitrary account — which
  /// is precisely the boundary the rest of this class is built to hold. The
  /// provider tree wires it once, at construction; a second attempt is a bug
  /// or an attempt, and either way the answer is no.
  void attachServerResolvers({
    required List<String> Function() serverIds,
    required bool Function(ServerId) isOwnerOrAdmin,
    int? Function(String profileId)? selfAccountId,
    Listenable? registryChanges,
  }) {
    if (_resolversAttached) {
      appLogger.w('TautulliProvider: refused a second attempt to wire the server resolvers');
      return;
    }
    _resolversAttached = true;
    _serverIds = serverIds;
    _isOwnerOrAdmin = isOwnerOrAdmin;
    if (selfAccountId != null) _selfAccountId = selfAccountId;
    _registryChanges?.removeListener(refreshBinding);
    _registryChanges = registryChanges?..addListener(refreshBinding);
    refreshBinding();
  }

  /// The integration for a server this profile *administers*, credential and
  /// all. Private: nothing outside this class needs the record itself, and the
  /// record carries the token.
  ///
  /// This is what every existing Tautulli surface is built on, and it keeps its
  /// old meaning exactly: only an admin ever had a session before, and only an
  /// admin gets one now. A regular profile can consume the integration through
  /// [TautulliImportAccess] without any admin surface opening up for it.
  TautulliServerIntegration? get _adminIntegration {
    for (final id in _serverIds()) {
      final integration = _integrations[id];
      if (integration != null && _isOwnerOrAdmin(ServerId(id))) return integration;
    }
    return null;
  }

  /// State of the administered integration for the admin settings screen: what
  /// it is configured to do, never what it is configured with. Configuration is
  /// changed through [commit], [setHistoryForRecommendations] and [disconnect],
  /// which is why nothing here ever needs to hand the existing token back.
  TautulliIntegrationStatus? get adminStatus => _adminIntegration?.status;

  TautulliSession? get session => _session;
  TautulliClient? get client => _client;

  bool get isConfigured => _session != null;

  /// The admin policy for the integration this profile administers. Absent
  /// means never set, which reads as on.
  bool get historyForRecommendations => _adminIntegration?.historyPolicyEnabled ?? true;

  /// Whether two conflicting legacy pairings were found for this server and an
  /// admin has to re-pair before import resumes.
  bool get hasIntegrationConflict => _adminIntegration?.hasUnresolvedConflict ?? false;

  /// Host only, for a settings subtitle. Never the token.
  String? get host {
    final s = _session;
    if (s == null) return null;
    return Uri.tryParse(s.baseUrl)?.host ?? s.baseUrl;
  }

  String? get serverName => _session?.serverName;

  /// Whether [_integrations] reflects the store rather than the empty default.
  bool get isHydrated => _hydration.isCompleted;

  /// Resolves when [isHydrated] turns true for the active profile.
  ///
  /// Never rejects: a store that cannot be read resolves as "no integrations",
  /// because a waiter that hangs is worse than one that refuses.
  Future<void> whenHydrated() => _hydration.future;

  /// Machine identifier of the Plex server this instance monitors, which is how
  /// the presence surfaces pick the client that can resolve its rating keys.
  String? get machineIdentifier => _session?.machineIdentifier;

  /// Single rebind seam: migrate anything legacy, reload the device's
  /// integrations and re-resolve which one this profile sees.
  Future<void> onActiveProfileChanged(String? newUserUuid) async {
    final uuid = newUserUuid ?? '';
    final generation = ++_generation;
    _activeUserUuid = uuid;
    // A new profile resolves its own integrations. Anything already waiting on
    // the previous profile was released when that load landed, so replacing a
    // *completed* completer strands nobody; replacing a pending one would.
    if (_hydration.isCompleted) _hydration = Completer<void>();

    try {
      // Runs before the load so a just-migrated record is in the map right away.
      await _store.migrateLegacySession(uuid);
      final integrations = await _store.loadAll();
      final legacy = await _store.loadLegacySession(uuid);
      if (isDisposed || generation != _generation || uuid != _activeUserUuid) return;

      _integrations = integrations;
      _legacySession = legacy;
      _rebind();
      safeNotifyListeners();
    } catch (e, s) {
      // Unreadable storage means "no integrations", not "wait forever" and not
      // "keep whatever was there". Keeping it would be wrong in the one case
      // that matters: this runs on a profile *switch*, and `_legacySession` is
      // profile-scoped, so leaving it in place would serve the previous
      // profile's own pairing to the new one. The waiter below is released
      // either way, and the import then refuses on an empty set — the same
      // answer an empty store would give.
      appLogger.w('TautulliProvider: could not load this device\'s integrations', error: e, stackTrace: s);
      if (!isDisposed && generation == _generation && uuid == _activeUserUuid) {
        _integrations = const {};
        _legacySession = null;
        _rebind();
        safeNotifyListeners();
      }
    } finally {
      // Only the newest call owns readiness. A superseded one returning early
      // must not announce a state it did not write.
      if (generation == _generation) _markHydrated();
    }
  }

  void _markHydrated() {
    if (!_hydration.isCompleted) _hydration.complete();
  }

  /// Re-resolve after the server registry changed. Cheap: it only re-picks from
  /// an in-memory map and swaps the client when the answer actually moved.
  void refreshBinding() {
    if (isDisposed) return;
    if (_rebind()) safeNotifyListeners();
  }

  /// Returns whether anything observable changed.
  bool _rebind() {
    final integration = _adminIntegration;
    // A legacy pairing without a server identifier still drives the presence
    // surfaces for its own profile, exactly as it did before.
    final next = integration?.session ?? (integration == null ? _legacySession : null);
    final same =
        next?.baseUrl == _session?.baseUrl &&
        next?.token == _session?.token &&
        next?.machineIdentifier == _session?.machineIdentifier;
    if (same) return false;
    _setSession(next);
    return true;
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
    // A breadcrumb per step, all under one prefix so it can be grepped out of
    // someone else's uploaded log. What it buys is which call was the last one:
    // "started, register_device succeeded, silence" says the failure was in
    // get_server_info without anyone having to reason about the request list.
    // No address and no token, here or in any of the lines below.
    appLogger.i('Tautulli test: started mode=${mode.name}');
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
        final reported = (machineIdentifier ?? '').isEmpty ? 'absent' : 'present';
        appLogger.i('Tautulli test: register_device succeeded pmsIdentifier=$reported');
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
          appLogger.i('Tautulli test: get_server_info succeeded');
        } on TautulliException catch (e) {
          appLogger.d('Tautulli did not report which Plex server it monitors', error: e);
        }
      }
      if (serverName == null) {
        serverName = await client.serverFriendlyName();
        appLogger.i('Tautulli test: friendly name retrieved');
      }
      if (version == null) {
        version = await client.version();
        appLogger.i('Tautulli test: Tautulli info retrieved');
      }
      appLogger.i('Tautulli test: succeeded');

      return (
        serverName: serverName,
        version: version,
        session: provisional.copyWith(serverName: serverName, machineIdentifier: machineIdentifier, version: version),
      );
    } finally {
      client.dispose();
    }
  }

  /// Persist a tested session as this server's integration and make it active.
  ///
  /// Re-pairing a server that was configured here before keeps that record's
  /// admin policy, so an explicit "off" is not quietly undone by reconnecting.
  /// Only a server never seen here starts on the default.
  Future<void> commit(TautulliSession session) async {
    final identifier = session.machineIdentifier?.trim() ?? '';
    if (identifier.isEmpty) {
      // Nothing to key a server record on. Keep it profile-scoped, exactly as
      // before; the presence surfaces work and import refuses, which is what an
      // unidentified instance deserves.
      appLogger.w('TautulliProvider: pairing without a server identifier stays profile-scoped');
      await TautulliIntegrationStore.instance.saveLegacySession(_activeUserUuid, session);
      _legacySession = session;
      _rebind();
      safeNotifyListeners();
      return;
    }
    if (!_mayAdminister(identifier)) return;

    final integration = TautulliServerIntegration.fromSession(
      session,
      machineIdentifier: identifier,
      existing: _integrations[identifier],
      configuredByProfileId: _activeUserUuid.isEmpty ? null : _activeUserUuid,
    );
    await _store.save(integration);
    // Every profile's legacy blob for this server is now superseded, and
    // leaving them is not harmless: on the next launch `migrateLegacySession`
    // finds a pairing for a server that already has a record, sees a different
    // URL or token, and flags the fresh record as conflicted. Re-pairing to fix
    // a broken instance would therefore switch import off, silently, one
    // restart later — and for a household, on whichever launch the *other*
    // profile happens to be active. The credentials in them also have no reason
    // to outlive the pairing they belonged to.
    final removed = await _store.clearLegacySessionsForServer(identifier);
    if (removed > 0) {
      appLogger.i('TautulliProvider: dropped $removed superseded profile-scoped pairing(s) for this server');
    }
    // Also the active profile's own, which may predate `pms_identifier` and so
    // would not have matched on the identifier above.
    await _store.clearLegacySession(_activeUserUuid);
    _legacySession = null;
    _integrations = {..._integrations, identifier: integration};
    _rebind();
    safeNotifyListeners();
  }

  /// Sets the admin policy for the administered integration.
  ///
  /// The gate lives here as well as on the settings route, so the decision
  /// cannot be flipped from a code path that skipped the UI.
  Future<void> setHistoryForRecommendations(bool enabled) async {
    final current = _adminIntegration;
    if (current == null || !_mayAdminister(current.machineIdentifier)) return;
    if (current.useHistoryForRecommendations == enabled) return;

    final updated = current.copyWith(
      useHistoryForRecommendations: enabled,
      policyChangedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _store.save(updated);
    _integrations = {..._integrations, updated.machineIdentifier: updated};
    appLogger.d('TautulliProvider: history policy for ${_shortIdentifier(updated.machineIdentifier)} set to $enabled');
    safeNotifyListeners();
  }

  /// Drops the credential and marks the pairing disconnected, keeping the
  /// admin's policy.
  ///
  /// Removing a credential is not the same act as revoking a decision: on
  /// reconnect the earlier explicit choice must still stand. Imported rows are
  /// kept but stop counting, because a disconnected integration is not an
  /// enabled one.
  Future<void> disconnect() async {
    final current = _adminIntegration;
    if (current == null) {
      // Legacy, profile-scoped pairing.
      final uuid = _activeUserUuid;
      _legacySession = null;
      _rebind();
      safeNotifyListeners();
      await TautulliIntegrationStore.instance.clearLegacySession(uuid);
      return;
    }
    if (!_mayAdminister(current.machineIdentifier)) return;

    final updated = current.copyWith(clearToken: true, connectionState: TautulliConnectionState.disconnected);
    await _store.save(updated);
    _integrations = {..._integrations, updated.machineIdentifier: updated};
    _rebind();
    safeNotifyListeners();
  }

  /// Configuring is admin-only. Consuming is not: see [TautulliImportAccess].
  bool _mayAdminister(String machineIdentifier) {
    if (_isOwnerOrAdmin(ServerId(machineIdentifier))) return true;
    appLogger.w('TautulliProvider: refused a Tautulli change from a profile that does not administer the server');
    return false;
  }

  /// State of one server's integration, regardless of who is looking.
  ///
  /// Used by the import binding, which needs to know whether it may run. This
  /// returns the credential-free view on purpose: the binding is resolved in
  /// every profile's context, so returning the record here would put the
  /// admin's token one field access away from a non-admin profile. The token
  /// stays behind [fetchImportHistory].
  TautulliIntegrationStatus? importStatusFor(ServerId serverId) => _integrations[serverId.toString()]?.status;

  // --- TautulliImportAccess ------------------------------------------------

  @override
  Set<String> enabledImportServerIds() {
    // Intersected with the servers this profile actually has. The record is
    // device-wide so one admin pairing serves the household, but "the household
    // shares the pairing" is not "every profile scores every server": a profile
    // that lost access to a server must stop being recommended on the strength
    // of what it watched there, and its imported rows stay excluded rather than
    // being deleted.
    final visible = _serverIds().toSet();
    return {
      for (final entry in _integrations.entries)
        if (visible.contains(entry.key) && entry.value.status.importEnabled) entry.key,
    };
  }

  @override
  Future<TautulliHistoryPage?> fetchImportHistory(
    ServerId serverId, {
    required String profileId,
    required int length,
    required int start,
    String? after,
    String? before,
  }) async {
    // Whose history this is gets decided here, not by the caller. The token is
    // the admin's, so a `userId` parameter would have let any code in any
    // profile's tree read any housemate's history through it.
    if (profileId.isEmpty || profileId != _activeUserUuid) return _refuseFetch('not the active profile');
    final userId = _selfAccountId(profileId);
    if (userId == null) return _refuseFetch('no exact Plex account for this profile');

    // Re-checked per page, not once per sync: an admin who switches the policy
    // off mid-import stops it immediately instead of at the next page boundary.
    // The membership check is the same one [enabledImportServerIds] applies, so
    // a server this profile does not have cannot be fetched either.
    if (!_serverIds().contains(serverId.toString())) return _refuseFetch('server not registered for this profile');
    final integration = _integrations[serverId.toString()];
    if (integration == null || !integration.status.importEnabled) return _refuseFetch('import not enabled');
    final session = integration.session;
    if (session == null) return _refuseFetch('no credential');

    final client = TautulliClient(session);
    try {
      return await client.history(
        userId: userId,
        length: length,
        start: start,
        after: after,
        before: before,
        // Ungrouped keeps row_id stable, which is what makes a re-import a
        // no-op; ordering by date descending is what both cursors assume.
        grouping: false,
        includeActivity: false,
        orderColumn: 'date',
        orderDir: 'desc',
      );
    } finally {
      client.dispose();
    }
  }

  /// A refusal is a diagnostic, never a message: there is no user-facing
  /// Tautulli surface outside the admin settings screen. Named so a silent
  /// "no history arrived" is traceable to which gate said no, without the
  /// reason naming a profile, a server or an address.
  Null _refuseFetch(String reason) {
    appLogger.d('TautulliProvider: refused an import fetch ($reason)');
    return null;
  }

  static String _shortIdentifier(String value) => value.length <= 6 ? value : '${value.substring(0, 6)}…';

  void _setSession(TautulliSession? session) {
    _client?.dispose();
    _session = session;
    _client = session == null ? null : TautulliClient(session);
  }

  @override
  void dispose() {
    // Release anything still waiting, or a background import started just
    // before a profile switch keeps a pending future alive for the run.
    _markHydrated();
    _registryChanges?.removeListener(refreshBinding);
    _registryChanges = null;
    _client?.dispose();
    _client = null;
    super.dispose();
  }
}
