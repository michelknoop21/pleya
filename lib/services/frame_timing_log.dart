import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';

import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';

/// Frame cost at one moment of use, in microseconds.
class FrameTimingSummary {
  const FrameTimingSummary({
    required this.frames,
    required this.buildP50,
    required this.buildP95,
    required this.buildMax,
    required this.rasterP50,
    required this.rasterP95,
    required this.rasterMax,
    required this.missed,
    required this.pacingP50,
    required this.pacingMax,
  });

  /// [missed] counts frames whose build or raster alone took longer than
  /// [budgetMicros]; a pipeline that only just fits keeps up, so the two
  /// durations are not added. [starts] are the vsync times of the frames in
  /// order; the gaps between them show dropped frames the two threads cannot,
  /// because GPU time counts towards neither. A gap over 100 ms is the app being
  /// idle, not a dropped frame.
  factory FrameTimingSummary.of(
    List<int> build,
    List<int> raster, {
    List<int> starts = const [],
    int budgetMicros = 16667,
  }) {
    final sortedBuild = [...build]..sort();
    final sortedRaster = [...raster]..sort();
    var missed = 0;
    for (var i = 0; i < build.length; i++) {
      if (build[i] > budgetMicros || raster[i] > budgetMicros) missed++;
    }
    final gaps = [
      for (var i = 1; i < starts.length; i++)
        if (starts[i] - starts[i - 1] <= 100000) starts[i] - starts[i - 1],
    ]..sort();
    return FrameTimingSummary(
      frames: build.length,
      buildP50: _percentile(sortedBuild, 50),
      buildP95: _percentile(sortedBuild, 95),
      buildMax: sortedBuild.last,
      rasterP50: _percentile(sortedRaster, 50),
      rasterP95: _percentile(sortedRaster, 95),
      rasterMax: sortedRaster.last,
      missed: missed,
      pacingP50: gaps.isEmpty ? 0 : _percentile(gaps, 50),
      pacingMax: gaps.isEmpty ? 0 : gaps.last,
    );
  }

  final int frames;
  final int buildP50;
  final int buildP95;
  final int buildMax;
  final int rasterP50;
  final int rasterP95;
  final int rasterMax;
  final int missed;
  final int pacingP50;
  final int pacingMax;

  static int _percentile(List<int> sorted, int percent) => sorted[((sorted.length - 1) * percent / 100).round()];

  static String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

  @override
  String toString() =>
      'frames=$frames missed=$missed '
      'build=${_ms(buildP50)}/${_ms(buildP95)}/${_ms(buildMax)} '
      'raster=${_ms(rasterP50)}/${_ms(rasterP95)}/${_ms(rasterMax)} '
      'pacing=${_ms(pacingP50)}/${_ms(pacingMax)}';
}

/// Writes frame cost to the diagnostic log on Apple TV.
///
/// A Release build cannot be attached to from Instruments or DevTools, so this
/// is the only view on frame cost from a real 4K output. Build is the Flutter
/// UI thread and raster the GPU side, which is what separates widget work from
/// full-screen effects. Short bursts are skipped: a lone frame says nothing
/// about a scroll.
void startFrameTimingLog() {
  SchedulerBinding.instance.addTimingsCallback((timings) {
    if (timings.length < 5 || !PlatformDetector.isTV()) return;
    final summary = FrameTimingSummary.of(
      [for (final t in timings) t.buildDuration.inMicroseconds],
      [for (final t in timings) t.rasterDuration.inMicroseconds],
      starts: [for (final t in timings) t.timestampInMicroseconds(FramePhase.vsyncStart)],
    );
    appLogger.d('FrameTiming: $summary');
  });
}
