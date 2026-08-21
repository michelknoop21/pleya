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

/// Geometry for the hero's two artwork layers: a full-hero ambient wash and a
/// smaller, cropped-free sharp layer on top of it.
///
/// On a wide box the sharp layer fills the whole hero with `BoxFit.cover`,
/// exactly as before — there is no ambient layer, since there is no gap
/// around the sharp layer for one to fill. On a narrow (phone/tablet-portrait)
/// box the sharp layer shrinks to the aspect ratio of its own source — square
/// or 16:9 — so a server-side crop is never asked to force a mismatched ratio
/// into the full hero box, and the ambient layer (the same source, blurred
/// and darkened, `BoxFit.cover` across the whole canvas) fills what the sharp
/// layer leaves empty so the hero never shows a bare panel under it.
/// [requestWidth]/[requestHeight] always match the sharp layer's own ratio,
/// which is what keeps the transcoder's crop a no-op.
class HomeHeroArtGeometry {
  const HomeHeroArtGeometry({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.sharpWidth,
    required this.sharpHeight,
    required this.requestWidth,
    required this.requestHeight,
    required this.sharpFadeHeight,
    required this.sharpTopInset,
    required this.hasSharpForeground,
    required this.useAmbientLayer,
    required this.coversHero,
    this.presentation = HomeHeroSharpPresentation.island,
  });

  /// Full hero canvas width, in logical pixels — what the ambient layer (when
  /// present) and the full-bleed frame (when [coversHero]) both fill.
  final double canvasWidth;

  /// Full hero canvas height, in logical pixels.
  final double canvasHeight;

  /// Sharp (foreground) layer width.
  final double sharpWidth;

  /// Sharp (foreground) layer height.
  final double sharpHeight;

  /// `maxWidth` to send toward the transcoder, matching the sharp layer's own
  /// ratio. The ambient layer reuses this exact request (same URL, same
  /// cache entry) rather than asking for a second, differently-cropped
  /// transcode of the same source.
  final double requestWidth;

  /// `maxHeight` to send toward the transcoder, matching the sharp layer's own
  /// ratio.
  final double requestHeight;

  /// Height of the band at the bottom of the sharp layer that blends it into
  /// the ambient layer beneath. Zero when the sharp layer already covers the
  /// whole hero (nothing beneath it to blend into).
  final double sharpFadeHeight;

  /// Where the sharp layer starts, measured from the top of the canvas.
  ///
  /// Non-zero only on the island branch, and only when the caller asked for it
  /// through `requestedSharpTopInset` — on an iPhone in portrait that is the
  /// Dynamic Island / notch inset, which the sharp layer has to clear or its
  /// top edge disappears under the cutout. The ambient layer ignores this
  /// entirely and keeps filling the canvas from `y = 0`.
  final double sharpTopInset;

  /// True whenever there is a sharp layer to draw. False for the zero/unusable
  /// geometry ([HomeHeroArtGeometry.zero]), and for the degenerate case where
  /// the requested top inset leaves no room for an island at all — there
  /// [useAmbientLayer] stays true, so the hero shows the ambient wash rather
  /// than an empty panel or a sharp layer shoved back under the cutout.
  final bool hasSharpForeground;

  /// True when a full-hero ambient wash of the same source should be drawn
  /// beneath the sharp layer — i.e. the sharp layer is a smaller island, not
  /// a full-bleed cover fill.
  final bool useAmbientLayer;

  /// True when the sharp layer fills the entire hero with `BoxFit.cover`, as
  /// before this change (wide box, or no 16:9/square source to shape an
  /// island from). False when the sharp layer is a shorter/narrower island
  /// sized to its own source ratio, with an ambient layer filling the rest.
  final bool coversHero;

  /// Which composition the sharp layer uses. The widget reads this to decide
  /// whether the square branch also gets a left/right blend: an island needs
  /// one, a full-width layer must not have one, because its edges are the
  /// canvas edges.
  final HomeHeroSharpPresentation presentation;

