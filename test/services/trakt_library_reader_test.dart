import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/models/trakt/trakt_title.dart';
import 'package:pleya/services/trackers/tracker_exceptions.dart';
import 'package:pleya/services/trackers/tracker_session.dart';
import 'package:pleya/services/trakt/trakt_client.dart';
import 'package:pleya/services/trakt/trakt_library_reader.dart';
import 'package:pleya/services/trakt/trakt_watched_identities.dart';

TrackerSession _session() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return TrackerSession(
    accessToken: 'at',
    refreshToken: 'rt',
    expiresAt: now + 3600,
    scope: 'public',
    createdAt: now,
    username: 'alice',
  );
}

Map<String, Object?> _movie(
  String title,
  int year, {
  String? imdb,
  int? tmdb,
  String at = '2026-01-01T00:00:00.000Z',
}) => {
  'plays': 1,
  'last_watched_at': at,
  'movie': {
    'title': title,
    'year': year,
    'ids': {'trakt': 1, 'slug': 'x', 'imdb': imdb, 'tmdb': tmdb},
  },
};

Map<String, Object?> _show(String title, int year, {int? tvdb, String at = '2026-01-01T00:00:00.000Z'}) => {
  'listed_at': at,
  'type': 'show',
  'show': {
    'title': title,
    'year': year,
    'ids': {'trakt': 2, 'tvdb': tvdb},
  },
};

TraktClient _client(Future<http.Response> Function(http.Request) handler) =>
    TraktClient(_session(), onSessionInvalidated: () {}, httpClient: MockClient(handler));

