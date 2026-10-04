import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/tmdb/tmdb_client.dart';

import 'assistant_find_fakes.dart';

/// Every non-Seerr host behind one fake, counting requests per host.
class FakeNet {
  final requests = <http.Request>[];
  int tmdbStatus = 200;
  Map<String, Object> tmdb = {};
  Object? trakt;
  Object? tvmaze;
  Object? wikiSearch;
  Object? wikiEntities;

  List<String> get hosts => [for (final r in requests) r.url.host];
  int count(String host) => hosts.where((h) => h == host).length;

  late final client = MockClient((request) async {
    requests.add(request);
    final body = switch (request.url.host) {
      'api.themoviedb.org' => tmdbStatus == 200 ? tmdb[request.url.path] : null,
      'api.trakt.tv' => trakt,
      'api.tvmaze.com' => tvmaze,
      'www.wikidata.org' => request.url.queryParameters['action'] == 'query' ? wikiSearch : wikiEntities,
      _ => throw StateError('unexpected host ${request.url.host}'),
    };
    if (request.url.host == 'api.themoviedb.org' && tmdbStatus != 200) return http.Response('{}', tmdbStatus);
    return body == null ? http.Response('{}', 404) : jsonResponse(body);
  });
}

Map<String, Object> tmdbMovie({double vote = 5.0}) => {
  'genres': [
    {'id': 1, 'name': 'Tmdb Genre'},
  ],
  'runtime': 99,
  'vote_average': vote,
  'vote_count': 1200,
  'popularity': 33.3,
  'release_dates': {
    'results': [
      {
        'iso_3166_1': 'NL',
        'release_dates': [
          {'certification': '16'},
        ],
      },
      {
        'iso_3166_1': 'DE',
        'release_dates': [
          {'certification': '12'},
        ],
      },
    ],
  },
  'credits': {
    'cast': [
      for (final n in ['A', 'B', 'C', 'D', 'E', 'F']) {'name': n},
    ],
  },
  'watch/providers': {
    'results': {
      'NL': {
        'flatrate': [
          {'provider_name': 'Netflix'},
        ],
        'rent': [
          {'provider_name': 'Apple TV'},
        ],
      },
    },
  },
  'external_ids': {'imdb_id': 'tt0133093'},
};

TitleFactsService service(
  FakeNet net, {
  FakeSeerr? seerr,
  String? tmdbKey = 'v3key',
  bool online = true,
  String trakt = '',
  int budget = 20,
  TitleFactsCache? cache,
}) => TitleFactsService(
  cache: cache ?? TitleFactsCache(),
  seerr: seerr == null ? null : () => seerr.client,
  tmdbKey: () => tmdbKey,
  online: () => online,
  traktClientId: trakt,
  budget: budget,
  httpClient: net.client,
);

const matrix = TitleRef(kind: TmdbKind.movie, title: 'The Matrix', year: 1999, tmdbId: 603);

