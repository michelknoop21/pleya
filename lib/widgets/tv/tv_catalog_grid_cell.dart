/// The wiring of one cell of `TvCatalogCardGrid`, and the clip of its rows.
library;

import 'package:flutter/widgets.dart';

/// One cell's wiring, handed to [TvCatalogCardGrid.itemBuilder].
///
/// The builder must forward every field onto the card it returns. That is a
/// contract rather than something this widget can enforce, and it is the
/// deliberate price of letting four screens draw four different cards on one
/// traversal: a grid that wrapped the card to impose the wiring would have to
/// own the focus node, and then the card could not be the thing the ring is
/// drawn around.
class TvCatalogGridCell {
  const TvCatalogGridCell({
    required this.index,
    required this.width,
    required this.focusNode,
    required this.onFocusChange,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });

  final int index;

  /// Resolved from the viewport by [TvCatalogGrid.forWidth] — never assumed.
  final double width;

  final FocusNode focusNode;

  /// Drives paging, artwork warm-up and the CAT10 scroll clamp. A card that
  /// does not forward it leaves all three unarmed.
  final ValueChanged<bool> onFocusChange;

  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  /// Menu on this card — see [TvCatalogCard.onBack].
  final VoidCallback? onBack;
}

/// Cuts a grid with fixed margins one row gap outside its whole rows.
///
/// The margins of a full-bleed grid are wider than its row gap, so without this
/// the year of the row above and a strip of the row below stand in them. Both
/// sit in the overscan band, the year as a loose line of text at the top of the
/// screen.
class TvCatalogRowBandClipper extends CustomClipper<Rect> {
  const TvCatalogRowBandClipper({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height - bottom);

  @override
  bool shouldReclip(TvCatalogRowBandClipper oldClipper) => oldClipper.top != top || oldClipper.bottom != bottom;
}
