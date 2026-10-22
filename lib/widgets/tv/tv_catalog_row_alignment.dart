/// Row-at-a-time scrolling for a TV card grid (A-06b, Michel, build 394).
///
/// Pure geometry, kept out of `TvCatalogCardGrid` so it can be tested without
/// a widget tree. The grid calls it with its own measurements and moves the
/// scroll position to the answer.
library;

import 'dart:math' as math;

/// How many whole rows fit in [viewport], each with room for a focused card's
/// ring ([growth]) above the top one and below the bottom one. Never less
/// than one: a viewport too short for a single row still shows the row the
/// remote is on.
int tvCatalogWholeRowsThatFit({
  required double viewport,
  required double cardHeight,
  required double gutter,
  required double growth,
}) {
  final pitch = cardHeight + gutter;
  if (pitch <= 0) return 1;
  // A hair of tolerance: a frame built to hold exactly two rows must not
  // round down to one.
  return math.max(1, ((viewport - 2 * growth + gutter) / pitch + 1e-6).floor());
}

/// The scroll offset that puts [row] on screen while keeping every visible
/// row whole and the top visible row on a row boundary.
///
/// The grid's content starts with [growth] of padding, so an offset of
/// `n * pitch` puts row `n` with its ring flush against the viewport's top.
/// The window of whole rows moves only as far as it has to: a row already in
/// it stays where it is, a row above it becomes the top row, a row below it
/// becomes the bottom row. [pixels] is where the scroll position is now, and
/// is rounded to the nearest row first, so an offset left between rows (a
/// restored place, the end of the content) settles on a boundary.
double tvCatalogRowAlignedOffset({
  required int row,
  required double pixels,
  required double viewport,
  required double cardHeight,
  required double gutter,
  required double growth,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  final pitch = cardHeight + gutter;
  if (pitch <= 0) return pixels.clamp(minScrollExtent, maxScrollExtent);
  final visible = tvCatalogWholeRowsThatFit(viewport: viewport, cardHeight: cardHeight, gutter: gutter, growth: growth);
  var top = (pixels / pitch).round();
  if (row < top) {
    top = row;
  } else if (row > top + visible - 1) {
    top = row - visible + 1;
  }
  return (top * pitch).clamp(minScrollExtent, maxScrollExtent);
}

/// The widest card for which two whole rows fit in a grid [viewport] tall,
/// with room around them (Michel, build 396: "nog steeds te weinig ruimte voor
/// de content").
///
/// Two cards, the gutter between them, the 6% focus scale-up above the top one
/// and below the bottom one, and [bottomMargin] (the grid's own bottom safe
/// margin) under the lot. On the Apple TV canvas, 1037.8 x 583.8 logical at a
/// ten-foot scale of 0.85, six columns at their natural width made a card 284
/// tall, so a viewport under the top navigation held one whole row, and the
/// folded Films/Series page two with no room at all. The column count stays;
/// the cards get narrower and the grid wider insets.
///
/// [cardHeight] is the caller's card height for a width, linear in the width
/// (poster block plus a fixed footer). Null when [viewport] is unbounded, so a
/// grid that is being measured keeps its natural width.
double? tvCatalogTwoRowCardWidth({
  required double viewport,
  required double gutter,
  required double bottomMargin,
  required double focusScale,
  required double Function(double cardWidth) cardHeight,
}) {
  if (!viewport.isFinite || viewport <= 0) return null;
  final maxCardHeight = (viewport - bottomMargin - gutter) / (1 + focusScale);
  final perWidth = cardHeight(1) - cardHeight(0);
  if (perWidth <= 0) return null;
  return math.max(0.0, (maxCardHeight - cardHeight(0)) / perWidth);
}

/// Library density (1 compact to 5 comfortable, default 3) scales the chosen
/// width: natural for the broad catalog, two-row fit for other opt-in grids.
/// Values 3 and up retain that width; 2 and 1 narrow it by 10% and 20%.
double tvCatalogDensityScale(int density) => density >= 3 ? 1.0 : 1.0 - (3 - density.clamp(1, 3)) * 0.1;
