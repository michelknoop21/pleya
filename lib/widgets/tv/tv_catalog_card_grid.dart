/// The wall of cards every TV surface in the catalog language scrolls, and the
/// focus contract of hoofdstuk 7.4 and 7.6 that makes it usable with a remote.
///
/// It was `TvUnifiedMediaGrid` until 7 September 2026;
/// [DEC-108](../../../docs/DECISIONS.md#dec-108) put the kijklijst, Alle
/// aanvragen and Zoeken on the same grid, and none of those hold an
/// [UnifiedMediaGroup]. So the part that is about *walking a grid with a
/// remote* lives here, over a list of stable ids and a builder, and the part
/// that is about a unified catalog stayed where it was.
///
/// Everything below is the contract that moved with it, unchanged.
///
/// ## Focus is keyed on the item, not on the index
///
/// Hoofdstuk 7.6 is explicit: "group krijgt een extra bron → geen remount en
/// geen focussprong", and a filtered-away card sends focus to its neighbour.
/// A grid that owns a `List<FocusNode>` by position satisfies neither — the
/// fase-3 merge recomputes its group list wholesale on every round, so position
/// 12 can be a different title one frame later, and focus would silently move
/// to whatever slid into the slot. The kijklijst has the same problem from a
/// different direction: it re-sorts and re-filters in memory.
///
/// So nodes live in a map keyed by [TvCatalogCardGrid.itemIds], which the
/// caller guarantees is stable across rounds. Paging appends ids and the
/// existing nodes keep their identity untouched; an id that leaves has its
/// node disposed, and only if it *held* focus does the grid move focus at all —
/// to the nearest surviving neighbour by its old position, because a user who
/// filtered a card away is still looking at that spot.
///
/// ## Why the whole grid is one scroll view of explicit rows
///
/// Not `GridView`: D-pad traversal here is wired, not inferred. Flutter's
/// directional traversal on a lazily-built grid can walk into an unbuilt row
/// and land nowhere, and hoofdstuk 7.4 needs UP out of the *first* row to reach
/// the header while UP anywhere else stays in the grid — a distinction the
/// default policy cannot make. Rows are explicit, and each card names its four
/// neighbours.
///
/// **Known debt, deliberately not paid.** Making the grid lazy is the change
/// that would turn a loaded page of several hundred titles into a viewport's
/// worth of image requests. It is not a swap of one scroll widget for another:
/// it reopens exactly the traversal question the paragraph above settles, on a
/// platform where the only honest verification is hardware.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../focus/directional_focus_history.dart';
import '../../focus/focus_history.dart';
import '../../focus/focus_theme.dart';
import '../../utils/layout_constants.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import 'tv_catalog_artwork_window.dart';
import 'tv_catalog_grid_cell.dart';
import 'tv_catalog_row_alignment.dart';
import 'tv_unified_layout.dart';

export 'tv_catalog_grid_cell.dart';

part 'tv_catalog_card_grid_scroll.dart';

class TvCatalogCardGrid extends StatefulWidget {
  const TvCatalogCardGrid({
    super.key,
    required this.itemIds,
    required this.itemBuilder,
    required this.cardHeight,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.focusScale = FocusTheme.fullCardFocusScale,
    this.onExitTop,
    this.onExitLeft,
    this.footer,
    this.controller,
    this.initialFocusedId,
    this.onFocusedIdChanged,
    this.onFocusedCell,
    this.reservedLeading = 0,
    this.onBack,
    this.nodeDebugLabel = 'TvCatalogCard',
    this.rowAligned = false,
    this.fitTwoRows = false,
    this.fitScale,
    this.successorOf,
    this.loadEagerly = false,
    this.gridResolver,
    this.onEmptied,
  });

  /// One stable id per item, in display order. Identity, not position: see the
  /// library doc.
  final List<String> itemIds;

  final Widget Function(BuildContext context, TvCatalogGridCell cell) itemBuilder;

