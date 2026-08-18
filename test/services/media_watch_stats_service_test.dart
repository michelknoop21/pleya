import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/media_watch_stats_service.dart';
import 'package:pleya/services/tautulli/tautulli_client.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

String fixture(String name) => File('test/fixtures/tautulli/$name').readAsStringSync();

String envelope(Object? data, {String result = 'success'}) => json.encode({
  'response': {'result': result, 'message': null, 'data': data},
});

TautulliClient clientFor(Map<String, String> byCommand, {List<String>? log}) => TautulliClient(
  const TautulliSession(
    baseUrl: 'https://tautulli.example.test',
    authMode: TautulliAuthMode.device,
    token: 'TESTTOKEN',
  ),
  httpClient: MockClient((request) async {
    final cmd = request.url.queryParameters['cmd']!;
    log?.add(cmd);
    return http.Response(
      byCommand[cmd] ?? '{"response":{"result":"error","message":"no fixture"}}',
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

MediaItem movie() => MediaItem(id: '2', backend: MediaBackend.plex, kind: MediaKind.movie);

void main() {
  const service = MediaWatchStatsService();

  test('reads the all-time window from the measured capture', () async {
    final client = clientFor({
      'get_item_watch_time_stats': envelope(json.decode(fixture('item_watch_time_stats.json'))),
      'get_item_user_stats': envelope(json.decode(fixture('item_user_stats_movie.json'))),
    });
    addTearDown(client.dispose);

    final stats = await service.resolve(movie(), tautulli: client);

    // query_days 0 is Tautulli's all-time bucket, not an empty one.
    expect(stats.totalPlays, 4);
    expect(stats.totalTime, const Duration(seconds: 6337));
    expect(stats.userCount, 2);
    expect(stats.isNotEmpty, isTrue);
  });

  test('picks up the 30-day window when it has plays', () async {
    final client = clientFor({
      'get_item_watch_time_stats': envelope([
        {'query_days': 30, 'total_plays': 2, 'total_time': 100},
        {'query_days': 0, 'total_plays': 9, 'total_time': 500},
      ]),
      'get_item_user_stats': envelope(const []),
    });
    addTearDown(client.dispose);

    final stats = await service.resolve(movie(), tautulli: client);
    expect(stats.playsLast30Days, 2);
    expect(stats.totalPlays, 9);
  });

  test('a title nobody played produces nothing rather than a row of zeroes', () async {
    final client = clientFor({
      'get_item_watch_time_stats': envelope([
        {'query_days': 30, 'total_plays': 0, 'total_time': 0},
        {'query_days': 0, 'total_plays': 0, 'total_time': 0},
      ]),
    });
    addTearDown(client.dispose);

    expect((await service.resolve(movie(), tautulli: client)).isEmpty, isTrue);
  });

  test('without Tautulli there is no section and no request', () async {
    final stats = await service.resolve(movie());
    expect(stats.isEmpty, isTrue);
  });

  test('a failing Tautulli degrades to empty instead of throwing', () async {
    final client = clientFor(const {});
    addTearDown(client.dispose);

    expect((await service.resolve(movie(), tautulli: client)).isEmpty, isTrue);
  });

  // The user count costs a second round-trip, so it must not be spent on a
  // title that was never played.
  test('skips the user lookup when there are no plays', () async {
    final log = <String>[];
    final client = clientFor({
      'get_item_watch_time_stats': envelope([
        {'query_days': 0, 'total_plays': 0, 'total_time': 0},
      ]),
    }, log: log);
    addTearDown(client.dispose);

    await service.resolve(movie(), tautulli: client);
    expect(log, ['get_item_watch_time_stats']);
  });

  test('a failing user lookup still yields the play and time totals', () async {
    final client = clientFor({
      'get_item_watch_time_stats': envelope(json.decode(fixture('item_watch_time_stats.json'))),
    });
    addTearDown(client.dispose);

    final stats = await service.resolve(movie(), tautulli: client);
    expect(stats.totalPlays, 4);
    expect(stats.userCount, isNull);
  });
}
