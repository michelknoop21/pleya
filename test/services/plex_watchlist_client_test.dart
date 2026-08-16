import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_key.dart';
import 'package:pleya/services/plex_watchlist_client.dart';

/// Captures of the live API, see `test/fixtures/watchlist/README.md`.
String fixture(String name) => File('test/fixtures/watchlist/$name').readAsStringSync();

http.Response ok(String body) => http.Response(body, 200, headers: {'content-type': 'application/json'});

void main() {
  group('fetch', () {
    test('walks every page until totalSize is reached', () async {
      final requested = <Uri>[];
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          requested.add(request.url);
          final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
          return ok(fixture(start == 0 ? 'watchlist_page1.json' : 'watchlist_page2.json'));
        }),
      );
      addTearDown(client.dispose);

      final items = await client.fetch(token: 'tok');

      expect(items, hasLength(3));
      expect(requested, hasLength(2));
      expect(requested.first.queryParameters['X-Plex-Container-Start'], '0');
      expect(requested.last.queryParameters['X-Plex-Container-Start'], '2');
    });

    test('walks three pages when the server answers in threes', () async {
      // Page one and two report two of five; page three closes the list.
      final pages = [
        _page(offset: 0, size: 2, totalSize: 5),
        _page(offset: 2, size: 2, totalSize: 5),
        _page(offset: 4, size: 1, totalSize: 5),
      ];
      final starts = <String>[];
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          final start = request.url.queryParameters['X-Plex-Container-Start']!;
          starts.add(start);
          return ok(pages[starts.length - 1]);
        }),
      );
      addTearDown(client.dispose);

      final items = await client.fetch(token: 'tok');

      expect(starts, ['0', '2', '4']);
      expect(items, hasLength(5));
    });

    test('stops instead of looping when the server promises more than it sends', () async {
      var calls = 0;
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          calls++;
          return ok(_page(offset: 0, size: 0, totalSize: 99));
        }),
      );
      addTearDown(client.dispose);

      expect(await client.fetch(token: 'tok'), isEmpty);
      expect(calls, 1);
    });

    test('an empty watchlist has no Metadata key at all', () async {
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((_) async => ok(fixture('watchlist_empty.json'))),
      );
      addTearDown(client.dispose);

      expect(await client.fetch(token: 'tok'), isEmpty);
    });

    test('the filter is a path segment, never a query parameter', () async {
      late Uri url;
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          url = request.url;
          return ok(fixture('watchlist_empty.json'));
        }),
      );
      addTearDown(client.dispose);

      await client.fetch(token: 'tok', filter: PlexWatchlistFilter.released);

      expect(url.host, 'discover.provider.plex.tv');
      expect(url.path, '/library/sections/watchlist/released');
      expect(url.queryParameters.containsKey('filter'), isFalse);
    });

    test('type and sort travel as query parameters', () async {
      late Uri url;
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          url = request.url;
          return ok(fixture('watchlist_empty.json'));
        }),
      );
      addTearDown(client.dispose);

      await client.fetch(token: 'tok', type: PlexWatchlistType.show, sort: 'titleSort:asc');

      expect(url.queryParameters['type'], '2');
      expect(url.queryParameters['sort'], 'titleSort:asc');
      expect(url.queryParameters['includeCollections'], '1');
      expect(url.queryParameters['includeExternalMedia'], '1');
    });

    test('maps a discover item without a server id and with an absolute poster', () async {
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
          return ok(fixture(start == 0 ? 'watchlist_page1.json' : 'watchlist_page2.json'));
        }),
      );
      addTearDown(client.dispose);

      final items = await client.fetch(token: 'tok');
      final sintel = items.firstWhere((i) => i.item.title == 'Sintel');

      expect(sintel.item.serverId, isNull);
      expect(sintel.item.kind, MediaKind.movie);
      expect(sintel.item.id, '5d77688123d5a3001f4ed3df');
      expect(sintel.guid, 'plex://movie/5d77688123d5a3001f4ed3df');
      expect(sintel.posterUrl, startsWith('https://'));
      expect(watchlistKeyForItem(sintel.item), 'plex:5d77688123d5a3001f4ed3df');
    });

    test('a show comes back as a show, not as a movie', () async {
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
          return ok(fixture(start == 0 ? 'watchlist_page1.json' : 'watchlist_page2.json'));
        }),
      );
      addTearDown(client.dispose);

      final items = await client.fetch(token: 'tok');

      expect(items.map((i) => i.item.kind), contains(MediaKind.show));
    });
  });

  group('headers', () {
    test('sends exactly the set PlexAuthService already uses, and nothing more', () async {
      late Map<String, String> sent;
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          sent = request.headers;
          return ok(fixture('watchlist_empty.json'));
        }),
        clientIdentifier: 'client-id',
      );
      addTearDown(client.dispose);

      await client.fetch(token: 'secret-token');

      final relevant = Map.of(sent)..removeWhere((key, _) => key.toLowerCase() == 'content-type');
      expect(relevant.keys.map((k) => k.toLowerCase()).toSet(), {
        'accept',
        'x-plex-product',
        'x-plex-client-identifier',
        'x-plex-token',
      });
      expect(client.headersForToken('secret-token')['X-Plex-Token'], 'secret-token');
    });

    test('carries no server identity, so no server token can ride along', () {
      final headers = PlexWatchlistClient.forTesting(
        httpClient: MockClient((_) async => ok('{}')),
      ).headersForToken('tok');

      expect(headers.keys.any((k) => k.toLowerCase().contains('device')), isFalse);
      expect(headers.keys.any((k) => k.toLowerCase().contains('platform')), isFalse);
      expect(headers.keys.any((k) => k.toLowerCase().contains('version')), isFalse);
    });
  });

  group('add and remove', () {
    test('use the discover rating key, the tail of the guid', () async {
      final calls = <({String method, Uri url})>[];
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          calls.add((method: request.method, url: request.url));
          return ok(fixture('action_success.json'));
        }),
      );
      addTearDown(client.dispose);

      final key = discoverRatingKeyFromGuid('plex://movie/5d77688123d5a3001f4ed3df')!;
      await client.add(token: 'tok', ratingKey: key);
      await client.remove(token: 'tok', ratingKey: key);

      expect(calls.map((c) => c.method), ['PUT', 'PUT']);
      expect(calls.first.url.path, '/actions/addToWatchlist');
      expect(calls.last.url.path, '/actions/removeFromWatchlist');
      for (final call in calls) {
        expect(call.url.host, 'discover.provider.plex.tv');
        expect(call.url.queryParameters['ratingKey'], '5d77688123d5a3001f4ed3df');
      }
    });

    test('adding a title that is already on the list is a success, not a rollback', () async {
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((_) async => ok(fixture('action_success.json'))),
      );
      addTearDown(client.dispose);

      await expectLater(client.add(token: 'tok', ratingKey: 'abc'), completes);
      await expectLater(client.add(token: 'tok', ratingKey: 'abc'), completes);
    });

    test('an unknown rating key throws instead of reporting success', () async {
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((_) async => http.Response(fixture('error_404_unknown_rating_key.json'), 404)),
      );
      addTearDown(client.dispose);

      await expectLater(client.add(token: 'tok', ratingKey: 'deadbeef'), throwsA(anything));
    });
  });

  group('fetchWatchlistedAt', () {
    test('reads the single UserState object, in seconds', () async {
      late Uri url;
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((request) async {
          url = request.url;
          return ok(fixture('user_state_watchlisted.json'));
        }),
      );
      addTearDown(client.dispose);

      final at = await client.fetchWatchlistedAt(token: 'tok', ratingKey: '5d7768352e80df001ebde4c9');

      expect(url.host, 'metadata.provider.plex.tv');
      expect(url.path, '/library/metadata/5d7768352e80df001ebde4c9/userState');
      expect(at, 1786904870);
    });

    test('a title that is off the list answers 200 with the key missing', () async {
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((_) async => ok(fixture('user_state_not_watchlisted.json'))),
      );
      addTearDown(client.dispose);

      expect(await client.fetchWatchlistedAt(token: 'tok', ratingKey: 'abc'), isNull);
    });
  });

  group('errors', () {
    test('401 surfaces instead of looking like an empty watchlist', () async {
      final client = PlexWatchlistClient.forTesting(
        httpClient: MockClient((_) async => http.Response(fixture('error_401_missing_token.json'), 401)),
      );
      addTearDown(client.dispose);

      await expectLater(client.fetch(token: 'stale'), throwsA(anything));
    });
  });
}

String _page({required int offset, required int size, required int totalSize}) {
  return jsonEncode({
    'MediaContainer': {
      'librarySectionID': 'watchlist',
      'librarySectionTitle': 'Watchlist',
      'identifier': 'tv.plex.provider.discover',
      'offset': offset,
      'totalSize': totalSize,
      'size': size,
      'Metadata': [
        for (var i = 0; i < size; i++)
          {'ratingKey': 'key-${offset + i}', 'guid': 'plex://movie/key-${offset + i}', 'type': 'movie', 'title': 'T$i'},
      ],
    },
  });
}
