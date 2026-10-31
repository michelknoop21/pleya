import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `VideoPlayerScreenState` cannot be built in a widget test, so the order inside
/// these methods is read from the source. The behaviour on either side has its own
/// tests in `deferred_subtitle_loader_test.dart` and `source_subtitle_cycle_test.dart`.
String _method(String path, String signature) {
  final source = File(path).readAsStringSync();
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature moved out of $path');
  final end = source.indexOf(RegExp(r'^  (Future|void|bool|int)\b', multiLine: true), start + signature.length);
  return source.substring(start, end < 0 ? source.length : end);
}

void main() {
  const navigation = 'lib/screens/video_player/parts/episode_navigation.dart';

  test('choosing the track that is being prepared does not stop its preparation', () {
    final body = _method(navigation, 'Future<void> _switchPlaybackSource(');
    final unchanged = body.indexOf(
      'if (!isVersionChange && !isPresetChange && !isAudioChange && !isSubtitleChange) return;',
    );
    final abort = body.indexOf('_deferredSubtitles.abortPending()');
    expect(unchanged, isNonNegative);
    expect(abort, greaterThan(unchanged));
  });

  test('the wait of the old episode ends before the next one opens', () {
    final body = _method(navigation, 'Future<void> _navigateToEpisode(');
    final abort = body.indexOf('_deferredSubtitles.abortPending()');
    expect(abort, isNonNegative);
    expect(abort, lessThan(body.indexOf('_reloadMediaInPlace(')));
  });

  test('the cycle key reaches the source list on a server that selects subtitles', () {
    final body = _method('lib/screens/video_player/parts/companion_remote.dart', 'void _cycleSubtitleTrack() {');
    final source = body.indexOf('_switchPlaybackSource(newSubtitleStreamId: next.id)');
    expect(body, contains('_serverSupportsSubtitleSelection && !_isOfflinePlayback'));
    expect(source, isNonNegative);
    expect(source, lessThan(body.indexOf('_trackManager?.cycleSubtitleTrack()')));
  });
}
