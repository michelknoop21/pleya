import '../../connection/connection.dart';
import 'pleya_companion_identity.dart';
import 'remote_auth_context.dart';
import 'remote_auth_service.dart';

const pleyaServerAuthBackend = 'pleyaServer';

/// Companion Remote identities for the Pleya Server accounts of the active
/// profile (DEC-XXX).
///
/// Two layers. The shared secret (HKDF over server id and user id) only picks
/// the context and keys the transport; it is not a secret against the
/// household, because user ids are visible to members (`/collections`,
/// `/items/{id}/activity`, the sub in every token). Who a device is comes
/// from a server-signed ticket ([PleyaCompanionIdentity]): every Pleya Server
/// context proves it as a client and demands it as a host. A member's
/// device can only get a ticket about its own user, so it cannot pose as the
/// owner.
///
/// Each account in [own] gives a context this device hosts and joins with.
/// Every other account on this device on the same server ([onDevice]) gives a
/// [RemoteAuthContext.hostOnly] context, so that member can reach this device
/// and the host switches to that member's profile with its PIN (A-23b). The
/// member list is therefore the set of accounts signed in here.
///
/// [identityFor] gives the ticket identity of an own account; an account
/// without one gets no context. [deviceId] is announced in beacons; it must
/// not be the connection id, which carries the user id.
Future<List<RemoteAuthContext>> pleyaServerAuthContexts({
  required Iterable<PleyaServerConnection> own,
  required Iterable<Connection> onDevice,
  required String deviceId,
  required PleyaCompanionIdentity? Function(PleyaServerConnection account) identityFor,
}) async {
  final auth = RemoteAuthService.instance;
  final contexts = <RemoteAuthContext>[];
  final seen = <String>{};

  Future<void> add(
    PleyaServerConnection account, {
    required String hostUser,
    required PleyaCompanionIdentity identity,
    required bool hostOnly,
  }) async {
    final userId = account.accountUserId!;
    final secret = await auth.derivePleyaServerSecret(serverId: account.serverId, userId: userId);
    final id = auth.computeAuthContextId(secret);
    if (!seen.add(id)) return;
    contexts.add(
      RemoteAuthContext(
        id: id,
        backend: pleyaServerAuthBackend,
        connectionId: account.id,
        homeSecret: secret,
        discoveryKey: await auth.deriveDiscoveryKey(secret),
        clientIdentifier: deviceId,
        userUuid: hostUser,
        allowedUserUuids: [userId],
        hostOnly: hostOnly,
        proveIdentity: hostOnly ? null : identity.prove,
        verifyIdentity: identity.verify,
      ),
    );
  }

  final members = onDevice.whereType<PleyaServerConnection>().where(_usable).toList();
  final active = [
    for (final account in own.where(_usable))
      if (identityFor(account) case final identity?) (account: account, identity: identity),
  ];
  for (final (:account, :identity) in active) {
    await add(account, hostUser: account.accountUserId!, identity: identity, hostOnly: false);
  }
  for (final (:account, :identity) in active) {
    for (final member in members) {
      if (member.serverId != account.serverId) continue;
      await add(member, hostUser: account.accountUserId!, identity: identity, hostOnly: true);
    }
  }
  return contexts;
}

/// Signed in, with a known account: a legacy connection without a user id in
/// its id, or one whose refresh chain is gone, proves no membership.
bool _usable(PleyaServerConnection c) => c.serverId.isNotEmpty && c.accountUserId != null && c.refreshToken.isNotEmpty;