  /// Height of the band at the *top* of the sharp layer that fades it in from
  /// the ambient layer beneath.
  ///
  /// A full-width layer starts at [sharpTopInset], so without this band its
  /// first pixel row jumps straight from ambient to fully sharp and draws a
  /// hard horizontal seam right under the Dynamic Island. Fading in over this
  /// band lets the ambient wash bleed through the top edge instead, the same
  /// trick the island's left/right blend uses, turned vertical.
  ///
  /// Zero for [HomeHeroSharpPresentation.island]: an island's top edge already
  /// sits inside the ambient field with nothing to butt up against.
  double get sharpTopBlendHeight {
    if (presentation != HomeHeroSharpPresentation.fullWidth) return 0;
    if (!hasSharpForeground || sharpHeight <= 0) return 0;
    // A covering frame has no ambient layer underneath, so there is nothing
    // for its top edge to blend into.
    if (coversHero || !useAmbientLayer) return 0;
    final band = (sharpHeight * _sharpTopBlendFraction).clamp(_sharpTopBlendMin, _sharpTopBlendMax);
    // The top band can never run into the bottom fade: on a very short layer
    // the two would cross and the alpha stops would stop ascending.
    return math.min(band, math.max(0.0, sharpHeight - sharpFadeHeight));
  }

  static const zero = HomeHeroArtGeometry(
    canvasWidth: 0,
    canvasHeight: 0,
    sharpWidth: 0,
    sharpHeight: 0,
    requestWidth: 0,
    requestHeight: 0,
    sharpFadeHeight: 0,
    sharpTopInset: 0,
    hasSharpForeground: false,
    useAmbientLayer: false,
    coversHero: false,
  );
}

/// The sharp island's width as a fraction of the hero's own width, on a
/// narrow box. Smaller than the full width on purpose — the mockup's
/// composition reads as a quiet, centred subject over an atmospheric
/// background, not another full-width banner.
const double _sharpIslandWidthFraction = 0.82;

/// How far down the sharp island's own height its blend into the ambient
/// layer begins. The remaining (1 - this) of the island's height is the
/// blend band itself (see [HomeHeroArtGeometry.sharpFadeHeight]).
const double _sharpFadeStartFraction = 0.55;

/// The full-width layer's top fade-in band, as a fraction of its own height,
/// clamped to a range that stays visible on a short 16:9 strip without eating
/// the subject on a tall square. See [HomeHeroArtGeometry.sharpTopBlendHeight].
const double _sharpTopBlendFraction = 0.18;
const double _sharpTopBlendMin = 36.0;
const double _sharpTopBlendMax = 64.0;

/// How the sharp layer is composed on a narrow box.
///
/// This is an explicit choice by the caller, not something inferred from a
/// non-zero [homeHeroArtGeometry.requestedSharpTopInset]: the inset says
/// *where* the sharp layer starts, never *how wide* it is, and reading
/// full-width out of "the inset happens to be non-zero" would tie two
/// unrelated decisions together.
enum HomeHeroSharpPresentation {
  /// A centred subject at [_sharpIslandWidthFraction] of the box width, blended
  /// into the ambient layer on all sides. iPad-portrait and every other
  /// existing caller.
  island,

  /// Edge to edge: the sharp layer spans the full canvas width at its own
  /// source ratio, starting straight under the hardware safe area. iPhone in
  /// portrait, where a centred island reads as a small card rather than a
  /// hero.
  fullWidth,
}

