/// One horizontal row of catalog cards, on the grid's own pitch.
///
/// Ontdekken (mockup 35 A) is a page of rows rather than a wall, and the whole
/// point of [DEC-108](../../../docs/DECISIONS.md#dec-108) is that a card there
/// is the same card as on Alle films: 281 wide on the page inset, the same
/// gutter, the same ring. So this shares [TvCatalogGrid] with
/// [TvCatalogCardGrid] and differs only in the axis.
///
/// **It is not [TvDiscoveryRail].** That one draws the wide 16:9 feed tile and
/// grows under focus, which is the Home language; this draws the catalog's
/// portrait card and holds still. Two rails rather than one configurable rail,
/// because the difference is not a parameter: the feed tile *is* the discovery
/// landing's identity, and CAT11 was the report that Aanvragen and Zoeken had
/// borrowed it by accident.
///
/// The focus contract is the same one [TvCatalogCardGrid] documents, read
/// sideways: nodes keyed on identity rather than position, LEFT off the first
/// card leaving the rail, and the last cards asking for the next page before the
/// viewer reaches them.
library;

import 'package:flutter/material.dart';

import '../../focus/focus_theme.dart';
import '../../utils/layout_constants.dart';
import 'tv_catalog_card_grid.dart';
import 'tv_unified_layout.dart';

class TvCatalogCardRail extends StatefulWidget {
  const TvCatalogCardRail({
    super.key,
    required this.itemIds,
    required this.itemBuilder,
    required this.cardHeight,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.focusScale = FocusTheme.fullCardFocusScale,
    this.onExitUp,
    this.onExitDown,
    this.onExitLeft,
    this.onFocusedIdChanged,
    this.reservedLeading = 0,
    this.onBack,
    this.nodeDebugLabel = 'TvCatalogRailCard',
  });

  /// One stable id per card, in display order.
  final List<String> itemIds;

  final Widget Function(BuildContext context, TvCatalogGridCell cell) itemBuilder;

  /// The height of the card [itemBuilder] draws — see
  /// [TvCatalogCardGrid.cardHeight] for why the caller states it.
  final double Function(double cardWidth) cardHeight;

  final double focusScale;

  final bool hasMore;
  final bool isLoadingMore;

  /// Fired when the focus reaches within [loadMoreThreshold] cards of the end.
  final VoidCallback onLoadMore;

  /// The rail above and the rail below. Both explicit rather than left null:
  /// a null handler falls through to Flutter's directional traversal, which on
  /// a page of horizontally scrolling rows lands on whichever card happens to
  /// be nearest in pixels rather than on the row the viewer meant.
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  /// LEFT off the first card. On these pages that opens CAT5's rail.
  final VoidCallback? onExitLeft;

  final ValueChanged<String>? onFocusedIdChanged;

  /// Width held back before the first card, for an open controls rail.
  final double reservedLeading;

  /// Menu on any card. Null leaves the press to the route.
  final VoidCallback? onBack;

  final String nodeDebugLabel;

  /// How close to the end the focus has to get before the next page is asked
  /// for, in cards.
  ///
  /// Counted in cards rather than in rows because a rail has one row; three is
  /// most of a D-pad flick of warning, and it is what turns "press RIGHT, wait,
  /// then the card appears" into "the card is already there".
  static const int loadMoreThreshold = 3;

  @override
  State<TvCatalogCardRail> createState() => TvCatalogCardRailState();
}

class TvCatalogCardRailState extends State<TvCatalogCardRail> {
  final Map<String, FocusNode> _nodes = {};
  String? _focusedId;

  @override
  void didUpdateWidget(TvCatalogCardRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final live = widget.itemIds.toSet();
    for (final id in _nodes.keys.where((id) => !live.contains(id)).toList()) {
      _nodes.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: '${widget.nodeDebugLabel}($id)'));

  /// Puts the remote on the card it was last on, or on the first one.
  bool focusRail() {
    final remembered = _focusedId;
    final node = (remembered != null ? _nodes[remembered] : null) ?? _nodes[widget.itemIds.firstOrNull];
    if (node == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  bool get hasFocusableCard => _nodes.values.any((node) => node.canRequestFocus);

  void _focusIndex(int index) {
    if (index < 0 || index >= widget.itemIds.length) return;
    final node = _nodes[widget.itemIds[index]];
    if (node != null && node.canRequestFocus) node.requestFocus();
  }

  void _maybeLoadMore(int index) {
    if (!widget.hasMore || widget.isLoadingMore) return;
    if (widget.itemIds.length - index > TvCatalogCardRail.loadMoreThreshold) return;
    widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final grid = TvCatalogGrid.forWidth(width, scale: scale, reservedLeading: widget.reservedLeading);
    final cardHeight = widget.cardHeight(grid.cardWidth);
    // The same reservation the grid pays above its first row, on both sides:
    // a focused card scales about its centre, so half the growth reaches past
    // each edge of the row's box, and a `ListView` clips at its own bounds.
    final headroom = TvCatalogGrid.focusHeadroom(cardHeight: cardHeight, focusScale: widget.focusScale);

    return SizedBox(
      height: cardHeight + headroom * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The ring of the first card reaches into the page margin, and the row
        // must not shear it off — the padding below is what it grows into, and
        // clipping would take it back.
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: grid.inset + grid.leading, vertical: headroom),
        itemCount: widget.itemIds.length,
        separatorBuilder: (_, _) => SizedBox(width: grid.gutter),
        itemBuilder: (context, index) {
          final id = widget.itemIds[index];
          return widget.itemBuilder(
            context,
            TvCatalogGridCell(
              index: index,
              width: grid.cardWidth,
              focusNode: _nodeFor(id),
              onFocusChange: (hasFocus) {
                if (!hasFocus) return;
                _focusedId = id;
                widget.onFocusedIdChanged?.call(id);
                _maybeLoadMore(index);
              },
              onNavigateUp: widget.onExitUp,
              onNavigateDown: widget.onExitDown,
              onNavigateLeft: index == 0 ? widget.onExitLeft : () => _focusIndex(index - 1),
              // The backstop the threshold above does not cover: `hasMore` can
              // become true after the focus has already settled on the last
              // card. It loads and keeps the focus exactly where it is.
              onNavigateRight: index == widget.itemIds.length - 1
                  ? (widget.hasMore && !widget.isLoadingMore ? widget.onLoadMore : null)
                  : () => _focusIndex(index + 1),
              onBack: widget.onBack,
            ),
          );
        },
      ),
    );
  }
}
