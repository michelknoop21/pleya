import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/pleya_server_client.dart';

void main() {
  const account = '00000000-0000-4000-8000-000000000001';
  const epoch = '00000000-0000-4000-8000-000000000002';
  late PleyaServerClient client;
  final requests = <http.Request>[];
  bool capability = true;
  bool current = true;
  String userId = account;
  String role = 'member';
  int status = 200;
  String errorCode = 'memory.conflict';
  bool switchDuringIdentity = false;
  Completer<void>? authHeld;
  bool switchOnUnauthorized = false;
  http.Response json(Object value, [int code = 200]) =>
      http.Response(jsonEncode(value), code, headers: {'content-type': 'application/json'});

  setUp(() async {
    requests.clear();
    capability = true;
    current = true;
    userId = account;
    role = 'member';
    status = 200;
    errorCode = 'memory.conflict';
    switchDuringIdentity = false;
    authHeld = null;
    switchOnUnauthorized = false;
    client = PleyaServerClient.create(
      PleyaServerConnection(
        id: 'pleyaServer.server.$account',
        baseUrl: 'http://fixture.invalid',
        serverId: 'server',
        serverName: 'Fixture',
        userName: 'me',
        refreshToken: 'fixture-token',
        role: 'member',
        createdAt: DateTime.utc(2026),
      ),
      httpClientFactory: () => MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/info'))
          return json({
            'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
            'server': {'id': 'server'},
            'capabilities': {
              'browse': true,
              'search': true,
              'artwork': true,
              'watch_state': true,
              'assistant_memory': capability,
            },
            'auth': {
              'methods': ['password'],
              'setup_required': false,
            },
          });
        if (request.url.path.endsWith('/auth/refresh')) {
          await authHeld?.future;
          return json({'access_token': 'fixture-access', 'refresh_token': 'fixture-refresh', 'expires_in_ms': 900000});
        }
        if (request.url.path.endsWith('/users/me')) {
          if (switchDuringIdentity) current = false;
          return json({'id': userId, 'username': 'me', 'role': role});
        }
        if (switchOnUnauthorized) {
          current = false;
          return json({
            'error': {'code': 'auth.invalid', 'message': 'no', 'retryable': false},
          }, 401);
        }
        if (status != 200)
          return json({
            'error': {'code': errorCode, 'message': 'private text', 'retryable': false},
          }, status);
        return json({'epoch': epoch, 'revision': 1, 'facts': []});
      }),
    );
    await client.refreshCapabilities();
    requests.clear();
  });
  tearDown(() => client.close());
  MemorySyncTransport transport() => client.assistantMemoryTransport(isCurrent: () => current);
  final fails = throwsA(isA<MemorySyncFailure>());

  test('fetch checks own live identity and sends no fact data to a cache', () async {
    final snapshot = await transport().fetch();
    expect(snapshot.epoch, epoch);
    expect(requests.last.url.path, '/pleya/v1/users/me/memory');
    expect(requests.last.headers['authorization'], 'Bearer fixture-access');
    expect(requests.last.body, isEmpty);
  });
  test('capability missing prevents every operation before auth/network', () async {
    capability = false;
    await client.refreshCapabilities();
    requests.clear();
    await expectLater(transport().fetch(), fails);
    await expectLater(transport().replace(epoch: epoch, baseRevision: 0, facts: []), fails);
    await expectLater(transport().clear(epoch: epoch, baseRevision: 0), fails);
    expect(requests, isEmpty);
  });
  test('another subject and a restricted role never reach memory endpoints', () async {
    userId = 'other';
    await expectLater(transport().fetch(), fails);
    userId = account;
    role = 'restricted';
    await expectLater(transport().fetch(), fails);
    expect(requests.where((r) => r.url.path.contains('/memory')), isEmpty);
  });
  test('profile switch during identity check prevents the pending PUT', () async {
    switchDuringIdentity = true;
    await expectLater(transport().replace(epoch: epoch, baseRevision: 0, facts: []), fails);
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
  });
  test('profile change during token minting prevents even the identity read', () async {
    authHeld = Completer<void>();
    final failed = expectLater(transport().fetch(), fails);
    await Future<void>.delayed(Duration.zero);
    current = false;
    authHeld!.complete();
    await failed;
    expect(requests.where((r) => r.url.path.contains('/users/')), isEmpty);
  });
  test('a profile change on the first 401 prevents a memory PUT retry', () async {
    switchOnUnauthorized = true;
    await expectLater(transport().replace(epoch: epoch, baseRevision: 0, facts: []), fails);
    expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
  });
  test('PUT and clear use closed bodies without client timestamps or user id', () async {
    await transport().replace(epoch: epoch, baseRevision: 0, facts: []);
    expect(jsonDecode(requests.last.body), {'epoch': epoch, 'base_revision': 0, 'facts': []});
    expect(requests.last.method, 'PUT');
    await transport().clear(epoch: epoch, baseRevision: 1);
    expect(requests.last.url.path, '/pleya/v1/users/me/memory/clear');
    expect(jsonDecode(requests.last.body), {'epoch': epoch, 'base_revision': 1});
  });
  test('coded errors retain only approved safe codes', () async {
    status = 409;
    await expectLater(
      transport().fetch(),
      throwsA(isA<MemorySyncFailure>().having((e) => e.code, 'code', 'memory.conflict')),
    );
    errorCode = 'private fact in unexpected error';
    await expectLater(
      transport().fetch(),
      throwsA(isA<MemorySyncFailure>().having((e) => e.code, 'code', 'unavailable')),
    );
  });
}
