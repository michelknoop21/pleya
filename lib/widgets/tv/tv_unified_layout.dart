/// Layout tokens for the Pleya Unified TV 2026 surfaces (hoofdstuk 8 of
/// docs/tvos-unified-experience.md, which asks for "één `TvUnifiedLayout` …
/// Geen losse magic numbers per widget").
///
/// **Reading the numbers.** Hoofdstuk 8 states every measurement on a
/// 1920×1080 TV *output* surface. [DEC-028] renders Apple TV at scale 1.85, so
/// the logical canvas a widget sees is roughly 1038×584 and a reference number
/// is never a Flutter logical pixel. Two different conversions apply, and
/// mixing them up is the mistake this file exists to prevent:
///
/// * **Box composition** — panel width, outer margins, corner radius — is a
///   proportion of the viewport. `resolveOverlaySheetGeometry` owns that half,
///   because it has the viewport; see the TV panel section there.
/// * **Type and touch density** — font sizes, row heights, gaps — goes through
///   [TvLayoutConstants.scaleOf], which is clamped to `[0.85, 1.35]` precisely
///   so 10-foot text does *not* shrink linearly with the canvas. The base
///   values below are therefore pre-divided by that clamp: a base of 22 renders
///   at 18.7 logical on the canonical canvas, which is ~34 reference px — inside
///   hoofdstuk 8.3's "source picker titel 32–38".
///
/// This grows one phase at a time. Fase 4 added the source picker; fase 5 adds
/// the Films/Series page header, grid and card ([TvCatalogLayout]). The
/// billboard and carousel tokens hoofdstuk 8 also lists land in the phases that
/// build those surfaces, rather than being invented here first.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
// `painting` and not `widgets`: this file states geometry, and [EdgeInsets] is
// the type that says "padding on four sides" without dragging a widget tree in.
import 'package:flutter/painting.dart';

import '../../focus/focus_theme.dart';
import '../../utils/layout_constants.dart';

/// Base metrics for the source picker of hoofdstuk 14. Multiply by
/// [TvLayoutConstants.scaleOf] at the use site.
class TvSourcePickerLayout {
  const TvSourcePickerLayout._();

  /// Padding inside the panel edge.
  static const double panelPadding = 26;

  /// Gap between the header artwork and the header text column.
  static const double headerGap = 20;

  /// Header artwork width. 2:3 poster, so the height follows from
  /// [posterAspectRatio]. Deliberately modest: the header's job is to say
  /// *which title* this is, and a poster that outweighs its own title turns the
  /// header into a product tile.
  static const double posterWidth = 74;

  static const double posterAspectRatio = 2 / 3;

  /// Corner radius on the header artwork and on a source row.
  static const double artworkRadius = 8;
  static const double rowRadius = 10;

  /// Minimum height of one source row. Rows size to their content — a source
  /// with no quality metadata has one line fewer (hoofdstuk 14.3: "Ontbrekende
  /// metadata wordt weggelaten") — but never collapse below this, or a sparse
  /// row stops reading as the same kind of thing as a rich one.
  static const double rowMinHeight = 64;

  /// Padding inside a source row.
  static const double rowPaddingHorizontal = 16;
  static const double rowPaddingVertical = 11;

  /// Vertical gap between source rows. Wide enough that a row reads as its own
  /// card rather than as a cell in a table — the difference between a picker
  /// and a settings list is largely this number.
  static const double rowGap = 9;

  /// Gap between the two text lines inside a row.
  static const double rowLineGap = 4;

  /// Gap above the resume bar. Its own number rather than a multiple of
  /// [rowLineGap], because the bar is not a fourth line of text: at line
  /// spacing it sits on the descenders of the quality line and reads as an
  /// underline of "E-AC3 Atmos" rather than as progress through the film.
  static const double progressBarGap = 9;

  /// Height of the progress bar on a row with resume progress. Three reference
  /// pixels vanished at three metres; this is the smallest that still reads as
  /// a bar rather than as a stray red line.
  static const double progressBarHeight = 4;

  /// Gap between a panel button's capsule and its focus ring. Without it a
  /// white ring around a white CTA merges into one slightly fatter capsule and
  /// stops saying "this is where I am" — hoofdstuk 34 pins both the white ring
  /// and the white primary CTA, so they need to be held apart by geometry.
  static const double buttonFocusRingGap = 3;

  /// Vertical gaps in the panel body.
  static const double sectionGap = 20;
  static const double footerGap = 18;

  /// Type sizes (hoofdstuk 8.3), before the TV scale.
  static const double titleFontSize = 22;
  static const double subtitleFontSize = 13.5;
  static const double rowPrimaryFontSize = 16.5;
  static const double rowSecondaryFontSize = 12.5;

  /// Third line: quality and progress. Deliberately a step below the second —
  /// hoofdstuk 14.3's row has three tiers, and three lines at one weight is
  /// how a source row starts reading as a table.
  static const double rowTertiaryFontSize = 11.5;
  static const double statusFontSize = 12;
  static const double buttonFontSize = 15;

  /// The ink ladder, as alphas on `MonoTokens.text`.
  ///
  /// Size alone does not build a hierarchy on a 10-foot surface: at three
  /// metres a 12.5px line at 85% white and a 16px line at 100% white read as
  /// two headings, which is exactly what made the first render look like a
  /// settings list. The tiers below are spaced far enough apart that the server
  /// name wins the row before the eye has resolved any of the smaller type.
  ///
  /// Alphas on an existing token, never new colours — hoofdstuk 34 fixes the
  /// palette, and `monoTheme` derives its own muted inks the same way.
  ///
  /// The floor is legibility, not taste: over the idle row fill these render at
  /// roughly #FFF / #BABABA / #949494, which is 7.2:1 and 4.6:1 against that
  /// fill. Tertiary is the resolution and audio format — small type that people
  /// squint at from a sofa — so it stays above AA rather than being dimmed
  /// until the hierarchy "looks" right on a monitor at arm's length.
  static const double inkPrimary = 1;
  static const double inkSecondary = 0.68;
  static const double inkTertiary = 0.5;
  static const double inkQuiet = 0.5;

  /// The same ladder on a row nobody can pick. Compressed and dimmed as a
  /// block: a disabled row still has to be readable ("which server is down?"),
  /// it just must not compete with the rows that can be chosen.
  static const double inkDisabledPrimary = 0.38;
  static const double inkDisabledSecondary = 0.3;
  static const double inkDisabledTertiary = 0.24;

  /// Surface alphas on `MonoTokens.text`, composited over the panel.
  ///
  /// `idleRowFill` sits far enough above `mono.surface` to read as a card and
  /// far enough below `mono.surfaceElevated` to leave the focused row somewhere
  /// to go. `focusedRowSheen` is the top stop of the focused row's fill: a
  /// surface lit from above is the cheapest depth cue there is, and it costs no
  /// layout, unlike a shadow the list viewport would clip anyway.
  static const double idleRowFill = 0.05;
  static const double idleRowOutline = 0.06;
  static const double focusedRowSheen = 0.05;

  /// The same top-lit wash on the panel itself, one step fainter — enough to
  /// give the whole surface a light direction, not enough to be seen as a
  /// gradient.
  static const double panelSheen = 0.035;

  /// Track behind the red resume fill.
  static const double progressTrack = 0.16;
}

/// Base metrics for the Films and Series pages of hoofdstuk 10. Multiply the
/// type and density values by [TvLayoutConstants.scaleOf] at the use site; the
/// column count and the gutters come from [TvCatalogGrid.forWidth], which needs
/// the live viewport.
class TvCatalogLayout {
  const TvCatalogLayout._();

