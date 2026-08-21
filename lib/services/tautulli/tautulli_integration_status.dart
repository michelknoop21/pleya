/// A Tautulli integration as everything outside the admin settings screen is
/// allowed to see it.
///
/// This type exists so that consuming an integration and holding its credential
/// are two different capabilities. It carries state, never secrets: no token,
/// no session, no client, and not even the base URL, because none of those is
/// needed to answer "may this profile import, and from which server". The only
/// route to the credential is [TautulliImportAccess.fetchImportHistory], whose
/// implementation looks the record up itself.
///
/// Deliberately not `const`-constructed from outside: build it with
/// `TautulliServerIntegration.status` so the rule below has exactly one input.
class TautulliIntegrationStatus {
  /// `pms_identifier` of the monitored Plex server. Same string as `ServerId`.
  final String machineIdentifier;

  /// Whether the pairing is meant to be live, as opposed to disconnected.
  final bool connected;

  /// Whether a credential is present and readable. Never the credential.
  final bool hasCredential;

  /// The admin's explicit choice, or null when it was never set.
  final bool? historyPolicy;

  /// Two conflicting legacy pairings were found and an admin has to re-pair.
  final bool hasUnresolvedConflict;

  const TautulliIntegrationStatus({
    required this.machineIdentifier,
    required this.connected,
    required this.hasCredential,
    required this.historyPolicy,
    required this.hasUnresolvedConflict,
  });

  /// The policy as the rest of the app reads it: absent means on.
  bool get historyEnabled => historyPolicy != false;

  /// Whether this integration may feed imported history into the taste engine.
  ///
  /// Four independent things all have to hold, and each of them is a state the
  /// admin can put the integration into on purpose. Written once, here, so the
  /// binding, the scoring filter and the importer cannot drift apart on what
  /// "enabled" means.
  bool get importEnabled => connected && hasCredential && historyEnabled && !hasUnresolvedConflict;

  @override
  String toString() =>
      'TautulliIntegrationStatus(${connected ? 'connected' : 'disconnected'}, '
      'credential: $hasCredential, policy: ${historyPolicy ?? 'default'}, '
      'conflict: $hasUnresolvedConflict)';
}
