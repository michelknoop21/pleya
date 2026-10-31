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

  test('the wait of the old title ends once the reload owns the transition, for every path to another title', () {
    final body = _method(navigation, 'Future<bool> _reloadMediaInPlace({');
    final claim = body.indexOf('_playbackTransition = _PlaybackTransition.reloadingMedia;');
    final abort = body.indexOf('_deferredSubtitles.abortPending()');
    expect(claim, isNonNegative);
    expect(body.substring(0, abort), endsWith('if (isItemChange) '), reason: 'a source switch keeps its own wait');
    expect(abort, greaterThan(claim), reason: 'a refused reload leaves the track of the playing title alone');
    expect(abort, lessThan(body.indexOf('playbackResolver.resolve(')), reason: 'before the next title opens');

    expect(_method(navigation, 'Future<void> _navigateToEpisode('), isNot(contains('abortPending')));
    expect(
      File('lib/screens/video_player/parts/watch_together.dart').readAsStringSync(),
      contains('_reloadMediaInPlace('),
    );
  });

  test('the cycle key reaches the source list on a server that selects subtitles', () {
    final body = _method('lib/screens/video_player/parts/companion_remote.dart', 'void _cycleSubtitleTrack() {');
    final source = body.indexOf('_switchPlaybackSource(newSubtitleStreamId: next.id)');
    expect(body, contains('_serverSupportsSubtitleSelection && !_isOfflinePlayback'));
    expect(source, isNonNegative);
    expect(source, lessThan(body.indexOf('_trackManager?.cycleSubtitleTrack()')));
  });

  test('the cycle key announces a track only when the switch can run', () {
    final body = _method('lib/screens/video_player/parts/companion_remote.dart', 'void _cycleSubtitleTrack() {');
    final accepted = body.indexOf('final accepted = _playbackTransition == _PlaybackTransition.idle;');
    final notice = body.indexOf('if (accepted && mounted) {');
    expect(accepted, isNonNegative);
    expect(accepted, lessThan(body.indexOf('_switchPlaybackSource(')), reason: 'read before the switch can claim it');
    expect(notice, greaterThan(accepted));
    expect(notice, lessThan(body.indexOf('showAppSnackBar(')));
  });
}
