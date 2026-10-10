import 'dart:math' as math;

/// How far [detailHeaderHeight]'s floor may lift the header on a short window,
/// as a fraction of the window height. No minimum window size is set anywhere,
/// so without this a window shorter than the floor got a header taller than
/// itself. 0.7 sits above the 60% baseline, so the floor still does its work
/// on a window that is only slightly short.
const double _maxHeaderViewportFraction = 0.7;

/// Height of the media detail hero header on desktop and iPad/tablet. TV uses
/// the full viewport and the phone has its own layout.
///
/// This was a flat 60% of the window height (F-D1): 864pt of backdrop on a
/// 2560x1440 desktop and 826pt on a 1032x1376 iPad in portrait. The title and
/// actions are anchored to the header's bottom edge and do not grow with it,
/// so a taller header only added empty backdrop.
///
/// [ceiling] bounds the height and [floor] keeps a usable backdrop on a short
/// window. The header is also capped at the height a 16:9 backdrop takes at
/// the window's width: past that it stretches the same image instead of
/// showing more of it. The Home hero in `home_hero_layout.dart` bounds its
/// height in a similar way, with its own numbers.
double detailHeaderHeight({
  required double screenWidth,
  required double screenHeight,
  required double ceiling,
  required double floor,
}) {
  final base = screenHeight * 0.6;
  final sixteenNineCap = screenWidth * 9 / 16;
  // max() first: on a very narrow window the 16:9 cap falls under the floor,
  // and clamp() throws when its upper bound is below its lower one.
  final upper = math.max(floor, math.min(ceiling, sixteenNineCap));
  final effectiveFloor = math.min(floor, screenHeight * _maxHeaderViewportFraction);
  return base.clamp(effectiveFloor, upper);
}

/// Desktop (macOS, Windows, Linux): `PlatformDetector.isDesktop`.
double desktopDetailHeaderHeight(double screenWidth, double screenHeight) =>
    detailHeaderHeight(screenWidth: screenWidth, screenHeight: screenHeight, ceiling: 680, floor: 400);

/// iPad and Android tablet: a lower ceiling and floor, in line with the more
/// compact tablet composition of the Home hero.
double tabletDetailHeaderHeight(double screenWidth, double screenHeight) =>
    detailHeaderHeight(screenWidth: screenWidth, screenHeight: screenHeight, ceiling: 600, floor: 360);
