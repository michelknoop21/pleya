import 'dart:math' as math;

/// Height of the home screen's hero billboard.
///
/// Pure so the "hero plus exactly one rail fills the screen" claim can be
/// checked against real device metrics without pumping the widget tree.
///
/// [viewportExtent] is the scroll view's own height. The Scaffold lays its body
/// out above the tab bar (no `extendBody`), so that value already excludes the
/// bar and the home indicator — which is why nothing here needs a per-device
/// fraction or a guess at the tab bar's height.
double homeHeroHeight({
  required bool useSideNav,
  required double viewportExtent,
  required double screenHeight,
  required double screenWidth,
  required double statusBarHeight,
  required double firstRailHeight,
}) {
  // Desktop and tablet keep a fixed slice: there the rails sit beside the hero
  // or well below the fold, so filling to the first rail would overshoot.
  if (useSideNav) return (screenHeight * 0.75).clamp(480.0, 900.0);

  // Fill whatever the first rail doesn't need, so opening the page shows the
  // hero and that one rail and nothing else.
  final fill = viewportExtent - firstRailHeight;

  // Floor: on a wide window (a Mac running the iOS build, an iPad in landscape)
  // the full 16:9 frame can be taller than what's left over, and sizing off the
  // leftover alone would leave the hero stunted. That frame is meant to sit
  // below the status bar, so it takes the inset — [fill] must not, since it is
  // already measured against the viewport.
  final sixteenNine = math.min(screenWidth * 9 / 16, screenHeight * 0.8) + statusBarHeight;

  // Cap: keep a sliver of the rail on screen on a short viewport, so the page
  // still reads as scrollable rather than looking like a dead end.
  return math.max(fill, sixteenNine).clamp(360.0, viewportExtent * 0.82);
}
