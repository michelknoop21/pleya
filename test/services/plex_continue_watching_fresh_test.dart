import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/utils/continue_watching_order.dart';

/// A Plex server for Verder kijken. Its hub holds one next-up episode per entry
/// of [addedDaysAgo] (series `show-<n>`); a series' own metadata answers from
/// [lastViewedDaysAgo] and fails for those in [failing].
class _PlexServer extends http.BaseClient {
  _PlexServer({
    required this.addedDaysAgo,
    this.lastViewedDaysAgo = const {},
    this.failing = const {},
    this.resume = false,
  });

  final List<int> addedDaysAgo;
  final Map<String, int> lastViewedDaysAgo;
  final Set<String> failing;
  final bool resume;
  final requests = <Uri>[];

  int _secondsAgo(int days) => DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;

  http.StreamedResponse _json(Object body, [int status = 200]) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: {'content-type': 'application/json'},
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final path = request.url.path;
    if (path == '/hubs') {
      return _json({
        'MediaContainer': {
          'Hub': [
            {
              'key': '/hubs/home/continueWatching',
              'title': 'Continue Watching',
              'type': 'mixed',
              'hubIdentifier': 'home.continue',
              'size': addedDaysAgo.length,
              'more': false,
              'Metadata': [
                for (var i = 0; i < addedDaysAgo.length; i++)
                  {
                    'ratingKey': 'ep-$i',
                    'type': 'episode',
                    'title': 'Episode $i',
                    'grandparentRatingKey': 'show-$i',
                    'grandparentTitle': 'Show $i',
                    'parentIndex': 2,
                    'index': 1,
                    'addedAt': _secondsAgo(addedDaysAgo[i]),
                    if (resume) ...{'viewOffset': 600000, 'duration': 2400000},
                  },
              ],
            },
          ],
        },
      });
    }
    final show = RegExp(r'^/library/metadata/(show-\d+)$').firstMatch(path)?.group(1);
    if (show != null) {
      if (failing.contains(show)) return _json({'error': 'boom'}, 500);
      final ago = lastViewedDaysAgo[show];
      return _json({
        'MediaContainer': {
          'Metadata': [
            {'ratingKey': show, 'type': 'show', 'title': show, if (ago != null) 'lastViewedAt': _secondsAgo(ago)},
          ],
        },
      });
    }
    return _json({'error': 'not found'}, 404);
  }
}

void main() {
  late _PlexServer server;

  Future<PlexClient> clientFor(_PlexServer s) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    server = s;
    final client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'http://server:32400',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Plezy',
        version: 'test',
      ),
      serverId: ServerId('server-id'),
      serverName: 'Server',
      httpClient: s,
    );
    addTearDown(client.close);
    return client;
  }

  List<Uri> seriesLookups() => server.requests.where((u) => u.path.startsWith('/library/metadata/show-')).toList();

  group('Plex next-up episodes that may be new', () {
    test(
      'a new episode gets the date the series was last watched, and is a new season at episode 1 of season 2',
      () async {
        final client = await clientFor(_PlexServer(addedDaysAgo: [3], lastViewedDaysAgo: {'show-0': 120}));

        final items = await client.fetchContinueWatching(count: 20);

        expect(seriesLookups(), hasLength(1));
        expect(items.single.lastViewedAt, isNotNull);
        expect(continueWatchingFreshness(items.single, now: DateTime.now()), ContinueWatchingFreshness.newSeason);
      },
    );

    test('an episode added more than two weeks ago costs no extra call', () async {
      final client = await clientFor(_PlexServer(addedDaysAgo: [30], lastViewedDaysAgo: {'show-0': 120}));

      final items = await client.fetchContinueWatching(count: 20);

      expect(seriesLookups(), isEmpty);
      expect(items.single.lastViewedAt, isNull);
    });

    test('something that was begun is not looked up', () async {
      final client = await clientFor(_PlexServer(addedDaysAgo: [3], lastViewedDaysAgo: {'show-0': 120}, resume: true));

      await client.fetchContinueWatching(count: 20);

      expect(seriesLookups(), isEmpty);
    });

    test('a failed lookup leaves the episode undated, so it is not called new', () async {
      final client = await clientFor(_PlexServer(addedDaysAgo: [3], failing: {'show-0'}));

      final items = await client.fetchContinueWatching(count: 20);

      expect(items.single.lastViewedAt, isNull);
      expect(continueWatchingFreshness(items.single, now: DateTime.now()), ContinueWatchingFreshness.none);
    });

    test('a series that was never watched stays undated', () async {
      final client = await clientFor(_PlexServer(addedDaysAgo: [3]));

      final items = await client.fetchContinueWatching(count: 20);

      expect(items.single.lastViewedAt, isNull);
    });

    test('at most six series are looked up in one refresh', () async {
      final client = await clientFor(
        _PlexServer(addedDaysAgo: List.filled(9, 2), lastViewedDaysAgo: {for (var i = 0; i < 9; i++) 'show-$i': 90}),
      );

      await client.fetchContinueWatching(count: 20);

      expect(seriesLookups(), hasLength(6));
    });
  });
}
