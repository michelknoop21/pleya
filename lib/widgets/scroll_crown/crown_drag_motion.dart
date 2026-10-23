/// Direct scrollbar mapping: a held crown reaches either end in one stroke.
/// The grab is anchored, so touching the crown never changes the content.
class CrownDragMotion {
  CrownDragMotion({required double y, required Duration time}) : _origin = y;

  static const model = 'position-direct-v3';
  final double _origin;
  double? _startPixels;
  double? _min;
  double? _max;

  double move({
    required double y,
    required Duration time,
    required double pixels,
    required double minExtent,
    required double maxExtent,
    required double travel,
    double? rangeExtent,
  }) {
    if (travel <= 0 || maxExtent <= minExtent) return pixels;
    final start = _startPixels ??= pixels.clamp(minExtent, maxExtent);
    final min = _min ??= minExtent;
    final max = _max ??= minExtent + (rangeExtent ?? maxExtent - minExtent);
    final delta = y - _origin;
    if (delta == 0) return start.clamp(minExtent, maxExtent);
    // Only an actual edge follows newly loaded content. Interior mapping stays
    // frozen for the drag, so fetching another page cannot stretch the scale.
    if (delta < 0 && y <= 0) return minExtent;
    if (delta > 0 && y >= travel) return maxExtent;
    final origin = _origin;
    final room = delta > 0 ? travel - origin : origin;
    if (room <= 0) return delta > 0 ? maxExtent : minExtent;
    final target = delta > 0 ? max : min;
    return (start + delta.abs() / room * (target - start)).clamp(minExtent, maxExtent);
  }
}
