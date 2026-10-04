import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/services/tmdb/tmdb_client.dart';

const _bearer = 'eyJhbGciOiJIUzI1NiJ9.test.sig';
const _v3Key = 'abc123v3key';

({TmdbClient client, List<http.Request> requests}) _client(
  String token, {
  int status = 200,
  Object body = const {'results': []},
}) {
  final requests = <http.Request>[];
  final mock = MockClient((req) async {
    requests.add(req);
    return http.Response(jsonEncode(body), status);
  });
  return (client: TmdbClient(token, httpClient: mock), requests: requests);
}

void main() {
  test('v4 read token goes as Bearer header without api_key', () async {
    final c = _client(_bearer);
    await c.client.trending(TmdbKind.movie);
    final req = c.requests.single;
    expect(req.headers['Authorization'], 'Bearer $_bearer');
    expect(req.url.queryParameters.containsKey('api_key'), isFalse);
  });

  test('v3 key goes as api_key query without Authorization', () async {
    final c = _client(_v3Key);
    await c.client.trending(TmdbKind.tv);
    final req = c.requests.single;
    expect(req.url.queryParameters['api_key'], _v3Key);
    expect(req.headers.containsKey('Authorization'), isFalse);
  });

  test('details asks append_to_response per kind and returns the appended blocks', () async {
    final c = _client(
      _bearer,
      body: {
        'id': 11,
        'title': 'Star Wars',
        'release_dates': {
          'results': [
            {
              'iso_3166_1': 'NL',
              'release_dates': [
                {'certification': '12'},
              ],
            },
          ],
        },
        'credits': {
          'cast': [
            {'name': 'Mark Hamill'},
          ],
        },
        'watch/providers': {
          'results': {
            'NL': {
              'flatrate': [
                {'provider_name': 'Disney Plus'},
              ],
            },
          },
        },
        'external_ids': {'imdb_id': 'tt0076759'},
      },
    );
    final movie = await c.client.details(TmdbKind.movie, 11, language: 'nl-NL');
    final url = c.requests.single.url;
    expect(url.path, '/3/movie/11');
    expect(url.queryParameters['append_to_response'], 'release_dates,credits,watch/providers,external_ids');
    expect(url.queryParameters['language'], 'nl-NL');
    expect((movie['external_ids'] as Map)['imdb_id'], 'tt0076759');
    expect(((movie['watch/providers'] as Map)['results'] as Map).containsKey('NL'), isTrue);
    expect(((movie['credits'] as Map)['cast'] as List).single['name'], 'Mark Hamill');

    final tv = _client(_bearer, body: {'id': 1396});
    await tv.client.details(TmdbKind.tv, 1396);
    final tvUrl = tv.requests.single.url;
    expect(tvUrl.path, '/3/tv/1396');
    expect(tvUrl.queryParameters['append_to_response'], 'content_ratings,credits,watch/providers,external_ids');
    expect(tvUrl.queryParameters.containsKey('language'), isFalse);
  });

  test('401 throws TmdbAuthException, other errors TmdbException', () async {
    await expectLater(
      _client(_bearer, status: 401, body: {'status_code': 7}).client.trending(TmdbKind.movie),
      throwsA(isA<TmdbAuthException>()),
    );
    await expectLater(
      _client(_bearer, status: 500, body: {}).client.trending(TmdbKind.movie),
      throwsA(isA<TmdbException>().having((e) => e.statusCode, 'statusCode', 500)),
    );
  });

  test('trending, similar, recommendations and find hit the right paths', () async {
    final c = _client(
      _bearer,
      body: {
        'results': [
          {'id': 1},
        ],
        'movie_results': [],
      },
    );
    expect(await c.client.trending(TmdbKind.movie), [
      {'id': 1},
    ]);
    await c.client.similar(TmdbKind.tv, 5);
    await c.client.recommendations(TmdbKind.movie, 6);
    await c.client.findByExternal('tt0076759', 'imdb_id');
    final urls = c.requests.map((r) => r.url).toList();
    expect(urls[0].path, '/3/trending/movie/week');
    expect(urls[1].path, '/3/tv/5/similar');
    expect(urls[2].path, '/3/movie/6/recommendations');
    expect(urls[3].path, '/3/find/tt0076759');
    expect(urls[3].queryParameters['external_source'], 'imdb_id');
    expect(urls.every((u) => u.host == 'api.themoviedb.org'), isTrue);
  });

  test('searchMulti filters on year client-side', () async {
    final c = _client(
      _bearer,
      body: {
        'results': [
          {'id': 1, 'release_date': '1977-05-25'},
          {'id': 2, 'first_air_date': '1977-01-01'},
          {'id': 3, 'release_date': '2019-12-18'},
          {'id': 4},
        ],
      },
    );
    final hits = await c.client.searchMulti('star wars', year: 1977);
    expect(hits.map((r) => r['id']), [1, 2]);
    expect(c.requests.single.url.path, '/3/search/multi');
    expect(c.requests.single.url.queryParameters['query'], 'star wars');
  });
}
