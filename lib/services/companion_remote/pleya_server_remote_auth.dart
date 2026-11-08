import '../../connection/connection.dart';
import 'remote_auth_context.dart';
import 'remote_auth_service.dart';

const pleyaServerAuthBackend = 'pleyaServer';

/// Companion Remote identities for the Pleya Server accounts of the active
/// profile (DEC-XXX). The Home is one server: the secret of an account is
/// derived from the server id and that account's user id, so a device of
/// another server, or of an account this device does not know, fails the
/// handshake.
///
/// Each account in [own] gives a context this device hosts and joins with.
/// Every other account on this device on the same server ([onDevice]) gives a
/// [RemoteAuthContext.hostOnly] context, so that member can reach this device
/// and the host switches to that member's profile with its PIN (A-23b), as a
/// Plex Home host does. Pleya Server has no Home secret a member can read
/// (members see only themselves in `/users`), so the member list is the set of
/// accounts signed in here, not the server's user list.
///
/// [deviceId] is announced in beacons; it must not be the connection id,
/// which carries the user id.
Future<List<RemoteAuthContext>> pleyaServerAuthContexts({
  required Iterable<PleyaServerConnection> own,
  required Iterable<Connection> onDevice,
  required String deviceId,
}) async {
  final auth = RemoteAuthService.instance;
  final contexts = <RemoteAuthContext>[];
  final seen = <String>{};

  Future<void> add(PleyaServerConnection account, {required String hostUser, required bool hostOnly}) async {
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
      ),
    );
  }

  final active = own.where(_usable).toList();
  for (final account in active) {
    await add(account, hostUser: account.accountUserId!, hostOnly: false);
  }
  final members = onDevice.whereType<PleyaServerConnection>().where(_usable).toList();
  for (final account in active) {
    for (final member in members) {
      if (member.serverId != account.serverId) continue;
      await add(member, hostUser: account.accountUserId!, hostOnly: true);
    }
  }
  return contexts;
}

/// Signed in, with a known account: a legacy connection without a user id in
/// its id, or one whose refresh chain is gone, proves no membership.
bool _usable(PleyaServerConnection c) => c.serverId.isNotEmpty && c.accountUserId != null && c.refreshToken.isNotEmpty;
