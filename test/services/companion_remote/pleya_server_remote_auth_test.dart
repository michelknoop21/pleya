import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/models/pleya_server/pleya_wire_companion.dart';
import 'package:pleya/services/companion_remote/companion_remote_peer_service.dart';
import 'package:pleya/services/companion_remote/pleya_companion_identity.dart';
import 'package:pleya/services/companion_remote/pleya_server_remote_auth.dart';
import 'package:pleya/services/companion_remote/remote_auth_context.dart';
import 'package:pleya/services/companion_remote/remote_auth_service.dart';

import 'fake_pleya_ticket_server.dart';

// Pleya Fly on Pleya Server (DEC-XXX): the secret picks the Home, a
// server-signed ticket says which user.
void main() {
  final auth = RemoteAuthService.instance;
  String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  group('secret derivation', () {
    test('stable for one account, case-insensitive', () async {
      final a = hex(await auth.derivePleyaServerSecret(serverId: 'srv-1', userId: 'user-a'));
      auth.clearCache();
      final again = hex(await auth.derivePleyaServerSecret(serverId: 'SRV-1', userId: 'USER-A'));
      expect(again, a);
    });

    test('another server or another user gives another secret', () async {
      final a = hex(await auth.derivePleyaServerSecret(serverId: 'srv-1', userId: 'user-a'));
      final otherServer = hex(await auth.derivePleyaServerSecret(serverId: 'srv-2', userId: 'user-a'));
      final otherUser = hex(await auth.derivePleyaServerSecret(serverId: 'srv-1', userId: 'user-b'));
      expect({a, otherServer, otherUser}, hasLength(3));
    });

    test('domain-separated from Jellyfin with the same inputs', () async {
      final pleya = hex(await auth.derivePleyaServerSecret(serverId: 'srv-1', userId: 'user-a'));
      final jellyfin = hex(await auth.deriveJellyfinSecret(serverMachineId: 'srv-1', userId: 'user-a'));
      expect(pleya, isNot(jellyfin));
    });

    test('the Jellyfin secret is unchanged by the shared derivation (pinned vector)', () async {
      auth.clearCache();
      final jellyfin = await auth.deriveJellyfinSecret(serverMachineId: 'Machine-A', userId: 'User-A');
      expect(hex(jellyfin), '3b7ea236b1bbc6c73b27691901f50c9c688d3f724dd4e5ee8db469cf0517fcd1');
    });
  });

  group('ticket identity', () {
    late FakePleyaTicketServer server;
    setUp(() async => server = await FakePleyaTicketServer.create('srv'));
    final transcript = utf8.encode('handshake-1');

    test('reads a ticket minted by the Go server (vector shared with auth/companion_test.go)', () async {
      const ticket =
          'plc1.eyJraWQiOiJUT2RuRVdPYm9xayIsInNydiI6InNydiIsInN1YiI6InUtYW5uYSIsImlhdCI6MTc5NDEzMTIwMCwiZXhwIjoxNzk0MTMxODAwLCJjbmYiOiJfUmNrT0ZxZ3gxdGstM2pOWUMtaDJaSDk2X2RyRThXTzF3THF5RFhwOWhnIn0.VKQWBFLLqFskfG8xOy7qAXZeqytVnoHYYBz6NBewUeaj3b2BO4eMv46WXRu_ji8CAPHJoCy13jxB7GvTTwrpDg';
      const serverKey = '_uF5MUwlc6n_9hwYDZ0xQ7LFZST0b_1Lrf7tGQJqf_0';
      const deviceSig = 'bIcGd3n1jJ1NR_hsCk1EAFYyOvJ1ccmPiw2jvRK7dXQl3OQZ_1ppfMWjm9UWbr_gJiilNawJn5ucEAqgkrP8DA';
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(ticket.split('.')[1])))) as Map;
      final host = PleyaCompanionIdentity(
        serverId: 'srv',
        now: () => DateTime.fromMillisecondsSinceEpoch(1794131260 * 1000),
        fetch: (_) async => PleyaCompanionTicket(
          ticket: 'own',
          expiresAt: DateTime.fromMillisecondsSinceEpoch(1794131800 * 1000),
          keyId: payload['kid'] as String,
          publicKey: serverKey,
        ),
      );
      final proof = {'ticket': ticket, 'ticketSig': deviceSig};
      final transcript = utf8.encode('vector-transcript');
      expect(await host.verify(proof, transcript, 'u-anna'), isTrue);
      expect(await host.verify(proof, transcript, 'u-bob'), isFalse);
      expect(await host.verify(proof, utf8.encode('other-transcript'), 'u-anna'), isFalse);
    });

    test('a ticket about the claimed user, signed by this server, with a matching device signature', () async {
      final host = server.identityFor('u-bob');
      final proof = await server.identityFor('u-anna').prove(transcript);
      expect(await host.verify(proof, transcript, 'u-anna'), isTrue);
    });

    test('a valid ticket for one user does not prove another (the kid claiming the owner)', () async {
      final proof = await server.identityFor('u-kid').prove(transcript);
      expect(await server.identityFor('u-bob').verify(proof, transcript, 'u-bob'), isFalse);
    });

    test('a proof replayed on another handshake fails', () async {
      final proof = await server.identityFor('u-anna').prove(transcript);
      expect(await server.identityFor('u-bob').verify(proof, utf8.encode('handshake-2'), 'u-anna'), isFalse);
    });

    test('a ticket of another server fails, also with the same server id', () async {
      final other = await FakePleyaTicketServer.create('srv', seed: 2);
      final proof = await other.identityFor('u-anna').prove(transcript);
      expect(await server.identityFor('u-bob').verify(proof, transcript, 'u-anna'), isFalse);
      final elsewhere = await FakePleyaTicketServer.create('other-srv');
      final foreign = await elsewhere.identityFor('u-anna').prove(transcript);
      final host = PleyaCompanionIdentity(serverId: 'srv', fetch: elsewhere.fetchFor('u-bob'));
      expect(await host.verify(foreign, transcript, 'u-anna'), isFalse, reason: 'srv must be this server');
    });

    test('an expired ticket fails', () async {
      final stale = PleyaCompanionIdentity(
        serverId: 'srv',
        fetch: server.fetchFor('u-anna', issuedAt: DateTime.now().subtract(const Duration(hours: 1))),
      );
      final proof = await stale.prove(transcript);
      expect(await server.identityFor('u-bob').verify(proof, transcript, 'u-anna'), isFalse);
    });

    test('a missing or broken proof fails closed', () async {
      final host = server.identityFor('u-bob');
      final proof = await server.identityFor('u-anna').prove(transcript);
      expect(await host.verify(const {}, transcript, 'u-anna'), isFalse);
      expect(await host.verify({'ticket': proof['ticket']!}, transcript, 'u-anna'), isFalse);
      final parts = proof['ticket']!.split('.');
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      payload['sub'] = 'u-bob';
      final forged = '${parts[0]}.${b64(utf8.encode(jsonEncode(payload)))}.${parts[2]}';
      expect(await host.verify({...proof, 'ticket': forged}, transcript, 'u-bob'), isFalse);
    });
  });

  group('contexts', () {
    late FakePleyaTicketServer server;
    setUp(() async => server = await FakePleyaTicketServer.create('srv'));

    test('own account: joins and hosts as itself; the beacon id is the device id', () async {
      final contexts = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-bob')],
        deviceId: 'device-tv',
        identityFor: (_) => server.identityFor('u-bob'),
      );
      expect(contexts, hasLength(1));
      final c = contexts.single;
      expect(c.hostOnly, isFalse);
      expect(c.userUuid, 'u-bob');
      expect(c.allowedUserUuids, ['u-bob']);
      expect(c.proveIdentity, isNotNull);
      expect(c.verifyIdentity, isNotNull, reason: 'a Pleya Server host always demands a ticket');
      expect(c.clientIdentifier, 'device-tv');
      expect(c.clientIdentifier, isNot(contains('u-bob')), reason: 'the beacon must not carry the user id');
    });

    test('another account of the same server on this device is a host-only member', () async {
      final contexts = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-bob'), _account('srv', 'u-anna'), _account('other-srv', 'u-carl')],
        deviceId: 'device-tv',
        identityFor: (_) => server.identityFor('u-bob'),
      );
      expect(contexts.map((c) => c.connectionId), ['pleyaServer.srv.u-bob', 'pleyaServer.srv.u-anna']);
      final anna = contexts.last;
      expect(anna.hostOnly, isTrue);
      expect(anna.allowedUserUuids, ['u-anna']);
      expect(anna.userUuid, 'u-bob', reason: 'the member is never the host user, so the host switches');
      expect(anna.proveIdentity, isNull);
      expect(anna.verifyIdentity, isNotNull);
    });

    test('no identity without a ticket source, an account id or a live sign-in', () async {
      expect(
        await pleyaServerAuthContexts(
          own: [_account('srv', 'u-bob')],
          onDevice: const [],
          deviceId: 'd',
          identityFor: (_) => null,
        ),
        isEmpty,
      );
      final legacy = PleyaServerConnection(
        id: 'pleyaServer.srv',
        baseUrl: 'http://nas.test',
        serverId: 'srv',
        serverName: 'NAS',
        userName: 'bob',
        refreshToken: 'r',
        createdAt: DateTime(2026),
      );
      PleyaCompanionIdentity identity(PleyaServerConnection _) => server.identityFor('u-bob');
      expect(
        await pleyaServerAuthContexts(own: [legacy], onDevice: [legacy], deviceId: 'd', identityFor: identity),
        isEmpty,
      );
      final signedOut = _account('srv', 'u-bob', refreshToken: '');
      expect(
        await pleyaServerAuthContexts(own: [signedOut], onDevice: [signedOut], deviceId: 'd', identityFor: identity),
        isEmpty,
      );
      final contexts = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-anna', refreshToken: '')],
        deviceId: 'd',
        identityFor: identity,
      );
      expect(contexts.map((c) => c.connectionId), ['pleyaServer.srv.u-bob']);
    });
  });

  group('handshake', () {
    late FakePleyaTicketServer server;
    // The Apple TV: Bob is active, Anna's account is also signed in here.
    late List<RemoteAuthContext> tv;
    late CompanionRemotePeerService host;
    late int port;
    final clients = <CompanionRemotePeerService>[];

    Future<int> startHost(List<RemoteAuthContext> contexts) async {
      host = CompanionRemotePeerService();
      return (await host.createSessionForContexts('Apple TV', 'tvOS', contexts)).port;
    }

    setUp(() async {
      server = await FakePleyaTicketServer.create('srv');
      tv = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-anna')],
        deviceId: 'device-tv',
        identityFor: (_) => server.identityFor('u-bob'),
      );
      port = await startHost(tv);
    });
    tearDown(() async {
      for (final c in clients) {
        await c.disconnect();
      }
      clients.clear();
      await host.disconnect();
    });

    Future<CompanionRemotePeerService> join(List<RemoteAuthContext> contexts) async {
      final client = CompanionRemotePeerService();
      clients.add(client);
      await client
          .joinSessionWithContexts('iPhone', 'iOS', '127.0.0.1:$port', contexts)
          .timeout(const Duration(seconds: 5));
      return client;
    }

    /// The device of [account], whose server session belongs to [ticketUser].
    Future<List<RemoteAuthContext>> phone(
      String serverId,
      String userId, {
      String? ticketUser,
      FakePleyaTicketServer? from,
    }) async => pleyaServerAuthContexts(
      own: [_account(serverId, userId)],
      onDevice: const [],
      deviceId: 'device-phone',
      identityFor: (_) =>
          PleyaCompanionIdentity(serverId: serverId, fetch: (from ?? server).fetchFor(ticketUser ?? userId)),
    );

    // A client the host refuses after it sent its tag waits for its own
    // timeout (the plaintext authFailed arrives after it started its cipher),
    // so these read the host's reply raw.
    Future<String> hostReply({
      required List<int> secret,
      required String contextId,
      required String claim,
      Future<Map<String, String>> Function(List<int> transcript)? prove,
    }) async {
      final socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      final frames = StreamIterator<dynamic>(socket);
      try {
        await frames.moveNext();
        final challenge = jsonDecode(frames.current as String) as Map<String, dynamic>;
        final hostNonce = base64Decode(challenge['nonce'] as String);
        final clientNonce = auth.generateNonce();
        List<int> transcript() => auth.authTranscript(
          hostNonce: hostNonce,
          clientNonce: clientNonce,
          hostClientId: 'device-tv',
          userUUID: claim,
          clientIdentifier: 'raw',
          deviceName: 'raw',
          platform: 'test',
        );
        final tag = auth.computeAuthTag(
          homeSecret: secret,
          hostNonce: hostNonce,
          clientNonce: clientNonce,
          hostClientId: 'device-tv',
          userUUID: claim,
          clientIdentifier: 'raw',
          deviceName: 'raw',
          platform: 'test',
        );
        socket.add(
          jsonEncode({
            'type': 'auth',
            'authContextId': contextId,
            'clientNonce': base64Encode(clientNonce),
            'userUUID': claim,
            'clientIdentifier': 'raw',
            'deviceName': 'raw',
            'platform': 'test',
            'authTag': tag,
            ...?(prove == null ? null : await prove(transcript())),
          }),
        );
        await frames.moveNext().timeout(const Duration(seconds: 5));
        final reply = frames.current;
        try {
          return (jsonDecode(reply as String) as Map<String, dynamic>)['type'] as String;
        } catch (_) {
          return 'encrypted';
        }
      } finally {
        await socket.close();
      }
    }

    test('the same account connects as the host user', () async {
      final client = await join(await phone('srv', 'u-bob'));
      expect(client.isConnected, isTrue);
      expect(host.clientIsHostUser, isTrue);
    });

    test('another member signed in here connects, and is not the host user (profile switch)', () async {
      final client = await join(await phone('srv', 'u-anna'));
      expect(client.isConnected, isTrue);
      expect(host.clientIsHostUser, isFalse);
      expect(host.clientUserUuid, 'u-anna');
      expect(tv.firstWhere((c) => c.id == host.selectedAuthContextId).connectionId, 'pleyaServer.srv.u-anna');
    });

    test('positive control: the raw helper is accepted with a real secret, claim and ticket', () async {
      final anna = (await phone('srv', 'u-anna')).single;
      expect(
        await hostReply(secret: anna.homeSecret, contextId: anna.id, claim: 'u-anna', prove: anna.proveIdentity),
        'encrypted',
      );
    });

    test('I1: a kid that knows the owner id derives his secret but has no ticket for him', () async {
      // The kid's device: the owner's context (secret from server id plus the
      // owner id, read from /collections or a token), with the kid's own
      // server session behind it.
      final posing = (await phone('srv', 'u-bob', ticketUser: 'u-kid')).single;
      expect(
        await hostReply(secret: posing.homeSecret, contextId: posing.id, claim: 'u-bob', prove: posing.proveIdentity),
        'authFailed',
      );
      expect(await hostReply(secret: posing.homeSecret, contextId: posing.id, claim: 'u-bob'), 'authFailed');
    });

    test('negative control: without the ticket check that kid is accepted as the owner', () async {
      await host.disconnect();
      port = await startHost([
        for (final c in tv)
          RemoteAuthContext(
            id: c.id,
            backend: c.backend,
            connectionId: c.connectionId,
            homeSecret: c.homeSecret,
            discoveryKey: c.discoveryKey,
            clientIdentifier: c.clientIdentifier,
            userUuid: c.userUuid,
            allowedUserUuids: c.allowedUserUuids,
            hostOnly: c.hostOnly,
          ),
      ]);
      final posing = (await phone('srv', 'u-bob', ticketUser: 'u-kid')).single;
      expect(await hostReply(secret: posing.homeSecret, contextId: posing.id, claim: 'u-bob'), 'encrypted');
    });

    test('a ticket overheard on another handshake is refused', () async {
      final anna = (await phone('srv', 'u-anna')).single;
      final overheard = await anna.proveIdentity!(utf8.encode('an earlier handshake'));
      expect(
        await hostReply(secret: anna.homeSecret, contextId: anna.id, claim: 'u-anna', prove: (_) async => overheard),
        'authFailed',
      );
    });

    test('an account of the same server that this device does not know is refused', () async {
      final carl = (await phone('srv', 'u-carl')).single;
      expect(
        await hostReply(secret: carl.homeSecret, contextId: carl.id, claim: 'u-carl', prove: carl.proveIdentity),
        'authFailed',
      );
    });

    test('another server, also naming this host\'s context, is refused', () async {
      final elsewhere = await FakePleyaTicketServer.create('other-srv', seed: 2);
      final forged = (await phone('other-srv', 'u-bob', from: elsewhere)).single;
      final bob = tv.firstWhere((c) => !c.hostOnly);
      expect(
        await hostReply(secret: forged.homeSecret, contextId: bob.id, claim: 'u-bob', prove: forged.proveIdentity),
        'authFailed',
      );
      await expectLater(
        join(await phone('other-srv', 'u-bob', from: elsewhere)),
        throwsA(isA<RemotePeerError>().having((e) => e.type, 'type', RemotePeerErrorType.authFailed)),
      );
    });

    test('a host-only context cannot join: its claim is the host user, not the member', () async {
      final tvMember = tv.firstWhere((c) => c.hostOnly);
      expect(
        await hostReply(
          secret: tvMember.homeSecret,
          contextId: tvMember.id,
          claim: tvMember.userUuid,
          prove: server.identityFor(tvMember.userUuid).prove,
        ),
        'authFailed',
      );
    });
  });
}

PleyaServerConnection _account(String serverId, String userId, {String refreshToken = 'refresh'}) =>
    PleyaServerConnection(
      id: pleyaServerConnectionId(serverId: serverId, userId: userId),
      baseUrl: 'http://nas.test',
      serverId: serverId,
      serverName: 'NAS',
      userName: userId,
      refreshToken: refreshToken,
      createdAt: DateTime(2026),
    );