/// [requestedSharpTopInset] moves the sharp layer down from the top of the
/// canvas so its top edge clears an iPhone's Dynamic Island. It only ever
/// offsets — it never resizes the layer, which is what turned the hero into a
/// small centred card. The full-bleed branch ignores it entirely, as does
/// every caller that passes the default 0 (iPad, Android, macOS, desktop).
///
/// [presentation] picks the composition; see [HomeHeroSharpPresentation].
HomeHeroArtGeometry homeHeroArtGeometry({
  required double screenWidth,
  required double heroHeight,
  required BillboardArtKind kind,
  double requestedSharpTopInset = 0,
  HomeHeroSharpPresentation presentation = HomeHeroSharpPresentation.island,
}) {
  if (heroHeight <= 0 || screenWidth <= 0) return HomeHeroArtGeometry.zero;

  final isWideBox = screenWidth / heroHeight >= billboardNarrowAspectRatioThreshold;
  if (isWideBox || kind == BillboardArtKind.fallback) {
    // Full-bleed cover fill: either the box is wide enough that a 16:9
    // backdrop needs no island treatment, or there is no 16:9/square source
    // at all (fallback) and the caller draws it blurred as atmosphere. Either
    // way there is no gap around the frame for an ambient layer to fill.
    return HomeHeroArtGeometry(
      canvasWidth: screenWidth,
      canvasHeight: heroHeight,
      sharpWidth: screenWidth,
      sharpHeight: heroHeight,
      requestWidth: screenWidth,
      requestHeight: math.max(screenWidth * 9 / 16, heroHeight),
      sharpFadeHeight: 0,
      // A full-bleed frame has no gap to fall into and no ambient layer behind
      // it, so pushing it down would just expose the scaffold at the top.
      sharpTopInset: 0,
      hasSharpForeground: true,
      useAmbientLayer: false,
      coversHero: true,
      // Carried through even though this branch has no ambient layer and so
      // never reads it: a geometry that reports a presentation the caller did
      // not ask for is a trap for the next reader of `sharpTopBlendHeight` or
      // the side-fade gate.
      presentation: presentation,
    );
  }

  // The inset offsets, it never resizes. Shrinking the layer by the inset is
  // what turned a full-width hero into a small centred card.
  final effectiveSharpTopInset = math.max(0.0, requestedSharpTopInset);

  // What is left under the inset. A full-width layer has to fit inside it: the
  // widget hands the layer loose constraints capped at this height, so an
  // oversized layer is squeezed by layout rather than honoured — and then
  // `BoxFit.contain` letterboxes it (a 375pt-wide square in a 340pt-tall box
  // draws 340x340 with 17.5pt of ambient down each side, so no longer edge to
  // edge) while the fade bands still compute their stops from a height the
  // layer never had. Clamping here keeps the geometry telling the truth.
  //
  // A square cannot be 1:1, uncropped, and full width at the same time in a box
  // shorter than it is wide. Image integrity wins over edge-to-edge: the layer
  // shrinks and stays centred, exactly as the island branch already does.
  final availableSharpHeight = math.max(0.0, heroHeight - effectiveSharpTopInset);

  // The layer at its natural size, before it has to fit anywhere. Kept around
  // because the degenerate branch below still needs a sane transcode request
  // for the ambient layer even when the clamped size collapses to nothing.
  final double naturalWidth, naturalHeight;
  switch ((presentation, kind)) {
    case (HomeHeroSharpPresentation.fullWidth, BillboardArtKind.square):
      naturalWidth = screenWidth;
      naturalHeight = screenWidth;
    case (HomeHeroSharpPresentation.fullWidth, BillboardArtKind.widescreen):
      naturalWidth = screenWidth;
      naturalHeight = screenWidth * 9 / 16;
    case (HomeHeroSharpPresentation.island, BillboardArtKind.square):
      // Clamped to both the hero's own width and height so a very short hero
      // (or a very narrow one) never asks for an island bigger than the box
      // it sits in.
      final side = math.min(screenWidth * _sharpIslandWidthFraction, math.min(screenWidth, heroHeight));
      naturalWidth = side;
      naturalHeight = side;
    case (HomeHeroSharpPresentation.island, BillboardArtKind.widescreen):
      naturalWidth = screenWidth;
      naturalHeight = math.min(screenWidth * 9 / 16, heroHeight);
    case (_, BillboardArtKind.fallback):
      naturalWidth = screenWidth; // unreachable: handled above
      naturalHeight = heroHeight; // unreachable: handled above
  }

  // Fit it under the inset, holding the source ratio exactly: height is what
  // gets trimmed, width follows from the ratio.
  final fitScale = naturalHeight <= 0 ? 1.0 : math.min(1.0, availableSharpHeight / naturalHeight);
  final sharpWidth = naturalWidth * fitScale;
  final sharpHeight = naturalHeight * fitScale;

  if (availableSharpHeight <= 0) {
    // The inset pushes the sharp layer entirely off the canvas. Falling back
    // to inset 0 would put it straight back under the cutout, which is the
    // defect this inset exists to fix, so drop the sharp layer and let the
    // ambient wash carry the hero. The request size stays at the layer's own
    // size so the ambient layer still asks for a sane transcode.
    return HomeHeroArtGeometry(
      canvasWidth: screenWidth,
      canvasHeight: heroHeight,
      sharpWidth: 0,
      sharpHeight: 0,
      requestWidth: naturalWidth,
      requestHeight: naturalHeight,
      sharpFadeHeight: 0,
      sharpTopInset: 0,
      hasSharpForeground: false,
      useAmbientLayer: true,
      coversHero: false,
      presentation: presentation,
    );
  }

  return HomeHeroArtGeometry(
    canvasWidth: screenWidth,
    canvasHeight: heroHeight,
    sharpWidth: sharpWidth,
    sharpHeight: sharpHeight,
    requestWidth: sharpWidth,
    requestHeight: sharpHeight,
    sharpFadeHeight: sharpHeight * (1 - _sharpFadeStartFraction),
    sharpTopInset: effectiveSharpTopInset,
    hasSharpForeground: true,
    useAmbientLayer: true,
    coversHero: false,
    presentation: presentation,
  );
}

