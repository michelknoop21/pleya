import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/pleya_server/pleya_wire_lists.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'package:pleya_verify_fixture_server/pleya_fake_server.dart' show FakeList;

import 'pleya_fake_server.dart';

// The manager wiring behind the assistant's rights stamp: a role the server
// changes must reach the manager's status stream, or nothing watching rights
// can see it (BP-04b).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  http.Response json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

  final connection = PleyaServerConnection(
    id: 'pleyaServer.srv-1',
    baseUrl: 'http://nas.lan:8832',
    serverId: 'srv-1',
    serverName: 'Zolder',
    userName: 'michel',
    refreshToken: 'rt-1',
    createdAt: DateTime.utc(2026, 8, 19),
  );

  test(
    'a role change on the server reaches the status stream and the authority check, and so does the way back',
    () async {
      var role = 'owner';
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugPleyaServerHttpClientFactory = () => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/info')) {
          return json({
            'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
            'server': {'id': 'srv-1'},
            'capabilities': {'browse': true, 'search': true, 'artwork': true, 'watch_state': false, 'users': true},
            'auth': {
              'methods': ['password'],
              'setup_required': false,
            },
          });
        }
        if (path.endsWith('/auth/refresh')) {
          return json(const {
            'access_token': 'at',
            'refresh_token': 'rt-2',
            'token_type': 'bearer',
            'expires_in_ms': 900000,
          });
        }
        if (path.endsWith('/users/me')) return json({'id': 'u1', 'username': 'michel', 'role': role});
        return json(const {'id': 'srv-1', 'name': 'Zolder', 'version': '0.2.0', 'started_at': '2026-08-18T19:25:33Z'});
      });
      expect(await manager.addPleyaServerConnection(connection), isTrue);
      final id = ServerId('srv-1');
      expect(manager.canAdministerServer(id), isTrue);

      var events = 0;
      final sub = manager.statusStream.listen((_) => events++);
      addTearDown(sub.cancel);

      role = 'member';
      await manager.getClient(id)!.checkHealth();
      await Future<void>.delayed(Duration.zero);
      expect(manager.canAdministerServer(id), isFalse);
      expect(events, greaterThan(0), reason: 'the demotion was announced');

      final afterDemotion = events;
      role = 'owner';
      await manager.getClient(id)!.checkHealth();
      await Future<void>.delayed(Duration.zero);
      expect(manager.canAdministerServer(id), isTrue);
      expect(events, greaterThan(afterDemotion), reason: 'the way back was announced too');
    },
  );

  group('canonical collections (S19.4)', () {
    final id = ServerId('srv-1');
    MediaItem movie(String itemId) => MediaItem(id: itemId, backend: MediaBackend.pleyaServer, kind: MediaKind.movie);
    MediaItem collection(String itemId) =>
        MediaItem(id: itemId, backend: MediaBackend.pleyaServer, kind: MediaKind.collection);
    final refused = throwsA(isA<MediaServerAuthException>().having((e) => e.statusCode, 'status', 403));

    Future<(MultiServerManager, PleyaServerClient, PleyaFakeServer)> signedIn(String role) async {
      final server = PleyaFakeServer()
        ..listsCapability = true
        ..usersCapability = true
        ..usersMeRole = role;
      server.addItem(id: 'm1', kind: 'movie', title: 'One');
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugPleyaServerHttpClientFactory = server.asHttpClient;
      expect(await manager.addPleyaServerConnection(connection), isTrue);
      return (manager, manager.getClient(id)! as PleyaServerClient, server);
    }

    test('the owner manages them', () async {
      final (manager, client, server) = await signedIn('owner');
      expect(manager.canManageCollections(id), isTrue);
      final created = await client.createCollection(libraryId: 'l', title: 'Eigen', items: [movie('m1')]);
      expect(server.lists.collections[created]!.itemIds, ['m1']);
      expect(await client.addToCollection(collectionId: created!, items: [movie('m1')]), isTrue);
      expect(await client.removeFromCollection(collectionId: created, item: movie('m1')), isTrue);
      expect(await client.deleteCollection(collection(created)), isTrue);
    });

    for (final role in ['admin', 'member', 'restricted', '']) {
      test('"$role" is refused every write before anything leaves the client', () async {
        final (manager, client, server) = await signedIn(role);
        expect(manager.canManageCollections(id), isFalse);
        await expectLater(client.createCollection(libraryId: 'l', title: 'x', items: const []), refused);
        await expectLater(client.addToCollection(collectionId: 'c', items: [movie('m1')]), refused);
        await expectLater(client.removeFromCollection(collectionId: 'c', item: movie('m1')), refused);
        await expectLater(client.deleteCollection(collection('c')), refused);
        expect(server.lists.writes, isEmpty);
      });
    }

    group('sharing, the exception', () {
      Future<bool> share(PleyaServerClient client) => client.setCollectionVisibility(
        collectionId: 'c',
        visibility: PleyaCollectionVisibility.users,
        sharedWith: const ['sanne'],
      );

      for (final role in ['owner', 'admin']) {
        test('"$role" shares, and the request says with whom', () async {
          final (_, client, server) = await signedIn(role);
          server.lists.collections['c'] = FakeList(id: 'c', title: 'c');
          expect(await share(client), isTrue);
          expect(server.lists.lastCollectionBody, {
            'visibility': 'users',
            'shared_with': ['sanne'],
          });
          expect(
            await client.setCollectionVisibility(collectionId: 'c', visibility: PleyaCollectionVisibility.private),
            isTrue,
          );
          expect(server.lists.lastCollectionBody, {'visibility': 'private'});
        });
      }

      for (final role in ['member', 'restricted', '']) {
        test('"$role" is refused before anything leaves the client', () async {
          final (_, client, server) = await signedIn(role);
          server.lists.collections['c'] = FakeList(id: 'c', title: 'c');
          await expectLater(share(client), refused);
          expect(server.lists.writes, isEmpty);
        });
      }

      test('an admin who is demoted just before the request stops the write', () async {
        final (manager, client, server) = await signedIn('admin');
        server.lists.collections['c'] = FakeList(id: 'c', title: 'c');
        expect(manager.canAdministerServer(id), isTrue, reason: 'the client still believes in the old role');
        server.usersMeRole = 'member';
        await expectLater(share(client), refused);
        expect(server.lists.writes, isEmpty);
      });

      test('a role that cannot be read refuses', () async {
        final (_, client, server) = await signedIn('admin');
        server.usersMeFailureStatus = 503;
        await expectLater(share(client), refused);
        expect(server.lists.writes, isEmpty);
      });

      test('a borrowed connection is refused', () async {
        final (manager, client, server) = await signedIn('admin');
        manager.setServerAuthorityRestrictions(serverIds: {'srv-1'});
        await expectLater(share(client), refused);
        expect(server.lists.writes, isEmpty);
      });

      test('a stale client reaches the server, and the server still refuses a member', () async {
        final (_, client, server) = await signedIn('member');
        server.lists.collections['c'] = FakeList(id: 'c', title: 'c');
        client.canAdministerServer = () => true;
        await expectLater(share(client), refused);
        expect(server.lists.collections['c']!.visibility, 'private');
      });
    });

    test('an admin passes canAdministerServer and still does not manage collections', () async {
      final (manager, _, _) = await signedIn('admin');
      expect(manager.canAdministerServer(id), isTrue);
      expect(manager.canManageCollections(id), isFalse);
    });

    test('a borrowed connection is refused even with the owner role', () async {
      final (manager, client, server) = await signedIn('owner');
      manager.setServerAuthorityRestrictions(serverIds: {'srv-1'});
      expect(manager.canManageCollections(id), isFalse);
      await expectLater(client.createCollection(libraryId: 'l', title: 'x', items: const []), refused);
      expect(server.lists.writes, isEmpty);
    });

    test('a client that is no longer the registered one is refused', () async {
      final (manager, stale, server) = await signedIn('owner');
      // Same server, same owner, a newer client: a replaced user is this case.
      manager.debugRegisterClientForTesting(
        PleyaServerClient.create(connection.copyWith(role: 'owner'), httpClientFactory: server.asHttpClient),
      );
      await expectLater(stale.createCollection(libraryId: 'l', title: 'x', items: const []), refused);
      expect(server.lists.writes, isEmpty);
    });

    test('a role lost on the server just before the request stops the write', () async {
      final (manager, client, server) = await signedIn('owner');
      expect(manager.canManageCollections(id), isTrue, reason: 'the client still believes in the old role');
      server.usersMeRole = 'member';
      await expectLater(client.createCollection(libraryId: 'l', title: 'x', items: const []), refused);
      await expectLater(client.deleteCollection(collection('c')), refused);
      expect(server.lists.writes, isEmpty);
      expect(manager.canManageCollections(id), isFalse);
    });

    test('a role moved to admin just before the request stops the write too', () async {
      final (_, client, server) = await signedIn('owner');
      server.usersMeRole = 'admin';
      await expectLater(client.addToCollection(collectionId: 'c', items: [movie('m1')]), refused);
      expect(server.lists.writes, isEmpty);
    });

    test('a role gained on the server opens the write without a health probe', () async {
      final (manager, client, server) = await signedIn('owner');
      server.usersMeRole = 'member';
      await expectLater(client.createCollection(libraryId: 'l', title: 'x', items: const []), refused);
      server.usersMeRole = 'owner';
      await manager.getClient(id)!.checkHealth();
      expect(await client.createCollection(libraryId: 'l', title: 'y', items: const []), isNotNull);
    });

    test('a role that cannot be read refuses instead of trusting the last one', () async {
      final (_, client, server) = await signedIn('owner');
      server.usersMeFailureStatus = 503;
      await expectLater(client.createCollection(libraryId: 'l', title: 'x', items: const []), refused);
      expect(server.lists.writes, isEmpty);
    });

    test('a removed account stops the write', () async {
      final (_, client, server) = await signedIn('owner');
      server.usersMeFailureStatus = 404;
      await expectLater(client.deleteCollection(collection('c')), refused);
      expect(server.lists.writes, isEmpty);
    });

    for (final role in ['admin', 'member', 'restricted', '']) {
      test('a personal playlist has no owner rule: "$role" keeps his own', () async {
        final (_, client, server) = await signedIn(role);
        server.usersMeFailureStatus = 503;
        final list = await client.createPlaylist(title: 'Eigen', items: [movie('m1')]);
        expect(server.lists.playlists[list!.id]!.itemIds, ['m1']);
        expect(await client.removeFromPlaylist(playlistId: list.id, item: movie('m1')), isTrue);
        expect(await client.deletePlaylist(list), isTrue);
      });
    }
  });
}
