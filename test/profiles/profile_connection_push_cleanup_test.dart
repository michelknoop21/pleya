import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_cleanup.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/storage_service.dart';

import '../pleya_server/pleya_fake_server.dart';
import '../test_helpers/prefs.dart';

// A removed Pleya Server connection used to keep its push installation on the
// server and its opt-in on the device, with no screen left to turn it off.
void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late StorageService storage;
  late MultiServerManager manager;
  final connection = PleyaServerConnection(
    id: 'pleyaServer.srv-1.alice',
    baseUrl: 'https://nas.example.org',
    serverId: 'srv-1',
    serverName: 'Zolder',
    userName: 'alice',
    refreshToken: 'rt-1',
    createdAt: DateTime.utc(2026, 8, 19),
  );
  const prefKey = 'pleya.push/p1/pleyaServer.srv-1.alice';

  setUp(() async {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
    storage = await StorageService.getInstance();
    manager = MultiServerManager();
    await connections.upsert(connection);
    await profileConnections.upsert(
      ProfileConnection(profileId: 'p1', connectionId: connection.id, userIdentifier: connection.userName),
    );
    await storage.setActiveProfileId('p1');
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList(prefKey, ['install-1', 'Zolder', 'movies']);
  });

  tearDown(() async {
    manager.dispose();
    await db.close();
  });

  Future<void> remove() => removeProfileConnectionAndCleanup(
    profileId: 'p1',
    connection: connection,
    profileConnections: profileConnections,
    connections: connections,
    storage: storage,
    serverManager: manager,
  );

  Future<List<http.Request>> bindClient() async {
    final fake = PleyaFakeServer();
    final requests = <http.Request>[];
    final client = PleyaServerClient.create(
      connection,
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.contains('/push-installations/') || request.url.path.endsWith('/auth/logout')) {
          requests.add(request);
          return http.Response('', 204);
        }
        final response = await fake.handle(request);
        if (!request.url.path.endsWith('/info')) return response;
        final info = jsonDecode(response.body) as Map<String, dynamic>;
        (info['capabilities'] as Map<String, dynamic>)['sessions'] = true;
        return http.Response(jsonEncode(info), 200, headers: {'content-type': 'application/json'});
      }),
    );
    await client.refreshCapabilities();
    manager.debugRegisterClientForTesting(client);
    return requests;
  }

  test('removing the last reference withdraws the installation, the opt-in and the session', () async {
    final requests = await bindClient();

    await remove();

    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'DELETE /pleya/v1/users/me/push-installations/install-1',
      'POST /pleya/v1/auth/logout',
    ]);
    expect((await BaseSharedPreferencesService.sharedCache()).containsKey(prefKey), isFalse);
  });

  test('another profile on the same connection keeps the session', () async {
    await profileConnections.upsert(
      ProfileConnection(profileId: 'p2', connectionId: connection.id, userIdentifier: connection.userName),
    );
    final requests = await bindClient();

    await remove();

    expect(requests.map((r) => r.method), ['DELETE']);
  });

  test('offline, the connection still goes and so does the local opt-in', () async {
    await remove();

    expect(await connections.get(connection.id), isNull);
    expect((await BaseSharedPreferencesService.sharedCache()).containsKey(prefKey), isFalse);
  });

  group('a profile that is not active', () {
    late String current;
    late List<String> presented;
    late List<String> calls;
    late PleyaFakeServer fake;
    Completer<void>? holdDelete;

    setUp(() {
      current = 'rt-1';
      presented = [];
      calls = [];
      fake = PleyaFakeServer();
      holdDelete = null;
      manager.debugPleyaServerHttpClientFactory = () => MockClient((request) async {
        if (request.url.path.endsWith('/info')) return fake.handle(request);
        if (request.url.path.endsWith('/auth/refresh')) {
          final token = (jsonDecode(request.body) as Map<String, dynamic>)['refresh_token'] as String;
          presented.add(token);
          if (token != current) {
            return http.Response(
              jsonEncode({
                'error': {'code': 'auth.refresh_token_reused', 'message': 'seen before', 'retryable': false},
              }),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          current = 'rt-${presented.length + 1}';
          return http.Response(
            jsonEncode({
              'access_token': 'at-${presented.length}',
              'refresh_token': current,
              'token_type': 'bearer',
              'expires_in_ms': 900000,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'DELETE') await holdDelete?.future;
        return http.Response('', 204);
      });
    });

    test('deleting it still withdraws the installation and ends the session', () async {
      await storage.setActiveProfileId('p2');

      await removeAllProfileConnectionsAndCleanup(
        profileId: 'p1',
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      expect(calls, ['DELETE /pleya/v1/users/me/push-installations/install-1', 'POST /pleya/v1/auth/logout']);
      expect(await connections.get(connection.id), isNull);
    });

    test('short-lived clients take turns and write the rotated refresh token back', () async {
      final persisted = <String>[];
      manager.onPleyaServerConnectionUpdated = (updated) => persisted.add(updated.refreshToken);

      await Future.wait([
        manager.withPleyaServerClient(connection, (client) => client.removePushInstallation('a')),
        manager.withPleyaServerClient(connection, (client) => client.removePushInstallation('b')),
      ]);

      expect(presented, ['rt-1', 'rt-2'], reason: 'the second turn starts from the rotated token');
      expect(persisted.last, 'rt-3');
      expect(calls, hasLength(2));
    });

    test('removing the connection from every profile reads it again per profile', () async {
      manager.onPleyaServerConnectionUpdated = connections.upsert;
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p2', connectionId: connection.id, userIdentifier: connection.userName),
      );
      await storage.setActiveProfileId('p3');

      await removeConnectionCompletely(
        connection: connection,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      expect(presented, ['rt-1', 'rt-2'], reason: 'the second profile must not present the token the first rotated');
      expect(calls, ['DELETE /pleya/v1/users/me/push-installations/install-1', 'POST /pleya/v1/auth/logout']);
    });

    test('binding waits for a short-lived turn and starts from the token it rotated to', () async {
      holdDelete = Completer<void>();
      final oneOff = manager.withPleyaServerClient(connection, (client) => client.removePushInstallation('a'));
      await pumpEventQueue();
      expect(presented, ['rt-1']);

      final binding = manager.addPleyaServerConnection(connection);
      await pumpEventQueue();
      expect(presented, ['rt-1'], reason: 'the binding may not refresh while the turn holds the token');
      holdDelete!.complete();
      await oneOff;
      await binding;

      expect(presented, ['rt-1', 'rt-2']);
    });
  });
}
