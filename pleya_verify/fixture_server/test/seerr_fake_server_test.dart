import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/seerr_fake_server.dart';
import 'package:test/test.dart';

Future<http.Response> _get(SeerrFakeServer server, String path, {String? apiKey, Map<String, String>? query}) {
  final uri = Uri.parse('http://fixture$path').replace(queryParameters: query);
  final request = http.Request('GET', uri);
  if (apiKey != null) request.headers['x-api-key'] = apiKey;
  return server.handle(request);
}

void main() {
  group('request routes', requestRouteTests);

  test('a missing or wrong api key is rejected', () async {
    final server = SeerrFakeServer(apiKey: 'the-real-key');

    final missing = await _get(server, '/seerr/api/v1/status');
    expect(missing.statusCode, 401);

    final wrong = await _get(server, '/seerr/api/v1/status', apiKey: 'wrong');
    expect(wrong.statusCode, 401);
  });

  test('status and auth/me answer with the right api key', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');

    final status = await _get(server, '/seerr/api/v1/status', apiKey: 'verify-key');
    expect(status.statusCode, 200);
    expect(jsonDecode(status.body)['version'], isA<String>());

    final me = await _get(server, '/seerr/api/v1/auth/me', apiKey: 'verify-key');
    expect(jsonDecode(me.body), {'id': 1, 'displayName': 'verify-admin', 'permissions': 2});
  });

  test('search answers the seeded titles that contain the query, and nothing for an empty one', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addSearchItem(tmdbId: 401, mediaType: 'movie', title: 'Ashfall', year: 2023);
    server.addSearchItem(tmdbId: 402, mediaType: 'tv', title: 'Glass Harbor', year: 2022);
    server.addSearchItem(tmdbId: 403, mediaType: 'movie', title: 'Tundra');

    Future<List<Object?>> titles(String query) async {
      final response = await _get(server, '/seerr/api/v1/search', apiKey: 'verify-key', query: {'query': query});
      return [for (final row in jsonDecode(response.body)['results'] as List) row['title'] ?? row['name']];
    }

    expect(await titles('AS'), ['Ashfall', 'Glass Harbor']);
    expect(await titles('tundra'), ['Tundra']);
    expect(await titles(''), isEmpty);
  });

  test('a 4K instance is listed only when the fixture says the server has one', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');

    Future<List<Object?>> qualities(String kind) async {
      final response = await _get(server, '/seerr/api/v1/service/$kind', apiKey: 'verify-key');
      return [for (final row in jsonDecode(response.body) as List) row['is4k']];
    }

    expect(await qualities('radarr'), [false]);
    expect((await _get(server, '/seerr/api/v1/service/radarr/1', apiKey: 'verify-key')).statusCode, 404);

    server.fourKServers = true;
    expect(await qualities('radarr'), [false, true]);
    expect(await qualities('sonarr'), [false, true]);
    final detail = await _get(server, '/seerr/api/v1/service/radarr/1', apiKey: 'verify-key');
    expect(jsonDecode(detail.body)['profiles'].single['name'], 'Ultra-HD');

    server.reset();
    expect(await qualities('radarr'), [false]);
  });

  test('a seeded title keeps its HD and 4K status apart', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addTitle(mediaType: 'movie', tmdbId: 301, title: 'Glacier Run', status: 5, status4k: 1);
    server.addTitle(mediaType: 'movie', tmdbId: 302, title: 'Never Seen');

    final known = jsonDecode((await _get(server, '/seerr/api/v1/movie/301', apiKey: 'verify-key')).body) as Map;
    expect(known['mediaInfo'], containsPair('status', 5));
    expect(known['mediaInfo'], containsPair('status4k', 1));
    final unseen = jsonDecode((await _get(server, '/seerr/api/v1/movie/302', apiKey: 'verify-key')).body) as Map;
    expect(unseen.containsKey('mediaInfo'), isFalse);
  });

  test('a seeded request comes back without its title, like real Overseerr', () async {
    // The title/poster a caller passes to addRequest must not leak straight
    // onto the request row — SeerrClient.needsDisplayData only ever fires the
    // /movie or /tv hydration round-trip when the row itself lacks them, and a
    // fixture that skips that round-trip cannot catch a regression in it.
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addRequest(id: 1, mediaType: 'movie', tmdbId: 101, title: 'Aurora Drift', year: 2024, status: 1);

    final counts = await _get(server, '/seerr/api/v1/request/count', apiKey: 'verify-key');
    expect(jsonDecode(counts.body), containsPair('pending', 1));

    final list = await _get(server, '/seerr/api/v1/request', apiKey: 'verify-key', query: const {'filter': 'all'});
    final results = jsonDecode(list.body)['results'] as List;
    expect(results, hasLength(1));
    final media = results.single['media'] as Map;
    expect(media.containsKey('title'), isFalse);
    expect(media.containsKey('posterPath'), isFalse);
    expect(media['tmdbId'], 101);
  });

  test('request listing honors take and skip', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    for (var id = 1; id <= 5; id++) {
      server.addRequest(id: id, mediaType: 'movie', tmdbId: 100 + id, title: 'Request $id');
    }

    final response = await _get(
      server,
      '/seerr/api/v1/request',
      apiKey: 'verify-key',
      query: const {'filter': 'all', 'take': '2', 'skip': '2'},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List;

    expect(results.map((item) => item['id']), [3, 4]);
    expect(body['pageInfo'], {'pages': 3});
  });

  test('the title a request was seeded with answers the hydration round-trip', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addRequest(
      id: 1,
      mediaType: 'movie',
      tmdbId: 101,
      title: 'Aurora Drift',
      year: 2024,
      posterPath: '/aurora.jpg',
    );

    final movie = await _get(server, '/seerr/api/v1/movie/101', apiKey: 'verify-key');
    final body = jsonDecode(movie.body) as Map<String, dynamic>;
    expect(body['title'], 'Aurora Drift');
    expect(body['releaseDate'], '2024-01-01');
    expect(body['posterPath'], '/aurora.jpg');
  });

  test('a tv request hydrates through name/firstAirDate, not title/releaseDate', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addRequest(id: 2, mediaType: 'tv', tmdbId: 202, title: 'Basalt Coast', year: 2023);

    final tv = await _get(server, '/seerr/api/v1/tv/202', apiKey: 'verify-key');
    final body = jsonDecode(tv.body) as Map<String, dynamic>;
    expect(body['name'], 'Basalt Coast');
    expect(body['firstAirDate'], '2023-01-01');
  });

  test('an id with no registered request is a 404, not a stale fixture default', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    final response = await _get(server, '/seerr/api/v1/movie/999', apiKey: 'verify-key');
    expect(response.statusCode, 404);
  });

  test('a discover bucket answers a page of results the client can parse', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addDiscoverItem('trending', tmdbId: 2001, mediaType: 'movie', title: 'Ember Field', year: 2025);

    final response = await _get(server, '/seerr/api/v1/discover/trending', apiKey: 'verify-key');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['results'], hasLength(1));
    expect(body['results'][0]['title'], 'Ember Field');
  });

  test('reset clears requests and every discover bucket', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addRequest(id: 1, mediaType: 'movie', tmdbId: 101, title: 'Aurora Drift');
    server.addDiscoverItem('trending', tmdbId: 2001, mediaType: 'movie', title: 'Ember Field');

    server.reset();

    expect(server.requests, isEmpty);
    expect(server.discover.values.every((bucket) => bucket.isEmpty), isTrue);
  });
}

