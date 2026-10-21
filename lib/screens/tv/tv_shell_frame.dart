/// The TV shell's frame: the bar above the content, and the [TvShellSurface]
/// marker the content reads its band from. Split out of `tv_root_shell.dart`
/// unchanged; that file re-exports [TvShellSurface] so no import moved.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Marks the subtree that the fase-7 TV shell already frames.
///
/// Two things a full-page TV screen normally provides for itself the shell now
/// provides instead: the page background, including hoofdstuk 8's slight lift
/// towards the top of the frame, and the top safe inset. A screen that painted
/// them again under the bar painted them twice — the lift left a hard
/// full-width step at the seam, and the inset stacked into a band of dead space
/// that pushed the first grid row about thirteen per cent of the canvas below
/// where the north star puts it.
///
/// A marker rather than a constructor flag, because the screens that read it are
/// reached both through the screens list and through nested routes, and
/// threading a boolean down both paths would be one more thing to forget. Its
/// absence is the standalone case — a golden, a focus test — where the screen
/// still owns its own frame and nothing about it changes.
class TvShellSurface extends InheritedNotifier<ValueNotifier<double>> {
  /// [topBandHeight] is the shell's measured bar height; a standalone host (a
  /// golden, a focus test) leaves it out and reads as a band of 0.
  const TvShellSurface({super.key, ValueNotifier<double>? topBandHeight, required super.child})
    : super(notifier: topBandHeight);

  static bool isPresent(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TvShellSurface>() != null;

  /// The measured height of the top-navigation band above the content box,
  /// and 0 in the standalone case.
  ///
  /// The Home feed extends its full-bleed hero up by exactly this much, so the
  /// backdrop runs behind the bar (DEC-095). Measured by [TvShellFrame]'s
  /// layout rather than computed from tokens: the bar's height is its pills'
  /// intrinsic height under a floor, which follows font metrics, text scaling
  /// and locale, and a token that restated it would drift on the first of
  /// those to change.
  static double topBandHeightOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvShellSurface>()?.notifier?.value ?? 0;
}

/// The bar above the content, laid out in that order and painted in the other.
///
/// The fase-7 shell stacked the two in a `Column`, which is the right layout
/// — the content box is whatever the bar leaves — and the wrong paint order
/// once Home's hero has to run *behind* the bar (DEC-095): a child painted
/// after the bar covers it. A `CustomMultiChildLayout` separates the two: the
/// delegate lays the bar out first and gives the content the rest, exactly as
/// the `Column` did, while the children list paints the content first and the
/// bar over it. The bar itself paints no background, so the shell's own
/// ground and, on Home, the backdrop show through it.
///
/// The measured band height is published to the content through
/// [TvShellSurface] one frame after layout, which is the only frame it can be:
/// a layout pass cannot rebuild the widgets it is laying out.
class TvShellFrame extends StatefulWidget {
  const TvShellFrame({super.key, required this.nav, required this.content});

  final Widget nav;
  final Widget Function(ValueNotifier<double> topBandHeight) content;

  @override
  State<TvShellFrame> createState() => _TvShellFrameState();
}

class _TvShellFrameState extends State<TvShellFrame> {
  final _topBand = ValueNotifier<double>(0);

  @override
  void dispose() {
    _topBand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _TvShellLayoutDelegate(_topBand),
      children: [
        LayoutId(id: _TvShellSlot.content, child: widget.content(_topBand)),
        LayoutId(id: _TvShellSlot.nav, child: widget.nav),
      ],
    );
  }
}

enum _TvShellSlot { nav, content }

class _TvShellLayoutDelegate extends MultiChildLayoutDelegate {
  _TvShellLayoutDelegate(this.topBand);

  final ValueNotifier<double> topBand;

  @override
  void performLayout(Size size) {
    // Width-tight, height-unbounded: exactly what the `Column` handed the bar.
    // A bounded height is not the same thing — the bar's `Align`ed profile chip
    // expands to whatever height it is offered, and under `size.height` the
    // bar took the whole screen and left the content a zero-height box.
    final nav = layoutChild(_TvShellSlot.nav, BoxConstraints(minWidth: size.width, maxWidth: size.width));
    positionChild(_TvShellSlot.nav, Offset.zero);
    final contentHeight = math.max(0.0, size.height - nav.height);
    layoutChild(_TvShellSlot.content, BoxConstraints.tightFor(width: size.width, height: contentHeight));
    positionChild(_TvShellSlot.content, Offset(0, nav.height));
    if (topBand.value != nav.height) {
      final measured = nav.height;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (topBand.value != measured) topBand.value = measured;
      });
    }
  }

  @override
  bool shouldRelayout(covariant _TvShellLayoutDelegate oldDelegate) => oldDelegate.topBand != topBand;
}