  /// The height of the card [itemBuilder] draws, for a card of the given width.
  ///
  /// **The caller states the card it draws.** Deriving it here from the poster
  /// aspect ratio is what CAT1 cost: the real poster is narrower than the card
  /// and the real card is taller, and the difference is wider than the focus
  /// ring, so the top row's ring was cut off flat. Screens that draw a third
  /// meta line pass [TvCatalogLayout.cardHeight] with `extraMetaLines: 1`.
  final double Function(double cardWidth) cardHeight;

  /// How far focus enlarges a card, so the scroll padding and the CAT10 clamp
  /// reserve the room the ring actually needs.
  final double focusScale;

  final bool hasMore;
  final bool isLoadingMore;

  /// Which current item continues [removedId], when an item's id changed
  /// rather than the item left (a unified group gaining external ids changes
  /// its content-derived id). Null or a miss falls back to the nearest
  /// survivor.
  final String? Function(String removedId)? successorOf;

  /// One long list instead of pages: keep asking for the next page as soon as
  /// the previous one landed, wherever the focus is, until [hasMore] is false.
  /// The focus-based look-ahead then never has anything left to wait for.
  final bool loadEagerly;

  /// Eager loading stops here: every card is a built widget with its own focus
  /// node (the grid is not virtualised), so a library beyond this keeps the
  /// focus look-ahead instead of loading unattended.
  static const int eagerLoadLimit = 3000;

  /// Called when the focus reaches within [loadMoreRowThreshold] rows of the
  /// end and more pages exist. Hoofdstuk 28: no full-page spinner, no reflow —
  /// the loaded cards stay exactly where they are and new rows appear
  /// underneath.
  final VoidCallback onLoadMore;

  /// UP out of the first row (hoofdstuk 7.4: "Up vanaf de eerste gridrij gaat
  /// naar de dichtstbijzijnde headeractie").
  final VoidCallback? onExitTop;

  /// LEFT out of the first column. On the catalog that opens CAT5's rail; on
  /// another surface it is whatever sits left of the page.
  final VoidCallback? onExitLeft;

  /// Drawn under the last row — a count line, a partial-state notice.
  final Widget? footer;

  final ScrollController? controller;

  /// Restoration: the card to come back to, by the same stable id the nodes are
  /// keyed on (hoofdstuk 7.6). Ignored when that id is no longer in
  /// [itemIds] — a title a filter removed cannot be focused, and the first card
  /// is the honest fallback.
  final String? initialFocusedId;

  /// Reports the card the remote moved to, so a screen that will be torn down
  /// can hand it to whatever outlives it. Fires on focus, not on scroll: on
  /// this platform focus *is* the cursor.
  final ValueChanged<String>? onFocusedIdChanged;

  /// The same event with the geometry attached, for a caller that warms artwork
  /// around the focused row and needs the column count to know what that row is.
  final void Function(int index, TvCatalogGrid grid)? onFocusedCell;

  /// Width held back before the first column, for CAT5's open controls rail.
  ///
  /// Handed to [TvCatalogGrid.forWidth] rather than added as padding here: the
  /// column count has to be resolved from what is left over, or the grid keeps
  /// six columns and the sixth runs off the right edge.
  final double reservedLeading;

  /// Menu on any card. Null leaves the press to the route.
  final VoidCallback? onBack;

  /// Prefix of the focus nodes' debug labels, so a focus trace says which grid
  /// a node belongs to when two are mounted at once.
  final String nodeDebugLabel;

  /// A-06b: scroll a whole row at a time and keep the focused row whole. UP and DOWN are wired here instead of falling through
  /// to Flutter's traversal, whose `ensureVisible` jumps the content into place
  /// and leaves rows cut off at the edge; the grid moves the focus to the card
  /// above or below and glides the content to a row boundary
  /// ([tvCatalogRowAlignedOffset]). Off by default, so every other surface on
  /// this grid keeps the CAT10 clamp it has.
  final bool rowAligned;

  /// Narrow the cards (same column count, wider insets) until two whole rows
  /// fit, with room around them; see [tvCatalogTwoRowCardWidth]. Opt-in for
  /// fixed-heading grids. The broad library catalog keeps its natural width.
  final bool fitTwoRows;

  /// Scales the two-row width, or the natural width when [fitTwoRows] is off.
  /// Null reads the density setting only for a two-row grid.
  final double? fitScale;