Future<http.Response> _send(SeerrFakeServer server, String method, String path, {Object? body}) {
  final request = http.Request(method, Uri.parse('http://fixture/seerr/api/v1$path'));
  request.headers['x-api-key'] = 'verify-key';
  if (body != null) request.body = jsonEncode(body);
  return server.handle(request);
}

/// The request routes mirror seerr-team/seerr `server/routes/request.ts`
/// (develop at 53e45647). These hold the fixture to the parts of that source a
/// scenario must not be able to pass around.
void requestRouteTests() {
  SeerrFakeServer seeded() => SeerrFakeServer(apiKey: 'verify-key')
    ..addRequest(
      id: 1,
      mediaType: 'tv',
      tmdbId: 201,
      title: 'Fjord Line',
      seasons: const [3, 4, 5],
      seasonCount: 5,
      serverId: 0,
      profileId: 1,
      rootFolder: '/media',
    )
    ..addRequest(id: 2, mediaType: 'movie', tmdbId: 202, title: 'Gantry Road', status: 3)
    ..addRequest(id: 3, mediaType: 'movie', tmdbId: 203, title: 'Harbor Light', status: 2);

  test('stored advanced fields are explicit even when unconfigured', () async {
    final server = seeded();
    final row = jsonDecode((await _send(server, 'GET', '/request/1')).body) as Map;
    expect(row.containsKey('tags'), isTrue);
    expect(row['tags'], isNull);
    expect(row.containsKey('languageProfileId'), isTrue);
    expect(row['languageProfileId'], isNull);
    final created =
        jsonDecode((await _send(server, 'POST', '/request', body: {'mediaType': 'movie', 'mediaId': 999})).body) as Map;
    expect(created.containsKey('tags'), isTrue);
    expect(created.containsKey('languageProfileId'), isTrue);
  });

  test('a declined filter is not a case in the route and answers with every status', () async {
    final server = seeded();
    final list = await _get(server, '/seerr/api/v1/request', apiKey: 'verify-key', query: const {'filter': 'declined'});
    final statuses = (jsonDecode(list.body)['results'] as List).map((r) => r['status']).toSet();
    expect(statuses, {1, 2, 3});
  });

  test('PUT without a mediaType saves nothing and still answers 200', () async {
    final server = seeded();
    final response = await _send(
      server,
      'PUT',
      '/request/1',
      body: {
        'seasons': [1],
      },
    );
    expect(response.statusCode, 200);
    expect((jsonDecode(response.body)['seasons'] as List).map((s) => s['seasonNumber']), [3, 4, 5]);
  });

  test('PUT never reads is4k, and clears a target the body leaves out', () async {
    final server = seeded();
    final response = await _send(
      server,
      'PUT',
      '/request/1',
      body: {
        'mediaType': 'tv',
        'is4k': true,
        'seasons': [3],
      },
    );
    final row = jsonDecode(response.body) as Map;
    expect(row['is4k'], isFalse);
    expect(row['serverId'], isNull, reason: 'the route assigns req.body.serverId unconditionally');
    expect((row['seasons'] as List).map((s) => s['seasonNumber']), [3]);
  });

  test('only a pending request can be changed or decided', () async {
    final server = seeded();
    expect((await _send(server, 'PUT', '/request/3', body: {'mediaType': 'movie'})).statusCode, 409);
    expect((await _send(server, 'POST', '/request/3/approve')).statusCode, 409);
    expect((await _send(server, 'POST', '/request/1/approve')).statusCode, 200);
    expect(jsonDecode((await _send(server, 'GET', '/request/1')).body)['status'], 2);
  });

  test('DELETE removes the request, and a second request for the same title is a 409', () async {
    final server = seeded();
    expect((await _send(server, 'DELETE', '/request/1')).statusCode, 204);
    expect((await _send(server, 'GET', '/request/1')).statusCode, 404);
    expect((await _send(server, 'POST', '/request', body: {'mediaType': 'movie', 'mediaId': 203})).statusCode, 409);
  });
}
