import 'package:flutter/widgets.dart';

import 'layout_constants.dart';

/// Apple's tvOS Human Interface Guidelines sizes, in points on the 1920x1080 pt
/// canvas a TV presents, and the conversion to Flutter logical pixels.
///
/// Text styles are the HIG "tvOS built-in text styles" table; tvOS text is 29 pt
/// by default and never under 23 pt. A tvOS button is at least 56x56 pt, grid
/// items sit 40 pt apart. Source: developer.apple.com/design/human-interface-
/// guidelines, pages Typography, Layout and Designing for games (DENS1).
///
/// Why this exists next to [TvLayoutConstants.scaleOf]: that scale is clamped at
/// 0.85, and on an Apple TV the panel is 584 logical pixels tall (the wrapper
/// multiplies by 1.85 to reach 1080), so every value that went through it came
/// out 1.57 times its nominal size. [of] is the unclamped panel height over
/// 1080, so `TvHig.body * TvHig.of(context)` lands on exactly 29 pt on screen,
/// on Apple TV and on an Android TV alike.
abstract final class TvHig {
  static const double title1 = 76;
  static const double title2 = 57;
  static const double title3 = 48;
  static const double headline = 38;
  static const double callout = 31;
  static const double body = 29;
  static const double caption1 = 25;
  static const double caption2 = 23;

  /// Line heights ("leading") the same table pairs with each style.
  static const double bodyLeading = 36;
  static const double caption1Leading = 32;

  static const double minButton = 56;
  static const double itemSpacing = 40;

  /// Logical pixels per HIG point for [context]'s TV panel.
  static double of(BuildContext context) =>
      (TvDisplayMetrics.maybeOf(context) ?? MediaQuery.sizeOf(context)).height / 1080;
}
