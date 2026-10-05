import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/tmdb_fake_server.dart';
import 'package:test/test.dart';

Future<http.Response> _get(TmdbFakeServer server, String path, {String? key}) =>
    server.handle(http.Request('GET', Uri.parse('http://fixture$path').replace(queryParameters: {'api_key': ?key})));

void main() {
  test('a missing or wrong key is rejected', () async {
    final server = TmdbFakeServer(apiKey: 'k');
    expect((await _get(server, '/tmdb/3/trending/movie/week')).statusCode, 401);
    expect((await _get(server, '/tmdb/3/trending/movie/week', key: 'x')).statusCode, 401);
  });

  test('movie and tv trending together hold eight titles, the library ones first', () async {
    final server = TmdbFakeServer();
    final movie = jsonDecode((await _get(server, '/tmdb/3/trending/movie/week', key: 'verify-tmdb-key')).body);
    final tv = jsonDecode((await _get(server, '/tmdb/3/trending/tv/week', key: 'verify-tmdb-key')).body);
    final titles = [for (final r in movie['results']) r['title'], for (final r in tv['results']) r['name']];
    expect(titles.length, 8);
    expect(titles.take(3), ['Aurora', 'Basalt', 'Cascade']);
    expect(titles, contains('Driftwood'));
    expect(movie['results'].first['release_date'], '2021-03-01');
  });

  test('another route is a 404', () async {
    expect((await _get(TmdbFakeServer(), '/tmdb/3/search/multi', key: 'verify-tmdb-key')).statusCode, 404);
  });
}
