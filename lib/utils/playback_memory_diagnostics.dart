import '../mpv/player/player.dart';
import 'app_logger.dart';

/// Read-only demuxer measurements, distinct from process RSS and GPU memory.
Future<void> logPlaybackMemoryCheckpoint(Player player, String stage) async {
  if (player.playerType != 'mpv') return;
  const properties = [
    'demuxer-cache-state/total-bytes',
    'demuxer-cache-state/fw-bytes',
    'demuxer-max-bytes',
    'demuxer-max-back-bytes',
  ];
  final timer = Stopwatch()..start();
  final values = await Future.wait(
    properties.map((name) async {
      try {
        final value = await player.getProperty(name).timeout(const Duration(seconds: 2), onTimeout: () => null);
        return int.tryParse(value ?? '');
      } catch (_) {
        // Unsupported properties and a player closing mid-sample are expected.
        return null;
      }
    }),
  );
  appLogger.i(
    'Playback memory: $stage sampleMs=${timer.elapsedMilliseconds} '
    '${[for (var i = 0; i < properties.length; i++) '${properties[i]}=${values[i] ?? 'unavailable'}'].join(' ')}',
  );
}
