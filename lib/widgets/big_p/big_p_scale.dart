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

  @override
  bool updateShouldNotify(BigPScale oldWidget) => oldWidget.pt != pt;
}
