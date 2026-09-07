/// The body of a catalog-language page: the content, with CAT5's rail standing
/// beside it.
///
/// Four screens draw this now — Films, Series, Kijklijst and Aanvragen — and
/// the placement is not obvious enough to be retyped four times. Extracted from
/// `tv_unified_catalog_screen.dart` unchanged when
/// [DEC-108](../../../docs/DECISIONS.md#dec-108) put three more pages on the
/// same rail.
///
/// A `Stack` rather than a `Row`, because the grid owns its own horizontal
/// padding and always has: it is the thing that resolves the page inset, and
/// putting it in a flex would mean handing that job to this widget and getting
/// the two edges from two different places. Instead the grid holds back
/// [TvCatalogGrid.leading] on its left — which is what [leadingFor] returns —
/// and the rail is positioned into exactly that band.
library;

import 'package:flutter/material.dart';

import '../../focus/focus_theme.dart';
import '../../utils/layout_constants.dart';
import 'tv_catalog_filter_rail.dart';
import 'tv_unified_layout.dart';

class TvCatalogRailScaffold extends StatelessWidget {
  const TvCatalogRailScaffold({
    super.key,
    required this.body,
    required this.rail,
    required this.cardHeight,
    this.focusScale = FocusTheme.fullCardFocusScale,
  });

  /// The grid, the skeleton or the empty state. It resolves its own columns
  /// from [leadingFor], so it already knows how much room the rail is taking.
  final Widget body;

  /// The open rail — the panel, or one of its subviews. Null is the resting
  /// state, and draws the hairline strip in the page's own left margin instead:
  /// Michel's condition on choosing a rail at all was "dan moet dit niet altijd
  /// in beeld blijven deze zijbalk".
  final Widget? rail;

  /// The height of the card [body] draws, for a card of the given width — used
  /// only to line the rail's top edge up with the first poster row. See
  /// [TvCatalogGrid.scrollPadding] for why the caller states this rather than
  /// having it derived here.
  final double Function(double cardWidth) cardHeight;

  final double focusScale;

  /// How much width an open rail takes out of the grid's content box.
  ///
  /// Zero while it is closed, because the strip lives in the page's own left
  /// margin, so all six columns stay. It is the panel plus its gap while it is
  /// open, which is what turns six columns into five.
  static double leadingFor(double width, {required bool expanded}) =>
      expanded ? width * ((TvCatalogLayout.railWidth + TvCatalogLayout.railGridGap) / TvCatalogGrid.referenceWidth) : 0;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final expanded = rail != null;
    final grid = TvCatalogGrid.forWidth(
      width,
      scale: scale,
      reservedLeading: leadingFor(width, expanded: expanded),
    );
    // The same headroom the grid reserves above its first row for a focused
    // card's ring, so the rail's top edge lines up with the first poster
    // instead of with the viewport.
    final top = TvCatalogGrid.focusHeadroom(cardHeight: cardHeight(grid.cardWidth), focusScale: focusScale);

    return Stack(
      children: [
        Positioned.fill(child: body),
        if (expanded)
          Positioned(
            left: grid.inset,
            top: top,
            // Bounded at the bottom by the page's own overscan margin, with the
            // panel aligned to the top of that band. `Align` hands its child a
            // *loose* height, so the panel still shrink-wraps to its rows; what
            // the bound buys is that a selection long enough to outgrow the
            // page scrolls inside the panel instead of overflowing it.
            bottom: grid.bottomSafeMargin,
            width: width * (TvCatalogLayout.railWidth / TvCatalogGrid.referenceWidth),
            child: Align(alignment: Alignment.topCenter, child: rail),
          )
        else
          Positioned(
            left: 0,
            top: top,
            bottom: 0,
            width: grid.inset,
            // Decoration, not a control: it must not take a hit test off the
            // page behind it, and there is nothing to hit-test it *for*.
            child: IgnorePointer(child: TvCatalogFilterRailStrip(scale: scale)),
          ),
      ],
    );
  }
}