  /// Takes the geometry out of [TvCatalogGrid.forWidth] altogether, for a page
  /// that states its own: [TvCatalogFullBleedLayout]. Receives the grid's width
  /// and height. [fitTwoRows], [fitScale] and [reservedLeading] do not apply.
  final TvCatalogGrid Function(double width, double height)? gridResolver;

  /// Where the focus goes when the card holding it left and no card survived.
  /// Null falls back to [onExitTop], which on most pages is the controls; a page
  /// whose UP deliberately goes nowhere names the controls here instead.
  final VoidCallback? onEmptied;

  /// The narrowest [fitTwoRows] card under a fixed heading, as a share of the
  /// natural six-across width: the width Alle films settles on at the default
  /// density, which reads whole (one-line two-word title, full year line).
  static const double minFitFraction = 0.8;

  /// The glide for [rowAligned]: the same easeOutCubic as the page heading,
  /// a little shorter because it runs on every press.
  static const Duration rowScrollDuration = Duration(milliseconds: 220);

  /// How close to the end of the loaded pages the focus has to get before the
  /// next page is asked for, in grid rows.
  ///
  /// Four, measured in rows rather than in cards because the column count is
  /// 5–7 depending on the panel: each row is one D-pad press of warning, and it is what turns "press DOWN, wait, then the row
  /// appears" into "the row is already there". Four rows of warning keep
  /// up with a held D-pad.
  static const int loadMoreRowThreshold = 4;

  @override
  State<TvCatalogCardGrid> createState() => TvCatalogCardGridState();
}

class TvCatalogCardGridState extends State<TvCatalogCardGrid> {
  /// Focus nodes by item id; see the library doc for why not by index.
  final Map<String, FocusNode> _nodes = {};

  /// The item that currently holds focus, so a rebuild that drops it knows
  /// where the user was standing. Seeded from
  /// [TvCatalogCardGrid.initialFocusedId] so a freshly built grid already knows
  /// where DOWN out of the header belongs, before anything has been focused at
  /// all.
  String? _focusedId;

  /// The last resolved grid, so a focus change can turn a card index into a
  /// visible range without re-deriving the column count from the viewport.
  TvCatalogGrid? _grid;

  /// The row the poster window is centred on (CAT18). Moves with the focus,
  /// but only every few rows; see [tvCatalogArtworkShouldRecenter].
  ///
  /// A notifier rather than state: a recenter re-evaluates each row's
  /// [TvCatalogArtworkScope] and nothing else, so only the rows whose
  /// `drawArtwork` flips rebuild, not every card of the list. Created on the
  /// first build, when the column count that turns the focus into a row is
  /// known.
  ValueNotifier<int>? _artworkCenter;

  /// The card height that went with [_grid], kept beside it for the same
  /// reason: [_keepFocusRingVisible] needs the row pitch and must not re-derive
  /// it from a viewport that may already have changed.
  double? _cardHeight;

  /// Used when the caller hands in no controller of its own.
  ///
  /// The grid needs to be able to read and correct its own scroll offset
  /// (CAT10), and a `SingleChildScrollView` without a controller keeps its
  /// position where nothing else can reach it. A standalone mount — a golden, a
  /// focus test — is exactly the case that used to have no controller at all,
  /// and it is also the mount where the correction went unnoticed the longest.
  ScrollController? _fallbackController;

  ScrollController get _controller => widget.controller ?? (_fallbackController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _focusedId = _restoredId();
    _loadEagerly();
  }

  /// The list length at the last eager request. A round that added nothing
  /// (slow or failing source) must not be asked again in a loop: the focus
  /// look-ahead still resumes it once the viewer nears the end.
  int _eagerRequestedAt = -1;

