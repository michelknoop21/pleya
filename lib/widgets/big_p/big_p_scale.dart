import 'package:flutter/widgets.dart';

import '../../utils/tv_hig.dart';

/// The point scale Big P's cards are drawn at. TV leaves it unset and gets
/// [TvHig.of]; a phone or tablet puts a fixed scale above the cards, so the
/// same widgets land on mobile type sizes (0.53 turns body 29 into 15.4 pt).
class BigPScale extends InheritedWidget {
  const BigPScale({super.key, required this.pt, required super.child});

  final double pt;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BigPScale>()?.pt ?? TvHig.of(context);

  /// Smallest touch target in points (HIG): 44 where a [BigPScale] was set
  /// (phone and tablet), 0 on TV, which is driven by focus and not by touch.
  static double minTouch(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BigPScale>() == null ? 0 : kBigPMinTouch;

  @override
  bool updateShouldNotify(BigPScale oldWidget) => oldWidget.pt != pt;
}

/// 44 pt, Apple's minimum for a touch target.
const kBigPMinTouch = 44.0;

/// Grows the touch area of a small control to [BigPScale.minTouch] without
/// drawing it larger: the [child] stays centred at its own size. Put it
/// inside the tap handler, so the whole box takes the tap. Nothing on TV.
class BigPTouchTarget extends StatelessWidget {
  const BigPTouchTarget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final min = BigPScale.minTouch(context);
    if (min == 0) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: min, minHeight: min),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }
}
