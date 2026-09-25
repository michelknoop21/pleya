import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The focus ring as one [ShapeBorder]: [ring] on [shape]'s outline, plus an
/// optional [separator] line hugging the ring's outer edge.
///
/// VIS-0925-A: the Light separator used to be a pair of `BoxShadow`s, and a
/// BoxShadow is painted as a filled box under the whole decoration, so it
/// darkened every translucent tile it sat under. A stroke only covers its own
/// band. [shape] supplies geometry only; its own side is ignored.
@immutable
class FocusRingBorder extends ShapeBorder {
  const FocusRingBorder({required this.shape, required this.ring, this.separator = BorderSide.none});

  final OutlinedBorder shape;
  final BorderSide ring;
  final BorderSide separator;

  /// [separator] aligned so its inner edge meets the ring's outer edge, on the
  /// same rect: a stroke align past 1 moves a stroke further outward, which
  /// keeps corner radii concentric for any [OutlinedBorder].
  BorderSide get _alignedSeparator =>
      separator.copyWith(strokeAlign: 1 + 2 * ring.strokeOutset / math.max(separator.width, 0.001));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(math.max(ring.strokeInset, 0));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      shape.getInnerPath(dimensions.resolve(textDirection).deflateRect(rect), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      shape.getOuterPath(rect, textDirection: textDirection);

  bool get _separatorVisible => separator.style != BorderStyle.none && separator.width > 0 && separator.color.a > 0;

  /// A ring drawn wholly inside its box ([BorderSide.strokeAlignInside] or
  /// further in) keeps the separator inside the box as well: the separator
  /// takes the outermost band and the ring moves in by its width. Outside the
  /// box a clipping ancestor cuts it off; that removed the separator on the
  /// first and last row of a settings card (VIS-0925 review, FIX 2), where a
  /// white ring on a light page is then invisible. A stroke align below -1
  /// moves a stroke further inward, on the same rect, for any [OutlinedBorder].
  bool get _inside => ring.strokeOutset <= 0;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (!_separatorVisible) {
      shape.copyWith(side: ring).paint(canvas, rect, textDirection: textDirection);
      return;
    }
    if (_inside) {
      final w = math.max(ring.width, 0.001);
      final inset = -ring.strokeOutset + separator.width;
      shape
          .copyWith(side: separator.copyWith(strokeAlign: -1 - 2 * -ring.strokeOutset / separator.width))
          .paint(canvas, rect, textDirection: textDirection);
      shape
          .copyWith(side: ring.copyWith(strokeAlign: -1 - 2 * inset / w))
          .paint(canvas, rect, textDirection: textDirection);
      return;
    }
    shape.copyWith(side: _alignedSeparator).paint(canvas, rect, textDirection: textDirection);
    shape.copyWith(side: ring).paint(canvas, rect, textDirection: textDirection);
  }

  @override
  ShapeBorder scale(double t) =>
      FocusRingBorder(shape: shape.scale(t) as OutlinedBorder, ring: ring.scale(t), separator: separator.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is FocusRingBorder && a.shape == shape) {
      return FocusRingBorder(
        shape: shape,
        ring: BorderSide.lerp(a.ring, ring, t),
        separator: BorderSide.lerp(a.separator, separator, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is FocusRingBorder && b.shape == shape) {
      return FocusRingBorder(
        shape: shape,
        ring: BorderSide.lerp(ring, b.ring, t),
        separator: BorderSide.lerp(separator, b.separator, t),
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      other is FocusRingBorder && other.shape == shape && other.ring == ring && other.separator == separator;

  @override
  int get hashCode => Object.hash(shape, ring, separator);

  @override
  String toString() => 'FocusRingBorder($shape, ring: $ring, separator: $separator)';
}
