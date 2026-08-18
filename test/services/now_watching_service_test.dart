import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/media/watch_session.dart';
import 'package:pleya/models/tautulli/tautulli_activity.dart';
import 'package:pleya/services/now_watching_service.dart';
import 'package:pleya/services/tautulli/tautulli_client.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

/// The translation from Tautulli's 238-field session rows to the neutral
/// [WatchSession] the UI renders, asserted against captures of a live instance.
/// What each capture showed is written up in `test/fixtures/tautulli/README.md`.

TautulliActivity activityFrom(String fixture) => TautulliActivity.fromJson(
  json.decode(File('test/fixtures/tautulli/$fixture').readAsStringSync()) as Map<String, dynamic>,
);

/// The one account in the captures, which is also the admin's own.
const capturedUserId = 4725462;

void main() {
  const service = NowWatchingService();

  group('mapping a measured stream', () {
    test('a movie carries its own title and year', () {
      final now = service.map(activityFrom('activity_movie_direct_play.json'));
      final s = now.sessions.single;

      expect(s.title, 'The Invite');
      expect(s.subtitle, '2026');
      expect(s.ratingKey, '57752');
      expect(s.delivery, StreamDelivery.directPlay);
      expect(s.transcodeSummary, isNull);
      expect(s.isLan, isTrue);
      expect(s.userName, 'user67');
    });

    // A row saying "Cage Fight" would mean nothing out of context, so an
    // episode is named by its series with the numbering underneath.
    test('an episode is named by its series', () {
      final now = service.map(activityFrom('activity_episode_direct_play.json'));
      final s = now.sessions.single;

      expect(s.title, 'Reacher');
      expect(s.subtitle, 'S4 · E2 · Cage Fight');
      expect(s.progressPercent, 86);
      expect(s.remainingSeconds, 418);
      expect(s.isPaused, isFalse);
    });

    test('a paused stream maps to paused', () {
      final now = service.map(activityFrom('activity_episode_transcode_paused.json'));
      expect(now.sessions.single.isPaused, isTrue);
    });

    // Tautulli reports player and product as the same word for this app; saying
    // it twice would be noise.
    test('the player label does not repeat itself', () {
      final now = service.map(activityFrom('activity_movie_direct_play.json'));
      expect(now.sessions.single.playerLabel, 'Pleya');
    });

    test('artwork stays null without a client to resolve Plex paths', () {
      final now = service.map(activityFrom('activity_movie_direct_play.json'));
      expect(now.sessions.single.artUrl, isNull);
    });
  });

  group('transcode summary', () {
    test('names the resolution drop from the measured transcode', () {
      final now = service.map(activityFrom('activity_episode_transcode.json'));
      final s = now.sessions.single;

      expect(s.delivery, StreamDelivery.transcode);
      expect(s.transcodeSummary, '1080p → 720p');
    });

    // The measured transcode kept h264 and changed only the audio, so a summary
    // built on the video codec would have claimed nothing was happening.
    test('falls back to the audio codec when only the audio is re-encoded', () {
      const stream = TautulliStream(
        sessionKey: '1',
        decision: TautulliDecision.transcode,
        sourceResolution: '1080p',
        streamResolution: '1080p',
        sourceVideoCodec: 'h264',
        streamVideoCodec: 'h264',
        sourceAudioCodec: 'eac3',
        streamAudioCodec: 'opus',
      );
      expect(NowWatchingService.transcodeSummary(stream), 'EAC3 → OPUS');
    });

    test('says nothing when Tautulli reports nothing that differs', () {
      const stream = TautulliStream(
        sessionKey: '1',
        decision: TautulliDecision.transcode,
        sourceResolution: '1080p',
        streamResolution: '1080p',
        sourceVideoCodec: 'h264',
        streamVideoCodec: 'h264',
      );
      expect(NowWatchingService.transcodeSummary(stream), isNull);
    });
  });

  group('the admin is not news', () {
    test('own playback is filtered out and counted separately', () {
      final now = service.map(activityFrom('activity_movie_direct_play.json'), selfUserId: capturedUserId);

      expect(now.sessions, isEmpty);
      expect(now.ownSessionCount, 1);
      expect(now.hasOthers, isFalse);
      // The totals still describe the server, so the panel can stay truthful
      // about load even when nothing is listed.
      expect(now.totalBandwidthKbps, greaterThan(0));
    });

    test('someone else stays in the list', () {
      final now = service.map(activityFrom('activity_movie_direct_play.json'), selfUserId: 999);
      expect(now.sessions, hasLength(1));
      expect(now.ownSessionCount, 0);
      expect(now.hasOthers, isTrue);
    });
  });

  group('totals', () {
    test('come from the container Tautulli computed', () {
      final now = service.map(activityFrom('activity_episode_transcode.json'));
      expect(now.totalBandwidthKbps, 3939);
      expect(now.lanBandwidthKbps, 3939);
      expect(now.wanBandwidthKbps, 0);
      expect(now.transcodeCount, 1);
      expect(now.hasTranscode, isTrue);
    });
  });

  group('failure', () {
    // Null rather than empty, and never a throw: "nobody is watching" is news
    // the UI acts on, "I could not ask" is something it rides out.
    test('an unreachable instance resolves to null instead of throwing', () async {
      final client = TautulliClient(
        TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: TautulliAuthMode.apiKey, token: 'T'),
        httpClient: MockClient((_) async => throw const SocketException('no route to host')),
      );
      addTearDown(client.dispose);

      expect(await service.resolve(client), isNull);
    });

    test('a Tautulli error envelope resolves to null too', () async {
      final client = TautulliClient(
        TautulliSession(baseUrl: 'https://tautulli.example.test', authMode: TautulliAuthMode.apiKey, token: 'T'),
        httpClient: MockClient(
          (_) async => http.Response(
            json.encode({
              'response': {'result': 'error', 'message': 'Invalid apikey', 'data': null},
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);

      expect(await service.resolve(client), isNull);
    });
  });
}
