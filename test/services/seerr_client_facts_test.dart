import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/services/seerr/seerr_account_store.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';

/// Shapes as Overseerr's `server/models/Movie.ts` and `Tv.ts` emit them.
const _movie = {
  'id': 603,
  'title': 'The Matrix',
  'releaseDate': '1999-03-31',
  'popularity': 87.5,
  'releases': {
    'results': [
      {
        'iso_3166_1': 'NL',
        'release_dates': [
          {'certification': '', 'type': 1},
          {'certification': '12', 'type': 3},
        ],
      },
      {
        'iso_3166_1': 'US',
        'release_dates': [
          {'certification': 'PG-13', 'type': 3},
        ],
      },
      {
        'iso_3166_1': 'FR',
        'release_dates': [
          {'certification': '', 'type': 3},
        ],
      },
    ],
  },
  'watchProviders': [
    {
      'iso_3166_1': 'NL',
      'flatrate': [
        {'id': 8, 'name': 'Netflix'},
        {'id': 337, 'name': 'Disney Plus'},
      ],
      'buy': [
        {'id': 2, 'name': 'Apple TV'},
      ],
    },
    {
      'iso_3166_1': 'US',
      'flatrate': <Object>[],
      'buy': [
        {'id': 2, 'name': 'Apple TV'},
      ],
    },
  ],
};

const _tv = {
  'id': 1399,
  'name': 'Game of Thrones',
  'firstAirDate': '2011-04-17',
  'popularity': 12,
  'contentRatings': {
    'results': [
      {'iso_3166_1': 'NL', 'rating': '16'},
      {'iso_3166_1': 'US', 'rating': 'TV-MA'},
      {'iso_3166_1': 'DE', 'rating': ''},
    ],
  },
  'watchProviders': [
    {
      'iso_3166_1': 'NL',
      'flatrate': [
        {'id': 1899, 'name': 'HBO Max'},
      ],
    },
  ],
};

const _bare = {'id': 1, 'title': 'Bare'};

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

SeerrSession _session([String baseUrl = 'https://seerr.example']) =>
    SeerrSession(baseUrl: baseUrl, authMode: SeerrAuthMode.apiKey, apiKey: 'k');

/// Records every path it is asked for and answers from [routes].
class _Server {
  final paths = <String>[];
  final Map<String, Object> routes;
  _Server(this.routes);

  late final client = MockClient((request) async {
    final path = request.url.path.replaceFirst(SeerrConstants.apiPrefix, '');
    paths.add(path);
    return _json(routes[path] ?? const {});
  });
}

/// In-memory store, so provider tests need no shared preferences.
class _MemoryStore implements SeerrAccountStore {
  final Map<String, SeerrSession> sessions = {};

  @override
  Future<SeerrSession?> load(String userUuid) async => sessions[userUuid];

  @override
  Future<void> save(String userUuid, SeerrSession session) async => sessions[userUuid] = session;

  @override
  Future<void> clear(String userUuid) async => sessions.remove(userUuid);
}

void main() {
  group('title facts on the detail', () {
    final server = _Server({'/movie/603': _movie, '/tv/1399': _tv, '/movie/1': _bare});
    final client = SeerrClient(_session(), httpClient: server.client);

    test('a film gives every country with a classification', () async {
      final detail = await client.getMediaDetail(tmdbId: 603, isMovie: true);

      expect(detail.certifications, {'NL': '12', 'US': 'PG-13'});
      expect(detail.providers, {
        'NL': ['Netflix', 'Disney Plus'],
      });
      expect(detail.popularity, 87.5);
    });

    test('a series reads its contentRatings', () async {
      final detail = await client.getMediaDetail(tmdbId: 1399, isMovie: false);

      expect(detail.certifications, {'NL': '16', 'US': 'TV-MA'});
      expect(detail.providers, {
        'NL': ['HBO Max'],
      });
      expect(detail.popularity, 12.0);
    });

    test('missing fields give empty maps and no popularity', () async {
      final detail = await client.getMediaDetail(tmdbId: 1, isMovie: true);

      expect(detail.certifications, isEmpty);
      expect(detail.providers, isEmpty);
      expect(detail.popularity, isNull);
    });
  });

  test('getSimilar asks the similar endpoint per media type', () async {
    final server = _Server({
      '/movie/603/similar': {
        'page': 1,
        'totalPages': 1,
        'results': [
          {'id': 604, 'mediaType': 'movie', 'title': 'The Matrix Reloaded'},
        ],
      },
    });
    final client = SeerrClient(_session(), httpClient: server.client);

    final page = await client.getSimilar(tmdbId: 603, isMovie: true);
    await client.getSimilar(tmdbId: 1399, isMovie: false);

    expect(page.items.single.tmdbId, 604);
    expect(server.paths, ['/movie/603/similar', '/tv/1399/similar']);
  });

  group('SeerrProvider injection', () {
    test('the active client talks through the injected http client and store', () async {
      final server = _Server({'/movie/603': _movie});
      final store = _MemoryStore()..sessions['user-1'] = _session();
      final provider = SeerrProvider(httpClient: server.client, store: store);
      addTearDown(provider.dispose);

      await provider.onActiveProfileChanged('user-1');
      final detail = await provider.client!.getMediaDetail(tmdbId: 603, isMovie: true);

      expect(detail.certifications['NL'], '12');
      expect(server.paths, ['/movie/603']);
    });

    test('test() uses the injected http client', () async {
      final server = _Server({
        '/status': {'version': '1.33.2'},
        '/auth/me': {'id': 1, 'displayName': 'Michel', 'permissions': 2},
      });
      final provider = SeerrProvider(httpClient: server.client, store: _MemoryStore());
      addTearDown(provider.dispose);

      final result = await provider.test(baseUrl: 'https://seerr.example', mode: SeerrAuthMode.apiKey, apiKey: 'k');

      expect(result.version, '1.33.2');
      expect(server.paths, ['/status', '/auth/me']);
    });

    test('without injection the mock client is never touched', () async {
      final server = _Server({'/movie/603': _movie});
      final store = _MemoryStore()..sessions['user-1'] = _session('http://127.0.0.1:1');
      final provider = SeerrProvider(store: store);
      addTearDown(provider.dispose);

      await provider.onActiveProfileChanged('user-1');
      await expectLater(provider.client!.getMediaDetail(tmdbId: 603, isMovie: true), throwsA(isA<SeerrException>()));

      expect(server.paths, isEmpty);
    });
  });
}
