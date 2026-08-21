import 'dart:convert';

import '../credential_vault.dart';
import 'tautulli_constants.dart';
import 'tautulli_session.dart';

/// Whether the admin currently intends this integration to be live.
///
/// The `.name` is persisted; renaming needs a migration.
enum TautulliConnectionState { connected, disconnected }

/// One Tautulli pairing for one Plex server, shared by every local profile that
/// has that server.
///
/// This is deliberately not a per-profile session. A Tautulli instance monitors
/// a *server*, and the admin authorises it once for that server; making the
/// record profile-scoped would mean every household member needed their own
/// admin credential, which is exactly the thing they must never have. What
/// stays per-profile is the data: an import is always bound to the active
/// profile's own Plex account id, and profiles never see each other's history.
///
/// The four concerns are separate fields on purpose:
///  * [useHistoryForRecommendations] is the admin's policy,
///  * [connectionState] is whether the pairing is meant to be live,
///  * [token] is the credential, which can go missing on its own,
///  * [machineIdentifier] is the server it all applies to.
///
/// They are separate because they genuinely diverge. Losing the vault key makes
/// the token unreadable while the policy is still perfectly valid, and dropping
/// the whole record there (which is what the per-profile session store does)
/// would silently turn an explicit "off" back into the default "on".
class TautulliServerIntegration {
  /// `pms_identifier` of the monitored Plex server. Also the storage key, and
  /// the same string as the app's `ServerId`.
  final String machineIdentifier;

  final String baseUrl;
  final TautulliAuthMode authMode;

  /// Device token or master API key. Vault-protected at rest. Null when the
  /// admin disconnected, or when the stored blob could not be decrypted.
  final String? token;

  final String? deviceId;
  final String? serverName;
  final String? version;

  final TautulliConnectionState connectionState;

  /// The admin's choice. Null means "never explicitly set", which reads as on,
  /// so a fresh valid pairing works without anyone switching anything and
  /// without a migration writing defaults into old records.
  final bool? useHistoryForRecommendations;

  /// Which profile configured this, for support and logging only. Never used
  /// to decide who may consume the integration.
  final String? configuredByProfileId;
  final int? configuredAtMs;
  final int? policyChangedAtMs;

  /// Two different legacy pairings were found for this same server and there is
  /// no defensible way to pick one. Import stays off until an admin re-pairs,
  /// which is a deliberate fail-closed stop rather than a coin flip over whose
  /// URL and whose credential the household runs on.
  final bool hasUnresolvedConflict;

  const TautulliServerIntegration({
    required this.machineIdentifier,
    required this.baseUrl,
    required this.authMode,
    this.token,
    this.deviceId,
    this.serverName,
    this.version,
    this.connectionState = TautulliConnectionState.connected,
    this.useHistoryForRecommendations,
    this.configuredByProfileId,
    this.configuredAtMs,
    this.policyChangedAtMs,
    this.hasUnresolvedConflict = false,
  });

  bool get hasCredential => (token ?? '').isNotEmpty;

  bool get isConnected => connectionState == TautulliConnectionState.connected;

  /// The policy as the rest of the app reads it: absent means on.
  bool get historyPolicyEnabled => useHistoryForRecommendations != false;

  /// A session usable by [TautulliClient], or null when there is no credential.
  TautulliSession? get session {
    final t = token;
    if (t == null || t.isEmpty) return null;
    return TautulliSession(
      baseUrl: baseUrl,
      authMode: authMode,
      token: t,
      deviceId: deviceId,
      serverName: serverName,
      machineIdentifier: machineIdentifier,
      version: version,
    );
  }

  TautulliServerIntegration copyWith({
    String? baseUrl,
    TautulliAuthMode? authMode,
    String? token,
    bool clearToken = false,
    String? deviceId,
    String? serverName,
    String? version,
    TautulliConnectionState? connectionState,
    bool? useHistoryForRecommendations,
    String? configuredByProfileId,
    int? configuredAtMs,
    int? policyChangedAtMs,
    bool? hasUnresolvedConflict,
  }) {
    return TautulliServerIntegration(
      machineIdentifier: machineIdentifier,
      baseUrl: baseUrl ?? this.baseUrl,
      authMode: authMode ?? this.authMode,
      token: clearToken ? null : (token ?? this.token),
      deviceId: deviceId ?? this.deviceId,
      serverName: serverName ?? this.serverName,
      version: version ?? this.version,
      connectionState: connectionState ?? this.connectionState,
      useHistoryForRecommendations: useHistoryForRecommendations ?? this.useHistoryForRecommendations,
      configuredByProfileId: configuredByProfileId ?? this.configuredByProfileId,
      configuredAtMs: configuredAtMs ?? this.configuredAtMs,
      policyChangedAtMs: policyChangedAtMs ?? this.policyChangedAtMs,
      hasUnresolvedConflict: hasUnresolvedConflict ?? this.hasUnresolvedConflict,
    );
  }

