import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/utils/player_utils.dart';

/// A Pleya Server conversion that started at a position keeps the title's
/// timestamps (DEC-XXX, startpositie in het afspeelplan). The player then reads
/// title time itself, so nothing is added on the Dart side.
void main() {
  group('playbackOpenTiming', () {
    test('a stream that keeps the title time opens absolute, at the resume point, with the title duration', () {
      final timing = playbackOpenTiming(
        backend: MediaBackend.pleyaServer,
        isTranscoding: false,
        resumePosition: const Duration(seconds: 70),
        durationMs: 6720000,
        streamStart: const Duration(milliseconds: 60186),
      );

      expect(timing.absoluteTimestamps, isTrue);
      expect(timing.timelineOffset, Duration.zero);
      expect(timing.mediaStart, const Duration(seconds: 70));
      // The stream is only the rest of the film; its own length would put the
      // position past the end of the seek bar.
      expect(timing.timelineDuration, const Duration(milliseconds: 6720000));
    });

    test('a Pleya Server stream from zero opens as before', () {
      final timing = playbackOpenTiming(
        backend: MediaBackend.pleyaServer,
        isTranscoding: true,
        resumePosition: const Duration(seconds: 70),
        durationMs: 6720000,
      );

      expect(timing.absoluteTimestamps, isFalse);
      expect(timing.timelineOffset, Duration.zero);
      expect(timing.mediaStart, const Duration(seconds: 70));
    });

    test('Plex keeps its own source offset', () {
      final timing = playbackOpenTiming(
        backend: MediaBackend.plex,
        isTranscoding: true,
        resumePosition: const Duration(seconds: 70),
        durationMs: 6720000,
      );

      expect(timing.absoluteTimestamps, isFalse);
      expect(timing.timelineOffset, const Duration(seconds: 70));
      expect(timing.mediaStart, isNull);
    });
  });

  group('seekNeedsNewStream', () {
    const streamStart = Duration(milliseconds: 60186);

    test('before the first frame of the stream a new stream is planned', () {
      expect(seekNeedsNewStream(streamStart: streamStart, target: const Duration(seconds: 10)), isTrue);
    });

    test('inside the stream the player seeks itself', () {
      expect(seekNeedsNewStream(streamStart: streamStart, target: streamStart), isFalse);
      expect(seekNeedsNewStream(streamStart: streamStart, target: const Duration(seconds: 90)), isFalse);
    });

    test('a stream from zero never needs one', () {
      expect(seekNeedsNewStream(streamStart: null, target: Duration.zero), isFalse);
    });
  });
}