  /// Hoofdstuk 8.1's vertical breathing room above the header, as a reference
  /// measurement: no text and no focus ring inside the outer 56 px.
  static const double topSafeInset = 56;

  /// The same band at the *bottom* edge, where 56 turned out to be a floor
  /// rather than a margin (P12).
  ///
  /// 56 reference px is 5.2% of the reference height, and ~5% per edge is what
  /// a consumer set overscans — so a page laid out to exactly 56 puts its last
  /// readable line and the bottom row's focus ring precisely *on* the band
  /// rather than clear of it, and a set that overscans a little more than
  /// nominal eats them. That is not a rule this changes: hoofdstuk 8.1 states a
  /// minimum ("geen tekst of focusring binnen de buitenste 56 pixels"), and 81
  /// keeps well inside it.
  ///
  /// 81 is 7.5% of the 1080 reference height, the upper end of consumer
  /// overscan, so the bottom edge clears the worst case instead of matching the
  /// nominal one. The top keeps [topSafeInset]: there the page heading pays the
  /// margin and the first thing under it is a heading, not the last line of the
  /// page, and its focus headroom is budgeted separately in
  /// [TvCatalogGrid.focusRingHeadroom].
  ///
  /// This is a straight increase in clearance, so it only pays off where the
  /// page has the room to give — which is what DEC-087's shorter rails
  /// deliver. Doing it alone would have pushed content up without giving any
  /// of it back.
  static const double bottomSafeInset = 81;

  /// Page heading, hoofdstuk 8.3's "paginaheading Films/Series 38–44" divided
  /// by the [TvLayoutConstants.scaleForHeight] clamp: 27 renders at ~23 logical
  /// on the canonical canvas, which is ~42 reference px — the upper half of the
  /// band. Deliberately not the top of it: this is the only permanent piece of
  /// chrome that says which catalog you are in, so it has to win the page, but
  /// at 47 reference px it started competing with the posters instead of
  /// introducing them.
  static const double pageTitleFontSize = 27;

  /// Gap between the page title and the header actions beside it.
  static const double titleActionGap = 26;

  /// Gap between the header line and the first grid row. Roomy on purpose: it
  /// is the whole separation between chrome and content on a page with no
  /// hero, no divider and no background change to do that job.
  static const double headerContentGap = 20;

  /// A header action's capsule.
  static const double actionFontSize = 15;
  static const double actionPaddingHorizontal = 15;
  static const double actionPaddingVertical = 8;
  static const double actionGap = 10;
  static const double actionRadius = 999;
  static const double actionIconSize = 17;
  static const double actionIconGap = 8;

  /// Gap between a capsule and its focus ring, for the same reason
  /// [TvSourcePickerLayout.buttonFocusRingGap] exists: a white ring drawn onto
  /// a pale capsule reads as a slightly fatter capsule, not as focus.
  static const double actionFocusRingGap = 3;

  /// The count badge on the Filters action (hoofdstuk 10.6).
  static const double actionBadgeSize = 18;
  static const double actionBadgeFontSize = 11;

  /// Card metrics. The poster is 2:3 (hoofdstuk 10.2, binding for both pages);
  /// the meta footer below it is the shared card language both mockups use.
  static const double posterAspectRatio = 2 / 3;
  static const double cardRadius = 10;

  /// Band of page background between the card's content and its focus ring —
  /// the same device, and the same reason, as
  /// [TvSourcePickerLayout.buttonFocusRingGap].
  ///
  /// Without it the ring is drawn flush against the artwork, and two things go
  /// wrong that a grid of grey placeholders could never show. A 2.5px white
  /// ring laid directly onto a bright poster has almost nothing to contrast
  /// with, so focus stops reading at three metres on exactly the cards that
  /// are most eye-catching; and the title underneath starts at the ring's inner
  /// edge, so the focused card is the one card whose text looks cropped. A
  /// couple of pixels of `MonoTokens.bg` fixes both, and costs the artwork
  /// nothing anyone can see.
  static const double cardFocusRingGap = 5;

  /// The shadow every poster casts, and the deeper one the focused poster casts.
  ///
  /// This is the difference between artwork that sits *on* the page and artwork
  /// that reads as a hole cut into it. On a `#141414` ground a black shadow has
  /// somewhere to go — the room is not actually black — so a soft dark pool
  /// under each poster gives the grid a surface to stand on, which is most of
  /// what separates a premium TV wall from a Flutter grid of flat swatches.
  ///
  /// Focus roughly doubles it and drops it further. Depth, not decoration: the
  /// focused card has to look nearer the viewer than its neighbours, and a ring
  /// alone cannot say that — a ring is a line on the same plane.
  static const double cardShadowBlur = 14;
  static const double cardShadowOffsetY = 5;
  static const double cardShadowAlpha = 0.55;
  static const double cardFocusShadowBlur = 30;
  static const double cardFocusShadowOffsetY = 12;
  static const double cardFocusShadowAlpha = 0.75;

  /// What the artwork of a focused card does. A small brightness lift, so the
  /// content itself answers the remote rather than only the chrome around it —
  /// the poster the user is standing on gets a little more light than the wall.
  static const double cardFocusArtworkLift = 0.10;

  /// How much lighter the top of the page is than the bottom, as an alpha on
  /// `MonoTokens.text` blended into `MonoTokens.bg`. Small on purpose: this is a
  /// horizon, not a gradient anyone should be able to name.
  static const double pageLift = 0.022;

  /// How far inside its own column a card's content actually starts.
  ///
  /// Two terms, and forgetting the first is the usual bug: the focus ring is a
  /// *border*, which costs [FocusTheme.focusBorderWidth] a side whether or not
  /// the card holds the focus, and only then does the card pad by
  /// [cardFocusRingGap]. Anything that has to line up with the posters — the
  /// page heading above them, a placeholder standing in for them, the card's
  /// own footer — has to count both.
  ///
  /// DEC-065 punt 4 moved the ring from around the whole card to around the
  /// artwork alone, but not the inset: the poster still starts here, so every
  /// other measurement on the page still lines up against this one.
  static double cardContentInset(double scale) => FocusTheme.focusBorderWidth + cardFocusRingGap * scale;

  /// Title and context line inside the footer. 14 renders at ~11.9 logical,
  /// ~22 reference px — inside hoofdstuk 8.3's "card title 18–21" at the top,
  /// which is where a two-line title still reads at three metres.
  static const double cardTitleFontSize = 14;

  /// Line height of a card title, and the multiplier that reserves two lines of
  /// it whether the title needs both or not — see the card's own comment.
  static const double cardTitleLineHeight = 1.2;
  static const double cardMetaFontSize = 11.5;

  /// Line height of the meta line, named for the same reason the title's is:
  /// [cardHeight] has to add up the card the footer actually draws.
  static const double cardMetaLineHeight = 1.2;

  /// The meta block under the artwork.
  ///
  /// No horizontal padding, because there is no longer a box to pad inside of:
  /// the title starts on the poster's own left edge, which is what makes a
  /// column of cards line up as a column. The vertical value is the gap between
  /// the poster and its title.
  static const double cardFooterPaddingVertical = 6;
  static const double cardFooterLineGap = 3;

