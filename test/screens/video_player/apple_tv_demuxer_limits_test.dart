import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/video_player_screen.dart';

void main() {
  group('appleTvDemuxerLimits', () {
    test('Apple TV in auto mode caps the demuxer at 64 MiB ahead and 16 MiB behind (PLR12)', () {
      expect(appleTvDemuxerLimits(isAppleTV: true, bufferSizeMB: 0), {
        'demuxer-max-bytes': '67108864',
        'demuxer-max-back-bytes': '16777216',
      });
    });

    test('an explicit buffer size on Apple TV stays the user\'s choice', () {
      expect(appleTvDemuxerLimits(isAppleTV: true, bufferSizeMB: 256), isEmpty);
    });

    test('other platforms keep their own limits', () {
      expect(appleTvDemuxerLimits(isAppleTV: false, bufferSizeMB: 0), isEmpty);
    });
  });
}
