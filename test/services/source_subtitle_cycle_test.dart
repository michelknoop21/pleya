import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/services/source_subtitle_cycle.dart';

void main() {
  final tracks = [
    for (final id in [11, 22, 33]) MediaSubtitleTrack(id: id, selected: false, forced: false),
  ];

  test('walks the source list and wraps at the end', () {
    expect(nextSourceSubtitleTrack(tracks, 11)?.id, 22);
    expect(nextSourceSubtitleTrack(tracks, 22)?.id, 33);
    expect(nextSourceSubtitleTrack(tracks, 33)?.id, 11);
  });

  test('starts at the first track from off or from an id it does not know', () {
    expect(nextSourceSubtitleTrack(tracks, 0)?.id, 11);
    expect(nextSourceSubtitleTrack(tracks, 99)?.id, 11);
    expect(nextSourceSubtitleTrack(tracks, null)?.id, 11);
  });

  test('has nothing to offer without tracks', () {
    expect(nextSourceSubtitleTrack(const [], 11), isNull);
  });
}