  /// The height `TvUnifiedMediaCard` lays out for a card [cardWidth] wide, and
  /// therefore the box that focus scales.
  ///
  /// Every term is fixed by the card's own construction rather than by its
  /// content, which is what makes this a function instead of a measurement: the
  /// poster is [posterAspectRatio] inside two [cardContentInset]s, the title
  /// block is a `SizedBox` of two lines whether the title needs them or not,
  /// and the meta line is drawn even when it has nothing to say. No string on
  /// the card can change the answer.
  ///
  /// The meta line is rounded up because the engine rounds it up: a 9.775px
  /// line at [cardMetaLineHeight] renders 12 logical pixels tall, not 11.73,
  /// and font metrics are not this file's to predict to the decimal. Rounding
  /// the way `MediaCardGridLayout.captionExtentFor` already does keeps this an
  /// upper bound of what the card lays out: over by at most one pixel, never
  /// under. `the computed card height bounds the height the card lays out` in
  /// `tv_unified_media_grid_test.dart` holds the two together.
  static double cardHeight(double cardWidth, double scale) {
    final inset = cardContentInset(scale);
    final posterBlock = (cardWidth - inset * 2) / posterAspectRatio + inset * 2;
    final footer =
        cardFooterPaddingVertical * scale * 2 +
        cardTitleFontSize * scale * cardTitleLineHeight * 2 +
        cardFooterLineGap * scale +
        (cardMetaFontSize * scale * cardMetaLineHeight).ceilToDouble();
    return posterBlock + footer;
  }

  /// The loading placeholder's fills, as alphas on `MonoTokens.text`.
  ///
  /// Two values rather than one because the placeholder is a card, not a
  /// rectangle: the poster block carries the eye and the two text bars under it
  /// have to read as subordinate to it, exactly as the real title and meta line
  /// do. Flat at one alpha the skeleton reads as a grid of grey slabs, which is
  /// the "Flutter database grid" impression the page exists to avoid.
  static const double skeletonArtworkFill = 0.055;
  static const double skeletonTextFill = 0.085;

  /// Widths of the two placeholder text bars, as fractions of the card. Unequal
  /// on purpose: two bars of the same length are a shape, two of these lengths
  /// are a title with a shorter line under it.
  static const double skeletonTitleWidthFraction = 0.72;
  static const double skeletonMetaWidthFraction = 0.45;
  static const double skeletonBarRadius = 3;

  /// Density of a panel option row — one line of text, sometimes two.
  ///
  /// Its own set rather than [TvSourcePickerLayout]'s row metrics: a source row
  /// carries server, library, quality and progress on three tiers and is sized
  /// for that, and inheriting it made the sort panel's seven fixed options
  /// overflow a panel they should never have needed to scroll. A list a remote
  /// has to walk is better when the whole list is on screen.
  static const double optionRowMinHeight = 44;
  static const double optionRowPaddingHorizontal = 16;
  static const double optionRowPaddingVertical = 10;
  static const double optionRowGap = 7;

  /// Fill and outline of a *selected* option row, as alphas on `MonoTokens.text`.
  ///
  /// [DEC-053] again, and the same failure it names: the row used to draw
  /// `idleRowFill` whether it was chosen or not, so "All" and "Unwatched" sat at
  /// the same grey and the only thing separating them was a tick glyph parked
  /// some 280 logical pixels away at the far end of the row. At three metres
  /// that is not a selection state, it is a rumour. The numbers match the
  /// category rail's active chip, because it is the same idea one zone over.
  static const double optionSelectedFill = 0.14;
  static const double optionSelectedOutline = 0.2;

  /// Added on top of whichever of the two fills the row already carries when it
  /// holds the focus. Deliberately additive rather than a third absolute value:
  /// selected and focused are independent states (a row can be either, both or
  /// neither), so the focused fill has to be legible over both.
  static const double optionFocusedSheen = 0.06;

  /// The filter panel's category rail (hoofdstuk 10.6), as a fraction of the
  /// panel's own inner width rather than a fixed number of pixels.
  ///
  /// The panel itself is a proportion of the viewport, so a rail in logical
  /// pixels would be a third of the panel on the canonical canvas and half of it
  /// in a small simulator window. The bounds are what keep the split readable
  /// where the fraction alone would not: below the floor a category label
  /// ellipsises, above the ceiling the options column — the half the user is
  /// actually choosing in — gets narrower than the rail that indexes it.
  static const double filterRailFraction = 0.34;
  static const double filterRailMinWidth = 120;
  static const double filterRailMaxWidth = 260;

  /// Gap between the category rail and the options column. Wide enough to read
  /// as two zones; a hairline divider was tried first and turned the panel back
  /// into a settings window.
  static const double filterZoneGap = 18;

  /// How many option rows the zone area is tall, regardless of how many the
  /// active category actually has.
  ///
  /// Without this the panel is as tall as its content, and content is whatever
  /// category the focus is on: Servers has three rows, Genre has ten. Walking
  /// DOWN the rail then resized the panel by some 165 logical pixels a step and
  /// — because the sheet is centred — slid it up and down the screen while the
  /// user was only moving between two labels. The footer moved under the
  /// pointer of attention every press.
  ///
  /// Six is chosen against both zones, not just one: it is taller than a full
  /// five-category rail (5 * 38 + 4 * 7 = 218 against 263), so the rail never
  /// sets the height and the split never reflows, and it leaves the short
  /// categories with quiet space under them rather than a cramped box. Longer
  /// lists keep scrolling under [_FadingEdges], which is the affordance that
  /// already says "there is more below".
  static const int filterZoneRows = 6;

  /// The count chip on a category that has active selections.
  static const double filterCountFontSize = 10.5;
  static const double filterCountPaddingHorizontal = 6;
  static const double filterCountPaddingVertical = 2;

  /// Fill and outline of the *active* category in the rail, as alphas on
  /// `MonoTokens.text`.
  ///
  /// Well above [TvSourcePickerLayout.idleRowFill], and that gap is the whole
  /// point. An inactive category carries no fill at all, so this number is not
  /// "a row, slightly lighter" — it is the entire difference between a label
  /// and a chip. The first attempt used 0.10 and the active category was
  /// legible only while it also held the focus ring; the moment the user moved
  /// RIGHT into the options the rail stopped saying which list was on screen,
  /// which is precisely the failure [DEC-053] is about.
  static const double filterActiveCategoryFill = 0.14;
  static const double filterActiveCategoryOutline = 0.2;

  /// Ink on an inactive category. Below [inkSecondary]: the rail is an index,
  /// and four of its five entries should sit behind the list they point at.
  static const double filterIdleCategoryInk = 0.55;

  /// The multi-source badge of hoofdstuk 10.3.
  static const double badgeFontSize = 10.5;
  static const double badgePaddingHorizontal = 7;
  static const double badgePaddingVertical = 3;
  static const double badgeRadius = 5;
  static const double badgeInset = 7;

  /// Progress bar along the bottom edge of the artwork.
  static const double progressBarHeight = 4;

  /// The watched tick, which sits on the artwork rather than in the context
  /// line. In the line it had to share a row with the genre, so at card width
  /// the genre truncated to make room for a 15px glyph and the result read as a
  /// broken string next to a dot. On the artwork it is a state marker beside
  /// the source badge, which is what it is.
  static const double watchedIconSize = 17;
  static const double watchedBadgePadding = 4;

  /// Ink ladder, as alphas on `MonoTokens.text` — the same three tiers and the
  /// same reasoning as [TvSourcePickerLayout]'s, so a card and a source row
  /// read as one design system rather than two.
  static const double inkPrimary = 1;
  static const double inkSecondary = 0.62;

  /// Fill and outline of a header action capsule, as alphas on
  /// `MonoTokens.text` over the page background.
  ///
  /// Deliberately faint. Hoofdstuk 10.2 wants the page title to own the header
  /// and the three actions to sit under it, and the first build had them at the
  /// card footer's old fill — which, once the grid behind them carried real
  /// artwork, read as three solid buttons competing with a one-word title.
  static const double actionFill = 0.035;
  static const double cardOutline = 0.06;

