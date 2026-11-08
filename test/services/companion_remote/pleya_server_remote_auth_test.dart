import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/companion_remote/companion_remote_peer_service.dart';
import 'package:pleya/services/companion_remote/pleya_server_remote_auth.dart';
import 'package:pleya/services/companion_remote/remote_auth_context.dart';
import 'package:pleya/services/companion_remote/remote_auth_service.dart';

// Pleya Fly on Pleya Server (DEC-XXX): the Home is one server, the secret is
// server id plus account user id.
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

  group('contexts', () {
    test('own account: joins and hosts as itself; the beacon id is the device id', () async {
      final contexts = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-bob')],
        deviceId: 'device-tv',
      );
      expect(contexts, hasLength(1));
      final c = contexts.single;
      expect(c.hostOnly, isFalse);
      expect(c.userUuid, 'u-bob');
      expect(c.allowedUserUuids, ['u-bob']);
      expect(c.clientIdentifier, 'device-tv');
      expect(c.clientIdentifier, isNot(contains('u-bob')), reason: 'the beacon must not carry the user id');
    });

    test('another account of the same server on this device is a host-only member', () async {
      final contexts = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-bob'), _account('srv', 'u-anna'), _account('other-srv', 'u-carl')],
        deviceId: 'device-tv',
      );
      expect(contexts.map((c) => c.connectionId), ['pleyaServer.srv.u-bob', 'pleyaServer.srv.u-anna']);
      final anna = contexts.last;
      expect(anna.hostOnly, isTrue);
      expect(anna.allowedUserUuids, ['u-anna']);
      expect(anna.userUuid, 'u-bob', reason: 'the member is never the host user, so the host switches');
    });

    test('no identity without an account id or a live sign-in', () async {
      final legacy = PleyaServerConnection(
        id: 'pleyaServer.srv',
        baseUrl: 'http://nas.test',
        serverId: 'srv',
        serverName: 'NAS',
        userName: 'bob',
        refreshToken: 'r',
        createdAt: DateTime(2026),
      );
      expect(await pleyaServerAuthContexts(own: [legacy], onDevice: [legacy], deviceId: 'd'), isEmpty);
      final signedOut = _account('srv', 'u-bob', refreshToken: '');
      expect(await pleyaServerAuthContexts(own: [signedOut], onDevice: [signedOut], deviceId: 'd'), isEmpty);
      // A signed-out member is no member.
      final contexts = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-anna', refreshToken: '')],
        deviceId: 'd',
      );
      expect(contexts.map((c) => c.connectionId), ['pleyaServer.srv.u-bob']);
    });
  });

  group('handshake', () {
    // The Apple TV: Bob is active, Anna's account is also signed in here.
    late List<RemoteAuthContext> tv;
    late CompanionRemotePeerService host;
    late int port;
    final clients = <CompanionRemotePeerService>[];

    setUp(() async {
      tv = await pleyaServerAuthContexts(
        own: [_account('srv', 'u-bob')],
        onDevice: [_account('srv', 'u-anna')],
        deviceId: 'device-tv',
      );
      host = CompanionRemotePeerService();
      port = (await host.createSessionForContexts('Apple TV', 'tvOS', tv)).port;
    });
    tearDown(() async {
      for (final c in clients) {
        await c.disconnect();
      }
      clients.clear();
      await host.disconnect();
    });

    Future<CompanionRemotePeerService> join(List<RemoteAuthContext> contexts, {String? authContextId}) async {
      final client = CompanionRemotePeerService();
      clients.add(client);
      await client
          .joinSessionWithContexts('iPhone', 'iOS', '127.0.0.1:$port', contexts, authContextId: authContextId)
          .timeout(const Duration(seconds: 5));
      return client;
    }

    Future<List<RemoteAuthContext>> phone(String serverId, String userId) =>
        pleyaServerAuthContexts(own: [_account(serverId, userId)], onDevice: const [], deviceId: 'device-phone');

    final rejected = throwsA(isA<RemotePeerError>().having((e) => e.type, 'type', RemotePeerErrorType.authFailed));

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

    test('an account of the same server that this device does not know is rejected', () async {
      await expectLater(join(await phone('srv', 'u-carl')), rejected);
      expect(host.isConnected, isFalse);
    });

    test('the same user id on another server is rejected', () async {
      await expectLater(join(await phone('other-srv', 'u-bob')), rejected);
    });

    // A client the host refuses after it sent its tag waits for its own
    // timeout (the plaintext authFailed arrives after it started its cipher),
    // so these read the host's reply raw.
    Future<String> hostReply({required List<int> secret, required String contextId, required String claim}) async {
      final socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      final frames = StreamIterator<dynamic>(socket);
      try {
        await frames.moveNext();
        final challenge = jsonDecode(frames.current as String) as Map<String, dynamic>;
        final hostNonce = base64Decode(challenge['nonce'] as String);
        final clientNonce = auth.generateNonce();
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

    test('positive control: a member with its own secret and claim is accepted', () async {
      final anna = (await phone('srv', 'u-anna')).single;
      expect(await hostReply(secret: anna.homeSecret, contextId: anna.id, claim: 'u-anna'), 'encrypted');
    });

    test('an unknown account of the same server is refused by the host too', () async {
      final carl = (await phone('srv', 'u-carl')).single;
      expect(await hostReply(secret: carl.homeSecret, contextId: carl.id, claim: 'u-carl'), 'authFailed');
    });

    test('another server naming this host\'s context fails the host tag check', () async {
      final forged = (await phone('other-srv', 'u-bob')).single;
      final bob = tv.firstWhere((c) => !c.hostOnly);
      expect(await hostReply(secret: forged.homeSecret, contextId: bob.id, claim: 'u-bob'), 'authFailed');
    });

    test('a member claiming another member with its own secret is rejected', () async {
      final anna = (await phone('srv', 'u-anna')).single;
      expect(await hostReply(secret: anna.homeSecret, contextId: anna.id, claim: 'u-bob'), 'authFailed');
    });

    test('negative control: a host-only context cannot join, its claim is not the member', () async {
      // Why the provider never joins with one: its claim is the host user.
      final tvMember = tv.firstWhere((c) => c.hostOnly);
      expect(
        await hostReply(secret: tvMember.homeSecret, contextId: tvMember.id, claim: tvMember.userUuid),
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
