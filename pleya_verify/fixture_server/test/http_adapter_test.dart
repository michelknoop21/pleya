import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_fixture_server/http_adapter.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:test/test.dart';

void main() {
  late FixtureHttpServer adapter;
  late PleyaFakeServer server;
  late String controlToken;

  setUp(() async {
    server = PleyaFakeServer();
    controlToken = FixtureHttpServer.generateControlToken();
    adapter = FixtureHttpServer(server: server, controlToken: controlToken);
    await adapter.start();
  });

  tearDown(() async {
    await adapter.stop();
  });

  Future<HttpClientResponse> verify(String method, String path, {Object? body, String? token}) async {
    final client = HttpClient();
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${adapter.port}$path'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${token ?? controlToken}');
    if (body != null) request.write(jsonEncode(body));
    return request.close();
  }

  Future<HttpClientResponse> pleyaApi(String method, String path, {Object? body, String? bearer}) async {
    final client = HttpClient();
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${adapter.port}/pleya/v1$path'));
    if (bearer != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    if (body != null) request.write(jsonEncode(body));
    return request.close();
  }

  Future<Map<String, dynamic>> jsonBody(HttpClientResponse response) async {
    final raw = await utf8.decoder.bind(response).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  group('/__verify/* control-plane auth', () {
    test('a missing Authorization header is rejected with 401', () async {
      final client = HttpClient();
      final request = await client.openUrl('POST', Uri.parse('http://127.0.0.1:${adapter.port}/__verify/reset'));
      final response = await request.close();
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('the wrong bearer token is rejected with 401', () async {
      final response = await verify('POST', '/__verify/reset', token: 'not-the-control-token');
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('the correct control token is accepted', () async {
      final response = await verify('POST', '/__verify/reset');
      expect(response.statusCode, HttpStatus.ok);
    });

    test('the control token is never accepted on /pleya/v1/*, and vice versa', () async {
      // The control token is not a Pleya access token — /info doesn't need
      // auth so this proves nothing there; /server does.
      final response = await pleyaApi('GET', '/server', bearer: controlToken);
      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('/pleya/v1/* passthrough', () {
    test('GET /info reaches the wrapped PleyaFakeServer and answers unauthenticated', () async {
      final response = await pleyaApi('GET', '/info');
      final body = await jsonBody(response);
      expect(response.statusCode, HttpStatus.ok);
      expect(body['protocol'], {'major': 1, 'feature_level': 1, 'profile': 'full'});
    });

    test('an unreachable server answers 502 instead of hanging or crashing the adapter', () async {
      server.unreachable = true;
      final response = await pleyaApi('GET', '/info');
      expect(response.statusCode, HttpStatus.badGateway);
    });
  });

  group('/__verify/seed', () {
    test('a known fixture name seeds the server and reports back which one', () async {
      final response = await verify('POST', '/__verify/seed', body: {'fixture': 'catalog.shows.v1'});
      final body = await jsonBody(response);
      expect(response.statusCode, HttpStatus.ok);
      expect(body, {'ok': true, 'fixture': 'catalog.shows.v1'});
      expect(server.libraries, isNotEmpty);
    });

    test('an unknown fixture name 400s without mutating the server', () async {
      final response = await verify('POST', '/__verify/seed', body: {'fixture': 'catalog.nope'});
      expect(response.statusCode, HttpStatus.badRequest);
      expect(server.libraries, isEmpty);
    });
  });

  group('/__verify/echo', () {
    test('hands the posted body back verbatim, merged under ok: true', () async {
      final response = await verify(
        'POST',
        '/__verify/echo',
        body: {
          'nested': {'oldPassword': 'hunter2'},
        },
      );
      final body = await jsonBody(response);
      expect(response.statusCode, HttpStatus.ok);
      expect(body, {
        'ok': true,
        'nested': {'oldPassword': 'hunter2'},
      });
    });
  });

  group('/__verify/add_episode', () {
    test('appends an episode under a seeded season and is reflected on /items/{id}/children', () async {
      await verify('POST', '/__verify/seed', body: {'fixture': 'catalog.shows.v1'});
      final season = server.items.values.singleWhere((i) => i['kind'] == 'season');

      final addResponse = await verify('POST', '/__verify/add_episode', body: {'parent_id': season['id']});
      final addBody = await jsonBody(addResponse);
      expect(addResponse.statusCode, HttpStatus.ok);
      expect(addBody['ok'], true);

      final childrenResponse = await pleyaApi('GET', '/items/${season['id']}/children', bearer: 'at-0');
      final childrenBody = await jsonBody(childrenResponse);
      expect(childrenBody['total_estimate'], 11);
    });

    test('an unknown parent_id 404s', () async {
      final response = await verify('POST', '/__verify/add_episode', body: {'parent_id': 'does-not-exist'});
      expect(response.statusCode, HttpStatus.notFound);
    });
  });

  group('/__verify/mark_watched', () {
    test('an unknown item_id 404s', () async {
      final response = await verify('POST', '/__verify/mark_watched', body: {'item_id': 'does-not-exist'});
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('a known item is marked watched and visible through the real Pleya API', () async {
      await verify('POST', '/__verify/seed', body: {'fixture': 'catalog.shows.v1'});
      final episode = server.items.values.firstWhere((i) => i['kind'] == 'episode');

      final markResponse = await verify('POST', '/__verify/mark_watched', body: {'item_id': episode['id']});
      expect(markResponse.statusCode, HttpStatus.ok);

      final stateResponse = await pleyaApi('GET', '/watch-state', bearer: 'at-0');
      final stateBody = await jsonBody(stateResponse);
      final entry = (stateBody['items'] as List).cast<Map<String, dynamic>>().singleWhere(
        (e) => e['item_id'] == episode['id'],
      );
      expect(entry['state']['watched'], isTrue);
    });
  });

  test('/__verify/expire_session forces the next access-token check to fail', () async {
    // A first successful call establishes the at-0 token is currently valid.
    final before = await pleyaApi('GET', '/server', bearer: 'at-0');
    expect(before.statusCode, HttpStatus.ok);

    final expireResponse = await verify('POST', '/__verify/expire_session');
    expect(expireResponse.statusCode, HttpStatus.ok);

    final after = await pleyaApi('GET', '/server', bearer: 'at-0');
    expect(after.statusCode, HttpStatus.unauthorized);
  });

  test('/__verify/fail_next queues exactly one failure for the real HTTP path', () async {
    final failResponse = await verify(
      'POST',
      '/__verify/fail_next',
      body: {'status': 503, 'error_code': 'storage.unavailable'},
    );
    expect(failResponse.statusCode, HttpStatus.ok);

    final first = await pleyaApi('GET', '/info');
    expect(first.statusCode, 503);

    final second = await pleyaApi('GET', '/info');
    expect(second.statusCode, HttpStatus.ok);
  });

  test('/__verify/latency adds real, measurable delay to the next response', () async {
    final latencyResponse = await verify('POST', '/__verify/latency', body: {'ms': 40, 'count': 1});
    expect(latencyResponse.statusCode, HttpStatus.ok);

    final stopwatch = Stopwatch()..start();
    await pleyaApi('GET', '/info');
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(35));
  });

  group('GET /pleya/v1/stream/{version_id} through the real HTTP server', () {
    test('a Range request returns 206 with the correct Content-Range over real dart:io headers', () async {
      await verify('POST', '/__verify/seed', body: {'fixture': 'catalog.shows.v1'});
      final episode = server.items.values.firstWhere((i) => i['kind'] == 'episode');
      final versionId = (episode['versions'] as List).cast<Map<String, dynamic>>().single['id'] as String;

      final client = HttpClient();
      final request = await client.openUrl(
        'GET',
        Uri.parse('http://127.0.0.1:${adapter.port}/pleya/v1/stream/$versionId'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer at-0');
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-9');
      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));

      expect(response.statusCode, 206);
      expect(bytes, hasLength(10));
      expect(response.headers.value('content-range'), startsWith('bytes 0-9/'));
    });
  });

  group('/__verify/requests and /__verify/state', () {
    test('requests accumulates real Pleya API traffic, observable via the control plane', () async {
      await pleyaApi('GET', '/info');
      await pleyaApi('GET', '/info');

      final response = await verify('GET', '/__verify/requests');
      final body = await jsonBody(response);
      expect((body['requests'] as List).length, 2);
      expect(body['total'], 2);
    });

    test('state reports the setup code alongside counts and the snapshot hash', () async {
      final response = await verify('GET', '/__verify/state');
      final body = await jsonBody(response);
      expect(body['setupCode'], server.setupCode);
      expect(body['snapshotHash'], isA<String>());
    });

    test('reset clears both the fixture data and the accumulated request log', () async {
      await verify('POST', '/__verify/seed', body: {'fixture': 'catalog.shows.v1'});
      await pleyaApi('GET', '/info');

      final resetResponse = await verify('POST', '/__verify/reset');
      expect(resetResponse.statusCode, HttpStatus.ok);

      final stateResponse = await verify('GET', '/__verify/state');
      final stateBody = await jsonBody(stateResponse);
      expect(stateBody['libraryCount'], 0);
      expect(stateBody['requestCount'], 0);
    });
  });

  test('a request to an unknown /__verify/* path 404s', () async {
    final response = await verify('GET', '/__verify/does-not-exist');
    expect(response.statusCode, HttpStatus.notFound);
  });
}