  /// Fill of the badge capsule, as an alpha on black over the artwork.
  ///
  /// Black rather than a theme colour: it sits on a poster, not on a surface,
  /// and hoofdstuk 10.3 asks for "kleine donkere/transparante capsule".
  ///
  /// **The number is a contrast floor, not a taste.** It came down from 0.62
  /// once the goldens carried real colour — against grey placeholders an
  /// almost-opaque capsule looked like part of the design, and against a pastel
  /// poster it looked like a debug label stuck onto the artwork. But it can
  /// only come down so far: the label is 10.5px semibold, which is small text
  /// by WCAG, so it needs 4.5:1. Measured off the brightest poster in the
  /// golden set (a near-white pastel, RGB 228/235/255 under the capsule), 0.46
  /// gives 4.00:1 and fails; 0.50 gives 4.55:1 and is the actual floor. This
  /// sits one step above it, at 5.4:1, so a poster brighter than anything in
  /// the fixture set still has somewhere to go before the badge stops being
  /// readable.
  static const double badgeFill = 0.55;

  /// The placeholder behind artwork that has not loaded, and behind a source
  /// with no poster at all.
  static const double artworkPlaceholderFill = 0.06;
}

/// A resolved Films/Series grid: how many columns fit, and how wide a card is.
///
/// Hoofdstuk 10.2 asks for "6–7 kolommen afhankelijk van dichtheid", which is a
/// *result*, not an input: it is what a 2:3 poster at a readable 10-foot size
/// works out to inside the safe area on the canonical canvas. Deriving it from
/// the live width instead of hardcoding it is what keeps that true on a 720p
/// output, in a simulator window and in the golden harness — and what stops a
/// hardcoded 6 from producing 40 logical pixels of poster on a narrow surface.
class TvCatalogGrid {
  const TvCatalogGrid({
    required this.columns,
    required this.cardWidth,
    required this.gutter,
    required this.inset,
    required this.bottomSafeMargin,
  });

  final int columns;
  final double cardWidth;
  final double gutter;
  final double inset;

  /// The overscan margin under the last row, so nothing the user needs to read
  /// ends up in the band at the bottom edge.
  ///
  /// It converts like every other box measurement here, as a fraction of the
  /// viewport: on a 16:9 surface `x/1080` of the height is exactly `x/1920` of
  /// the width, so the vertical margin falls out of the same reference the
  /// horizontal one uses. It reads [TvCatalogLayout.bottomSafeInset], not
  /// `topSafeInset`: see there for why the two edges no longer share one
  /// number.
  ///
  /// The room a focused card needs on top of this is *not* in here. See
  /// [scrollPadding], and CAT1 for what it costs to fold the two together.
  final double bottomSafeMargin;

  /// The padding a scrolling grid of cards [cardHeight] tall pays on all four
  /// sides.
  ///
  /// Focus enlarges a card about its centre, so half the added height reaches
  /// past its top edge and half past its bottom one. Inside the grid that
  /// overhang lands in a gutter and nobody sees it; at the first and the last
  /// row there is no gutter, only the edge of the scroll viewport, which clips.
  /// So both ends reserve the growth, and the bottom reserves the overscan
  /// margin as well.
  ///
  /// **The caller states the card it draws.** The first version of this derived
  /// the growth here, from `cardWidth / posterAspectRatio`, which is the height
  /// of a poster as wide as the whole card. That is not the box focus scales: the
  /// real poster is narrower (it sits inside two [TvCatalogLayout.cardContentInset]s)
  /// and the real card is taller (the title and meta line hang below it). On
  /// the canonical canvas it reserved 6.885 logical pixels where the card needs
  /// 8.282, and the 1.4 that were missing are wider than the ring itself: the
  /// top row's focus ring was cut off flat against the header, corners and all,
  /// on every column at once. Two surfaces draw different cards through this
  /// same grid, the catalog's `TvUnifiedMediaCard` and the watchlist's
  /// `WatchlistCard`, at two different focus scales, so a number computed here
  /// could only ever be right for one of them.
  EdgeInsets scrollPadding({required double cardHeight, required double focusScale}) {
    final growth = cardHeight * (focusScale - 1) / 2;
    return EdgeInsets.fromLTRB(inset, growth, inset, bottomSafeMargin + growth);
  }

  /// Ideal card width on the 1920-wide reference surface, expressed as a
  /// fraction so it converts like every other box measurement in this file
  /// (see `overlay_sheet_geometry.dart`'s TV panel section for the same rule).
  ///
  /// It is derived, not chosen: 1920 minus two 72px safe insets is 1776, and
  /// six columns with five 26px gutters divide that into 274px cards. Six
  /// rather than seven because hoofdstuk 10.2's band is 6–7 "afhankelijk van
  /// dichtheid", and on a 2:3 poster the wider end is what keeps a card title
  /// readable from three metres — the whole reason the band has a bottom.
  static const double _referenceCardWidth = 281;
  static const double _referenceGutter = 22;

  /// The page's own side margin, in reference pixels, rather than
  /// [TvLayoutConstants.horizontalInset].
  ///
  /// 72 is the shared TV inset and it stays that for every other surface; a
  /// panel or a source row is content in the middle of the screen and can
  /// afford it. A wall of posters cannot: sixteen reference pixels a side is
  /// most of a gutter, and on this page it was margin bought at the posters'
  /// expense. 56 is hoofdstuk 8.1's actual floor — "geen tekst of focusring
  /// binnen de buitenste 56 pixels" — so this spends the slack the shared
  /// constant was holding in reserve, and spends it on artwork.
  static const double _referenceInset = 56;
  static const double _referenceWidth = 1920;

  /// Hard bounds on the result. Six and seven are the contract's band; the
  /// clamp exists for surfaces the contract does not describe, where honouring
  /// the band literally would be worse than leaving it (a 640-wide window
  /// cannot show six readable posters, and pretending otherwise renders six
  /// unreadable ones).
  static const int minColumns = 3;
  static const int maxColumns = 8;

  /// Resolves the grid for a viewport [width].
  ///
  /// **The insets and gutters are viewport fractions, not `scale` multiples.**
  /// This file's own header states the rule — box composition is a proportion
  /// of the viewport, type and density go through the clamped
  /// [TvLayoutConstants.scaleOf] — and getting it wrong here is expensive:
  /// `72 * 0.85` is 61 logical pixels, which on the canonical canvas is 113
  /// *reference* pixels, half again as wide as hoofdstuk 8.1's margin. That
  /// wider margin is what pushed the first render down to six cramped columns
  /// with the page's whole left edge in the wrong place.
  ///
  /// [scale] is still taken, because a caller resolving a grid has one and the
  /// card *content* inside it needs it; it deliberately does not enter the box
  /// arithmetic.
  factory TvCatalogGrid.forWidth(double width, {required double scale}) {
    final inset = width * (_referenceInset / _referenceWidth);
    final gutter = width * (_referenceGutter / _referenceWidth);
    final available = math.max(0.0, width - inset * 2);
    final ideal = width * (_referenceCardWidth / _referenceWidth);

    // Round to the column count whose cards land closest to the ideal width,
    // rather than flooring: flooring biases every surface towards cards wider
    // than intended, and on the canonical canvas it is the difference between
    // six columns and five.
    final raw = ideal <= 0 ? minColumns : ((available + gutter) / (ideal + gutter)).round();
    final columns = raw.clamp(minColumns, maxColumns);
    final cardWidth = math.max(0.0, (available - gutter * (columns - 1)) / columns);
    return TvCatalogGrid(
      columns: columns,
      cardWidth: cardWidth,
      gutter: gutter,
      inset: inset,
      bottomSafeMargin: width * (TvCatalogLayout.bottomSafeInset / _referenceWidth),
    );
  }
}

