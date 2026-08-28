import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Left inset of a row separator: clears the leading icon badge so the line
/// starts under the title, not under the icon.
const double kSettingsSeparatorIndent = 68;

/// Lays out settings rows exactly like a [Column] (same defaults: vertical,
/// start-aligned, max main-axis size, centered cross-axis) but paints a
/// hairline separator above every *visible* row after the first, instead of
/// reserving one for every widget in the list.
///
/// The difference matters when a row collapses to [SizedBox.shrink] at
/// runtime (a [StreamBuilder] with nothing to show, a [Consumer] gated on a
/// condition): a separator keyed to list position draws one either side of
/// that zero-height gap, and two collapsed rows in a row stack two
/// separators directly on top of each other. Keying separators to the actual
/// laid-out geometry, a plain [RenderFlex] does the layout unmodified, means
/// a row that isn't there doesn't get a line either side of it.
class SettingsRows extends MultiChildRenderObjectWidget {
  const SettingsRows({
    super.key,
    required super.children,
    required this.separatorColor,
    this.separatorIndent = kSettingsSeparatorIndent,
  });

  final Color separatorColor;
  final double separatorIndent;

  @override
  RenderSettingsRows createRenderObject(BuildContext context) {
    return RenderSettingsRows(
      direction: Axis.vertical,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      textDirection: Directionality.maybeOf(context),
      verticalDirection: VerticalDirection.down,
      separatorColor: separatorColor,
      separatorIndent: separatorIndent,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSettingsRows renderObject) {
    renderObject
      ..direction = Axis.vertical
      ..mainAxisAlignment = MainAxisAlignment.start
      ..mainAxisSize = MainAxisSize.max
      ..crossAxisAlignment = CrossAxisAlignment.center
      ..textDirection = Directionality.maybeOf(context)
      ..verticalDirection = VerticalDirection.down
      ..separatorColor = separatorColor
      ..separatorIndent = separatorIndent;
  }
}

/// The [RenderFlex] behind [SettingsRows]. Layout, hit-testing, intrinsics
/// and overflow all come from [RenderFlex] unmodified: only [paint] and
/// [separatorRects] are new, so the geometry stays bit-identical to a plain
/// `Column` and the change is confined to what gets drawn on top of it.
class RenderSettingsRows extends RenderFlex {
  RenderSettingsRows({
    required super.direction,
    required super.mainAxisAlignment,
    required super.mainAxisSize,
    required super.crossAxisAlignment,
    required super.textDirection,
    required super.verticalDirection,
    required Color separatorColor,
    required double separatorIndent,
  }) : _separatorColor = separatorColor,
       _separatorIndent = separatorIndent;

  Color _separatorColor;
  set separatorColor(Color value) {
    if (_separatorColor == value) return;
    _separatorColor = value;
    markNeedsPaint();
  }

  double _separatorIndent;
  set separatorIndent(double value) {
    if (_separatorIndent == value) return;
    _separatorIndent = value;
    markNeedsPaint();
  }

  /// One filled rect per boundary between two visible children, in this
  /// render object's own coordinate space, not the offset it happens to
  /// paint at. That is what lets a test read it directly off the render
  /// object instead of having to know where the surrounding card landed on
  /// screen, and what lets [paint] just add its own `offset` on top.
  ///
  /// A child counts as visible when it laid out to a non-zero height; a
  /// `SizedBox.shrink()` result and an explicit empty case both go through
  /// that path, so both are skipped the same way.
  List<Rect> get separatorRects {
    final rects = <Rect>[];
    RenderBox? child = firstChild;
    var sawVisible = false;
    while (child != null) {
      final parentData = child.parentData! as FlexParentData;
      if (child.size.height > 0) {
        if (sawVisible) {
          rects.add(Rect.fromLTWH(_separatorIndent, parentData.offset.dy, size.width - _separatorIndent, 1));
        }
        sawVisible = true;
      }
      child = parentData.nextSibling;
    }
    return rects;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final rects = separatorRects;
    if (rects.isEmpty) return;
    final paint = Paint()..color = _separatorColor;
    for (final rect in rects) {
      context.canvas.drawRect(rect.shift(offset), paint);
    }
  }
}
