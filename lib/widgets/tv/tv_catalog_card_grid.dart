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

import '../../focus/focus_theme.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';

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

  /// How close to the end of the loaded pages the focus has to get before the
  /// next page is asked for, in grid rows.
  ///
  /// Two, measured in rows rather than in cards because the column count is
  /// 5–7 depending on the panel: two rows is one D-pad press of warning at
  /// the slowest, and it is what turns "press DOWN, wait, then the row
  /// appears" into "the row is already there".
  static const int loadMoreRowThreshold = 2;

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
    _reconcileNodes(previous: oldWidget.itemIds);
    // The first page can land after this grid was built empty, which is the
    // ordinary case on a restored mount: the remembered card only becomes
    // resolvable once it is actually in the list.
    _focusedId ??= _restoredId();
  }

  @override
  void dispose() {
    _fallbackController?.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Keeps the whole of the focused card — ring included — inside the viewport
  /// after directional traversal has had its say (CAT10, and CAT8 at the other
  /// edge).
  ///
  /// The grid does not claim UP and DOWN between its own rows: [_buildCell]
  /// binds `onNavigateUp` only on the first row and `onNavigateDown` only on
  /// the last, so every move *within* the grid falls through to Flutter's
  /// `DirectionalFocusAction` and ends in
  /// `Scrollable.ensureVisible(alignmentPolicy: keepVisibleAtStart)`. That
  /// reveals the card's **resting** box, and the resting box is not what gets
  /// drawn: [FocusableWrapper] scales the card about its centre, so the ring
  /// reaches [TvCatalogGrid.focusHeadroom] beyond the box at both ends.
  ///
  /// [TvCatalogGrid.scrollPadding] reserves exactly that headroom, which is why
  /// the first row is whole at rest — and only at rest. `keepVisibleAtStart`
  /// puts the resting box flush against the viewport, so it scrolls the
  /// reservation itself out of view and the `SingleChildScrollView` clips what
  /// was standing in it. Measured on the tvOS simulator on 7 September 2026:
  /// at rest the top edge of the ring sits at y=445 of 2160 and after DOWN then
  /// UP it is gone, with the rest of the ring 30 physical pixels higher.
  ///
  /// So rather than reveal a different box, this states the range the offset
  /// may be in for the focused row and clamps it there. The upper bound is
  /// where the ring meets the top edge, the lower bound where it meets the
  /// bottom one; a card taller than the viewport keeps the top. It runs after
  /// the frame because that is when traversal has already moved the position —
  /// correcting before it would be overwritten by it.
  void _keepFocusRingVisible(int index) {
    final grid = _grid;
    final cardHeight = _cardHeight;
    if (grid == null || cardHeight == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      if (!position.hasViewportDimension || !position.hasContentDimensions) return;

      final growth = TvCatalogGrid.focusHeadroom(cardHeight: cardHeight, focusScale: widget.focusScale);
      // The row's box inside the scroll content. The top padding is that same
      // growth, so on row zero the two cancel and the bound is simply 0.
      final rowTop = growth + (index ~/ grid.columns) * (cardHeight + grid.gutter);

      final upper = rowTop - growth;
      final lower = rowTop + cardHeight + growth - position.viewportDimension;
      final target = (position.pixels.clamp(math.min(lower, upper), upper) as double).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      if ((target - position.pixels).abs() < 0.5) return;
      position.jumpTo(target);
    });
  }

  /// Asks for the next page once the focus is within
  /// [TvCatalogCardGrid.loadMoreRowThreshold] rows of the end (P11).
  ///
  /// The trigger used to be DOWN on the last row and nothing else — no scroll
  /// listener, no threshold, no background prefetch — so the viewer had to
  /// navigate into the end of the loaded set and then wait, every page, which
  /// is exactly the stall that was reported.
  ///
  /// Focus rather than scroll offset: on this platform focus *is* the cursor.
  /// And it is a threshold rather than a replacement of the DOWN trigger —
  /// that one still stands, one row further down, for the case where `hasMore`
  /// only became true after the focus had already settled at the bottom.
  void _maybeLoadMore(int index) {
    if (!widget.hasMore || widget.isLoadingMore) return;
    final grid = _grid;
    if (grid == null || grid.columns <= 0 || widget.itemIds.isEmpty) return;
    final rows = (widget.itemIds.length / grid.columns).ceil();
    final row = index ~/ grid.columns;
    if (rows - row > TvCatalogCardGrid.loadMoreRowThreshold) return;
    widget.onLoadMore();
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
    if (node != null && node.canRequestFocus) node.requestFocus();
  }

  bool get hasFocusableCard => _nodes.values.any((node) => node.canRequestFocus);

  FocusNode _nodeFor(String id) => _nodes.putIfAbsent(id, () => FocusNode(debugLabel: '${widget.nodeDebugLabel}($id)'));

  /// Drops nodes for items that are gone, and rescues focus if one of them had
  /// it (hoofdstuk 7.6: "kaart verdwijnt door filter/verwijdering →
  /// eerstvolgende buur").
  ///
  /// "Had it" means the ring was on that card at this moment, which is a
  /// narrower thing than [_focusedId]. That field is a *memory*: it is seeded
  /// from [TvCatalogCardGrid.initialFocusedId] before anything has been focused
  /// at all, and it is never cleared when the focus walks out of the grid. So
  /// the replacement is always recorded, because the next [focusGrid] has to
  /// land somewhere sensible, but the focus is only moved when the grid is
  /// holding it.
  ///
  /// CAT17 is what the wider reading cost. A sort change re-pages the catalog,
  /// so the remembered card is routinely absent from the new page one, and the
  /// rescue fired while the viewer was standing in the catalog rail, one frame
  /// after `_withLauncherFocusRestore` had put the ring back on Sortering. The
  /// ring ended on a grid card with the rail still open, and from there the
  /// remote had no way back into it.
  void _reconcileNodes({required List<String> previous}) {
    final live = widget.itemIds.toSet();
    final removed = _nodes.keys.where((id) => !live.contains(id)).toList();
    if (removed.isEmpty) return;

    final focusedId = _focusedId;
    final losesFocus = focusedId != null && removed.contains(focusedId);
    // Read before the dispose loop, while the node is still attached: after it
    // there is nothing left to ask.
    final heldTheFocus = losesFocus && (_nodes[focusedId]?.hasFocus ?? false);
    // Measured against the *old* list: the neighbour a user expects is the card
    // that was next to theirs before the update, and the new list no longer
    // contains the position to measure from.
    final oldIndex = losesFocus ? previous.indexOf(focusedId) : -1;

    for (final id in removed) {
      _nodes.remove(id)?.dispose();
    }
    if (!losesFocus) return;

    final replacement = _nearestSurvivor(previous: previous, from: oldIndex);
    _focusedId = replacement;
    if (!heldTheFocus) return;
    // After the frame that removes the card: the replacement's node may not be
    // attached yet on this one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = replacement == null ? null : _nodes[replacement];
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
      } else {
        // Nothing survived — an empty result after a filter change. Focus goes
        // back up to the controls, which is the only thing left to operate.
        widget.onExitTop?.call();
      }
    });
  }

  /// The nearest still-present item to position [from] in the old list.
  ///
  /// Walks outward, forward first: a tie means the user filtered away a card
  /// with survivors on both sides, and the one *after* it is the one they had
  /// not reached yet — the same tie-break `nextFocusAfterAvailabilityChange`
  /// uses in the source picker, for the same reason.
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

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final grid = TvCatalogGrid.forWidth(
      MediaQuery.sizeOf(context).width,
      scale: scale,
      reservedLeading: widget.reservedLeading,
    );
    _grid = grid;
    final cardHeight = widget.cardHeight(grid.cardWidth);
    _cardHeight = cardHeight;
    final rows = <Widget>[];

    for (var start = 0; start < widget.itemIds.length; start += grid.columns) {
      final end = (start + grid.columns).clamp(0, widget.itemIds.length);
      rows.add(_buildRow(grid: grid, start: start, end: end, isFirstRow: start == 0));
    }

    return SingleChildScrollView(
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
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: grid.gutter), rows[i]],
          if (widget.footer != null) ...[SizedBox(height: grid.gutter), widget.footer!],
        ],
      ),
    );
  }

  Widget _buildRow({required TvCatalogGrid grid, required int start, required int end, required bool isFirstRow}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = start; index < end; index++) ...[
          if (index > start) SizedBox(width: grid.gutter),
          _buildCell(grid: grid, index: index, isFirstRow: isFirstRow),
        ],
        // Keeps the last row left-aligned on the same rhythm as a full one
        // instead of stretching four cards across six columns.
        if (end - start < grid.columns)
          SizedBox(width: (grid.cardWidth + grid.gutter) * (grid.columns - (end - start)) - grid.gutter),
      ],
    );
  }

  Widget _buildCell({required TvCatalogGrid grid, required int index, required bool isFirstRow}) {
    final id = widget.itemIds[index];
    final column = index % grid.columns;
    final isFirstColumn = column == 0;
    final isLastRow = index + grid.columns >= widget.itemIds.length;

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
          _keepFocusRingVisible(index);
          widget.onFocusedCell?.call(index, grid);
          _maybeLoadMore(index);
        },
        onNavigateUp: isFirstRow ? widget.onExitTop : null,
        // DOWN on the last row is the *backstop*, not the trigger any more —
        // see [_maybeLoadMore], which fires two rows earlier. It fires the load
        // and keeps focus exactly where it is: hoofdstuk 28 forbids a reflow,
        // and moving focus to a card that does not exist yet is the reset this
        // whole widget is built to avoid.
        onNavigateDown: isLastRow && widget.hasMore && !widget.isLoadingMore ? widget.onLoadMore : null,
        onNavigateLeft: isFirstColumn ? widget.onExitLeft : null,
        onNavigateRight: null,
        onBack: widget.onBack,
      ),
    );
  }
}