/// Geometry of the fase-6 discovery landing (hoofdstuk 10.2a, DEC-064): the
/// row-based surface that sits *in front of* the catalog [TvCatalogLayout]
/// draws, and deliberately does not look like it.
///
/// The two live in one file because they are one design system seen from two
/// distances, and splitting them is how they drift. What separates them is a
/// single decision about what focus is allowed to do. In the catalog, focus
/// must not move anything: you are walking a wall of five hundred posters and
/// the wall has to hold still under you. On a discovery landing, focus *is*
/// the composition — the item you are standing on becomes a wide frame with its
/// own context, and its neighbours stay beside it, smaller.
///
/// ## Why one height and two widths
///
/// The expansion is expressed entirely in width. Every tile in a rail is
/// [cardHeight] tall whether it is focused or not; what changes is whether it is
/// [posterAspectRatio] wide (2:3) or [wideAspectRatio] wide (16:9). That is not
/// a styling preference, it is the fix for the failure fase 5 already paid for
/// once: a row whose height depends on which item holds the focus drags every
/// row beneath it up and down the screen while the user is trying to read them.
/// With the height fixed, the band is reserved at its maximum from the first
/// frame, neighbours slide horizontally, and nothing below the rail moves at
/// all — see hoofdstuk 20 of the fase-6 brief and [railBandHeight].
///
/// The metadata block under a rail is reserved the same way and for the same
/// reason: it is [metaBlockHeight] tall whether anything is focused or not, so
/// a title with a two-line synopsis and a title with none occupy identical
/// space and the rail below never shifts.
class TvDiscoveryLayout {
  const TvDiscoveryLayout._();

  /// Page heading. Deliberately *not* [TvCatalogLayout.pageTitleFontSize] any
  /// more: the two started shared, on the argument that "Films" is the same
  /// word at both levels, but the visual gate against the Netflix TV reference
  /// showed the landing needs a heading that owns a much larger composition —
  /// one dominant rail instead of a wall of posters. 30 renders at 25.5
  /// logical on the canonical canvas (~47 reference px); the catalog keeps its
  /// own 27, and the one-size step on the way into Alles bekijken is the
  /// honest price of the landing reading as a stage rather than an index.
  static const double pageTitleFontSize = 30;

  /// Left/right page inset. Wider than the catalog's, because a rail runs off
  /// the right edge by design and needs a visible margin to run off *from*.
  static const double pageInset = 48;

  /// Gap between the page heading and the first rail's own heading.
  static const double titleRailGap = 22;

  /// A rail's own heading — hoofdstuk 8.3's section title band. Under the page
  /// title and above the content it names, so it has to be clearly subordinate
  /// to the first and clearly dominant over the second.
  ///
  /// 17 renders at 27 reference px, inside hoofdstuk 8.3's 25–28 band for a
  /// rail heading; 20 rendered at 31.5 (styling audit, divergentie 6).
  static const double sectionTitleFontSize = 17;
  static const double sectionHeaderGap = 12;

  /// Tile height, constant across focused and unfocused (see the class comment).
  ///
  /// The number is the whole difference between a discovery rail and a bigger
  /// catalog row, so it is worth stating what it buys on the canonical
  /// 1038×584 canvas (scale 0.85, usable rail width 964.9 — see
  /// [railUsableWidth]). At rest a tile occupies [posterWidth] plus its two
  /// focus-ring gaps, and the pitch between two tiles adds [itemGap]:
  ///
  /// | cardHeight | poster | wide | at rest | beside the focused tile |
  /// |---|---|---|---|---|
  /// | 270 | 153.0 | 408.0 | 5 full + 89 px | 3 full, focused 42.3% |
  /// | 240 | 136.0 | 362.7 | 6 full + 16 px | 3 full, focused 37.6% |
  /// | **220** | **124.7** | **332.4** | **6 full + 84 px** | **4 full, focused 34.5%** |
  /// | 200 | 113.3 | 302.2 | 7 full + 17 px | 4 full, focused 31.3% |
  ///
  /// 220 is the value DEC-087 fixes, and it supersedes 33.2's absolute band
  /// numbers and 33.3's "focused 16:9 ≈ 40%, three neighbours". The reasoning
  /// is that both halves of the density requirement have to hold at once: six
  /// full tiles at rest *with* a visibly partial seventh, so the row reads as
  /// running off the page rather than as ending, and four full neighbours
  /// beside the focused tile, so the expansion is a change of emphasis rather
  /// than a takeover of the row. 270 met neither (five at rest, three
  /// neighbours, and the focused frame taking 42% of the band); 200 met the
  /// second at the cost of a seventh full tile at rest, which is the catalog
  /// grid impression this surface exists to avoid.
  ///
  /// The knock-on is deliberate: one rail drops from 374.8 to ≈332 logical
  /// pixels, 57% of the canonical canvas instead of 64%, which is the vertical
  /// room [TvCatalogGrid.bottomSafeInset] and the hero return path both needed.
  static const double cardHeight = 220;
  static const double posterAspectRatio = 2 / 3;
  static const double wideAspectRatio = 16 / 9;
  static const double cardRadius = 10;
  static const double itemGap = 16;

  /// Band of page background between a tile's artwork and its focus ring, for
  /// the reason [TvCatalogLayout.cardFocusRingGap] spells out: a 2.5px white
  /// ring laid straight onto bright artwork has nothing to contrast with, and
  /// stops reading at three metres on exactly the tiles that catch the eye.
  static const double cardFocusRingGap = 5;

  /// Brightness lift on the focused tile's artwork. Small on purpose, and
  /// smaller than the catalog's: at discovery scale the artwork *is* the
  /// composition, and at 0.14 the lift read as a white wash over exactly the
  /// picture the user is choosing by. Focus is carried by the geometry
  /// expansion, the white ring, and the shadow; this is only the faintest
  /// confirmation that the light follows the remote.
  static const double cardFocusArtworkLift = 0.05;

  /// What an *unfocused* neighbour's artwork is dimmed by. Small: neighbours
  /// must stay visible (hoofdstuk 19), so this is a recession, not a curtain —
  /// and at 0.18 it was becoming one, a spotlight where only the focused
  /// artwork still lived. The neighbours are colourful content, not backdrop.
  static const double neighbourDim = 0.10;

  /// The new-content marker on a TV card: an amber dot of 12 reference px
  /// (hoofdstuk 34, 33.6; DEC-095 (6)), never the text pill.
  static const double newDotSize = 8;

  static const double cardShadowBlur = 14;
  static const double cardShadowOffsetY = 5;
  static const double cardShadowAlpha = 0.38;
  static const double cardFocusShadowBlur = 38;
  static const double cardFocusShadowOffsetY = 10;
  static const double cardFocusShadowAlpha = 0.5;

  /// The focused item's context block, under the rail (hoofdstuk 10.2a's own
  /// sketch puts it there rather than over the artwork). Three tiers: title,
  /// one meta line, up to two lines of synopsis.
  ///
  /// Sized against the ~408-wide focused frame above it, not against the old
  /// compact band: a 16px title under a frame that large read as a caption.
  /// Rendered on the canonical canvas these come to ~20 / 13.6 / 12.3 logical
  /// — readable from a sofa, still clearly three tiers.
  ///
  /// DEC-095 (5), mockup 30 B/C: title 27, meta 20 and one line of synopsis
  /// at 19 reference px, 18 above the title and 26 to the next rail's label.
  /// One line of synopsis rather than DEC-087's two is what lets the next rail
  /// stand wholly under the focused one instead of only its label.
  static const double metaTitleFontSize = 17;
  static const double metaContextFontSize = 13;
  static const double metaSynopsisFontSize = 12;
  static const double metaLineHeight = 1.3;
  static const int metaSynopsisMaxLines = 1;
  static const double railMetaGap = 4;
  static const double metaLineGap = 3;

