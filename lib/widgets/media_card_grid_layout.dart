import 'package:flutter/widgets.dart';

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

  static double posterWidthFor(double cardWidth) => cardWidth - horizontalInset;

  /// Posters are 2:3, measured on the poster itself rather than on the cell,
  /// so the artwork is not cropped by the horizontal inset.
  static double posterHeightFor(double cardWidth) => posterWidthFor(cardWidth) * 3 / 2;

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
}
