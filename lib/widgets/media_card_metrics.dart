import 'package:flutter/material.dart';

import '../focus/focus_theme.dart';

/// The measurable parts of a standard poster card, in one place.
///
/// The card draws against these, a grid reserves its cell height with them,
/// and the rails size their rows with them. Every copy of these numbers that
/// lives somewhere else is a way for a grid to clip its own captions or for a
/// rail to end up a few points short.
class MediaCardMetrics {
  MediaCardMetrics._();

  /// Inset between the cell edge and the card itself. This is the gutter that
  /// separates cards inside a rail, and in a grid it sits on top of the
  /// delegate's spacing.
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(3, 3, 3, 1);

  /// Gap between the poster and the title.
  static const double captionGap = 2;

  static const double titleFontSize = 13;
  static const double titleHeightFactor = 1.1;
  static const double subtitleFontSize = 11;
  static const double subtitleHeightFactor = 1.1;

  /// Height of the title line plus the metadata line under it.
  ///
  /// Both lines are capped at one line each, so this is exact rather than a
  /// worst case. It follows the OS text scale: a larger system font then makes
  /// the grid taller instead of getting cut off by it.
  static double captionHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return scaler.scale(titleFontSize) * titleHeightFactor + scaler.scale(subtitleFontSize) * subtitleHeightFactor;
  }

  /// Title style on a grid card. Shared so [captionHeight] and the card itself
  /// cannot drift apart.
  static const TextStyle titleStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: titleFontSize,
    height: titleHeightFactor,
  );

  /// Metadata style under the title, for the same reason as [titleStyle].
  static TextStyle? subtitleStyle(BuildContext context, {required Color color}) => Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: color, fontSize: subtitleFontSize, height: subtitleHeightFactor);

  /// Room a grid cell keeps free on every side so a focused card can grow
  /// without leaving its own cell.
  ///
  /// Focus scales the card around its centre, so it reaches half the added
  /// width past its edges. Reserving exactly that means the card at
  /// [focusScale] ends up filling the cell it was given, and the gap the grid
  /// draws between cells is never crossed: the distance to the neighbour stays
  /// the delegate's spacing no matter where focus sits.
  static double focusInset(double cellWidth, {double focusScale = FocusTheme.focusScale}) =>
      cellWidth * (focusScale - 1) / 2;

  /// Width left for the poster inside a cell [cellWidth] wide.
  static double posterWidth(double cellWidth, {double focusInset = 0}) =>
      cellWidth - focusInset * 2 - cardPadding.horizontal;

  /// Height of one grid cell: the reserved focus room, the card's own padding,
  /// the poster at its natural aspect, and the caption block under it.
  ///
  /// [imageAspectRatio] is width over height, so 2/3 for a poster and 16/9 for
  /// an episode thumbnail.
  static double cellHeight(
    BuildContext context,
    double cellWidth, {
    required double imageAspectRatio,
    double focusInset = 0,
  }) {
    final poster = posterWidth(cellWidth, focusInset: focusInset) / imageAspectRatio;
    return focusInset * 2 + cardPadding.vertical + poster + captionGap + captionHeight(context);
  }
}