  /// Reserved height of that block, computed rather than guessed so a font-size
  /// change cannot silently start moving the rail below it.
  static double metaBlockHeight(double scale) =>
      (metaTitleFontSize * metaLineHeight +
          metaLineGap +
          metaContextFontSize * metaLineHeight +
          metaLineGap +
          metaSynopsisFontSize * metaLineHeight * metaSynopsisMaxLines) *
      scale;

  /// Height of the tile band alone — the tallest a tile can draw, focus ring
  /// and its gap included, so an expanded tile never overflows the band it was
  /// given and never asks the column to re-measure.
  /// Page ground between the band's edge and a tile's artwork: the ring gap
  /// plus the ring itself, on each side.
  static double railBandInset(double scale) => cardFocusRingGap * scale + FocusTheme.focusBorderWidth;

  static double railBandHeight(double scale) => cardHeight * scale + railBandInset(scale) * 2;

  /// Full vertical extent of one rail: heading, tiles, and the context block.
  /// Constant by construction — nothing in it depends on where focus is.
  static double railSectionHeight(double scale) =>
      sectionTitleFontSize * metaLineHeight * scale +
      sectionHeaderGap * scale +
      railBandHeight(scale) +
      railMetaGap * scale +
      metaBlockHeight(scale);

  static double posterWidth(double scale) => cardHeight * scale * posterAspectRatio;
  static double wideWidth(double scale) => cardHeight * scale * wideAspectRatio;

  /// The box a tile actually lays out: its artwork plus the focus-ring gap on
  /// both sides, which `TvExpandableMediaTile` pads itself by.
  ///
  /// Density, the rail's scroll arithmetic and the layout test all have to
  /// agree on this, and before DEC-087 each of them re-derived it from
  /// [posterWidth] and [cardFocusRingGap] by hand.
  static double tileWidth(double scale, {required bool focused}) =>
      (focused ? wideWidth(scale) : posterWidth(scale)) + cardFocusRingGap * scale * 2;

  /// Distance from one resting tile's left edge to the next one's.
  static double railPitch(double scale) => tileWidth(scale, focused: false) + itemGap * scale;

  /// The rail list's own leading inset: the page inset minus the gap the tile
  /// pads itself by, so the first tile's *artwork* lines up with the heading
  /// above it rather than sitting a ring-gap further right.
  static double railLeadInset(double scale) => math.max(0.0, pageInset * scale - cardFocusRingGap * scale);

  /// What a tile grows by when it takes the focus, and therefore the room the
  /// band has to hold in reserve past its last tile (LAND3).
  ///
  /// A tile expands inside the scrollable, so focusing one *grows the content*,
  /// and that growth arrives over the focus animation: several frames after the
  /// reveal has already decided where to scroll to. Without this reserve the
  /// band's `maxScrollExtent` at that moment is the resting content, which is
  /// short by exactly this much, and the clamp cuts the reveal off at the one
  /// tile that needs the whole of it: the last one.
  ///
  /// The reserve is unconditional rather than added when the last tile takes
  /// the focus, because a scroll extent that changes with focus is the same
  /// timing dependency in a different place.
  static double railFocusHeadroom(double scale) => tileWidth(scale, focused: true) - tileWidth(scale, focused: false);

  /// Width a rail has for tiles on a viewport [width].
  static double railUsableWidth(double width, double scale) => math.max(0.0, width - railLeadInset(scale) * 2);

  /// How many tiles [usableWidth] shows in full, laid out at rest.
  ///
  /// The last tile carries no trailing gap, so the run of `n` tiles is
  /// `(n - 1) * railPitch + tileWidth`. Used by the density test and by
  /// nothing in production — the rail itself never counts tiles, it scrolls.
  @visibleForTesting
  static int fullTilesAtRest(double usableWidth, double scale) {
    final pitch = railPitch(scale);
    final tile = tileWidth(scale, focused: false);
    if (pitch <= 0 || usableWidth < tile) return 0;
    return 1 + ((usableWidth - tile) / pitch).floor();
  }

  /// The "Alle films ▸ Alles bekijken" section action that closes a landing
  /// (hoofdstuk 10.2a, DEC-064 punt 3). A full-width row rather than a text
  /// link: it is a first-class route, and a remote has to be able to land on it
  /// without aiming.
  ///
  /// Low-chrome on purpose. The first build gave the idle row a fill and an
  /// outline, and against the Netflix reference it read as a settings row —
  /// a form control parked under the content. Idle it is now just type on the
  /// page, sized like a section heading with its action beside it; the fill
  /// appears only under focus, where the white ring already says where you
  /// are. Reachability is untouched: still full-width, still one DOWN from
  /// the last rail.
  static const double viewAllRadius = 10;
  static const double viewAllPaddingHorizontal = 12;
  static const double viewAllPaddingVertical = 6;

  /// Half the page title's size, near enough. The gap is what makes the two
  /// read as heading and sibling action rather than as two headings — at 20
  /// against the title's 30 they competed, and the band started looking like
  /// a toolbar.
  static const double viewAllActionFontSize = 16;
  static const double viewAllIconSize = 18;
  static const double viewAllIconGap = 4;
  static const double viewAllFocusRingGap = 4;
  static const double viewAllFill = 0;
  static const double viewAllFocusedFill = 0.08;

  /// How far up from the bottom edge the page fades out (hoofdstuk 33.3).
  ///
  /// The next row's posters are meant to peek, and a peek that is chopped off
  /// square reads as a rendering bug rather than as "there is more below".
  /// Short enough that it only ever touches the strip already half out of
  /// view — a longer fade starts dimming content the viewer is reading.
  static const double pageBottomFade = 26;

  /// Space between the page title and the action beside it.
  ///
  /// Two failure modes to stay between, and both are visible at a glance:
  /// too little and the action reads as part of the heading ("FilmsAlle
  /// films"), too much and it drifts to the page edge, which is the
  /// right-aligned variant DEC-068 rejected — it costs horizontal remote
  /// travel for no gain. This is a fixed gap, not a `Spacer`, precisely so a
  /// long locale moves the action a little further out instead of parking it
  /// against the margin.
  static const double pageTitleActionGap = 28;

  /// Vertical gap between two rails, and between the last rail and the
  /// view-all row.
  static const double sectionGap = 17;

  /// Progress bar on a tile that has an active resume position.
  static const double progressBarHeight = 5;
  static const double progressTrackAlpha = 0.22;

  /// The multi-source capsule (hoofdstuk 10.3), same language as the catalog
  /// card's so one badge means one thing across both levels.
  static const double badgeInset = 7;

  /// Ink alphas on `MonoTokens.text` for the context block's three tiers.
  static const double inkPrimary = 1;
  static const double inkSecondary = 0.7;
  static const double inkTertiary = 0.56;
}

/// The TV root shell's top navigation (fase 7, hoofdstuk 6.2 and the shared
/// shell of hoofdstuk 33).
///
/// Reference measurements come from the frozen north star: the bar sits at
/// y≈44..96 on a 1920×1080 surface, the labelled items are 24px Inter 500 with
/// a 40px gap, the search glyph is 26, the profile chip 44, and the wordmark
/// lockup stands on the same 52px band. Base values below are pre-divided by
/// the `[0.85, 1.35]` clamp exactly as [TvCatalogLayout]'s are, so
/// `base * TvLayoutConstants.scaleOf(context)` lands back on the reference
/// number on the canonical canvas.
class TvTopNavLayout {
  const TvTopNavLayout._();

