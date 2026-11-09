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

  /// The tab row of a series, above the slot.
  static const double tabsTop = 41;
  static const double tabHeight = 48;
  static const double tabInset = 8;
  static const double tabPadding = 16;
  static const double tabGap = 16;

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

  // A season tab (01). Its row stays on one height whatever the text does.
  static const double seasonLogoTop = 128;
  static const double seasonLogoHeight = 100;
  static const double seasonLogoWidth = 526;
  static const double seasonNameGap = 8;
  static const double seasonNameHeight = 38;
  static const double seasonSynopsisGap = 118;
  static const double seasonRowGap = 80;
  static const double seasonFooterGap = 40;
  static const double seasonFooterBottom = 24;

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

  /// The pill of 06: a smaller ring and type than the round buttons carry,
  /// a little more room after the text than before the ring.
  static const double pillRingSize = 28;
  static const double pillPaddingStart = 18;
  static const double pillPaddingEnd = 22;

  /// The glyph in a round button, as large as 06 draws it.
  static const double actionIconSize = 34;
  static const double techLabelHeight = 40;
  static const double techLabelGap = 16;

  /// Two thirds of the row. The labels take their own width up to here, and
  /// the activity line beside them everything that is left.
  static const double techLabelsMaxWidth = 1130;

  // The activity line (06). The small overlap leaves two initials readable.
  static const double activityAvatarSize = 54;
  static const double activityAvatarRing = 2;
  static const double activityAvatarOverlap = 8;
  static const double activityTextGap = 16;

  static const double sectionHeadingGap = 24;
  static const double sectionGap = 56;
  static const double cardGutter = 32;
  static const double textGap = 16;

  static const double portraitSize = 240;
  static const double posterWidth = 240;
  static const double wideCardWidth = 512;
  static const double wideCardHeight = 288;
  static const double reviewCardHeight = 256;
  static const double reviewCardRadius = 16;
  static const double reviewIconSize = 40;
  static const double reviewPadding = 24;

  /// The page's end, under the last row.
  static const double bottomPadding = 96;

  // Discussies (04 and 07): the size of a review card, read at a lower text.
  static const double discussionAvatar = 56;
  static const double discussionPadding = 16;
  static const double discussionTop = 24;
  static const double discussionTextGap = 40;

  // Meer acties (12).
  static const double panelPadding = 65;
  static const double panelTitleTop = 66;
  static const double panelTitleHeight = 36;
  static const double panelRowsTop = 74;
  static const double panelRowHeight = 63;
  static const double panelRowGap = 13;
  static const double panelIconCentre = 32;
  static const double panelLabelInset = 71;
  static const double panelValueInset = 24;

  /// A row's value, set smaller and heavier than its label as 12 does. A whole
  /// audio track, "Engels (EAC3 5.1 + Atmos)", fits on one line beside it.
  static const double panelValueSize = 20;
  static const double panelValueGap = 12;

  /// In logical pixels. Heavy enough that no shape of the artwork survives, only
  /// its colours: at 34 a dark edge in the picture still read as an edge.
  static const double backdropBlur = 110;

  /// The artwork is decoded this small before the blur: there is nothing left
  /// to see of the rest, and it keeps a full 4K still out of memory.
  static const Size backdropDecodeSize = Size(96, 54);

  /// How much of the artwork's brightness and of its colour the backdrop
  /// keeps. The old black scrim at 0.6 kept 0.4 of both, and dark artwork came
  /// out black-brown. These keep less light and more hue, the largest pair at
  /// which body ink still holds 4.5:1 over any artwork, see [worstCaseContrast].
  static const double backdropLight = 0.30;
  static const double backdropColour = 0.70;

  /// In the dark theme the brightness is pulled towards this grey and not
  /// towards black, so a dark poster still leaves a colour (06's deep blue).
  static const double backdropDarkFloor = 40 / 255;

  // Rec. 709 weights, applied to the sRGB values as the colour matrix sees them.
  static const double _wr = 0.2126, _wg = 0.7152, _wb = 0.0722;

  /// The weighted brightness of [c], 0 to 1.
  static double luma(Color c) => _wr * c.r + _wg * c.g + _wb * c.b;

  /// The backdrop's colour matrix: brightness pulled towards [floor] (0 to 1),
  /// the colour around it kept at [backdropColour].
  static List<double> backdropMatrix({required double floor}) {
    const k = backdropLight, s = backdropColour;
    final offset = (1 - k) * floor * 255;
    List<double> row(int i) => [
      (i == 0 ? s : 0) + (k - s) * _wr,
      (i == 1 ? s : 0) + (k - s) * _wg,
      (i == 2 ? s : 0) + (k - s) * _wb,
      0,
      offset,
    ];
    return [...row(0), ...row(1), ...row(2), 0, 0, 0, 1, 0];
  }

  /// [artwork] as [backdropMatrix] draws it.
  static Color backdropColor(Color artwork, {required double floor}) {
    final m = backdropMatrix(floor: floor);
    double channel(int i) =>
        ((m[i * 5] * artwork.r + m[i * 5 + 1] * artwork.g + m[i * 5 + 2] * artwork.b) + m[i * 5 + 4] / 255).clamp(0, 1);
    return Color.from(alpha: 1, red: channel(0), green: channel(1), blue: channel(2));
  }

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

  /// The contrast of [ink] over [artwork] once [backdropMatrix] has drawn it,
  /// the measurement behind [backdropLight] and [backdropColour].
  static double worstCaseContrast({required Color ink, required double floor, required Color artwork}) {
    final a = ink.computeLuminance();
    final b = backdropColor(artwork, floor: floor).computeLuminance();
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
