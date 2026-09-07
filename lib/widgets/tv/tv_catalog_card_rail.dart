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

  /// The rail above and the rail below, told which column the step left from.
  ///
  /// Both explicit rather than left null: a null handler falls through to
  /// Flutter's directional traversal, which on a page of horizontally scrolling
  /// rows lands on whichever card happens to be nearest in pixels rather than
  /// on the row the viewer meant.
  ///
  /// The index is what LAND4 needs. A rail keeps focus memory — that is what
  /// makes returning from a detail page work — but that memory must not decide
  /// where UP and DOWN land: standing on item 2 of this rail, item 2 of the
  /// next one is the destination however far right that rail was parked.
  final ValueChanged<int>? onExitUp;
  final ValueChanged<int>? onExitDown;

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
  final _controller = ScrollController();
  String? _focusedId;

  /// The pitch this rail was last laid out on, so [focusColumn] can scroll to a
  /// card that has not been built yet. Set in `build` rather than recomputed,
  /// because the geometry depends on the viewport and on `reservedLeading`, and
  /// a second computation is a second thing to keep in step.
  double _pitch = 0;
  double _leadingPad = 0;

  @override
  void didUpdateWidget(TvCatalogCardRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcileNodes(previous: oldWidget.itemIds);
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: '${widget.nodeDebugLabel}($id)'));

  /// Drops nodes for items that are gone, and rescues focus if one of them had
  /// it — the same rule [TvCatalogCardGrid._reconcileNodes] carries for the
  /// grid, ported rather than reinvented. A card disappearing from under the
  /// remote (a refresh, a filter, a page reload) used to just call
  /// `_nodes.remove(id)?.dispose()`: `dispose()` frees the node all the way up
  /// to the enclosing scope, and a rail that was holding focus left the page
  /// focused with nothing focused on it — the tvOS dead page this whole
  /// contract exists to prevent.
  void _reconcileNodes({required List<String> previous}) {
    final live = widget.itemIds.toSet();
    final removed = _nodes.keys.where((id) => !live.contains(id)).toList();
    if (removed.isEmpty) return;

    final focusedId = _focusedId;
    final losesFocus = focusedId != null && removed.contains(focusedId);
    // Measured against the *old* list: the neighbour a viewer expects is the
    // card that was next to theirs before the update, and the new list no
    // longer contains the position to measure from.
    final oldIndex = losesFocus ? previous.indexOf(focusedId) : -1;

    for (final id in removed) {
      _nodes.remove(id)?.dispose();
    }
    if (!losesFocus) return;

    final replacement = _nearestSurvivor(previous: previous, from: oldIndex);
    _focusedId = replacement;
    // After the frame that removes the card: the replacement's node may not be
    // attached yet on this one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = replacement == null ? null : _nodes[replacement];
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
      } else {
        // Nothing survived, or it has not been built yet. LEFT is what this
        // rail's own callers wire to the CAT5 controls (`onExitLeft: _openRail`
        // on every page), which is the only thing left to operate once the
        // shelf under the remote has emptied.
        widget.onExitLeft?.call();
      }
    });
  }

  /// The nearest still-present item to position [from] in the old list.
  ///
  /// Walks outward, forward first: a tie means a card that had survivors on
  /// both sides disappeared, and the one *after* it is the one the viewer had
  /// not reached yet — the same tie-break [TvCatalogCardGrid]'s own
  /// `_nearestSurvivor` uses, for the same reason.
  String? _nearestSurvivor({required List<String> previous, required int from}) {
    if (from < 0) return widget.itemIds.firstOrNull;
    final live = widget.itemIds.toSet();
    for (var distance = 1; distance < previous.length; distance++) {
      final after = from + distance;
      if (after < previous.length && live.contains(previous[after])) return previous[after];
      final before = from - distance;
      if (before >= 0 && live.contains(previous[before])) return previous[before];
    }
    return widget.itemIds.firstOrNull;
  }

  /// Puts the remote on the card it was last on, or on the first one.
  ///
  /// `node.parent != null` is the attachment test, and it is checked before
  /// `canRequestFocus` on purpose: `_nodes` keeps an entry for every id this
  /// rail has ever built, for the life of the widget, independent of whether
  /// the `ListView` still has that cell on screen. A card that scrolled out of
  /// view is detached — `FocusNode.canRequestFocus` is `true` on a detached
  /// node, because it short-circuits on `enclosingScope == null` — so without
  /// this test a scrolled-away rail answers `true` and `requestFocus()` on it
  /// is a silent no-op. The return value is load-bearing for callers that stop
  /// a search loop at the first `true` (`TvSearchView.focusFirstResult`,
  /// `TvSeerrDiscoverViewState.focusFirstContent`): a false positive there
  /// means nothing gets the focus at all. See `tv_discovery_rail.dart`'s
  /// `_focusIndex`, which carries the same guard for the same reason.
  bool focusRail() {
    final remembered = _focusedId;
    final node = (remembered != null ? _nodes[remembered] : null) ?? _nodes[widget.itemIds.firstOrNull];
    if (node == null || node.parent == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  bool get hasFocusableCard => _nodes.values.any((node) => node.canRequestFocus);

  /// LAND4's destination for a vertical step that left column [column].
  ///
  /// Same index is the preferred rule; the clamp is what the geometry rule
  /// reduces to here. Every rail in the catalog language is laid out by
  /// [TvCatalogGrid.forWidth] at one card width and one gutter, so column *n*
  /// of one rail sits at the same horizontal centre as column *n* of the next,
  /// and "nearest centre" and "same index" are the same answer. A shorter rail
  /// clamps on its last card: six items, focus on five, into a rail of four
  /// gives item four.
  ///
  /// Deliberately not [focusRail]: that one restores what this rail remembers,
  /// which is right for arriving from a detail page and wrong for a step from
  /// the rail above.
  bool focusColumn(int column) {
    if (widget.itemIds.isEmpty) return false;
    final target = column.clamp(0, widget.itemIds.length - 1);
    final node = _nodes[widget.itemIds[target]];
    // `node.parent != null` — see [focusRail] for why the attachment test has
    // to come before `canRequestFocus`. A node this branch skips over is not
    // "not built yet": `_nodes` only gains an entry once a cell has actually
    // been built, so an entry that fails this test was built and then scrolled
    // away, which is exactly the case the fallback below exists to recover.
    if (node != null && node.parent != null && node.canRequestFocus) {
      node.requestFocus();
      return true;
    }
    // Either never built, or built and scrolled away: a `ListView` only keeps
    // what is in view, and this rail may be parked somewhere else entirely.
    // Bring the column into view first and ask again next frame — without
    // this, LAND4 would hold only for the part of a rail that happens to be on
    // screen, which is the half of the bug that is hardest to see.
    if (!_controller.hasClients || _pitch <= 0) return false;
    final position = _controller.position;
    final wanted = (_leadingPad + target * _pitch).clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.jumpTo(wanted);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final built = _nodes[widget.itemIds[target]];
      if (built != null && built.parent != null && built.canRequestFocus) built.requestFocus();
    });
    return true;
  }

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
    _pitch = grid.cardWidth + grid.gutter;
    _leadingPad = grid.inset + grid.leading;

    return SizedBox(
      height: cardHeight + headroom * 2,
      child: ListView.separated(
        controller: _controller,
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
              onNavigateUp: widget.onExitUp == null ? null : () => widget.onExitUp!(index),
              onNavigateDown: widget.onExitDown == null ? null : () => widget.onExitDown!(index),
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
