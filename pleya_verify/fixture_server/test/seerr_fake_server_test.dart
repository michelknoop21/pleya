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

  test('a seeded request round-trips with its embedded media', () async {
    final server = SeerrFakeServer(apiKey: 'verify-key');
    server.addRequest(id: 1, mediaType: 'movie', tmdbId: 101, title: 'Aurora Drift', year: 2024, status: 1);

    final counts = await _get(server, '/seerr/api/v1/request/count', apiKey: 'verify-key');
    expect(jsonDecode(counts.body), containsPair('pending', 1));

    final list = await _get(server, '/seerr/api/v1/request', apiKey: 'verify-key', query: const {'filter': 'all'});
    final results = jsonDecode(list.body)['results'] as List;
    expect(results, hasLength(1));
    expect(results.single['media']['title'], 'Aurora Drift');
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
