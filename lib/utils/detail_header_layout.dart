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
/// How far [floor] may lift the header past the un-clamped 60% baseline on a
/// short window, as a fraction of `screenHeight`.
///
/// Finding 2, review round on `docs/density-audit-2026-09.md`: no minimum
/// window height exists anywhere in the app (`setMinimumSize` has zero hits
/// under `lib/`, `macos/`, `windows/`, `linux/`), so a floor pursued
/// regardless of window height can dominate a short one — at the limit
/// (`screenHeight` under the floor itself) the header could exceed the
/// window that asked for it. 0.7 is not arbitrary: it sits meaningfully
/// above the 60% baseline, so the floor still lifts a marginally short
/// window the way it always has, and meaningfully under the 75% this same
/// audit already flagged as the worst density offender in the app
/// (`homeHeroHeight` at 900/1080pt, its biggest MEDIA-tagged finding, left
/// out of this fixronde on Michel's own instruction) — the floor must never
/// make this surface worse than the one the audit already called out.
const double _maxHeaderViewportFraction = 0.7;

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
  // effectiveFloor <= floor <= upper always, so clamp()'s upper bound is
  // just upper itself — no separate effectiveUpper to compute.
  final effectiveFloor = math.min(floor, screenHeight * _maxHeaderViewportFraction);
  return base.clamp(effectiveFloor, upper);
}

/// Desktop (macOS/Windows/Linux) tier: `PlatformDetector.isDesktop`.
double desktopDetailHeaderHeight(double screenWidth, double screenHeight) =>
    detailHeaderHeight(screenWidth: screenWidth, screenHeight: screenHeight, ceiling: 680, floor: 400);

/// iPad / Android tablet tier: shorter ceiling and floor, matching the more
/// compact composition `HomeHeroContentTier.tabletPortrait` already uses for
/// iPad elsewhere (see `home_hero_layout.dart`).
double tabletDetailHeaderHeight(double screenWidth, double screenHeight) =>
    detailHeaderHeight(screenWidth: screenWidth, screenHeight: screenHeight, ceiling: 600, floor: 360);