  /// Space above the bar. The same overscan reasoning as
  /// [TvCatalogLayout.topSafeInset]: nothing, focus ring included, inside the
  /// outer band.
  static const double topInset = 28;

  /// Height of the bar's row. The pill, the glyph and the wordmark all centre
  /// on it, so it is what keeps them on one optical line.
  ///
  /// A *minimum*, not a fixed height — see [TvTopNavigation]. A locale with
  /// taller metrics must push the bar down rather than have its labels cut off
  /// at the top edge, which is what a hard `SizedBox` did.
  static const double barHeight = 33;

  /// Gap below the bar, before a destination's own content starts.
  static const double contentGap = 22;

  /// Left/right page inset, shared with [TvDiscoveryLayout.pageInset] so the
  /// profile chip and the wordmark line up with the content beneath them
  /// instead of floating on their own margin.
  static const double pageInset = 48;

  /// A labelled destination.
  static const double itemFontSize = 15;
  static const double itemGap = 25;

  /// The active pill. A capsule, so the radius is deliberately unbounded
  /// rather than a number that would need re-tuning with the height.
  ///
  /// The vertical padding is derived, not chosen: the north star draws a 42px
  /// pill inside a 52px band on the 1920 reference, which is 27 and 33 here.
  /// A 15px label sets about 18 tall, so (27 − 18) / 2 leaves 4.5 either side,
  /// and the remaining 6 is the focus-ring gap top and bottom. Rounding this up
  /// is what made the first render clip its own pills against [barHeight].
  static const double pillPaddingHorizontal = 17;
  static const double pillPaddingVertical = 4.5;
  static const double pillRadius = 999;

  /// Gap between a destination's own box and its focus ring, for the reason
  /// [TvCatalogLayout.actionFocusRingGap] exists: a white ring drawn straight
  /// onto the white active pill reads as a slightly fatter pill, not as focus.
  /// This gap is what keeps "where I am" and "what is open" tellable apart
  /// ([DEC-053]).
  static const double focusRingGap = 3;

  /// The compact Search control.
  static const double searchIconSize = 17;

  /// Hoofdstuk 18.4's "klein statuspunt bij Mijn Pleya".
  ///
  /// Drawn as an overlay on the destination, never as another child in the
  /// row: an extra box would move every destination beside it the moment a
  /// server's token expired, and hoofdstuk 7.2's whole point about the bar is
  /// that it does not move under the remote. Sized against the label rather
  /// than the pill so it reads as a mark on the word, not as a second control.
  static const double attentionDotSize = 7;

  /// How far the dot's centre sits above and right of the pill's own corner.
  /// Outside the pill, so the active state's white fill never swallows it.
  static const double attentionDotInset = 1;

  /// The profile chip at the far left.
  static const double profileChipSize = 28;

  /// The wordmark lockup at the far right. Sized by height; the asset's own
  /// aspect ratio gives the width, because hoofdstuk 33 forbids a clipped or
  /// re-proportioned mark.
  ///
  /// Hoofdstuk 33 puts it "op navhoogte 52", so this is [barHeight] and not a
  /// separately chosen number. An earlier 23 rendered the lockup about thirty
  /// per cent narrower than the reference against an otherwise correctly
  /// proportioned bar.
  static const double wordmarkHeight = barHeight;

  /// Ink on `MonoTokens.text` for an inactive destination — present, readable
  /// at three metres, and clearly quieter than the active pill. Hoofdstuk 33:
  /// "inactive destinations = rustige white/muted text".
  static const double inactiveInk = 0.72;

  /// Focus transition duration (hoofdstuk 8.4: "Topnav-focus 150–180 ms").
  /// The bar under an open overlay (audit divergentie 13, mockup 30 E).
  static const double dimmedOpacity = 0.35;

  static const Duration focusDuration = Duration(milliseconds: 160);
}

/// Mijn Pleya on TV (hoofdstuk 18.1 and north star 08).
class TvMyPleyaLayout {
  const TvMyPleyaLayout._();

  /// Page heading, matching [TvCatalogLayout.pageTitleFontSize]'s band so the
  /// three root surfaces introduce themselves at the same weight.
  static const double pageTitleFontSize = 27;

  /// Gap under the page heading, and between the groups below it.
  static const double titleGap = 16;
  static const double groupGap = 18;

  /// The profile header card.
  static const double headerRadius = 12;
  static const double headerPadding = 18;
  static const double avatarSize = 46;
  static const double headerNameFontSize = 22;
  static const double headerMetaFontSize = 13;
  static const double headerGap = 16;

  /// The server list on the header's right-hand side.
  static const double serverRowFontSize = 13;
  static const double serverRowGap = 6;
  static const double serverDotSize = 6;

  /// A group heading ("Mijn content", "Bibliotheken en bronnen", "Pleya").
  static const double groupLabelFontSize = 14;
  static const double groupLabelGap = 9;

  /// A menu tile. Four to a row on the reference width, and the tile keeps its
  /// height whether or not it carries a count, so a group with one counted tile
  /// does not sit taller than its neighbours.
  static const int tilesPerRow = 4;
  static const double tileGap = 14;
  static const double tileRadius = 10;
  static const double tilePadding = 14;
  static const double tileMinHeight = 74;
  static const double tileIconSize = 19;
  static const double tileTitleFontSize = 15;
  static const double tileSubtitleFontSize = 12;
  static const double tileCountFontSize = 15;
  static const double tileIconTitleGap = 14;
  static const double tileTitleSubtitleGap = 3;

  /// Fill of a tile at rest, and when it holds the focus.
  ///
  /// **Menu tiles do not scale on focus** (hoofdstuk 33.8): a wall of twelve
  /// boxes where one grows pushes nothing but still reads as unstable, and the
  /// ring plus the lighter fill already say where you are. That is the
  /// difference between this surface and a poster grid, where the scale is the
  /// point.
  static const double tileFillAlpha = 0.055;
  static const double tileFocusedFillAlpha = 0.13;

  /// Gap between a tile and its focus ring.
  static const double tileFocusRingGap = 3;

  /// The footer line ("Aangemeld als … · Pleya x.y.z").
  static const double footerFontSize = 12;
  static const double footerGap = 18;

  /// Ink tiers on `MonoTokens.text`.
  static const double inkPrimary = 1;
  static const double inkSecondary = 0.7;
  static const double inkTertiary = 0.5;
}

/// Home tokens: the full-bleed hero and where the rails sit under it
/// (hoofdstuk 9.1/9.2 as revised by [DEC-095], mockup 30 A1/B/C in
/// `docs/assets/tvos-unified/mockups-2026-09-04/`).
///
/// **The hero is the page, not a card on it.** The fase-8 billboard was a
/// 1770×718 rounded card on a 75px inset (33.1, "nooit full bleed"); on a 16:9
/// backdrop that card showed 72% of the picture, and HERO1 could only decide
/// *which* 72%. DEC-095 replaces the card: the backdrop is 16:9 across the
/// whole screen, behind the top navigation and the text, and the first rail
/// peeks under it. Every number below is read off mockup 30 A1 on the
/// 1920×1080 reference and divided by 1.57 (DEC-028's reference-to-token
/// conversion on the canonical 1038×584 canvas at scale 0.85).
///
/// Rows below the hero are [TvDiscoveryLayout]'s, unchanged and deliberately:
/// 33.2 draws Home's focused row with exactly the composition 33.3 draws on the
/// Films landing — one expanded 16:9 frame, 2:3 neighbours, one metadata block
/// underneath — so a second set of row constants would be two names for one
/// picture, drifting apart on their first correction.
class TvHomeLayout {
  const TvHomeLayout._();