  void _loadEagerly() {
    if (!widget.loadEagerly || widget.itemIds.length >= TvCatalogCardGrid.eagerLoadLimit) return;
    if (widget.itemIds.length == _eagerRequestedAt) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.loadEagerly || !widget.hasMore || widget.isLoadingMore) return;
      _eagerRequestedAt = widget.itemIds.length;
      widget.onLoadMore();
    });
  }

  /// The remembered card, but only while it is still in the list.
  String? _restoredId() {
    final wanted = widget.initialFocusedId;
    if (wanted == null) return null;
    return widget.itemIds.contains(wanted) ? wanted : null;
  }

  @override
  void didUpdateWidget(TvCatalogCardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _preserveFocusedRow(previous: oldWidget.itemIds);
    _reconcileNodes(previous: oldWidget.itemIds);
    if (focusPositionsChanged(oldWidget.itemIds, widget.itemIds)) {
      final node = _nodes[_focusedId] ?? _nodes.values.firstOrNull;
      if (node != null) clearFocusHistory(node);
    }
    // The first page can land after this grid was built empty, which is the
    // ordinary case on a restored mount: the remembered card only becomes
    // resolvable once it is actually in the list.
    _focusedId ??= _restoredId();
    _loadEagerly();
    // A finished load can leave the focus inside the threshold again (fast
    // scrolling, or a short page); no focus event will follow, so re-check.
    final focusedId = _focusedId;
    if (!widget.loadEagerly && oldWidget.isLoadingMore && !widget.isLoadingMore && focusedId != null) {
      final index = widget.itemIds.indexOf(focusedId);
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeLoadMore(index);
        });
      }
    }
  }

  @override
  void dispose() {
    _fallbackController?.dispose();
    _artworkCenter?.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Focuses the first card, for the header's DOWN exit (hoofdstuk 7.4: "Down
  /// vanaf header gaat naar het laatst gefocuste griditem").
  ///
  /// Prefers the remembered card and falls back to the first one, so returning
  /// from a detail page or closing a panel lands where the user was rather than
  /// at the top-left every time.
  void focusGrid() {
    final remembered = _focusedId ?? _restoredId();
    final node = (remembered != null ? _nodes[remembered] : null) ?? _nodes[widget.itemIds.firstOrNull];
    if (node != null && node.canRequestFocus) requestFocusClearingDirectionalHistory(node);
  }

  /// Focuses the very first card, whatever was remembered, for a choice that
  /// replaced the wall.
  void focusFirstCard() {
    final first = widget.itemIds.firstOrNull;
    if (first != null) focusItem(first);
  }

  /// Puts the focus on one named card, or reports that it could not — same
  /// contract as [TvDiscoveryRailState.focusGroup]: a card scrolled out of a
  /// virtualized range has no node yet, and the caller decides what a false
  /// means (for restoration, a further fallback).
  bool focusItem(String id) {
    final node = _nodes[id];
    if (node == null || !node.canRequestFocus) return false;
    _focusedId = id;
    // Before the focus: a jump far down must find its row drawing a poster on
    // the first frame it is on screen.
    final columns = _grid?.columns ?? 0;
    if (columns > 0) _recenterArtwork(widget.itemIds.indexOf(id) ~/ columns);
    requestFocusClearingDirectionalHistory(node);
    return true;
  }

  bool get hasFocusableCard => _nodes.values.any((node) => node.canRequestFocus);

  FocusNode _nodeFor(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: '${widget.nodeDebugLabel}($id)'));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _buildForWidth(context, constraints.maxWidth, constraints.maxHeight),
  );

  Widget _buildForWidth(BuildContext context, double width, double height) {
    final scale = TvLayoutConstants.scaleOf(context);
    final grid = widget.gridResolver?.call(width, height) ?? _resolveGrid(width, height, scale);
    _grid = grid;
    final cardHeight = widget.cardHeight(grid.cardWidth);
    _cardHeight = cardHeight;
    final rows = <Widget>[];
    final focusedIndex = _focusedId == null ? -1 : widget.itemIds.indexOf(_focusedId!);
    final artworkCenter = _artworkCenter ??= ValueNotifier(focusedIndex < 0 ? 0 : focusedIndex ~/ grid.columns);

    for (var start = 0; start < widget.itemIds.length; start += grid.columns) {
      final end = (start + grid.columns).clamp(0, widget.itemIds.length);
      final row = start ~/ grid.columns;
      rows.add(
        // Its own layer, so a scroll frame or a focus scale repaints one row
        // at most rather than every card in the column.
        RepaintBoundary(
          child: ValueListenableBuilder<int>(
            valueListenable: artworkCenter,
            builder: (context, centerRow, child) => TvCatalogArtworkScope(
              drawArtwork: tvCatalogArtworkRowInWindow(row: row, centerRow: centerRow),
              child: child!,
            ),
            child: _buildRow(grid: grid, start: start, end: end, isFirstRow: start == 0),
          ),
        ),
      );
    }

    final scrollView = SingleChildScrollView(
      controller: _controller,
      // A bottom inset as well as the side ones. Hoofdstuk 8.1: "geen tekst of
      // focusring binnen de buitenste 56 pixels". With only the horizontal
      // padding the last row's count line and the partial-coverage notice sat
      // some 18 logical pixels off the bottom edge — inside the overscan band on
      // a real set, which is where a warning that the catalogue is incomplete is
      // the worst thing to lose. Focus is the sharper case: directional
      // traversal scrolls with `keepVisibleAtEnd`, so a focused bottom-row card
      // parked its ring flush against the viewport edge at zero margin.
      // The top inset is the same problem seen from the other end, and it was
      // missed the first time: a focused card scales up about its centre, so
      // row one's ring reaches *above* the first row's box. At zero top
      // padding the scroll viewport clipped it, and the row the remote lands
      // on first was the one row whose focus ring had no top edge.
      padding: grid.scrollPadding(cardHeight: cardHeight, focusScale: widget.focusScale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: grid.rowGutter), rows[i]],
          if (widget.footer != null) ...[SizedBox(height: grid.rowGutter), widget.footer!],
        ],
      ),
    );
    final topInset = grid.topInset;
    if (topInset == null) return scrollView;
    return ClipRect(
      clipper: TvCatalogRowBandClipper(
        top: math.max(0, topInset - grid.rowGutter),
        bottom: math.max(0, grid.bottomSafeMargin - grid.rowGutter),
      ),
      child: scrollView,
    );
  }

  Widget _buildCell({required TvCatalogGrid grid, required int index, required bool isFirstRow}) {
    final id = widget.itemIds[index];
    final column = index % grid.columns;
    final isFirstColumn = column == 0;
    final isLastRow = index + grid.columns >= widget.itemIds.length;

    // A local ValueKey cannot move a card between different Row parents.
    // Reparent the existing cell with its already-owned node, preserving its
    // focus decoration and artwork state when a late source shifts a row.
    return KeyedSubtree(
      key: _TvCatalogCellKey(_nodeFor(id)),
      child: widget.itemBuilder(
        context,
        TvCatalogGridCell(
          index: index,
          width: grid.cardWidth,
          focusNode: _nodeFor(id),
          onFocusChange: (hasFocus) {
            if (!hasFocus) return;
            _focusedId = id;
            _recenterArtwork(index ~/ grid.columns);
            widget.onFocusedIdChanged?.call(id);
            _keepFocusRingVisible(index);
            widget.onFocusedCell?.call(index, grid);
            _maybeLoadMore(index);
          },
          onNavigateUp: isFirstRow
              ? widget.onExitTop
              : widget.rowAligned
              ? () => _moveToRow(index, grid.columns, -1)
              : null,
          // DOWN on the last row is the *backstop*, not the trigger any more —
          // see [_maybeLoadMore], which fires two rows earlier. It fires the load
          // and keeps focus exactly where it is: hoofdstuk 28 forbids a reflow,
          // and moving focus to a card that does not exist yet is the reset this
          // whole widget is built to avoid.
          onNavigateDown: isLastRow
              ? (widget.hasMore && !widget.isLoadingMore ? widget.onLoadMore : null)
              : widget.rowAligned
              ? () => _moveToRow(index, grid.columns, 1)
              : null,
          onNavigateLeft: isFirstColumn ? widget.onExitLeft : null,
          // The end of the list is an end: a short last row has cards above it to
          // the right, and the traversal would take the nearest of those.
          onNavigateRight: index == widget.itemIds.length - 1 ? () {} : null,
          onBack: widget.onBack,
        ),
      ),
    );
  }
}

/// Private key type prevents collisions with other uses of the same node.
class _TvCatalogCellKey extends GlobalObjectKey {
  const _TvCatalogCellKey(FocusNode super.value);
}
