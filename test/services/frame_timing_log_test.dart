import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/frame_timing_log.dart';

void main() {
  test('percentiles come from the sorted durations, not the arrival order', () {
    final summary = FrameTimingSummary.of([9000, 1000, 5000], [3000, 2000, 1000]);

    expect(summary.frames, 3);
    expect(summary.buildP50, 5000);
    expect(summary.buildMax, 9000);
    expect(summary.rasterP50, 2000);
  });

  test('a frame over budget on either thread counts once as missed', () {
    final summary = FrameTimingSummary.of([20000, 1000, 20000], [1000, 20000, 20000]);

    expect(summary.missed, 3);
  });

  test('a frame inside the budget on both threads is not missed', () {
    expect(FrameTimingSummary.of([16000], [16000]).missed, 0);
  });

  test('the log line reads p50, p95 and max in milliseconds', () {
    final line = FrameTimingSummary.of([2000], [24000]).toString();

    expect(line, 'frames=1 missed=1 build=2.0/2.0/2.0 raster=24.0/24.0/24.0 pacing=0.0/0.0');
  });

  test('pacing shows a dropped frame and leaves idle time out', () {
    final summary = FrameTimingSummary.of(
      [1000, 1000, 1000, 1000, 1000],
      [1000, 1000, 1000, 1000, 1000],
      starts: [0, 16667, 33334, 66667, 400000],
    );

    expect(summary.pacingP50, 16667);
    expect(summary.pacingMax, 33333);
  });
}
