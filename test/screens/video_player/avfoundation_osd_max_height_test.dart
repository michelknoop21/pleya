import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/video_player_screen.dart';

void main() {
  group('avfoundationOsdMaxHeight', () {
    test('Apple TV caps the subtitle layer at 1080p so a 4K display does not allocate a 4K pool', () {
      expect(avfoundationOsdMaxHeight(isAppleTV: true), 1080);
    });

    test('iPhone and iPad keep the display resolution', () {
      expect(avfoundationOsdMaxHeight(isAppleTV: false), 0);
    });
  });
}
