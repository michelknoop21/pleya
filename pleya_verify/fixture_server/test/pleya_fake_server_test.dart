import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:pleya_verify_fixture_server/src/fixtures/sample_media.dart';
import 'package:test/test.dart';

PleyaFakeServer _serverWithOneLibrary() {
  final server = PleyaFakeServer();
  server.addLibrary(id: 'lib-1', title: 'Films', kind: 'movie', itemCount: 1);
  server.addItem(id: 'item-1', kind: 'movie', title: 'Sintel', libraryId: 'lib-1', year: 2010, durationMs: 888000);
  return server;
}

Future<http.Response> _get(PleyaFakeServer server, String path, {String token = 'at-0', Map<String, String>? headers}) {
  final request = http.Request('GET', Uri.parse('http://fixture$path'));
  request.headers['Authorization'] = 'Bearer $token';
  headers?.forEach((key, value) => request.headers[key] = value);
  return server.handle(request);
}

Future<http.Response> _post(PleyaFakeServer server, String path, Object body, {String? token}) {
  final request = http.Request('POST', Uri.parse('http://fixture$path'));
  if (token != null) request.headers['Authorization'] = 'Bearer $token';
  request.body = jsonEncode(body);
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

  group('auth: login and setup', () {
    test('POST /auth/setup creates the owner, mints tokens, and flips setup_required off', () async {
      final server = PleyaFakeServer(setupRequired: true);
      final response = await _post(server, '/pleya/v1/auth/setup', {
        'setup_code': server.setupCode,
        'username': 'michel',
        'password': 'hunter22',
      });
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['access_token'], 'at-1');
      expect(server.setupRequired, isFalse);
    });

    test('a second /auth/setup call after the owner exists is rejected with auth.setup_already_done', () async {
      final server = PleyaFakeServer(setupRequired: true);
      await _post(server, '/pleya/v1/auth/setup', {
        'setup_code': server.setupCode,
        'username': 'michel',
        'password': 'hunter22',
      });
      final response = await _post(server, '/pleya/v1/auth/setup', {
        'setup_code': server.setupCode,
        'username': 'other',
        'password': 'irrelevant1',
      });
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 409);
      expect((body['error'] as Map)['code'], 'auth.setup_already_done');
    });

    test('a wrong setup_code is rejected without creating an owner', () async {
      final server = PleyaFakeServer(setupRequired: true);
      final response = await _post(server, '/pleya/v1/auth/setup', {
        'setup_code': 'WRONG-CODE',
        'username': 'michel',
        'password': 'hunter22',
      });

      expect(response.statusCode, 401);
      expect(server.setupRequired, isTrue);
    });

    test('POST /auth/login succeeds for a registered credential and 401s otherwise', () async {
      final server = PleyaFakeServer(setupRequired: true);
      await _post(server, '/pleya/v1/auth/setup', {
        'setup_code': server.setupCode,
        'username': 'michel',
        'password': 'hunter22',
      });

      final good = await _post(server, '/pleya/v1/auth/login', {'username': 'michel', 'password': 'hunter22'});
      expect(good.statusCode, 200);
      expect(jsonDecode(good.body)['access_token'], isNotNull);

      final bad = await _post(server, '/pleya/v1/auth/login', {'username': 'michel', 'password': 'wrong'});
      final badBody = jsonDecode(bad.body) as Map<String, dynamic>;
      expect(bad.statusCode, 401);
      expect((badBody['error'] as Map)['code'], 'auth.invalid_credentials');
    });

    test('reset() forgets registered credentials and restores the constructor setup_required', () async {
      final server = PleyaFakeServer(setupRequired: true);
      await _post(server, '/pleya/v1/auth/setup', {
        'setup_code': server.setupCode,
        'username': 'michel',
        'password': 'hunter22',
      });
      expect(server.setupRequired, isFalse);

      server.reset();

      expect(server.setupRequired, isTrue);
      final loginAfterReset = await _post(server, '/pleya/v1/auth/login', {
        'username': 'michel',
        'password': 'hunter22',
      });
      expect(loginAfterReset.statusCode, 401, reason: 'the credential from before reset() must not survive it');
    });
  });

  group('control-plane mutations (kernel)', () {
    test('addEpisode appends under an existing parent and keeps child/episode counts in sync', () {
      final server = PleyaFakeServer();
      server.addItem(id: 'season-1', kind: 'season', title: 'Season 1', childCount: 10, episodeCount: 10);
      for (var i = 1; i <= 10; i++) {
        server.addItem(id: 'ep-$i', kind: 'episode', title: 'E$i', parentId: 'season-1', index: i, durationMs: 1000);
      }

      final newId = server.addEpisode(parentId: 'season-1');

      expect(newId, isNotNull);
      expect(server.children['season-1'], hasLength(11));
      expect(server.items['season-1']!['child_count'], 11);
      expect(server.items['season-1']!['episode_count'], 11);
      expect(server.versionBytes.containsKey('$newId-v1'), isTrue, reason: 'the new episode must be playable too');
    });

    test('addEpisode against an unknown parent id returns null and mutates nothing', () {
      final server = PleyaFakeServer();
      expect(server.addEpisode(parentId: 'does-not-exist'), isNull);
      expect(server.items, isEmpty);
    });

    test('markWatched sets watched with the item duration as position_ms', () {
      final server = _serverWithOneLibrary();
      server.markWatched('item-1');
      expect(server.watchStates['item-1']!['watched'], isTrue);
      expect(server.watchStates['item-1']!['position_ms'], 888000);
    });
  });

  group('fault injection', () {
    test('queueFailure fails exactly the next matching request, then reverts to normal', () async {
      final server = _serverWithOneLibrary();
      server.queueFailure(status: 503, errorCode: 'storage.unavailable');

      final first = await _get(server, '/pleya/v1/info');
      expect(first.statusCode, 503);
      expect((jsonDecode(first.body)['error'] as Map)['code'], 'storage.unavailable');

      final second = await _get(server, '/pleya/v1/info');
      expect(second.statusCode, 200, reason: 'fail_next is one-shot');
    });

    test('a pathPrefix on queueFailure only matches requests under that prefix', () async {
      final server = _serverWithOneLibrary();
      server.queueFailure(pathPrefix: '/libraries', status: 500, errorCode: 'x');

      final info = await _get(server, '/pleya/v1/info');
      expect(info.statusCode, 200);

      final libraries = await _get(server, '/pleya/v1/libraries');
      expect(libraries.statusCode, 500);
    });

    test('queueLatency delays exactly the configured number of responses', () async {
      final server = _serverWithOneLibrary();
      server.queueLatency(const Duration(milliseconds: 30), count: 2);

      final stopwatch = Stopwatch()..start();
      await _get(server, '/pleya/v1/info');
      await _get(server, '/pleya/v1/info');
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(55));

      final unaffected = Stopwatch()..start();
      await _get(server, '/pleya/v1/info');
      unaffected.stop();
      expect(unaffected.elapsedMilliseconds, lessThan(20));
    });
  });

  group('GET /artwork/{id}', () {
    test('falls back to the shared bytes when no per-id override was registered', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/artwork/whatever');
      expect(response.bodyBytes, server.artworkBytes);
    });

    test('serves the registered per-id override instead of the shared bytes', () async {
      final server = _serverWithOneLibrary();
      server.artworkById['item-1'] = [1, 2, 3, 4];
      final response = await _get(server, '/pleya/v1/artwork/item-1');
      expect(response.bodyBytes, [1, 2, 3, 4]);
    });
  });

  group('GET /stream/{version_id}', () {
    test('a full request without Range returns 200 with Accept-Ranges and a weak ETag', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/item-1-v1');

      expect(response.statusCode, 200);
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.headers['etag'], startsWith('W/"'));
      expect(response.bodyBytes, sampleMediaMp4Bytes);
    });

    test('a single Range request returns 206 with the requested slice and Content-Range', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/item-1-v1', headers: {'Range': 'bytes=0-9'});

      expect(response.statusCode, 206);
      expect(response.bodyBytes, sampleMediaMp4Bytes.sublist(0, 10));
      expect(response.headers['content-range'], 'bytes 0-9/${sampleMediaMp4Bytes.length}');
    });

    test('a suffix Range request returns the last N bytes', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/item-1-v1', headers: {'Range': 'bytes=-10'});

      expect(response.statusCode, 206);
      expect(response.bodyBytes, sampleMediaMp4Bytes.sublist(sampleMediaMp4Bytes.length - 10));
    });

    test('a multi-range Range header falls back to the full file as 200 — the documented fallback', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/item-1-v1', headers: {'Range': 'bytes=0-9,20-29'});

      expect(response.statusCode, 200);
      expect(response.bodyBytes, sampleMediaMp4Bytes);
    });

    test('a well-formed but out-of-bounds range 416s with playback.range_not_satisfiable', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/item-1-v1', headers: {'Range': 'bytes=999999999-'});

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(response.statusCode, 416);
      expect((body['error'] as Map)['code'], 'playback.range_not_satisfiable');
    });

    test('a present If-Range makes the server ignore Range and answer the full file as 200', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(
        server,
        '/pleya/v1/stream/item-1-v1',
        headers: {'Range': 'bytes=0-9', 'If-Range': '"some-etag"'},
      );

      expect(response.statusCode, 200);
      expect(response.bodyBytes, sampleMediaMp4Bytes);
    });

    test('an unknown version id 404s with library.not_found', () async {
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/does-not-exist-v1');
      expect(response.statusCode, 404);
    });

    test('a reversed range (start > end) 416s instead of an empty body or a crash', () async {
      // A reversal of exactly 1 byte used to compute an empty sublist
      // silently instead of erroring: start == end + 1 trivially satisfies
      // sublist's start <= end requirement.
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/item-1-v1', headers: {'Range': 'bytes=2-1'});

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(response.statusCode, 416);
      expect((body['error'] as Map)['code'], 'playback.range_not_satisfiable');
    });

    test('a larger reversed range 416s instead of throwing an uncaught RangeError', () async {
      // bytes=5-2 computes sublist(5, 3): start(5) > end(3) throws a raw
      // RangeError from List.sublist, uncaught by the existing
      // _RangeNotSatisfiable handler — a 500-shaped crash, not the
      // documented 416.
      final server = _serverWithOneLibrary();
      final response = await _get(server, '/pleya/v1/stream/item-1-v1', headers: {'Range': 'bytes=5-2'});

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(response.statusCode, 416);
      expect((body['error'] as Map)['code'], 'playback.range_not_satisfiable');
    });
  });
}
