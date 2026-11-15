import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/mpv/player/player_native.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/services/playback_initialization_types.dart';

import '../../pleya_server/pleya_fake_server.dart';

/// A resumed Pleya Server conversion, end to end through the pieces the screen
/// joins: the plan, [playbackOpenTiming], [openWithTiming] on mpv, and the
/// watch-state report. The stream keeps the title's timestamps, so mpv's time is
/// the title's and nothing is added on top (DEC-XXX, startpositie in het
/// afspeelplan). Adding the measured start as an offset, as the Plex path does,
/// would report 75 s as 135 s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a resumed conversion reports title time to /watch-state', () async {
    final server = PleyaFakeServer(watchState: true)
      ..playbackPlanCapability = true
      ..playbackStartPositionCapability = true
      ..planDeliveryMode = 'transcode';
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    server.addItem(id: 'movie-1', kind: 'movie', title: 'Grease', libraryId: 'lib-films', durationMs: 6720000);
    final item = MediaItem(
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      id: 'movie-1',
      title: 'Grease',
      viewOffsetMs: 70000,
      durationMs: 6720000,
      mediaVersions: const [MediaVersion(id: 'version-1', container: 'mkv')],
    );
    final client = server.client();
    await client.refreshCapabilities();

    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methods = MethodChannel('com.pleya/mpv_player');
    const events = MethodChannel('com.pleya/mpv_player/events');
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return call.method == 'initialize' ? true : null;
    });
    messenger.setMockMethodCallHandler(events, (call) async => null);
    final player = PlayerNative();
    try {
      // `startAtViewOffset` and `resumePosition` are passed by hand here. The
      // screen's own calls (video_player_screen.dart, episode_navigation.dart,
      // playback_start.dart) are not covered by this test; the Verify scenario
      // pleya_verify/scenarios/ios.pleya.start-position.yaml covers those.
      final result = await client.getPlaybackInitialization(
        PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0, startAtViewOffset: true),
      );
      expect(result.streamStart, const Duration(milliseconds: 60186));

      final timing = playbackOpenTiming(
        backend: item.backend,
        isTranscoding: result.isTranscoding,
        resumePosition: const Duration(seconds: 70),
        durationMs: item.durationMs,
        streamStart: result.streamStart,
      );
      await openWithTiming(player, Media(result.videoUrl!, start: timing.mediaStart), timing, play: true);

      final loadfile = calls
          .where((c) => c.method == 'command')
          .map((c) => Map<Object?, Object?>.from(c.arguments as Map)['args'] as List)
          .firstWhere((args) => args.first == 'loadfile');
      expect(loadfile, contains('rebase-start-time=no'));

      // mpv keeps the stream's timestamps: 75 s into the film is time-pos 75.
      player.handlePropertyChange('time-pos', 75.0);
      player.handlePropertyChange('duration', 59.889);
      await client.reportPlaybackProgress(
        itemId: item.id,
        position: player.currentPosition,
        duration: player.state.duration,
      );

      expect(server.watchEvents.last['position_ms'], 75000);
      expect(server.watchEvents.last['duration_ms'], 6720000);
    } finally {
      await player.dispose();
      await client.closeGracefully();
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMethodCallHandler(events, null);
    }
  });
}