/// Which content-layout treatment the hero's info column (logo, metadata,
/// play button, summary, pagination) uses.
///
/// [wide] is desktop and iPad-*landscape*: the hero is wide enough that
/// left-aligned content beside the artwork reads naturally. [tabletPortrait]
/// is an iPad held in portrait: still centred and compact like [phone], but on
/// a canvas wide enough that the content column and clear-logo need their own
/// width cap so they don't stretch across the whole box. [phone] is every
/// other narrow, portrait box.
///
/// iPad specifically, not "a tablet": the gate is
/// `PlatformDetector.isHandheldIOS`, which reads
/// `Theme.of(context).platform == TargetPlatform.iOS`. An 800pt Android tablet
/// in portrait reports `TargetPlatform.android` and therefore gets [phone],
/// with the phone logo box. That is a known gap, not an accident of wording.
enum HomeHeroContentTier { phone, tabletPortrait, wide }

/// Constraints for the hero's clear-logo (or fallback title) box.
class HomeHeroLogoMetrics {
  const HomeHeroLogoMetrics({required this.width, required this.height});

  final double width;
  final double height;
}

/// On [HomeHeroContentTier.wide] the logo box stays a fixed 400×120: the hero
/// is wide enough there that a fixed box never gets squeezed by the
/// surrounding padding. On [HomeHeroContentTier.phone] a fixed 400pt box can
/// be wider than the screen itself, so the padding would compress it — the
/// logo image gets requested at 400px but drawn at whatever's left,
/// softening it. Scaling both dimensions off the screen width keeps the
/// request and the drawn size in agreement.
///
/// [HomeHeroContentTier.tabletPortrait] does *not* reuse the phone formula:
/// that formula tops out at 400×96 well before iPad widths, which technically
/// stays under the mockup's roughly-520pt cap but reads visibly smaller than
/// the mockup's logo. It scales more aggressively instead (0.55× width,
/// 0.18× height) so the box actually grows with the canvas up to the 520×160
/// cap, landing at roughly 422×138 (768pt), 459×150 (834pt), and 520×160
/// (1024pt).
HomeHeroLogoMetrics homeHeroLogoConstraints({required double screenWidth, required HomeHeroContentTier tier}) {
  switch (tier) {
    case HomeHeroContentTier.wide:
      return const HomeHeroLogoMetrics(width: 400, height: 120);
    case HomeHeroContentTier.tabletPortrait:
      final width = math.min(520.0, math.min(screenWidth * 0.55, screenWidth - 64));
      final height = (screenWidth * 0.18).clamp(120.0, 160.0);
      return HomeHeroLogoMetrics(width: width, height: height);
    case HomeHeroContentTier.phone:
      final width = math.min(400.0, math.min(screenWidth * 0.78, screenWidth - 48));
      final height = (screenWidth * 0.23).clamp(90.0, 96.0);
      return HomeHeroLogoMetrics(width: width, height: height);
  }
}

/// Vertical rhythm of the hero's info column, plus how far its bottom anchor
/// and the pagination row sit from the hero's own bottom edge.
///
/// [phone] and [tabletPortrait] share one compact rhythm — the mockups show
/// the same tight, centred composition on both, just on a wider canvas for
/// the latter — while [wide] keeps the spacing this hero always used.
class HomeHeroContentMetrics {
  const HomeHeroContentMetrics({
    required this.logoToMeta,
    required this.metaToButton,
    required this.buttonToSummary,
    required this.contentToPagination,
    required this.paginationHeight,
    required this.paginationBottomInset,
    required this.contentBottomInset,
    required this.paginationToRailHeading,
    required this.maxContentWidth,
  });

