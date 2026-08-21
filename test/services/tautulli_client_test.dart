import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/models/tautulli/tautulli_activity.dart';
import 'package:pleya/services/tautulli/tautulli_client.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

/// Contract tests against captures of a live Tautulli v2.17.2. What each
/// capture proved is written up in `test/fixtures/tautulli/README.md`.
///
/// The point of these is to pin the shapes we measured, so a future refactor
/// that quietly changes a field name or drops the `response` envelope fails
/// here rather than on someone's Apple TV.

String fixture(String name) => File('test/fixtures/tautulli/$name').readAsStringSync();

/// Wrap raw `data` the way Tautulli wraps everything.
String envelope(Object? data, {String result = 'success', String? message}) => json.encode({
  'response': {'result': result, 'message': message, 'data': data},
});

String envelopeFixture(String name) => envelope(json.decode(fixture(name)));

http.Response ok(String body) => http.Response(body, 200, headers: {'content-type': 'application/json'});

TautulliSession _session({TautulliAuthMode mode = TautulliAuthMode.device}) =>
    TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: mode, token: 'TESTTOKEN');

/// Builds a client whose transport answers with [response] verbatim, for the
/// cases where the status code, the content type or a non-JSON body is the
/// thing under test.
TautulliClient rawClientFor(http.Response response, {TautulliAuthMode mode = TautulliAuthMode.device}) =>
    TautulliClient(_session(mode: mode), httpClient: MockClient((_) async => response));

/// Builds a client whose transport answers from [handler], and records the
/// query parameters of every request for assertions.
({TautulliClient client, List<Map<String, String>> requests}) clientFor(
  String Function(Map<String, String> query) handler, {
  TautulliAuthMode mode = TautulliAuthMode.device,
}) {
  final requests = <Map<String, String>>[];
  final client = TautulliClient(
    _session(mode: mode),
    httpClient: MockClient((request) async {
      requests.add(request.url.queryParameters);
      return ok(handler(request.url.queryParameters));
    }),
  );
  return (client: client, requests: requests);
}

