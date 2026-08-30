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

  /// Title and context line inside the footer. 14 renders at ~11.9 logical,
  /// ~22 reference px — inside hoofdstuk 8.3's "card title 18–21" at the top,
  /// which is where a two-line title still reads at three metres.
  static const double cardTitleFontSize = 14;

  /// Line height of a card title, and the multiplier that reserves two lines of
  /// it whether the title needs both or not — see the card's own comment.
  static const double cardTitleLineHeight = 1.2;
  static const double cardMetaFontSize = 11.5;

  /// The meta block under the artwork.
  ///
  /// No horizontal padding, because there is no longer a box to pad inside of:
  /// the title starts on the poster's own left edge, which is what makes a
  /// column of cards line up as a column. The vertical value is the gap between
  /// the poster and its title.
  static const double cardFooterPaddingVertical = 8;
  static const double cardFooterLineGap = 3;

  /// Density of a panel option row — one line of text, sometimes two.
  ///
  /// Its own set rather than [TvSourcePickerLayout]'s row metrics: a source row
  /// carries server, library, quality and progress on three tiers and is sized
  /// for that, and inheriting it made the sort panel's seven fixed options
  /// overflow a panel they should never have needed to scroll. A list a remote
  /// has to walk is better when the whole list is on screen.
  static const double optionRowMinHeight = 38;
  static const double optionRowPaddingHorizontal = 16;
  static const double optionRowPaddingVertical = 8;
  static const double optionRowGap = 7;

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
  const TvCatalogGrid({required this.columns, required this.cardWidth, required this.gutter, required this.inset});

  final int columns;
  final double cardWidth;
  final double gutter;
  final double inset;

  /// Ideal card width on the 1920-wide reference surface, expressed as a
  /// fraction so it converts like every other box measurement in this file
  /// (see `overlay_sheet_geometry.dart`'s TV panel section for the same rule).
  ///
  /// It is derived, not chosen: 1920 minus two 72px safe insets is 1776, and
  /// six columns with five 26px gutters divide that into 274px cards. Six
  /// rather than seven because hoofdstuk 10.2's band is 6–7 "afhankelijk van
  /// dichtheid", and on a 2:3 poster the wider end is what keeps a card title
  /// readable from three metres — the whole reason the band has a bottom.
  static const double _referenceCardWidth = 274;
  static const double _referenceGutter = 26;
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
    final inset = width * (TvLayoutConstants.horizontalInset / _referenceWidth);
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
    return TvCatalogGrid(columns: columns, cardWidth: cardWidth, gutter: gutter, inset: inset);
  }
}