  /// Gap between the logo/title and the metadata line.
  final double logoToMeta;

  /// Gap between the metadata line and the play button (phone/tabletPortrait
  /// order: logo, metadata, button, summary).
  final double metaToButton;

  /// Gap between the play button and the summary.
  final double buttonToSummary;

  /// Gap the info column's bottom anchor keeps above the pagination row.
  final double contentToPagination;

  /// Height of the pagination dot row itself.
  final double paginationHeight;

  /// Distance from the hero's bottom edge to the pagination row.
  final double paginationBottomInset;

  /// Distance from the hero's bottom edge to the info column's own bottom
  /// anchor (fed to the content `Positioned.bottom`). Derived from the three
  /// values above on the narrow tiers so overlap with the pagination row is
  /// provably impossible; a fixed legacy value on [HomeHeroContentTier.wide].
  final double contentBottomInset;

  /// Distance from the pagination row's own bottom edge to the top of the
  /// "Verder kijken" heading directly below the hero. Not enforced by this
  /// hero widget itself — it exists so tests can pin the gap against
  /// `HubSection`'s own header padding (see the doc comment at the call
  /// site) without duplicating that number here.
  final double paginationToRailHeading;

  /// Cap on the info column's width. Null means unconstrained (phone is
  /// already narrow enough that it never needs one; wide already limits
  /// itself via the `right:` inset at the call site).
  final double? maxContentWidth;
}

/// `HubSection`'s own top padding above its title row (`vertical: 2` inside
/// `vertical: 2` — see `HubSectionState.build`), which sits directly below
/// the hero sliver with nothing in between. Shared here so
/// [HomeHeroContentMetrics.paginationToRailHeading] can be checked against
/// the rail's real header offset instead of a number copied by hand.
const double _railHeaderTopPadding = 4.0;

/// Distance from the hero's bottom edge to the pagination row.
///
/// Deliberately one number rather than a per-tier one: all three tiers landed
/// on the same 16, so asking for the tier just to read this back cost a
/// `MediaQuery.orientationOf` dependency (and a rotation rebuild) for a
/// constant. [HomeHeroContentMetrics.paginationBottomInset] still carries it
/// so the metrics object stays self-describing.
const double homeHeroPaginationBottomInset = 16.0;

const HomeHeroContentMetrics _compactContentMetrics = HomeHeroContentMetrics(
  logoToMeta: 12,
  metaToButton: 16,
  buttonToSummary: 12,
  contentToPagination: 14,
  paginationHeight: 18,
  paginationBottomInset: homeHeroPaginationBottomInset,
  contentBottomInset: 48, // paginationBottomInset + paginationHeight + contentToPagination
  paginationToRailHeading: 16 + _railHeaderTopPadding, // paginationBottomInset + _railHeaderTopPadding
  maxContentWidth: null,
);

HomeHeroContentMetrics homeHeroContentMetrics({required HomeHeroContentTier tier}) => switch (tier) {
  HomeHeroContentTier.phone => _compactContentMetrics,
  // Same rhythm as [HomeHeroContentTier.phone] (see the doc comment on
  // [HomeHeroContentMetrics]) — only `maxContentWidth` differs, so the
  // values are spelled out again here rather than read off
  // `_compactContentMetrics.field`, which Dart won't const-evaluate.
  HomeHeroContentTier.tabletPortrait => const HomeHeroContentMetrics(
    logoToMeta: 12,
    metaToButton: 16,
    buttonToSummary: 12,
    contentToPagination: 14,
    paginationHeight: 18,
    paginationBottomInset: homeHeroPaginationBottomInset,
    contentBottomInset: 48,
    paginationToRailHeading: 16 + _railHeaderTopPadding,
    maxContentWidth: 600,
  ),
  HomeHeroContentTier.wide => HomeHeroContentMetrics(
    logoToMeta: 16,
    metaToButton: 20,
    buttonToSummary: 12,
    contentToPagination: 14,
    paginationHeight: 18,
    paginationBottomInset: homeHeroPaginationBottomInset,
    contentBottomInset: 80,
    paginationToRailHeading: 16 + _railHeaderTopPadding,
    maxContentWidth: null,
  ),
};