void main() {
  group('transport', () {
    test('every call goes to /api/v2 with the token and the command', () async {
      final f = clientFor((_) => envelope('Plexflix'));
      addTearDown(f.client.dispose);

      await f.client.serverFriendlyName();

      expect(f.requests.single['cmd'], 'get_server_friendly_name');
      expect(f.requests.single['apikey'], 'TESTTOKEN');
    });

    // api2.py only consults the mobile-device table when app=1 is present, so
    // omitting it makes a valid device token look like a wrong key.
    test('a device token sends app=1', () async {
      final f = clientFor((_) => envelope('Plexflix'));
      addTearDown(f.client.dispose);

      await f.client.serverFriendlyName();
      expect(f.requests.single['app'], '1');
    });

    test('a master API key does not send app=1', () async {
      final f = clientFor((_) => envelope('Plexflix'), mode: TautulliAuthMode.apiKey);
      addTearDown(f.client.dispose);

      await f.client.serverFriendlyName();
      expect(f.requests.single.containsKey('app'), isFalse);
    });

    // Tautulli puts the reason in the envelope whatever the status is, so a 200
    // is no proof of success on its own. The 400 that the measured instance
    // actually sends for a rejected key has its own test below.
    test('a wrong key arrives as HTTP 200 and still raises an auth error', () async {
      final f = clientFor((_) => envelope(null, result: 'error', message: 'Invalid apikey'));
      addTearDown(f.client.dispose);

      await expectLater(
        f.client.serverFriendlyName(),
        throwsA(isA<TautulliException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });

    test('any other error surfaces the message Tautulli sent', () async {
      final f = clientFor((_) => envelope(null, result: 'error', message: 'Item does not exist'));
      addTearDown(f.client.dispose);

      await expectLater(
        f.client.serverFriendlyName(),
        throwsA(
          isA<TautulliException>()
              .having((e) => e.message, 'message', 'Item does not exist')
              .having((e) => e.isAuth, 'isAuth', isFalse),
        ),
      );
    });

    // Tautulli sends `message: ""` for some failures rather than leaving the
    // field out, and that reached the settings screen as a blank error line.
    test('an empty message still says something', () async {
      final f = clientFor((_) => envelope(null, result: 'error', message: '  '));
      addTearDown(f.client.dispose);

      await expectLater(
        f.client.serverFriendlyName(),
        throwsA(isA<TautulliException>().having((e) => e.message, 'message', 'Unknown error')),
      );
    });

    // Measured against a live instance: Tautulli rejects a key with HTTP 400,
    // not the 200 this client assumed. The status check used to run first, so
    // isAuth was never set and the settings screen printed the string
    // "HTTP 400" at someone who had simply pasted the wrong one of their two
    // credentials into the wrong field.
    test('a rejected key arrives as HTTP 400 and is still an auth error', () async {
      final client = rawClientFor(
        http.Response(
          json.encode({
            'response': {'result': 'error', 'message': 'Invalid apikey', 'data': {}},
          }),
          400,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.serverFriendlyName(),
        throwsA(isA<TautulliException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });

    // The failure in log bcjk3: five requests, all HTTP 200, no error line
    // anywhere and a generic message on screen. json.decode sat outside the
    // error boundary, so an HTML page left through a FormatException.
    test('an HTML page on HTTP 200 is reported as not-Tautulli, not a crash', () async {
      final client = rawClientFor(
        http.Response(
          '<html><head><title>Sign in</title></head><body>…</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.serverFriendlyName(),
        throwsA(
          isA<TautulliException>()
              .having((e) => e.isNotTautulli, 'isNotTautulli', isTrue)
              .having((e) => e.isMalformed, 'isMalformed', isFalse),
        ),
      );
    });

    test('JSON without a Tautulli envelope is malformed rather than not-Tautulli', () async {
      final client = rawClientFor(http.Response('{"foo":"bar"}', 200, headers: {'content-type': 'application/json'}));
      addTearDown(client.dispose);

      await expectLater(
        client.serverFriendlyName(),
        throwsA(
          isA<TautulliException>()
              .having((e) => e.isMalformed, 'isMalformed', isTrue)
              .having((e) => e.isNotTautulli, 'isNotTautulli', isFalse),
        ),
      );
    });

    // The reason decode alone does not decide: a broken gateway also answers
    // with HTML, and calling that "not Tautulli" sends the user off to check an
    // address that was right.
    test('an HTML page on HTTP 502 keeps the status code', () async {
      final client = rawClientFor(
        http.Response('<html><body>Bad Gateway</body></html>', 502, headers: {'content-type': 'text/html'}),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.serverFriendlyName(),
        throwsA(
          isA<TautulliException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.message, 'message', 'HTTP 502')
              .having((e) => e.isNotTautulli, 'isNotTautulli', isFalse),
        ),
      );
    });

    test('an empty body on HTTP 500 is reported as the status', () async {
      final client = rawClientFor(http.Response('', 500));
      addTearDown(client.dispose);

      await expectLater(
        client.serverFriendlyName(),
        throwsA(isA<TautulliException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('a valid envelope still succeeds', () async {
      final client = rawClientFor(
        http.Response(envelope('Plexflix'), 200, headers: {'content-type': 'application/json'}),
      );
      addTearDown(client.dispose);

      expect(await client.serverFriendlyName(), 'Plexflix');
    });

    test('ping reports false instead of throwing', () async {
      final f = clientFor((_) => envelope(null, result: 'error', message: 'Invalid apikey'));
      addTearDown(f.client.dispose);

      expect(await f.client.ping(), isFalse);
    });
  });

  group('get_item_user_stats', () {
    test('parses the measured movie capture', () async {
      final f = clientFor((_) => envelopeFixture('item_user_stats_movie.json'));
      addTearDown(f.client.dispose);

      final stats = await f.client.itemUserStats('2');

      expect(f.requests.single['rating_key'], '2');
      expect(stats, hasLength(2));
      final first = stats.first;
      expect(first.userId, 4725462);
      expect(first.totalPlays, 3);
      expect(first.totalTime, 6272);
      expect(first.userThumb, startsWith('https://plex.tv/users/'));
    });

    // The Plex Media Server's own /accounts returned an empty thumb for all 23
    // accounts; this is the reason Tautulli is worth the integration at all.
    test('every user carries an avatar', () async {
      final f = clientFor((_) => envelopeFixture('item_user_stats_movie.json'));
      addTearDown(f.client.dispose);

      final stats = await f.client.itemUserStats('2');
      expect(stats.every((s) => (s.userThumb ?? '').isNotEmpty), isTrue);
    });

    test('a show aggregates every episode into one row per user', () async {
      final f = clientFor((_) => envelopeFixture('item_user_stats_show.json'));
      addTearDown(f.client.dispose);

      final stats = await f.client.itemUserStats('46473');
      expect(stats, hasLength(2));
      expect(stats.first.totalPlays, greaterThan(100));
    });

    test('displayName prefers the admin-set friendly name', () {
      final f = clientFor((_) => envelopeFixture('item_user_stats_movie.json'));
      addTearDown(f.client.dispose);
      // Covered through the model rather than the wire, so the rule stays
      // asserted even if the capture is refreshed.
      expect((json.decode(fixture('item_user_stats_movie.json')) as List).first['friendly_name'], isNotEmpty);
    });
  });

  group('get_history', () {
    test('parses the container totals and the rows', () async {
      final f = clientFor((_) => envelopeFixture('history_movie.json'));
      addTearDown(f.client.dispose);

      final page = await f.client.history(ratingKey: '2');
      expect(page.entries, isNotEmpty);
      expect(page.recordsFiltered, greaterThan(0));

      final e = page.entries.first;
      expect(e.watchedStatus, 1);
      expect(e.percentComplete, 95);
      expect(e.platform, 'tvOS');
      expect(e.transcodeDecision, 'direct play');
      expect(e.location, 'lan');
    });

    test('series history is fetched on grandparent_rating_key', () async {
      final f = clientFor((_) => envelopeFixture('history_show.json'));
      addTearDown(f.client.dispose);

      await f.client.history(grandparentRatingKey: '46473');
      expect(f.requests.single['grandparent_rating_key'], '46473');
      expect(f.requests.single.containsKey('rating_key'), isFalse);
    });
  });

  group('watchersOf', () {
    // The whole reason this method exists: get_item_user_stats counts abandoned
    // plays, so "watched by" built on it would name someone who stopped at 10%.
    test('drops plays that were never finished', () async {
      final f = clientFor((_) => envelopeFixture('history_movie.json'));
      addTearDown(f.client.dispose);

      final rows = (json.decode(fixture('history_movie.json'))['data'] as List).cast<Map<String, dynamic>>();
      expect(
        rows.any((r) => r['watched_status'] == 0),
        isTrue,
        reason: 'the capture must contain an unfinished play for this test to mean anything',
      );

      final watchers = await f.client.watchersOf('2');
      expect(watchers.every((w) => w.isWatched), isTrue);
    });

    test('reports a person once, however often they rewatched', () async {
      final f = clientFor((_) => envelopeFixture('history_movie.json'));
      addTearDown(f.client.dispose);

      final watchers = await f.client.watchersOf('2');
      expect(watchers.map((w) => w.userId).toSet(), hasLength(watchers.length));
    });
  });

  group('get_users', () {
    test('parses the measured capture', () async {
      final f = clientFor((_) => envelopeFixture('users.json'));
      addTearDown(f.client.dispose);

      final users = await f.client.users();
      expect(users, hasLength(17));
      expect(users.every((u) => (u.thumb ?? '').isNotEmpty), isTrue);
      expect(users.where((u) => u.isAdmin), hasLength(1));
    });
  });

  group('get_item_watch_time_stats', () {
    test('exposes the all-time window as query_days 0', () async {
      final f = clientFor((_) => envelopeFixture('item_watch_time_stats.json'));
      addTearDown(f.client.dispose);

      final stats = await f.client.itemWatchTimeStats('2');
      final allTime = stats.singleWhere((s) => s.isAllTime);
      expect(allTime.totalPlays, 4);
      expect(allTime.totalTime, 6337);
    });
  });

  group('get_activity', () {
    test('an idle server answers with a container and no sessions', () async {
      final f = clientFor((_) => envelopeFixture('activity_idle.json'));
      addTearDown(f.client.dispose);

      final activity = await f.client.activity();
      expect(f.requests.single['cmd'], 'get_activity');
      expect(activity.streams, isEmpty);
      expect(activity.streamCount, 0);
      expect(activity.totalBandwidth, 0);
    });

    test('parses the measured movie stream', () async {
      final f = clientFor((_) => envelopeFixture('activity_movie_direct_play.json'));
      addTearDown(f.client.dispose);

      final s = (await f.client.activity()).streams.single;
      expect(s.mediaType, 'movie');
      expect(s.title, 'The Invite');
      expect(s.year, 2026);
      expect(s.grandparentTitle, isNull);
      expect(s.ratingKey, '57752');
      expect(s.decision, TautulliDecision.directPlay);
      expect(s.state, 'playing');
      expect(s.location, 'lan');
      expect(s.player, 'Pleya');
      expect(s.qualityProfile, 'Original');
    });

    test('parses the measured episode stream, series and numbering included', () async {
      final f = clientFor((_) => envelopeFixture('activity_episode_direct_play.json'));
      addTearDown(f.client.dispose);

      final s = (await f.client.activity()).streams.single;
      expect(s.isEpisode, isTrue);
      expect(s.grandparentTitle, 'Reacher');
      expect(s.title, 'Cage Fight');
      expect(s.seasonNumber, 4);
      expect(s.episodeNumber, 2);
      expect(s.percentComplete, 86);
    });

    // One container, two number types: this is why the readers are lenient
    // rather than cast. Session rows are strings throughout, including
    // progress_percent and the millisecond fields, while user_id is an int.
    test('the container mixes string and int numbers in adjacent fields', () {
      final container = json.decode(fixture('activity_movie_direct_play.json')) as Map<String, dynamic>;
      expect(container['stream_count'], isA<String>());
      expect(container['stream_count_transcode'], isA<int>());

      final session = (container['sessions'] as List).single as Map<String, dynamic>;
      expect(session['progress_percent'], isA<String>());
      expect(session['user_id'], isA<int>());
    });

    test('a transcode reports the container counts and the resolution drop', () async {
      final f = clientFor((_) => envelopeFixture('activity_episode_transcode.json'));
      addTearDown(f.client.dispose);

      final activity = await f.client.activity();
      expect(activity.transcodeCount, 1);
      expect(activity.directPlayCount, 0);

      final s = activity.streams.single;
      expect(s.decision, TautulliDecision.transcode);
      expect(s.sourceResolution, '1080p');
      expect(s.streamResolution, '720p');
      expect(s.qualityProfile, '4 Mbps 720p');
      expect(s.hardwareTranscode, isTrue);
    });

    // Measured, and the reason the summary is not built from these: Tautulli
    // left both empty while genuinely downscaling 1080p to 720p.
    test('transcode_width and transcode_height stay empty during a real transcode', () {
      final s = (json.decode(fixture('activity_episode_transcode.json'))['sessions'] as List).single;
      expect(s['transcode_width'], '');
      expect(s['transcode_height'], '');
    });

    test('a paused stream is readable as paused', () async {
      final f = clientFor((_) => envelopeFixture('activity_episode_transcode_paused.json'));
      addTearDown(f.client.dispose);

      final s = (await f.client.activity()).streams.single;
      expect(s.state, 'paused');
      expect(s.isPaused, isTrue);
    });

    test('remaining time comes from the millisecond fields', () async {
      final f = clientFor((_) => envelopeFixture('activity_episode_direct_play.json'));
      addTearDown(f.client.dispose);

      final s = (await f.client.activity()).streams.single;
      // 2929952 ms total, 2511050 ms in.
      expect(s.remainingSeconds, 418);
    });

    // The rule this whole integration is held to: an address may not reach a
    // model, a log, a cache key or a fixture.
    test('no capture carries an address', () {
      for (final name in [
        'activity_idle.json',
        'activity_movie_direct_play.json',
        'activity_episode_direct_play.json',
        'activity_episode_transcode.json',
        'activity_episode_transcode_paused.json',
      ]) {
        expect(fixture(name), isNot(contains('ip_address')), reason: name);
      }
    });
  });

  group('normalizeBaseUrl', () {
    // The measured instance runs behind a reverse proxy on 443, not on 8181, so
    // nothing may assume the default port or rewrite the path.
    test('keeps a reverse-proxied host and path intact', () {
      expect(TautulliConstants.normalizeBaseUrl('https://tautulli.example.test/'), 'https://tautulli.example.test');
      expect(
        TautulliConstants.normalizeBaseUrl('https://media.example.test/tautulli'),
        'https://media.example.test/tautulli',
      );
    });

    test('assumes http for a bare host:port, since LAN installs are plain', () {
      expect(TautulliConstants.normalizeBaseUrl('192.168.1.10:8181'), 'http://192.168.1.10:8181');
    });

    test('tolerates a pasted /api/v2 suffix', () {
      expect(TautulliConstants.normalizeBaseUrl('http://192.168.1.10:8181/api/v2'), 'http://192.168.1.10:8181');
    });
  });

  // Both a stale device token and an API key used in device mode come back as
  // "Invalid apikey", so the settings screen tells them apart by shape. Getting
  // this wrong costs the user real time: the log of 18 August shows three
  // register_device attempts with a master key while the screen kept saying the
  // token had expired.
  // Auth recognition used to be `message.contains('apikey')`, spread over two
  // places in _call. Any message that merely names the parameter then reads as
  // a rejected credential, and the screen answers that with "generate a new
  // token", which is an afternoon spent on the wrong thing.
  group('isAuthMessage', () {
    test('Tautulli\'s own wording is recognised', () {
      expect(TautulliClient.isAuthMessage('Invalid apikey'), isTrue);
      expect(TautulliClient.isAuthMessage('  invalid apikey  '), isTrue);
    });

    test('the variants other builds and proxies produce are recognised', () {
      expect(TautulliClient.isAuthMessage('Invalid api key'), isTrue);
      expect(TautulliClient.isAuthMessage('The apikey is invalid'), isTrue);
      expect(TautulliClient.isAuthMessage('401 Unauthorized'), isTrue);
      expect(TautulliClient.isAuthMessage('Authentication required'), isTrue);
    });

    test('naming the parameter is not the same as rejecting it', () {
      expect(TautulliClient.isAuthMessage('The apikey parameter is not required for this command'), isFalse);
      expect(TautulliClient.isAuthMessage('Item does not exist'), isFalse);
      expect(TautulliClient.isAuthMessage(''), isFalse);
    });
  });

  group('looksLikeApiKey', () {
    test('a master key is 32 lowercase hex characters', () {
      expect(TautulliConstants.looksLikeApiKey('b73978aaa7154073b9048bbf0f33966a'), isTrue);
    });

    test('a device token carries characters outside the hex alphabet', () {
      expect(TautulliConstants.looksLikeApiKey('nmbmTEa2qxMOz0X2OF_sqrpaR5dXqtNO'), isFalse);
    });

    test('surrounding whitespace does not change the answer', () {
      expect(TautulliConstants.looksLikeApiKey('  b73978aaa7154073b9048bbf0f33966a\n'), isTrue);
    });

    test('length matters, so a truncated or padded key is not one', () {
      expect(TautulliConstants.looksLikeApiKey('b73978aaa7154073b9048bbf0f33966'), isFalse);
      expect(TautulliConstants.looksLikeApiKey('b73978aaa7154073b9048bbf0f33966ab'), isFalse);
    });

    test('uppercase hex is not what Tautulli generates', () {
      expect(TautulliConstants.looksLikeApiKey('B73978AAA7154073B9048BBF0F33966A'), isFalse);
    });

    test('an empty field is not a key', () {
      expect(TautulliConstants.looksLikeApiKey(''), isFalse);
      expect(TautulliConstants.looksLikeApiKey('   '), isFalse);
    });
  });
}
