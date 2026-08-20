import 'dart:math' as math;

import '../media/media_item.dart' show BillboardArtKind, billboardNarrowAspectRatioThreshold;

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
  final cap = viewportExtent * 0.82;

  // A viewport this small is a transient layout, not a screen anyone is
  // looking at. Returning zero keeps the caller in bounds; the next layout
  // pass sizes the hero for real.
  if (cap <= 0) return 0;

  // The cap wins when the viewport is too short to honour the floor: the hero
  // can never be taller than the space it is drawn in. Ordering these the
  // other way round is not a rounding detail — `clamp` throws when its lower
  // bound exceeds its upper one, and a throw inside the layout builder costs
  // the whole billboard: release builds swap it for a blank error box, so the
  // home screen loses its artwork, title and play button at once. That is
  // reachable in normal use, because the home tab stays laid out inside the
  // IndexedStack while the search keyboard shrinks the viewport under it.
  final floor = math.min(360.0, cap);

  return math.max(fill, sixteenNine).clamp(floor, cap);
}

/// Geometry for the hero's sharp artwork layer, decoupled from the hero's own
/// total height.
///
/// On a wide box the frame fills the whole hero, exactly as before. On a
/// narrow (phone-portrait) box the frame shrinks to the aspect ratio of its
/// own source — square or 16:9 — so a server-side crop is never asked to
/// force a mismatched ratio into the full hero box. [requestHeight] always
/// matches that frame ratio, which is what keeps the transcoder's crop a
/// no-op.
class HomeHeroArtGeometry {
  const HomeHeroArtGeometry({
    required this.width,
    required this.height,
    required this.requestHeight,
    required this.fadeHeight,
    required this.coversHero,
  });

  /// Frame width, in logical pixels.
  final double width;

  /// Frame height, in logical pixels.
  final double height;

  /// `maxHeight` to send toward the transcoder, matching the frame's own ratio.
  final double requestHeight;

  /// Height of the bottom band that fades the frame into the scaffold
  /// background. Zero when the frame already covers the whole hero.
  final double fadeHeight;

  /// True when the frame fills the entire hero with `BoxFit.cover`, as before
  /// this change. False when the frame is a shorter island sized to its own
  /// source ratio.
  final bool coversHero;

  static const _zero = HomeHeroArtGeometry(width: 0, height: 0, requestHeight: 0, fadeHeight: 0, coversHero: false);
}

HomeHeroArtGeometry homeHeroArtGeometry({
  required double screenWidth,
  required double heroHeight,
  required BillboardArtKind kind,
}) {
  if (heroHeight <= 0 || screenWidth <= 0) return HomeHeroArtGeometry._zero;

  final isWideBox = screenWidth / heroHeight >= billboardNarrowAspectRatioThreshold;
  if (isWideBox || kind == BillboardArtKind.fallback) {
    return HomeHeroArtGeometry(
      width: screenWidth,
      height: heroHeight,
      requestHeight: math.max(screenWidth * 9 / 16, heroHeight),
      fadeHeight: 0,
      coversHero: true,
    );
  }

  final height = switch (kind) {
    BillboardArtKind.square => math.min(screenWidth, heroHeight),
    BillboardArtKind.widescreen => math.min(screenWidth * 9 / 16, heroHeight),
    BillboardArtKind.fallback => heroHeight, // unreachable: handled above
  };
  final requestHeight = switch (kind) {
    BillboardArtKind.square => screenWidth,
    BillboardArtKind.widescreen => screenWidth * 9 / 16,
    BillboardArtKind.fallback => screenWidth * 9 / 16, // unreachable: handled above
  };

  return HomeHeroArtGeometry(
    width: screenWidth,
    height: height,
    requestHeight: requestHeight,
    fadeHeight: math.min(height * 0.35, 180.0),
    coversHero: false,
  );
}

/// Constraints for the hero's clear-logo (or fallback title) box.
class HomeHeroLogoMetrics {
  const HomeHeroLogoMetrics({required this.width, required this.height});

  final double width;
  final double height;
}

/// On large screens the logo box stays a fixed 400×120: the hero is wide
/// enough there that a fixed box never gets squeezed by the surrounding
/// padding. On phones a fixed 400pt box is wider than the screen itself, so
/// the padding compresses it — the logo image gets requested at 400px but
/// drawn at whatever's left, softening it. Scaling both dimensions off the
/// screen width keeps the request and the drawn size in agreement.
HomeHeroLogoMetrics homeHeroLogoConstraints({required double screenWidth, required bool isLargeScreen}) {
  if (isLargeScreen) return const HomeHeroLogoMetrics(width: 400, height: 120);

  final width = math.min(400.0, math.min(screenWidth * 0.78, screenWidth - 48));
  final height = (screenWidth * 0.23).clamp(90.0, 96.0);
  return HomeHeroLogoMetrics(width: width, height: height);
}
