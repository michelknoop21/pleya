import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/app_logger.dart';
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

  testWidgets('a focus change on TV logs once, after the frame that shows it', (tester) async {
    TvDetectionService.debugSetTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetTVOverride(null));
    startFocusFrameLog();
    final a = FocusNode();
    final b = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await tester.pumpWidget(
      Column(
        children: [
          Focus(focusNode: a, child: const SizedBox()),
          Focus(focusNode: b, child: const SizedBox()),
        ],
      ),
    );
    int count() => MemoryLogOutput.getLogs().where((e) => e.message.startsWith('FocusFrame: +')).length;
    final before = count();

    // Focus applies in a microtask, so the change can land after the pumped
    // frame; the second pump is the frame that shows it.
    a.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(count() - before, 1);

    b.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(count() - before, 2);
  });

  test('on TV a memory checkpoint lands every five minutes', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    TvDetectionService.debugSetTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetTVOverride(null));
    int count() => MemoryLogOutput.getLogs().where((e) => e.message.startsWith('MemoryCheckpoint rss=')).length;
    fakeAsync((async) {
      final before = count();
      final timer = startMemoryCheckpointLog();
      async.elapse(const Duration(minutes: 11));
      timer?.cancel();
      expect(count() - before, 2);
    });
  });

  test('off TV there is no memory checkpoint timer', () {
    TvDetectionService.debugSetTVOverride(false);
    addTearDown(() => TvDetectionService.debugSetTVOverride(null));
    expect(startMemoryCheckpointLog(), isNull);
  });
}
