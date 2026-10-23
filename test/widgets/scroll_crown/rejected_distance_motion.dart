// Frozen physically rejected distance candidate; negative control only.
import 'dart:math' as math;

/// Short excursions stay precise; longer ones progressively cover more range.
/// The same spatial path produces the same motion regardless of event timing.
class RejectedDistanceMotion {
  RejectedDistanceMotion({required double y, required Duration time}) : _y = y;

  static const model = 'distance-relative-v2';
  double _y;
  double _distance = 0;
  double _room = 0;
  double _direction = 0;

  double move({
    required double y,
    required Duration time,
    required double pixels,
    required double minExtent,
    required double maxExtent,
    required double travel,
    double? rangeExtent,
    double precisionGain = 4,
    double rangeGain = .25,
    double fineTravel = 48,
    int exponent = 4,
  }) {
    if (travel <= 0 || maxExtent <= minExtent) return pixels;
    final previous = _y;
    final next = y;
    final delta = next - previous;
    _y = next;
    if (delta == 0) return pixels;
    if (delta.sign != _direction) {
      _direction = delta.sign;
      _distance = 0;
      // A grip near the edge must not amplify a tiny correction into a jump.
      final origin = previous.clamp(0.0, travel);
      _room = math.max(travel / 2, delta > 0 ? travel - origin : origin);
    }
    final before = _distance;
    _distance += delta.abs();
    final ramp = math.max(fineTravel, _room - fineTravel);
    double curve(double distance) => math.pow(math.max(0, distance - fineTravel) / ramp, exponent).toDouble();
    final extra = (rangeExtent ?? maxExtent - minExtent) * rangeGain * (curve(_distance) - curve(before));
    return (pixels + precisionGain * delta + _direction * extra).clamp(minExtent, maxExtent);
  }
}
