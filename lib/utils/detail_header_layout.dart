import 'dart:math' as math;

/// Height of the media-detail hero header on desktop and iPad/tablet
/// (`MediaDetailScreen`'s generic branch — TV uses the full viewport, and
/// phone has its own compact layout via `_buildMobileDetailScreen`).
///
/// Used to be a flat `size.height * 0.6` regardless of window size, which
/// reads fine on a laptop but turns into hundreds of pixels of near-empty
/// backdrop above the title block on a large desktop display or a portrait
/// iPad (864pt of pure artwork at 2560×1440; 826pt on a 1032×1376 iPad
/// portrait) — F-D1, docs/density-audit-2026-09.md. The title/actions block
/// itself is anchored to the header's bottom edge and does not grow with it,
/// so a taller header only ever adds dead backdrop, never more content.
///
/// [ceiling] bounds how tall the header may get; [floor] keeps a usable
/// backdrop on a short window. Both size classes also cap the header at the
/// height a 16:9 backdrop naturally wants for the window's width — beyond
/// that the header is just stretching the same image taller, not showing
/// more of it — mirroring the reasoning `homeHeroHeight` already uses for the
/// Home hero, without reusing its own 900pt cap (a different surface with a
/// different content column).
double detailHeaderHeight({
  required double screenWidth,
  required double screenHeight,
  required double ceiling,
  required double floor,
}) {
  final base = screenHeight * 0.6;
  final sixteenNineCap = screenWidth * 9 / 16;
  // max() first: on a very narrow window sixteenNineCap can fall under floor,
  // and clamp() throws if its upper bound is below its lower one.
  final upper = math.max(floor, math.min(ceiling, sixteenNineCap));
  return base.clamp(floor, upper);
}

/// Desktop (macOS/Windows/Linux) tier: `PlatformDetector.isDesktop`.
double desktopDetailHeaderHeight(double screenWidth, double screenHeight) =>
    detailHeaderHeight(screenWidth: screenWidth, screenHeight: screenHeight, ceiling: 680, floor: 400);

/// iPad / Android tablet tier: shorter ceiling and floor, matching the more
/// compact composition `HomeHeroContentTier.tabletPortrait` already uses for
/// iPad elsewhere (see `home_hero_layout.dart`).
double tabletDetailHeaderHeight(double screenWidth, double screenHeight) =>
    detailHeaderHeight(screenWidth: screenWidth, screenHeight: screenHeight, ceiling: 600, floor: 360);
