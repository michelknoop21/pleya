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

  /// The meta block under the artwork.
  ///
  /// No horizontal padding, because there is no longer a box to pad inside of:
  /// the title starts on the poster's own left edge, which is what makes a
  /// column of cards line up as a column. The vertical value is the gap between
  /// the poster and its title.
  static const double cardFooterPaddingVertical = 6;
  static const double cardFooterLineGap = 3;

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
    required this.bottomSafeInset,
    required this.focusRingHeadroom,
  });

  final int columns;
  final double cardWidth;
  final double gutter;
  final double inset;

  /// Room under the last row, so nothing the user needs to read — or the focus
  /// ring — ends up in hoofdstuk 8.1's outer 56 reference pixels.
  ///
  /// Two parts. The safe margin itself converts like every other box
  /// measurement here, as a fraction of the viewport: on a 16:9 surface
  /// `56/1080` of the height is exactly `56/1920` of the width, so the vertical
  /// margin falls out of the same reference the horizontal one uses. On top of
  /// that comes the room a focused card needs to grow into, because
  /// [FocusTheme.fullCardFocusScale] enlarges it about its centre and the bottom
  /// row has nothing below it to grow into — and directional traversal scrolls
  /// with `keepVisibleAtEnd`, so without this the ring lands flush against the
  /// edge of the screen.
  final double bottomSafeInset;

  /// Room *above* the first row, for the half of a focused card's growth that
  /// goes upward.
  ///
  /// [bottomSafeInset] has carried the downward half since fase 5, and the
  /// upward half was simply missed: the grid's own top padding was zero, so
  /// row one — the row directional traversal lands on first — had its focus
  /// ring clipped flat against the top of the scroll viewport. The heading
  /// above already pays the hoofdstuk 8.1 safe margin, so this is only the
  /// focus growth, not the margin again.
  final double focusRingHeadroom;

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
    final cardHeight = cardWidth / TvCatalogLayout.posterAspectRatio;
    final focusGrowth = cardHeight * (FocusTheme.fullCardFocusScale - 1) / 2;
    return TvCatalogGrid(
      columns: columns,
      cardWidth: cardWidth,
      gutter: gutter,
      inset: inset,
      bottomSafeInset: width * (TvCatalogLayout.topSafeInset / _referenceWidth) + focusGrowth,
      focusRingHeadroom: focusGrowth,
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
  static const double sectionTitleFontSize = 20;
  static const double sectionHeaderGap = 12;

  /// Tile height, constant across focused and unfocused (see the class comment).
  ///
  /// The number is the whole difference between a discovery rail and a bigger
  /// catalog row, so it is worth stating what it buys on the canonical
  /// 1038×584 canvas (scale 0.85): 270 renders the tile band 229.5 tall, the
  /// focused 16:9 frame ~408 wide — about 40% of the usable content width —
  /// and a 2:3 neighbour ~153 wide, which leaves room for roughly *three*
  /// neighbours beside the focused item. That is the Netflix TV composition
  /// the reference screenshots show. The first build used 172, which put six
  /// neighbours on screen and made the landing read as a slightly larger
  /// catalog grid — the exact impression the phase exists to avoid.
  static const double cardHeight = 270;
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
  static const double metaTitleFontSize = 23.5;
  static const double metaContextFontSize = 16;
  static const double metaSynopsisFontSize = 14.5;
  static const double metaLineHeight = 1.3;
  static const int metaSynopsisMaxLines = 2;
  static const double railMetaGap = 16;
  static const double metaLineGap = 6;

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
  static double railBandHeight(double scale) =>
      cardHeight * scale + (cardFocusRingGap * scale + FocusTheme.focusBorderWidth) * 2;

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
  static const double sectionGap = 26;

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
