import 'package:flutter/widgets.dart';

import '../../../utils/tv_hig.dart';
import '../../../widgets/tv/tv_unified_layout.dart';

/// The film detail page's measurements, in points on the 1920 canvas
/// ([TvHig]). The northstars in `pleya-northstar-refs/2026-10-30/` were read at
/// 2000 wide, so a value here is that reading times 0.96.
abstract final class TvDetailLayout {
  /// 107/1600 of the width, the margin Michel set for the page.
  static const double leftMarginFraction = 107 / 1600;
  static const double rightMargin = 96;

  /// The top of the logo or title slot. The hero hangs from here: its rows
  /// follow one another down, nothing is anchored to the bottom of the screen.
  static const double headingTop = 125;

  /// The slot a logo or a title stands in. Whatever fills it stands on the
  /// bottom edge, so the metadata line sits at one height for both.
  static const double headingHeight = 168;
  static const double logoWidth = 720;
  static const double titleWidth = 790;
  static const double titleHeight = 200;

  static const double metaGap = 7;
  static const double scoreGap = 8;
  static const double synopsisGap = 24;
  static const double directorGap = 14;
  static const double actionRowGap = 18;
  static const double activityGap = 28;

  static const double synopsisWidth = 818;
  static const int synopsisLines = 3;

  /// Where a focused section's heading is centred, on the page and in points
  /// (420 in the 2000-wide reading of 04, 05, 07 and 09). What was above it
  /// has left the screen, the hero included.
  static const double focusHeadingCentre = 403;
  static const double headingLineHeight = 1.2;

  /// How far a section's top sits from the page's top once its heading is on
  /// [focusHeadingCentre].
  static double focusedSectionTop(double pt) => (focusHeadingCentre - headingSize() * headingLineHeight / 2) * pt;

  static const double actionSize = 64;
  static const double actionGap = 32;
  static const double progressRingSize = 32;
  static const double techLabelHeight = 40;
  static const double techLabelGap = 16;

  static const double sectionHeadingGap = 24;
  static const double sectionGap = 56;
  static const double cardGutter = 32;
  static const double textGap = 16;

  static const double portraitSize = 240;
  static const double posterWidth = 240;
  static const double wideCardWidth = 512;
  static const double reviewCardHeight = 256;
  static const double reviewCardRadius = 16;
  static const double reviewIconSize = 40;
  static const double reviewPadding = 24;

  /// The page's end, under the last row.
  static const double bottomPadding = 96;

  /// In logical pixels. Heavy enough that no shape of the artwork survives, only
  /// its colours: at 34 a dark edge in the picture still read as an edge.
  static const double backdropBlur = 110;

  /// The artwork is decoded this small before the blur: there is nothing left
  /// to see of the rest, and it keeps a full 4K still out of memory.
  static const Size backdropDecodeSize = Size(96, 54);

  /// Scrim over the blurred artwork. The smallest alpha at which body ink holds
  /// 4.5:1 over the worst artwork a title can bring, in either theme: see
  /// [worstCaseContrast].
  static const double scrimAlpha = 0.60;

  static double leftMargin(double width) => width * leftMarginFraction;

  /// A row in this page's own geometry rather than the catalog's column.
  ///
  /// [artworkInset] is what a catalog card keeps around its artwork for the
  /// ring. The row gives it back at both ends of the pitch, so the artwork, not
  /// the card, starts on the margin under the heading.
  static TvCatalogGrid rowGrid({
    required double width,
    required double cardWidth,
    required double pt,
    double artworkInset = 0,
  }) => TvCatalogGrid(
    columns: 1,
    cardWidth: cardWidth,
    gutter: cardGutter * pt - artworkInset * 2,
    inset: leftMargin(width) - artworkInset,
    bottomSafeMargin: 0,
  );

  /// The contrast of [ink] over [scrim] at [scrimAlpha] on [artwork], the
  /// measurement behind the alpha above.
  static double worstCaseContrast({required Color ink, required Color scrim, required Color artwork}) {
    final over = Color.alphaBlend(scrim.withValues(alpha: scrimAlpha), artwork);
    final a = ink.computeLuminance();
    final b = over.computeLuminance();
    return ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
  }

  /// [TvCatalogLayout.cardHeight] for a card whose artwork is not 2:3.
  static double cardHeight(double width, double scale, {required double aspectRatio}) {
    final inset = TvCatalogLayout.cardContentInset(scale);
    final artworkWidth = width - inset * 2;
    return TvCatalogLayout.cardHeight(width, scale, titleLines: 1) -
        artworkWidth / TvCatalogLayout.posterAspectRatio +
        artworkWidth / aspectRatio;
  }

  static double headingSize() => TvHig.callout;
}
