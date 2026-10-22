import 'scroll_crown_painter.dart';

/// The ratchet behind the scroll crown: one tick per [toothPitch] of drag,
/// never faster than [minTickInterval]. Teeth that pass inside the interval
/// are dropped rather than queued, so a fast drag never buzzes on.
class CrownRatchet {
  CrownRatchet({required this.now});

  /// Monotonic time source for the rate limit.
  final Duration Function() now;

  /// Drag distance per tooth: one ratchet tick and one tooth of rotation.
  static const double toothPitch = 7.0;

  /// Fastest ratchet rate (about 28 ticks a second); faster drags drop teeth.
  static const Duration minTickInterval = Duration(milliseconds: 35);

  double _travel = 0;
  Duration? _lastTick;

  /// Gear rotation for [dragDelta] of travel: one tooth per [toothPitch], so
  /// what you see and what you feel stay in step.
  static double phaseFor(double dragDelta) => dragDelta * ScrollCrownPainter.toothAngle / toothPitch;

  /// Starts a new drag: travel left over from the previous one is dropped.
  void reset() => _travel = 0;

  /// Records a tick fired elsewhere (a firmer one), so the rate limit counts
  /// it as well.
  void markTick() => _lastTick = now();

  /// Adds [distance] of travel and returns whether a tick should fire now.
  bool advance(double distance) {
    _travel += distance;
    if (_travel < toothPitch) return false;
    _travel %= toothPitch;
    final at = now();
    final last = _lastTick;
    if (last != null && at - last < minTickInterval) return false;
    _lastTick = at;
    return true;
  }
}
