/// Geometry of Alle films and Alle series with nothing above the grid (A-06c):
/// six across, two whole rows, on the whole window.
///
/// [TvCatalogLayout] sizes a card as a poster inside a focus inset with a
/// two-line footer under it, and focus scales all of that. On the 584-high
/// Apple TV canvas that leaves two rows of 130 by 195. The compact card this
/// file sizes has no inset, a footer of one title line and one meta line, and
/// focus scales only the poster, so the same height carries a poster of 145 by
/// 217 (`tv_catalog_full_bleed_test.dart` measures it).
///
/// The height is the binding side: the poster follows from what two rows leave
/// over, and the spare width goes to the gutters rather than to the side
/// insets, which keeps the outer margins where they are on every other page.
library;

import 'dart:math' as math;

import '../../focus/focus_theme.dart';
import 'tv_unified_layout.dart';

class TvCatalogFullBleedLayout {
  const TvCatalogFullBleedLayout._();

  static const int columns = 6;
  static const int rows = 2;

  /// Apple's title-safe 60 of 1080, above the first row and under the last.
  /// A focused top row reaches into hoofdstuk 8.1's outer band with its ring.
  static const double verticalMarginFraction = 60 / 1080;

  /// The side inset of the broad grid, so the edge does not jump from the
  /// landing into the catalog.
  static const double sideInsetFraction = 72 / 1920;

  /// 10 of the canonical 584. Small, because the row gap is what is left after
  /// the poster: a focused ring ([focusedRingReach]) just fits inside it, and
  /// the grid clips one row gap outside its two rows, so nothing of the rows
  /// above and below stands in the margins.
  static const double rowGapFraction = 10 / 584;

  /// The footer, 37 logical on the canonical canvas (measured in the
  /// 2026-10-30 reference). Base units, like the rest of [TvCatalogLayout]'s
  /// type metrics: multiply by the ten-foot scale.
  static const double footerHeight = 37 / 0.85;

  /// Line heights of the two footer lines. Tighter than the wrapped card's
  /// 1.2: what these save is the gap between poster and title.
  static const double titleLineHeight = 1.15;
  static const double metaLineHeight = 1.15;

  /// Focus enlarges the poster and nothing else. 1.05 rather than the wrapped
  /// card's 1.06, because here a ring has only the row gap to grow into.
  static const double posterFocusScale = 1.05;

  /// Clear space between poster and ring, in base units.
  static const double ringGap = 2;

  /// How long the footer takes to make way, and how far past the ring it goes.
  static const Duration footerFocusDuration = Duration(milliseconds: 160);
  static const double _focusFooterClearance = 1.75;

  /// Space between poster and title at rest. The lines are rounded up because
  /// the engine rounds them up, as [TvCatalogLayout.cardHeight] documents.
  static double footerTopGap(double scale) {
    final title = (TvCatalogLayout.cardTitleFontSize * scale * titleLineHeight).ceilToDouble();
    final meta = (TvCatalogLayout.cardMetaFontSize * scale * metaLineHeight).ceilToDouble();
    return math.max(0, footerHeight * scale - title - meta);
  }

  /// How far the ring reaches past the poster's resting edge once focused.
  static double focusedRingReach(double posterHeight, double scale) =>
      posterHeight * (posterFocusScale - 1) / 2 + (FocusTheme.focusBorderWidth + ringGap * scale) * posterFocusScale;

  /// How far the footer moves down while its poster holds the focus, so the
  /// ring never lands on the title. Paint only: no row moves.
  static double focusedFooterShift(double posterHeight, double scale) =>
      math.max(0, focusedRingReach(posterHeight, scale) + _focusFooterClearance * scale - footerTopGap(scale));

  /// The card for a poster [cardWidth] wide. There is no inset, so the card and
  /// the poster are the same width.
  static double cardHeight(double cardWidth, double scale) =>
      cardWidth / TvCatalogLayout.posterAspectRatio + footerHeight * scale;

  /// The grid for a window [width] by [height].
  ///
  /// [density] is [tvCatalogDensityScale]: at 1 two rows fill the height, and
  /// below 1 the cards shrink with the gutters left as they are, so what comes
  /// free becomes margin on all four sides and the page stays six by two.
  static TvCatalogGrid grid({
    required double width,
    required double height,
    required double scale,
    double density = 1,
  }) {
    final footer = footerHeight * scale;
    final rowGap = height * rowGapFraction;
    final margin = height * verticalMarginFraction;
    final side = width * sideInsetFraction;

    final fullCardHeight = (height - margin * 2 - rowGap * (rows - 1)) / rows;
    final fullPosterHeight = math.max(0.0, fullCardHeight - footer);
    final available = math.max(0.0, width - side * 2);
    // On a window too narrow for the height-derived poster the width decides,
    // with one reference gutter between the columns.
    final minGutter = width * (22 / TvCatalogGrid.referenceWidth);
    final fullWidth = math.min(
      fullPosterHeight * TvCatalogLayout.posterAspectRatio,
      (available - minGutter * (columns - 1)) / columns,
    );
    final gutter = (available - fullWidth * columns) / (columns - 1);

    final cardWidth = fullWidth * density;
    final posterHeight = cardWidth / TvCatalogLayout.posterAspectRatio;
    final used = (posterHeight + footer) * rows + rowGap * (rows - 1);
    return TvCatalogGrid(
      columns: columns,
      cardWidth: cardWidth,
      gutter: gutter,
      rowGutter: rowGap,
      inset: (width - cardWidth * columns - gutter * (columns - 1)) / 2,
      topInset: (height - used) / 2,
      bottomSafeMargin: (height - used) / 2,
    );
  }
}
