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

  /// Where the first section's heading starts, as a fraction of the page: the
  /// rest of the first screen is the row peeking in under the hero.
  static const double heroHeightFraction = 773 / 1080;

  /// Where a focused row's artwork is centred, as a fraction of the page.
  static const double focusBandCentre = 576 / 1080;

  static const double logoWidth = 653;
  static const double logoHeight = 168;

  /// A title without a logo: type needs more room than a mark does.
  static const double titleWidth = 790;
  static const double titleHeight = 220;
  static const double synopsisWidth = 818;
  static const int synopsisLines = 3;

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

  /// Scrim over the blurred artwork. The smallest alpha at which body ink holds
  /// 4.5:1 over the worst artwork a title can bring, in either theme: see
  /// [worstCaseContrast].
  static const double scrimAlpha = 0.60;

  static double leftMargin(double width) => width * leftMarginFraction;

  /// A row in this page's own geometry rather than the catalog's column.
  static TvCatalogGrid rowGrid({required double width, required double cardWidth, required double pt}) => TvCatalogGrid(
    columns: 1,
    cardWidth: cardWidth,
    gutter: cardGutter * pt,
    inset: leftMargin(width),
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

  /// The two lines under a card, for the row's scroll anchor.
  static double cardFooterHeight(double width, double scale) =>
      cardHeight(width, scale, aspectRatio: TvCatalogLayout.posterAspectRatio) -
      (width - TvCatalogLayout.cardContentInset(scale) * 2) / TvCatalogLayout.posterAspectRatio -
      TvCatalogLayout.cardContentInset(scale) * 2;

  static double headingSize() => TvHig.callout;
}
