class RemoteAuthContext {
  const RemoteAuthContext({
    required this.id,
    required this.backend,
    required this.connectionId,
    required this.homeSecret,
    required this.discoveryKey,
    required this.clientIdentifier,
    required this.userUuid,
    required this.allowedUserUuids,
    this.hostOnly = false,
    this.proveIdentity,
    this.verifyIdentity,
  });

  final String id;
  final String backend;
  final String connectionId;
  final List<int> homeSecret;
  final List<int> discoveryKey;
  final String clientIdentifier;
  final String userUuid;
  final List<String> allowedUserUuids;

  /// Accepted when this device hosts, never used to join a host: the identity
  /// of another member of the Home, kept so the host can switch to that
  /// member's profile (A-23b). [userUuid] is then this device's own user, so
  /// the member never counts as the host user.
  final bool hostOnly;

  /// Client side: extra fields for the auth message that prove who this
  /// device is, given the handshake transcript (a Pleya Server ticket, DEC-XXX).
  final Future<Map<String, String>> Function(List<int> transcript)? proveIdentity;

  /// Host side: whether the auth message proves the claimed [userUuid]; the
  /// handshake fails on false. Null for identities the shared secret alone
  /// carries (Plex Home, Jellyfin).
  final Future<bool> Function(Map<String, dynamic> auth, List<int> transcript, String userUuid)? verifyIdentity;
}
