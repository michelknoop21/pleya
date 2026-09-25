import 'dart:math' as math;

/// SCRUB1: how far the free-scrub cursor moves for one Siri Remote pan
/// sample of [dx] points over [elapsed], on a touch surface that maps to
/// [surfaceWidth] points.
///
/// A slow full-width swipe covers a fifth of the video, at least one minute
/// and at most ten; a fast flick multiplies that up to [_maxGain] times, so
/// a long film is crossed in a few swipes and a short clip stays precise.
// ponytail: fixed gain curve, tune _fastSpeed/_maxGain after the hardware check.
Duration appleTvScrubPanDelta({
  required double dx,
  required Duration elapsed,
  required double surfaceWidth,
  required Duration duration,
}) {
  final durationMs = duration.inMilliseconds;
  if (surfaceWidth <= 0 || durationMs <= 0 || dx == 0) return Duration.zero;
  final spanMs = (durationMs / 5).clamp(math.min(_minSpanMs, durationMs), _maxSpanMs);
  final elapsedMs = elapsed.inMicroseconds / 1000;
  final speed = elapsedMs > 0 ? dx.abs() / elapsedMs : 0.0;
  final gain = (1 + speed / _fastSpeed).clamp(1.0, _maxGain);
  return Duration(milliseconds: (dx / surfaceWidth * spanMs * gain).round());
}

const int _minSpanMs = 60 * 1000;
const int _maxSpanMs = 10 * 60 * 1000;
// Points per millisecond at which the gain has doubled.
const double _fastSpeed = 2;
const double _maxGain = 4;