  /// Where a backdrop that does not share the screen's ratio is anchored when
  /// it is cover-cropped into it. On a 16:9 source at full-bleed there is no
  /// crop at all and this value is idle; for any other ratio it is the one
  /// owner of the cut (DEC-094): `-0.3` keeps the upper 35% intact and takes
  /// the rest from both ends, the anchor the mockup family draws as
  /// `object-position: 50% 35%`. HERO1.
  static const Alignment heroArtAlignment = Alignment(0, -0.3);

  /// How much of the first rail's artwork is on screen on the landing: 147
  /// reference px of the 346 band (mockup 30 A1, "de rail piept"). The subject
  /// of the backdrop stays whole above it; the rail becomes fully visible on
  /// DOWN, when the feed scrolls to [rowFocusAnchor].
  static const double firstRailPeek = 94;

  /// From the bottom of the CTA row to the label of the first rail: 40
  /// reference px.
  static const double heroTextRailGap = 26;

  /// Where the label of the focused *first* rail lands, measured from the top
  /// of the content box, once DOWN has scrolled the feed: 372 reference px on
  /// screen (northstar 02), 242 inside the content box. The dimmed backdrop
  /// stays visible above it. Deeper rails anchor at 0, under the top
  /// navigation, so the rail below them is wholly on screen (mockup 30 C).
  static const double rowFocusAnchor = 154;

  /// The hero block: everything the landing shows above the first rail's
  /// label. Derived rather than fixed so the peek is exactly [firstRailPeek]
  /// on any viewport — the tokens for the label line, the header gap and the
  /// band's ring inset are the rail's own.
  static double heroBlockHeight(double viewportHeight, double scale) => math.max(
    0.0,
    viewportHeight -
        TvDiscoveryLayout.sectionTitleFontSize * TvDiscoveryLayout.metaLineHeight * scale -
        TvDiscoveryLayout.sectionHeaderGap * scale -
        TvDiscoveryLayout.railBandInset(scale) -
        firstRailPeek * scale,
  );

  /// The vertical scroll target for a tile in row [index] of the Home feed,
  /// as the fraction of the viewport its centre is scrolled to
  /// (`FocusableWrapper.scrollAlignment`). Row 0 anchors its label at
  /// [rowFocusAnchor]; every deeper row anchors its label at the top of the
  /// content box. Expressed as a fraction because that is the wrapper's
  /// contract; computed from the same tokens the rail is laid out with, so
  /// the anchor is exact on any canvas rather than tuned to one.
  static double rowTileScrollAlignment(int index, double viewportHeight, double scale) {
    if (viewportHeight <= 0) return 0.5;
    final labelToTileCentre =
        (TvDiscoveryLayout.sectionTitleFontSize * TvDiscoveryLayout.metaLineHeight +
                TvDiscoveryLayout.sectionHeaderGap) *
            scale +
        TvDiscoveryLayout.railBandHeight(scale) / 2;
    final anchor = index == 0 ? rowFocusAnchor * scale : 0.0;
    return ((anchor + labelToTileCentre) / viewportHeight).clamp(0.0, 1.0);
  }

  /// Cap on the text column: 900 reference px (hoofdstuk 9.2 as revised).
  /// Wide enough for two lines of synopsis at hero size, narrow enough that
  /// the artwork's subject keeps the right half of the screen.
  static const double heroTextMaxWidth = 573;

  /// Title, meta line, synopsis. Sized against the screen rather than against
  /// a rail: this is the one element on Home that is read first and from
  /// furthest away.
  static const double heroTitleFontSize = 40;
  static const double heroTitleLetterSpacing = 1.2;
  static const int heroTitleMaxLines = 2;
  static const double heroMetaFontSize = 16.5;
  static const double heroSynopsisFontSize = 16;
  static const int heroSynopsisMaxLines = 2;
  static const double heroLineHeight = 1.28;
  static const double heroTitleMetaGap = 10;
  static const double heroMetaSynopsisGap = 8;
  static const double heroSynopsisActionsGap = 20;

  /// The clearlogo box, when the title has one (hoofdstuk 9.4). Height-bounded
  /// so a wide wordmark and a tall stacked mark occupy the same band and the
  /// metadata line under them never moves.
  static const double heroLogoMaxHeight = 76;

  /// The band the title block occupies, type or clearlogo: the *larger* of
  /// the two things that live in it, which is a two-line title (HERO2).
  static const double heroTitleBandHeight = heroTitleFontSize * heroLineHeight * heroTitleMaxLines;
  static const double heroLogoMaxWidth = heroTextMaxWidth;

  static const double heroActionHeight = 40;
  static const double heroActionRadius = 20;
  static const double heroActionPaddingHorizontal = 20;
  static const double heroActionGap = 3;
  static const double heroActionFontSize = 16;
  static const double heroActionIconSize = 19;
  static const double heroActionIconLabelGap = 8;

  static const double heroActionFocusRingGap = 4;

  static const double heroSecondaryFillAlpha = 0.26;

  /// The reading scrim: a left-to-right ramp over the full height, so the text
  /// column and the profile chip above it both read against it (mockup 30 A1,
  /// `linear-gradient(90deg, .92 0%, .70 28%, .12 56%, 0 100%)`).
  static const List<double> heroScrimReadingStops = [0, 0.28, 0.56, 1];
  static const List<double> heroScrimReadingAlphas = [0.92, 0.70, 0.12, 0];

  /// The vertical scrim: a wash under the top navigation, clear across the
  /// subject, then down to the page ground before the first rail's posters,
  /// so they stand on the ground and not on the picture.
  static const List<double> heroScrimVerticalStops = [0, 0.18, 0.52, 0.78, 0.96];
  static const List<double> heroScrimVerticalAlphas = [0.66, 0, 0, 0.70, 1];

  /// Once a row holds the focus the backdrop steps back (mockup 30 B): a veil
  /// at [heroDimAlpha] over the whole picture, and a steeper vertical scrim
  /// that reaches the page ground at 40% so the focused band sits on ground.
  static const double heroDimAlpha = 0.66;
  static const List<double> heroDimScrimStops = [0, 0.12, 0.26, 0.40];
  static const List<double> heroDimScrimAlphas = [0.72, 0.20, 0.45, 1];

  /// Hoofdstuk 9.4's poster-only fallback under full-bleed (mockup 30 D): the
  /// sharp poster as an island of 600 reference px high, its top at 150 and
  /// its right edge 220 in from the screen's, over the same poster blurred
  /// and darkened as the fill.
  static const double heroPosterIslandHeightFraction = 600 / 1080;
  static const Alignment heroPosterIslandAlignment = Alignment(0.71, -0.375);

  /// Under the last row, so the feed can still scroll it to its anchor.
  static const double heroRowGap = 26;

  static const Duration heroCrossfade = Duration(milliseconds: 460);

  static const Duration heroAutoAdvance = Duration(seconds: 8);

  static const Duration heroSegmentIndicatorHold = Duration(seconds: 2);
  static const double heroSegmentIndicatorWidth = 18;
  static const double heroSegmentIndicatorHeight = 3;
  static const double heroSegmentIndicatorGap = 6;
  static const double heroSegmentIndicatorIdleAlpha = 0.34;

  static const double inkPrimary = 1;
  static const double inkSecondary = 0.78;
  static const double inkTertiary = 0.62;
}
