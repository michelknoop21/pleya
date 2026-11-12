import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_part.dart';
import 'package:pleya/media/media_stream.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/services/playback_initialization_types.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// The native player on a stream session (DEC-051) instead of the access
/// token. mpv replays the headers it got at open on every reconnect and seek,
/// so whatever it holds has to stay valid for the whole film, also after a
/// long pause.
void main() {
  late PleyaFakeServer server;
  late PleyaServerClient client;

  MediaItem movie({bool sidecar = false}) {
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    server.addItem(id: 'movie-1', kind: 'movie', title: 'Grease', libraryId: 'lib-films', durationMs: 6720000);
    server.versionBytes['version-1'] = List<int>.generate(64, (i) => i);
    return MediaItem(
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      id: 'movie-1',
      title: 'Grease',
      durationMs: 6720000,
      mediaVersions: [
        MediaVersion(
          id: 'version-1',
          container: 'mkv',
          parts: [
            if (sidecar)
              const MediaPart(
                id: 'version-1',
                streams: [
                  MediaStream(
                    id: 'sidecar',
                    kind: MediaStreamKind.subtitle,
                    codec: 'srt',
                    languageCode: 'nld',
                    sidecarPath: 'pleya-subtitle:sidecar',
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Future<PleyaServerClient> connected() async {
    final c = server.client();
    await c.refreshCapabilities();
    return c;
  }

  Future<PlaybackInitializationResult> play(MediaItem item) =>
      client.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0));

  int mints() => server.requests.where((r) => r == '/pleya/v1/auth/stream-session').length;

  /// What mpv does with the result: open the URL with exactly these headers.
  Future<int> openAsPlayer(String url, Map<String, String>? headers) async {
    final request = http.Request('GET', Uri.parse(url))..headers.addAll(headers ?? const {});
    return (await server.handle(request)).statusCode;
  }

  tearDown(() => client.close());

  test('mpv gets ss in the URL and the secret as a cookie, and no bearer', () async {
    server = PleyaFakeServer(watchState: true);
    final item = movie();
    client = await connected();

    final result = await play(item);

    expect(result.videoUrl, 'http://nas.lan:8832/pleya/v1/stream/version-1?ss=ss-1');
    expect(result.streamHeaders, {'Cookie': 'pleya_ss_ss-1=secret-1'});
    expect(result.videoUrl, isNot(contains('secret-1')));
    expect(await openAsPlayer(result.videoUrl!, result.streamHeaders), 200);
  });

  test('the session keeps opening the stream after the access token was replaced', () async {
    server = PleyaFakeServer(watchState: true);
    final item = movie();
    client = await connected();
    final result = await play(item);

    // The app refreshes its token; the one it had is now refused. That is the
    // reconnect that failed on the Apple TV with a bearer in mpv's headers.
    server.rejectCurrentAccessTokens = true;
    expect(await openAsPlayer(result.videoUrl!, {...?result.streamHeaders, 'Authorization': 'Bearer at-1'}), 401);
    expect(await openAsPlayer(result.videoUrl!, result.streamHeaders), 200);
  });

  test('a reopen of the same version reuses its session instead of using up the eight', () async {
    server = PleyaFakeServer(watchState: true);
    final item = movie();
    client = await connected();

    final first = await play(item);
    final second = await play(item);

    expect(second.videoUrl, first.videoUrl);
    expect(mints(), 1);
    expect(server.streamSessionUses, ['HEAD /stream/version-1']);
  });

  test('a session the server no longer knows is replaced, not handed to mpv', () async {
    server = PleyaFakeServer(watchState: true);
    final item = movie();
    client = await connected();

    await play(item);
    server.streamSessions.remove('ss-1');
    final again = await play(item);

    expect(again.videoUrl, endsWith('?ss=ss-2'));
    expect(again.streamHeaders, {'Cookie': 'pleya_ss_ss-2=secret-2'});
  });

  /// A client and a resolved result inside [time], the way the player gets it.
  PlaybackInitializationResult resolve(FakeAsync time, MediaItem item) {
    final local = client = server.client();
    unawaited(local.refreshCapabilities());
    time.flushMicrotasks();
    late PlaybackInitializationResult result;
    play(item).then((r) => result = r);
    time.flushMicrotasks();
    return result;
  }

  test('a paused player keeps its session alive until the result leaves the player', () {
    fakeAsync((time) {
      server = PleyaFakeServer(watchState: true);
      final result = resolve(time, movie());
      result.hold!();

      // Two hours of pause: nothing else uses the session, the keep-alive does.
      time.elapse(const Duration(hours: 2));
      expect(server.streamSessionUses.length, 60);
      expect(server.streamSessionUses.toSet(), {'HEAD /stream/version-1'});

      // Also without a stop report: a player left before the first frame sends none.
      result.release!();
      server.streamSessionUses.clear();
      time.elapse(const Duration(hours: 1));
      expect(server.streamSessionUses, isEmpty, reason: 'a released result must not hold one of the eight');
      client.close();
    });
  });

  test('a result the player never takes holds nothing', () {
    fakeAsync((time) {
      server = PleyaFakeServer(watchState: true);
      resolve(time, movie());

      time.elapse(const Duration(hours: 1));
      expect(server.streamSessionUses, isEmpty);
      client.close();
    });
  });

  test('each result ends only its own keep-alive', () {
    fakeAsync((time) {
      server = PleyaFakeServer(watchState: true);
      final item = movie();
      final older = resolve(time, item);
      late PlaybackInitializationResult newer;
      play(item).then((r) => newer = r);
      time.flushMicrotasks();
      older.hold!();
      newer.hold!();
      server.streamSessionUses.clear();

      older.release!();
      time.elapse(const Duration(minutes: 3));
      expect(server.streamSessionUses, ['HEAD /stream/version-1']);
      client.close();
    });
  });

  test('a refused keep-alive stops asking, a failing server does not', () {
    fakeAsync((time) {
      server = PleyaFakeServer(watchState: true);
      resolve(time, movie()).hold!();
      int asked() => server.requests.where((r) => r.startsWith('/pleya/v1/stream/')).length;

      server.queueFailure(status: 503, errorCode: 'server.unavailable', pathPrefix: '/stream/');
      time.elapse(const Duration(minutes: 2));
      final afterFailure = asked();
      time.elapse(const Duration(minutes: 2));
      expect(asked(), afterFailure + 1, reason: 'a 503 is worth the next tick');

      server.streamSessions.remove('ss-1');
      time.elapse(const Duration(minutes: 2));
      final afterRefusal = asked();
      time.elapse(const Duration(hours: 1));
      expect(asked(), afterRefusal);
      client.close();
    });
  });

  test('two overlapping starts of one version share one session', () async {
    server = PleyaFakeServer(watchState: true);
    final item = movie();
    client = await connected();

    final both = await Future.wait([play(item), play(item)]);

    expect(mints(), 1);
    expect(both.map((r) => r.videoUrl).toSet(), {'http://nas.lan:8832/pleya/v1/stream/version-1?ss=ss-1'});
  });

  test('sidecar subtitles carry a stream token, because /subtitles takes no stream session', () async {
    server = PleyaFakeServer(watchState: true);
    final item = movie(sidecar: true);
    server.subtitleFiles['sidecar'] = '1\n00:00:01,000 --> 00:00:02,000\nHallo\n';
    client = await connected();

    final result = await play(item);

    final uri = result.externalSubtitles.single.uri!;
    expect(uri, 'http://nas.lan:8832/pleya/v1/subtitles/sidecar?stream_token=st-for-version-1');
    expect(await openAsPlayer(uri, result.streamHeaders), 200);
  });

  test('HLS gets the session as well: the server repeats ss on every playlist entry', () async {
    server = PleyaFakeServer(watchState: true)
      ..playbackPlanCapability = true
      ..planDeliveryMode = 'transcode';
    final item = movie();
    client = await connected();

    final result = await play(item);

    expect(result.isTranscoding, isTrue);
    expect(result.videoUrl, 'http://nas.lan:8832/pleya/v1/playback/sessions/sess-1/index.m3u8?ss=ss-1');
    expect(result.streamHeaders, {'Cookie': 'pleya_ss_ss-1=secret-1'});
    expect(await openAsPlayer(result.videoUrl!, result.streamHeaders), 200);
  });

  test('without the capability the player keeps the bearer header', () async {
    server = PleyaFakeServer();
    final item = movie();
    client = await connected();

    final result = await play(item);

    expect(result.videoUrl, 'http://nas.lan:8832/pleya/v1/stream/version-1');
    expect(result.streamHeaders, isNull);
    expect(mints(), 0);
  });

  test('a refused session falls back to the bearer header instead of failing playback', () async {
    server = PleyaFakeServer(watchState: true)..streamSessionFailureStatus = 409;
    final item = movie();
    client = await connected();

    final result = await play(item);

    expect(result.videoUrl, 'http://nas.lan:8832/pleya/v1/stream/version-1');
    expect(result.streamHeaders, isNull);
    expect(client.streamHeaders['Authorization'], startsWith('Bearer '));
  });
}
