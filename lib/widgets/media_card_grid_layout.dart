import 'package:flutter/widgets.dart';

import '../focus/focus_theme.dart';

/// Shared sizing math for media cards rendered as standard grid cards:
/// a poster with a title and one line of metadata underneath.
///
/// The one thing to know before using [MediaCard] in a grid or a row: its
/// `height` is the **poster** height, not the card height. The caption is
/// drawn below that, outside it. Every caller therefore has to budget
/// [textExtentFor] on top of the poster when it sizes the cell or the rail.
/// (`fullBleedImage` cards are the exception: those are image-only, so there
/// `height` is the whole card.)
///
/// Sibling of [MediaCardListLayout], which does the same for list mode.
class MediaCardGridLayout {
  /// Horizontal padding [MediaCard] puts around its poster: 3 either side.
  static const double horizontalInset = 6;

  /// Vertical padding above the poster and below the caption.
  static const double topInset = 3;
  static const double bottomInset = 1;

  /// Space between the bottom of the poster and the first line of text.
  static const double posterCaptionGap = 2;

  static const double titleFontSize = 13;
  static const double subtitleFontSize = 11;

  /// Line height multiplier both caption lines use.
  static const double lineHeightFactor = 1.1;

  /// Title style on a grid card, so the height math and the card itself cannot
  /// drift apart.
  static const TextStyle titleStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: titleFontSize,
    height: lineHeightFactor,
  );

  /// Metadata style under the title, for the same reason.
  static TextStyle subtitleStyleFrom(TextStyle? base, {required Color color}) =>
      (base ?? const TextStyle()).copyWith(color: color, fontSize: subtitleFontSize, height: lineHeightFactor);

  /// Room a grid cell keeps free on every side so a focused card can grow
  /// without leaving its own cell.
  ///
  /// Focus scales the card around its centre, so it reaches half the added
  /// width past its edges. Reserving exactly that means a card at
  /// [focusScale] ends up filling the cell it was given, and the gap the grid
  /// draws between cells is never crossed: the distance to the neighbour stays
  /// the delegate's spacing no matter where focus sits.
  static double focusInsetFor(double cellWidth, {double focusScale = FocusTheme.focusScale}) =>
      cellWidth * (focusScale - 1) / 2;

  static double posterWidthFor(double cardWidth, {double focusInset = 0}) =>
      cardWidth - focusInset * 2 - horizontalInset;

  /// Posters are 2:3, measured on the poster itself rather than on the cell,
  /// so the artwork is not cropped by the horizontal inset.
  static double posterHeightFor(double cardWidth, {double focusInset = 0}) =>
      posterWidthFor(cardWidth, focusInset: focusInset) * 3 / 2;

  /// Height of the caption block: one title line plus one subtitle line.
  ///
  /// Resolved against the system text setting rather than frozen as a
  /// constant. A fixed number is right at scale 1.0 and overflows into the
  /// row below the moment a user turns text size up, which is exactly the
  /// failure this contract exists to prevent.
  static double captionExtentFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = scaler.scale(titleFontSize) * lineHeightFactor;
    final subtitle = scaler.scale(subtitleFontSize) * lineHeightFactor;
    return (title + subtitle).ceilToDouble();
  }

  /// What a grid cell has to reserve on top of the poster.
  static double textExtentFor(BuildContext context) =>
      topInset + posterCaptionGap + captionExtentFor(context) + bottomInset;

  static double cardHeightFor(BuildContext context, double cardWidth) =>
      posterHeightFor(cardWidth) + textExtentFor(context);

  /// Height of a grid cell [cellWidth] wide: the reserved focus room, the
  /// card's padding, the artwork at its own aspect, and the caption.
  ///
  /// [imageAspectRatio] is width over height, so 2/3 for a poster and 16/9 for
  /// an episode thumbnail. Measuring it this way is the point: a single aspect
  /// ratio for poster plus caption cannot hold, because the caption does not
  /// shrink with the column, so on a narrow column it ran out of the cell and
  /// into the row below.
  static double cellHeightFor(
    BuildContext context,
    double cellWidth, {
    required double imageAspectRatio,
    double focusInset = 0,
  }) {
    final artwork = posterWidthFor(cellWidth, focusInset: focusInset) / imageAspectRatio;
    return focusInset * 2 + artwork + textExtentFor(context);
  }
}
