import 'dart:math' as math;

// Frozen rejected12b973a4 mapping; negative control only, never a product path.
double rejectedVelocityStep({
  required double delta,
  required double seconds,
  required double origin,
  required double travel,
  required double pixels,
  required double max,
}) {
  if (seconds <= 0 || delta == 0) return pixels;
  final blend = ((delta.abs() / seconds - 80) / 65).clamp(0.0, 1.0);
  final weight = blend * blend * (3 - 2 * blend);
  final room = delta > 0 ? travel - origin : origin;
  final gain = 4 + (math.max(4, max / (room > 0 ? room : travel) * 1.5) - 4) * weight;
  return (pixels + delta * gain).clamp(0.0, max);
}
