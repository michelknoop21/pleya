import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:test/test.dart';

PleyaFakeServer _serverWithOneLibrary() {
  final server = PleyaFakeServer();
  server.addLibrary(id: 'lib-1', title: 'Films', kind: 'movie', itemCount: 1);
  server.addItem(id: 'item-1', kind: 'movie', title: 'Sintel', libraryId: 'lib-1', year: 2010, durationMs: 888000);
  return server;
}

Future<http.Response> _get(PleyaFakeServer server, String path, {String token = 'at-0'}) {
  final request = http.Request('GET', Uri.parse('http://fixture$path'));
  request.headers['Authorization'] = 'Bearer $token';
  return server.handle(request);
}

void main() {
  group('contract', () {
    test('GET /info reports protocol shape', () async {
      final server = PleyaFakeServer();
      final request = http.Request('GET', Uri.parse('http://fixture/pleya/v1/info'));
      final response = await server.handle(request);
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['protocol'], {'major': 1, 'feature_level': 1, 'profile': 'full'});
      expect(body['auth'], {
        'methods': ['password'],
        'setup_required': false,
      });
    });

    test('a request without a valid bearer token is rejected with auth.invalid_token', () async {
      final server = PleyaFakeServer();
      final response = await _get(server, '/pleya/v1/server', token: 'wrong');
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 401);
      expect((body['error'] as Map)['code'], 'auth.invalid_token');
    });

    test('POST /auth/refresh mints a rotating token pair', () async {
      final server = PleyaFakeServer();
      final request = http.Request('POST', Uri.parse('http://fixture/pleya/v1/auth/refresh'));
      final response = await server.handle(request);
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['access_token'], 'at-1');
      expect(body['refresh_token'], 'rt-2');
    });

    test('a library item list paginates via an opaque cursor', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/libraries/lib-1/items');
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect((body['items'] as List).single, containsPair('id', 'item-1'));
      expect(body['next_cursor'], isNull);
    });

    test('an unknown library id 404s with library.not_found', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/libraries/does-not-exist/items');
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 404);
      expect((body['error'] as Map)['code'], 'library.not_found');
    });

    test('unreachable throws PleyaFakeServerUnreachable instead of answering', () async {
      final server = PleyaFakeServer()..unreachable = true;
      final request = http.Request('GET', Uri.parse('http://fixture/pleya/v1/info'));
      await expectLater(() => server.handle(request), throwsA(isA<PleyaFakeServerUnreachable>()));
    });

    test('reset() clears fixture data and mutable flags back to fresh', () async {
      final server = _serverWithOneLibrary();
      await _get(server, '/pleya/v1/info');
      server
        ..rejectCurrentAccessTokens = true
        ..refreshCount = 5;

      server.reset();

      expect(server.items, isEmpty);
      expect(server.libraries, isEmpty);
      expect(server.requests, isEmpty);
      expect(server.unreachable, isFalse);
      expect(server.rejectCurrentAccessTokens, isFalse);
      expect(server.refreshCount, 0);
    });
  });

  group('determinism', () {
    test('two fresh servers given the same requests answer byte-identically', () async {
      final serverA = _serverWithOneLibrary();
      final serverB = _serverWithOneLibrary();

      final infoA = await _get(serverA, '/pleya/v1/info');
      final infoB = await _get(serverB, '/pleya/v1/info');
      expect(infoA.body, infoB.body);

      final itemA = await _get(serverA, '/pleya/v1/items/item-1');
      final itemB = await _get(serverB, '/pleya/v1/items/item-1');
      expect(itemA.body, itemB.body);
    });

    test('no wall-clock time leaks into a response', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/items/item-1');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // Fixed fixture timestamp, not DateTime.now() — see addedAt default.
      expect(body['added_at'], '2026-06-18T21:34:02Z');
    });
  });
}
