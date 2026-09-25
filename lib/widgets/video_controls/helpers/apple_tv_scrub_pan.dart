import 'dart:math' as math;

/// SCRUB1: how far the free-scrub cursor moves for [dx] points of Siri Remote
/// pan at [speed] points per millisecond, when [fullTravel] points is one full
/// swipe across the touch surface.
///
/// A slow full swipe covers a fifth of the video, at least one minute and at
/// most ten; a fast flick multiplies that up to [_maxGain] times, so a long
/// film is crossed in a few swipes and a short clip stays precise.
// ponytail: fixed gain curve, tune _fastSpeed/_maxGain after the hardware check.
Duration appleTvScrubPanDelta({
  required double dx,
  required double speed,
  required double fullTravel,
  required Duration duration,
}) {
  final durationMs = duration.inMilliseconds;
  if (fullTravel <= 0 || durationMs <= 0 || dx == 0) return Duration.zero;
  final spanMs = (durationMs / 5).clamp(math.min(_minSpanMs, durationMs), _maxSpanMs);
  final gain = (1 + speed.abs() / _fastSpeed).clamp(1.0, _maxGain);
  return Duration(milliseconds: (dx / fullTravel * spanMs * gain).round());
}

const int _minSpanMs = 60 * 1000;
const int _maxSpanMs = 10 * 60 * 1000;
// Points per millisecond at which the gain has doubled.
const double _fastSpeed = 2;
const double _maxGain = 4;
