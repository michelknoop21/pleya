import 'package:flutter/widgets.dart';

/// Layout and sizing constants used throughout the application
/// Screen width breakpoints for responsive design
class ScreenBreakpoints {
  static const double mobile = 600;

  static const double wideTablet = 900;

  static const double desktop = 1200;

  static const double largeDesktop = 1600;

  // Legacy alias for backward compatibility
  static const double tablet = mobile;

  static bool isMobile(double width) => width < mobile;

  static bool isTablet(double width) => width >= mobile && width < desktop;

  static bool isWideTablet(double width) => width >= wideTablet && width < desktop;

  static bool isDesktop(double width) => width >= desktop && width < largeDesktop;

  static bool isLargeDesktop(double width) => width >= largeDesktop;

  static bool isDesktopOrLarger(double width) => width >= desktop;

  static bool isWideTabletOrLarger(double width) => width >= wideTablet;
}

/// Animation and notification durations.
class AppDurations {
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration snackBarDefault = Duration(seconds: 3);
  static const Duration snackBarLong = Duration(seconds: 4);
}

class GridLayoutConstants {
  static const double posterAspectRatio = 2 / 3.3;

  static const double fullCardPosterAspectRatio = 2 / 3;

  static const double episodeThumbnailAspectRatio = 16 / 9;

  static const double episodeGridCellAspectRatio = 1.4;

  static const double crossAxisSpacing = 0;
  static const double mainAxisSpacing = 0;

  static double fullCardGridSpacingForScale(double scale) => (12 * scale).clamp(8, 18).toDouble();

  /// Gap a grid keeps between poster cards, in both axes.
  ///
  /// It used to be zero, with the only separation coming from the padding
  /// inside the card. A focused card scales up by [FocusTheme.focusScale] and
  /// ate that padding, so the neighbour of a focused card sat visibly tighter
  /// than every other pair in the grid. A real gap in the delegate is wider
  /// than that overhang, so the row keeps its rhythm wherever focus lands.
  static double posterGridSpacingForScale(double scale) => (12 * scale).clamp(8, 18).toDouble();

  /// Standard grid padding
  static EdgeInsets get gridPadding => const EdgeInsets.only(left: 2, right: 2, bottom: 2);
}

class TvLayoutConstants {
  static const double horizontalInset = 72;
  static const double shelfHorizontalInset = 56;
  static const double shelfVerticalGap = 32;
  static const double heroLogoWidth = 700;
  static const double heroLogoHeight = 200;
  static const double compactHeroLogoWidth = 420;
  static const double compactHeroLogoHeight = 112;

  static double scaleForHeight(double height) => (height / 1080).clamp(0.85, 1.35).toDouble();

  static double scaleForSize(Size size) => scaleForHeight(size.height);

  /// The ten-foot scale for [context].
  ///
  /// Reads [TvDisplayMetrics] before `MediaQuery`, and the difference matters
  /// exactly once: inside a nested TV route. INV-1 of
  /// `docs/tvos-redesign-implementatiecontract.md` makes such a route see the
  /// content box rather than the window, and the content box is shorter than
  /// the window by the height of the top bar. Feeding that to a *typography*
  /// scale would shrink every letter in a nested route by about nine per cent
  /// against the same screen mounted as a destination root — two renderings of
  /// one screen, differing only in how it was opened.
  ///
  /// So the viewport shrinks and the scale does not. The display size is a
  /// property of the panel someone is sitting in front of, which no amount of
  /// chrome above the content changes. Off TV, and in any test that did not
  /// mount the shell, nothing is published and this is `MediaQuery` as before.
  static double scaleOf(BuildContext context) =>
      scaleForSize(TvDisplayMetrics.maybeOf(context) ?? MediaQuery.sizeOf(context));
}

/// The size of the whole TV display, published once by the shell.
///
/// It exists because [TvLayoutConstants.scaleOf] used to derive the ten-foot
/// scale from `MediaQuery.sizeOf`, and INV-1 took that reading away: a nested
/// route's `MediaQuery` is its content box now, deliberately. Everything that
/// asks "how far away is the viewer" still needs the panel, not the box, and
/// this is where it asks.
///
/// Published by `TvRootShell` around its whole frame, so the destination roots
/// and the nested routes above them resolve the same value and one screen
/// renders identically whichever way it was opened.
class TvDisplayMetrics extends InheritedWidget {
  const TvDisplayMetrics({super.key, required this.size, required super.child});

  /// The shell's own box: the full window, before the top bar takes its band.
  final Size size;

  static Size? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TvDisplayMetrics>()?.size;

  @override
  bool updateShouldNotify(TvDisplayMetrics oldWidget) => oldWidget.size != size;
}
