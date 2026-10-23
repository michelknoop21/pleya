/// Frozen build401 baseline with a96pt gear, for historical replay only.
double baselineOffsetForDrag({
  required double startPixels,
  required double startY,
  required double dragDelta,
  required double railHeight,
  required double minExtent,
  required double maxExtent,
}) {
  final start = startPixels.clamp(minExtent, maxExtent);
  if (railHeight <= 96 || maxExtent <= minExtent || dragDelta == 0) return start;
  final origin = startY.clamp(0.0, railHeight);
  final towardEnd = dragDelta > 0;
  final target = towardEnd ? maxExtent : minExtent;
  final room = towardEnd ? railHeight - 96 / 2 - origin : origin - 96 / 2;
  if (room <= 0 || dragDelta.abs() >= room) return target;
  return start + dragDelta.abs() / room * (target - start);
}