void main() {
  test('the chain decides per field: server, then Seerr, then TMDB', () async {
    final net = FakeNet()..tmdb['/3/movie/603'] = tmdbMovie();
    final seerr = FakeSeerr()
      ..details['/movie/603'] = {
        'genres': [
          {'id': 1, 'name': 'Seerr Genre'},
        ],
        'voteAverage': 6.0,
        'releases': {
          'results': [
            {
              'iso_3166_1': 'NL',
              'release_dates': [
                {'certification': '12'},
              ],
            },
            {
              'iso_3166_1': 'US',
              'release_dates': [
                {'certification': 'R'},
              ],
            },
          ],
        },
      };
    final item = MediaItem(
      id: 'i1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'The Matrix',
      contentRating: 'PG-13',
      rating: 7.5,
    );
    final facts = await service(
      net,
      seerr: seerr,
    ).factsFor([TitleRef(kind: TmdbKind.movie, title: 'The Matrix', tmdbId: 603, item: item, serverId: 's')]);
    final f = facts.single;
    expect(f.score, 7.5);
    expect(f.origin['score'], 'server');
    expect(f.certifications, {'US': 'PG-13', 'NL': '12', 'DE': '12'});
    expect(f.origin['cert:NL'], 'seerr');
    expect(f.origin['cert:DE'], 'tmdb');
    expect(f.genres, ['Seerr Genre']);
    expect(f.runtimeMin, 99);
    expect(f.cast, hasLength(5));
    expect(f.providers, {
      'NL': ['Netflix'],
    });
    expect(f.sources, {'server', 'seerr', 'tmdb'});
    expect(f.toModelJson('NL'), {
      'age': {'NL': '12', 'US': 'PG-13'},
      'age_min': 12,
      'genres': ['Seerr Genre'],
      'runtime_min': 99,
      'cast': ['A', 'B', 'C'],
      'score': 7.5,
      'providers': ['Netflix'],
    });

    // Without the server item, Seerr's score wins from TMDB's.
    final bare = await service(net, seerr: seerr).factsFor([matrix]);
    expect(bare.single.score, 6.0);
  });

  test('online off: only Seerr, no other host', () async {
    final net = FakeNet();
    final seerr = FakeSeerr()..details['/tv/1399'] = {'voteAverage': 8.4};
    final facts = await service(net, seerr: seerr, online: false, trakt: 'cid').factsFor([
      const TitleRef(kind: TmdbKind.tv, title: 'GoT', tmdbId: 1399, imdb: 'tt0944947', tvdb: 121361),
      const TitleRef(kind: TmdbKind.movie, title: 'The Matrix', tmdbId: 603, imdb: 'tt0133093'),
    ]);
    expect(net.requests, isEmpty);
    expect(seerr.paths, containsAll(['/tv/1399', '/movie/603']));
    expect(facts.first.score, 8.4);
  });

  test('without an own TMDB key there is no TMDB call', () async {
    final net = FakeNet();
    await service(net, tmdbKey: null).factsFor([matrix]);
    await service(net, tmdbKey: '').factsFor([matrix]);
    expect(net.count('api.themoviedb.org'), 0);
  });

  test('a cache hit makes no second call, also from the database', () async {
    final net = FakeNet()..tmdb['/3/movie/603'] = tmdbMovie();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = TitleFactsCache(db: db);
    await service(net, cache: cache).factsFor([matrix]);
    final again = await service(net, cache: cache).factsFor([matrix]);
    final fromDb = await service(net, cache: TitleFactsCache(db: db)).factsFor([matrix]);
    expect(net.count('api.themoviedb.org'), 1);
    expect(again.single.score, 5.0);
    expect(fromDb.single.certifications['NL'], '16');
  });

  test('ten identical refs make one call', () async {
    final net = FakeNet()..tmdb['/3/movie/603'] = tmdbMovie();
    final facts = await service(net).factsFor(List.filled(10, matrix));
    expect(facts, hasLength(10));
    expect(net.count('api.themoviedb.org'), 1);
  });

  test('the budget caps external lookups', () async {
    final net = FakeNet();
    for (var i = 1; i <= 6; i++) {
      net.tmdb['/3/movie/$i'] = tmdbMovie();
    }
    final facts = await service(
      net,
      budget: 3,
    ).factsFor([for (var i = 1; i <= 6; i++) TitleRef(kind: TmdbKind.movie, title: '$i', tmdbId: i)]);
    expect(net.count('api.themoviedb.org'), 3);
    expect(facts.where((f) => f.isEmpty), hasLength(3));
  });

  test('a 401 from TMDB is skipped quietly and not retried', () async {
    final net = FakeNet()..tmdbStatus = 401;
    final seerr = FakeSeerr()..details['/movie/603'] = {'voteAverage': 6.0};
    final svc = service(net, seerr: seerr);
    final facts = await svc.factsFor([matrix]);
    await svc.factsFor([const TitleRef(kind: TmdbKind.movie, title: 'Other', tmdbId: 604)]);
    expect(facts.single.score, 6.0);
    expect(net.count('api.themoviedb.org'), 1);
  });

  test('Trakt needs a client id and sends only the public key', () async {
    final net = FakeNet()
      ..trakt = [
        {
          'type': 'movie',
          'movie': {
            'certification': 'R',
            'rating': 8.7,
            'votes': 900,
            'genres': ['action'],
          },
        },
      ];
    await service(net, tmdbKey: null).factsFor([matrix]);
    expect(net.count('api.trakt.tv'), 0);

    final facts = await service(net, tmdbKey: null, trakt: 'cid').factsFor([matrix]);
    final request = net.requests.singleWhere((r) => r.url.host == 'api.trakt.tv');
    expect(request.url.path, '/search/tmdb/603');
    expect(request.url.queryParameters, {'type': 'movie', 'extended': 'full'});
    expect(request.headers['trakt-api-key'], 'cid');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(facts.single.certifications, {'US': 'R'});
    expect(facts.single.score, 8.7);
  });

  test('TVmaze only for series', () async {
    final net = FakeNet()
      ..tvmaze = {
        'genres': ['Drama'],
        'runtime': 60,
        'rating': {'average': 8.9},
      };
    await service(
      net,
      tmdbKey: null,
    ).factsFor([const TitleRef(kind: TmdbKind.movie, title: 'The Matrix', imdb: 'tt0133093')]);
    expect(net.count('api.tvmaze.com'), 0);

    final facts = await service(
      net,
      tmdbKey: null,
    ).factsFor([const TitleRef(kind: TmdbKind.tv, title: 'GoT', tvdb: 121361)]);
    final request = net.requests.singleWhere((r) => r.url.host == 'api.tvmaze.com');
    expect(request.url.queryParameters, {'thetvdb': '121361'});
    expect(facts.single.genres, ['Drama']);
    expect(facts.single.runtimeMin, 60);
    expect(facts.single.score, 8.9);
  });

  test('Wikidata P1657 gives the MPA rating of a film', () async {
    final net = FakeNet()
      ..wikiSearch = {
        'query': {
          'search': [
            {'title': 'Q83495'},
          ],
        },
      }
      ..wikiEntities = {
        'entities': {
          'Q83495': {
            'claims': {
              'P1657': [
                {
                  'mainsnak': {
                    'datavalue': {
                      'value': {'entity-type': 'item', 'id': 'Q18665344'},
                    },
                  },
                },
              ],
            },
          },
        },
      };
    final facts = await service(
      net,
      tmdbKey: null,
    ).factsFor([const TitleRef(kind: TmdbKind.movie, title: 'The Matrix', imdb: 'tt0133093')]);
    expect(facts.single.certifications, {'US': 'R'});
    expect(facts.single.origin['cert:US'], 'wikidata');
    expect(net.requests.first.url.queryParameters['srsearch'], 'haswbstatement:P345=tt0133093');
  });
}
