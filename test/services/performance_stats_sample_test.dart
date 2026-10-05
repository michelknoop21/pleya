import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/widgets/video_controls/widgets/performance_overlay/performance_stats_service.dart';

class _StatsPlayer implements Player {
  _StatsPlayer({this.providesNativeStats = false});

  @override
  final bool providesNativeStats;
  Map<String, String?> properties = {};
  Map<String, dynamic> nativeStats = {};
  bool fail = false;

  @override
  Future<String> runtimePlayerType() async => providesNativeStats ? 'exoplayer' : 'mpv';

  @override
  Future<String?> getProperty(String name) async {
    if (fail) throw StateError('fixture read failed');
    return properties[name];
  }

  @override
  Future<Map<String, dynamic>> getStats() async => nativeStats;

  // One-shot sampling must never install player-stream listeners.
  @override
  PlayerStreams get streams => throw StateError('one-shot read subscribed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one-shot MPV sampling never retains a previous failed or missing observation', () async {
    final player = _StatsPlayer()..properties = {'video-codec': 'hevc', 'demuxer-cache-duration': '0'};
    final service = PerformanceStatsService(player);
    addTearDown(service.dispose);
    final first = await service.sample();
    expect(first?.videoCodec, 'HEVC');
    expect(first?.cacheDuration, 0);
    player.fail = true;
    final previousLogger = appLogger;
    try {
      appLogger = Logger(level: Level.off);
      expect(await service.sample(), isNull);
    } finally {
      appLogger = previousLogger;
    }
    player.fail = false;
    player.properties = {};
    final missing = await service.sample();
    expect(missing?.videoCodec, isNull);
    expect(missing?.cacheDuration, isNull);
  });

  test('native missing buffer remains unknown while measured zero remains zero', () async {
    final player = _StatsPlayer(providesNativeStats: true)..nativeStats = {'playerType': 'exoplayer'};
    final service = PerformanceStatsService(player);
    addTearDown(service.dispose);
    expect((await service.sample())?.cacheDuration, isNull);
    player.nativeStats['totalBufferedDurationMs'] = 0;
    expect((await service.sample())?.cacheDuration, 0);
  });

  test('observed EAC3 remains distinct from AC3', () async {
    final player = _StatsPlayer()..properties = {'audio-codec-name': 'eac3'};
    final service = PerformanceStatsService(player);
    addTearDown(service.dispose);
    expect((await service.sample())?.audioCodec, 'EAC3');
    player.properties['audio-codec-name'] = 'ac3';
    expect((await service.sample())?.audioCodec, 'AC3');
  });
}
