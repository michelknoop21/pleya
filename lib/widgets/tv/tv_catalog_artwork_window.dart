/// Which rows of a catalog grid draw their poster (CAT18).
///
/// `TvCatalogCardGrid` builds every cell of every loaded page, because its
/// D-pad traversal is wired across explicit rows. A cell that draws its poster
/// keeps that decoded image alive, and Flutter's image cache cannot evict an
/// image something still listens to, so a long scroll through Alle films grew
/// memory until tvOS killed the app. The cells stay; rows far from the focus
/// draw the placeholder fill in the same box instead.
library;

import 'package:flutter/widgets.dart';

/// Rows either side of the window's centre row that keep their poster.
///
/// A 1080p viewport shows two to three rows, so six keeps more than a screen
/// of posters beyond each edge. The centre moves before the focus reaches the
/// edge (see [tvCatalogArtworkShouldRecenter]), so a card never comes into view
/// without its image.
const int tvCatalogArtworkWindowRows = 6;

/// Whether row [row] draws its poster for a window centred on [centerRow].
bool tvCatalogArtworkRowInWindow({required int row, required int centerRow}) =>
    (row - centerRow).abs() <= tvCatalogArtworkWindowRows;

/// Whether the focus on [focusedRow] has walked far enough from [centerRow] to
/// move the window. Half the radius, so the grid rebuilds every few rows rather
/// than on every D-pad press.
bool tvCatalogArtworkShouldRecenter({required int focusedRow, required int centerRow}) =>
    (focusedRow - centerRow).abs() > tvCatalogArtworkWindowRows ~/ 2;

/// Tells a `TvCatalogCard` below it whether to draw its artwork.
class TvCatalogArtworkScope extends InheritedWidget {
  const TvCatalogArtworkScope({super.key, required this.drawArtwork, required super.child});

  final bool drawArtwork;

  /// True when there is no scope: a card outside a grid always draws.
  static bool drawsArtwork(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvCatalogArtworkScope>()?.drawArtwork ?? true;

  @override
  bool updateShouldNotify(TvCatalogArtworkScope oldWidget) => drawArtwork != oldWidget.drawArtwork;
}
