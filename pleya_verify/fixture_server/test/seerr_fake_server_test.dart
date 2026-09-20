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