  /// Builds a connected integration from a freshly tested session, carrying an
  /// [existing] record's admin policy forward.
  ///
  /// Re-pairing the same server must not silently re-enable something the admin
  /// turned off; only a server that was never configured here starts on the
  /// default.
  static TautulliServerIntegration fromSession(
    TautulliSession session, {
    required String machineIdentifier,
    TautulliServerIntegration? existing,
    String? configuredByProfileId,
    int? nowMs,
  }) {
    return TautulliServerIntegration(
      machineIdentifier: machineIdentifier,
      baseUrl: session.baseUrl,
      authMode: session.authMode,
      token: session.token,
      deviceId: session.deviceId,
      serverName: session.serverName,
      version: session.version,
      connectionState: TautulliConnectionState.connected,
      useHistoryForRecommendations: existing?.useHistoryForRecommendations,
      configuredByProfileId: configuredByProfileId ?? existing?.configuredByProfileId,
      configuredAtMs: existing?.configuredAtMs ?? nowMs ?? DateTime.now().millisecondsSinceEpoch,
      policyChangedAtMs: existing?.policyChangedAtMs,
      // Re-pairing is the admin stating which instance is the real one, so it
      // is exactly the act that clears a conflict.
      hasUnresolvedConflict: false,
    );
  }

  /// Whether [other] describes the same pairing: same host, same auth mode,
  /// same credential. Used to tell a duplicate legacy blob (harmless) from two
  /// genuinely different pairings (a conflict).
  bool describesSamePairing(TautulliServerIntegration other) =>
      baseUrl == other.baseUrl && authMode == other.authMode && token == other.token;

  Future<String> encode() async {
    final t = token;
    return json.encode(<String, dynamic>{
      'machine_identifier': machineIdentifier,
      'base_url': baseUrl,
      'auth_mode': authMode.name,
      'token': t == null || t.isEmpty ? null : await CredentialVault.protect(t),
      'device_id': deviceId,
      'server_name': serverName,
      'version': version,
      'connection_state': connectionState.name,
      'use_history_for_recommendations': useHistoryForRecommendations,
      'configured_by_profile_id': configuredByProfileId,
      'configured_at_ms': configuredAtMs,
      'policy_changed_at_ms': policyChangedAtMs,
      'has_unresolved_conflict': hasUnresolvedConflict,
    });
  }

  /// Throws on a payload that is not a usable record at all (no identifier, no
  /// URL, unknown auth mode).
  ///
  /// An unreadable *token* is not that case. The record still says which server
  /// it is about and what the admin decided, and both must survive, so the
  /// credential alone is dropped and [hasCredential] reports the truth.
  static Future<TautulliServerIntegration> decode(String raw) async {
    final map = json.decode(raw) as Map<String, dynamic>;
    final machineIdentifier = map['machine_identifier'];
    final baseUrl = map['base_url'];
    if (machineIdentifier is! String || machineIdentifier.isEmpty) {
      throw const FormatException('Tautulli integration has no machine identifier');
    }
    if (baseUrl is! String || baseUrl.isEmpty) {
      throw const FormatException('Tautulli integration has no base url');
    }
    final authMode = TautulliAuthMode.values.firstWhere(
      (m) => m.name == map['auth_mode'],
      orElse: () => throw FormatException('Unknown Tautulli auth mode: ${map['auth_mode']}'),
    );

    String? token;
    final protectedToken = map['token'];
    if (protectedToken is String && protectedToken.isNotEmpty) {
      try {
        token = await CredentialVault.reveal(protectedToken);
      } catch (_) {
        token = null; // credential lost; policy and binding stay.
      }
    }

    final policy = map['use_history_for_recommendations'];
    return TautulliServerIntegration(
      machineIdentifier: machineIdentifier,
      baseUrl: baseUrl,
      authMode: authMode,
      token: token,
      deviceId: map['device_id'] as String?,
      serverName: map['server_name'] as String?,
      version: map['version'] as String?,
      connectionState: TautulliConnectionState.values.firstWhere(
        (s) => s.name == map['connection_state'],
        orElse: () => TautulliConnectionState.connected,
      ),
      useHistoryForRecommendations: policy is bool ? policy : null,
      configuredByProfileId: map['configured_by_profile_id'] as String?,
      configuredAtMs: map['configured_at_ms'] as int?,
      policyChangedAtMs: map['policy_changed_at_ms'] as int?,
      hasUnresolvedConflict: map['has_unresolved_conflict'] == true,
    );
  }

  /// Never let the token reach a log line.
  @override
  String toString() =>
      'TautulliServerIntegration($serverName, ${connectionState.name}, '
      'credential: $hasCredential, policy: ${useHistoryForRecommendations ?? 'default'}, '
      'conflict: $hasUnresolvedConflict)';
}

/// Whether this integration may feed imported history into the taste engine.
///
/// Four independent things all have to hold, and each of them is a state the
/// admin can put the integration into on purpose. Written once, here, so the
/// binding, the scoring filter and the importer cannot drift apart on what
/// "enabled" means.
bool importEnabled(TautulliServerIntegration? integration) =>
    integration != null &&
    integration.isConnected &&
    integration.hasCredential &&
    integration.historyPolicyEnabled &&
    !integration.hasUnresolvedConflict;
