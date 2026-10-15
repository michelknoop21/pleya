import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/player/player.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/playback_memory_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('memory checkpoints read only bounded numeric demuxer properties', () async {
    final player = _MemoryPlayer();
    await logPlaybackMemoryCheckpoint(player, 'diagnostic-test');
    expect(player.reads, [
      'demuxer-cache-state/total-bytes',
      'demuxer-cache-state/fw-bytes',
      'demuxer-max-bytes',
      'demuxer-max-back-bytes',
    ]);
    final line = MemoryLogOutput.getLogs().firstWhere((e) => e.message.contains('diagnostic-test')).message;
    expect(line, contains('total-bytes=104857600'));
    expect(line, contains('fw-bytes=unavailable'));
    expect(line, contains('demuxer-max-bytes=unavailable'));
    expect(line, isNot(contains('private-value')));
  });

  test('memory checkpoint includes actual Flutter cache counts', () {
    final cache = TestWidgetsFlutterBinding.instance.imageCache;
    logCheckpoint('cache-diagnostic-test');
    final line = MemoryLogOutput.getLogs().firstWhere((e) => e.message.contains('cache-diagnostic-test')).message;
    expect(line, contains('imageCacheBytes=${cache.currentSizeBytes}'));
    expect(line, contains('liveImages=${cache.liveImageCount}'));
  });

  test('non-mpv backends do not receive mpv queries', () async {
    final player = _MemoryPlayer(type: 'exoplayer');
    await logPlaybackMemoryCheckpoint(player, 'non-mpv');
    expect(player.reads, isEmpty);
  });
}

class _MemoryPlayer implements Player {
  _MemoryPlayer({this.type = 'mpv'});
  final String type;
  final reads = <String>[];

  @override
  String get playerType => type;

  @override
  Future<String?> getProperty(String name) async {
    reads.add(name);
    if (name == 'demuxer-max-bytes') throw StateError('player closed');
    if (name == 'demuxer-cache-state/fw-bytes') return 'private-value';
    return '104857600';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