void main() {
  group('TraktClient list reads', () {
    test('watched series are asked without the season tree', () async {
      final paths = <String>[];
      final client = _client((r) async {
        paths.add(r.url.toString());
        return http.Response('[]', 200);
      });
      await client.getWatched(shows: true);
      await client.getWatched(shows: false);
      expect(paths[0], contains('/sync/watched/shows?extended=noseasons'));
      expect(paths[1], endsWith('/sync/watched/movies'));
      client.dispose();
    });

    test('entries without a title or ids are skipped, the rest is read', () async {
      final client = _client(
        (r) async => http.Response(
          json.encode([
            _movie('Dune', 2021, imdb: 'tt1160419', tmdb: 438631),
            {
              'movie': {'title': '', 'ids': {}},
            },
            {
              'movie': {'title': 'No ids'},
            },
            'junk',
          ]),
          200,
        ),
      );
      final titles = await client.getWatched(shows: false);
      expect(titles.map((t) => t.title), ['Dune']);
      expect(titles.single.ids.tmdb, 438631);
      client.dispose();
    });

    test('a 200 that is not a list throws instead of reading as an empty list', () async {
      final client = _client((r) async => http.Response('<html>blocked</html>', 200));
      await expectLater(client.getWatched(shows: false), throwsA(isA<TrackerApiException>()));
      await expectLater(client.getWatchlist(shows: true), throwsA(isA<TrackerApiException>()));
      client.dispose();
    });

    test('the watchlist is read newest first with a limit', () async {
      late Uri uri;
      final client = _client((r) async {
        uri = r.url;
        return http.Response('[]', 200);
      });
      await client.getWatchlist(shows: false, limit: 20);
      expect(uri.path, '/sync/watchlist/movies/added/desc');
      expect(uri.queryParameters['limit'], '20');
      client.dispose();
    });
  });

  group('TraktLibraryReader', () {
    late int calls;
    late bool failing;
    late TraktClient? client;
    late String user;
    late DateTime clock;
    late TraktLibraryReader reader;

    setUp(() {
      calls = 0;
      failing = false;
      user = 'u1';
      clock = DateTime(2026, 10, 11, 12);
      client = _client((r) async {
        calls++;
        if (failing) return http.Response('boom', 500);
        return http.Response(json.encode([_movie('Dune', 2021, imdb: 'tt1160419')]), 200);
      });
      reader = TraktLibraryReader(clientOf: () => client, userOf: () => user, now: () => clock);
    });

    test('a second read inside the ttl makes no request', () async {
      await reader.seen(expectUser: 'u1');
      final after = calls;
      final again = await reader.seen(expectUser: 'u1');
      expect(calls, after);
      expect(again!.movies.single.title, 'Dune');
    });

    test('simultaneous reads share one request', () async {
      final a = reader.seen(expectUser: 'u1');
      final b = reader.seen(expectUser: 'u1');
      await Future.wait([a, b]);
      expect(calls, 2); // movies + shows, once
    });

    test('another profile than the one bound gets nothing', () async {
      expect(await reader.seen(expectUser: 'someone-else'), isNull);
      expect(await reader.watchlist(expectUser: 'someone-else'), isNull);
      expect(calls, 0);
    });

    test('no client gives nothing and does not throw', () async {
      client = null;
      expect(await reader.seen(expectUser: 'u1'), isNull);
    });

    test('a failing read is not cached as an empty list and is not retried at once', () async {
      failing = true;
      expect(await reader.seen(expectUser: 'u1'), isNull);
      final after = calls;
      expect(await reader.seen(expectUser: 'u1'), isNull);
      expect(calls, after, reason: 'backoff');

      failing = false;
      clock = clock.add(TraktLibraryReader.failureBackoff + const Duration(seconds: 1));
      expect((await reader.seen(expectUser: 'u1'))!.movies, isNotEmpty);
    });

    test('the last good list is used while Trakt fails, until it is too old', () async {
      await reader.seen(expectUser: 'u1');
      failing = true;
      clock = clock.add(TraktLibraryReader.ttl + const Duration(minutes: 1));
      expect((await reader.seen(expectUser: 'u1'))!.movies.single.title, 'Dune');

      clock = clock.add(TraktLibraryReader.staleFor + const Duration(minutes: 1));
      expect(await reader.seen(expectUser: 'u1'), isNull);
    });

    test('reset drops the cache and a read in flight does not land in the new one', () async {
      final gate = Completer<void>();
      client = _client((r) async {
        await gate.future;
        return http.Response(json.encode([_movie('Old', 2000, imdb: 'tt0000001')]), 200);
      });
      final inFlight = reader.seen(expectUser: 'u1');
      reader.reset();
      gate.complete();
      expect(await inFlight, isNull);

      client = _client((r) async => http.Response(json.encode([_movie('New', 2001, imdb: 'tt0000002')]), 200));
      expect((await reader.seen(expectUser: 'u1'))!.movies.single.title, 'New');
    });

    test('a read that hangs is cut off', () async {
      client = _client((r) => Completer<http.Response>().future);
      final slow = TraktLibraryReader(
        clientOf: () => client,
        userOf: () => user,
        timeout: const Duration(milliseconds: 50),
      );
      expect(await slow.seen(expectUser: 'u1'), isNull);
    });
  });

  group('traktWatchedIdentities', () {
    TraktTitle title(String t, int y, {String? imdb, int? tmdb, bool show = false}) => TraktTitle.fromEntry(
      show ? _show(t, y) : _movie(t, y, imdb: imdb, tmdb: tmdb),
      isShow: show,
    )!;

    test('a film carries imdb and tmdb tokens in the log schema, plus title and year', () {
      final seen = TraktSeen(movies: [title('Dune', 2021, imdb: 'TT1160419', tmdb: 438631)]);
      final id = traktWatchedIdentities(seen).single;
      expect(id.tokens, containsAll(['movie:imdb:tt1160419', 'movie:tmdb:438631']));
      expect(id.title, 'Dune');
      expect(id.year, 2021);
      expect(id.show, isFalse);
    });

    test('series are seen but never completed', () {
      final seen = TraktSeen(
        movies: [title('Dune', 2021, imdb: 'tt1160419')],
        shows: [title('Severance', 2022, show: true)],
      );
      expect(traktWatchedIdentities(seen).map((i) => i.show), [false, true]);
      expect(traktWatchedIdentities(seen, completedOnly: true).map((i) => i.show), [false]);
    });
  });
}
