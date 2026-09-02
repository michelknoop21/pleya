/// The Films/Series poster grid (hoofdstuk 10.2 of
/// docs/tvos-unified-experience.md), and the focus contract of hoofdstuk 7.4
/// and 7.6 that makes it usable with a remote.
///
/// ## Focus is keyed on the group, not on the index
///
/// Hoofdstuk 7.6 is explicit: "group krijgt een extra bron → geen remount en
/// geen focussprong", and a filtered-away card sends focus to its neighbour.
/// A grid that owns a `List<FocusNode>` by position satisfies neither — the
/// fase-3 merge recomputes its group list wholesale on every round, so position
/// 12 can be a different title one frame later, and focus would silently move
/// to whatever slid into the slot.
///
/// So nodes live in a map keyed by [UnifiedMediaGroup.groupId], which the
/// snapshot guarantees is stable across rounds. Paging appends groups and the
/// existing nodes keep their identity untouched; a group that leaves has its
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
/// ## What that costs, and what the prefetcher does about it
///
/// Building every row eagerly means every card is mounted, so every poster is
/// requested as soon as the page is built — not when it comes into view. The
/// prefetcher below therefore does *not* buy laziness here; what it buys is
/// ordering and a ceiling. It warms the cards nearest the user first and holds
/// itself to fewer in-flight requests than `image_cache_service.dart` grants
/// artwork globally, so the warm-up can never occupy every slot and starve the
/// row on screen.
///
/// **Known debt, deliberately not paid in fase 5.** Making the grid lazy is the
/// change that would turn a loaded page of several hundred titles into a
/// viewport's worth of image requests, and it is the change that would make the
/// prefetcher load-bearing rather than merely well-behaved. It is not a
/// swap of one scroll widget for another: it reopens exactly the traversal
/// question the paragraph above settles, on a platform where the only honest
/// verification is hardware that is not available until after fase 10A. It is
/// recorded here rather than attempted.
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../services/unified_catalog/unified_artwork_prefetcher.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';
import 'tv_unified_media_card.dart';

class TvUnifiedMediaGrid extends StatefulWidget {
  const TvUnifiedMediaGrid({
    super.key,
    required this.groups,
    required this.onActivate,
    this.onContextMenu,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.clientFor,
    this.onExitTop,
    this.onExitLeft,
    this.footer,
    this.controller,
    this.initialFocusedGroupId,
    this.onFocusedGroupChanged,
    this.precache,
  });

  final List<UnifiedMediaGroup> groups;

  /// Hands one group to the fase-4 activation coordinator. The grid never
  /// chooses a source and never navigates.
  final ValueChanged<UnifiedMediaGroup> onActivate;

  /// Hoofdstuk 23's menu on a long Select or the context-menu key. Null on a
  /// surface with no actions to offer, which keeps the gesture unarmed rather
  /// than opening an empty panel.
  final ValueChanged<UnifiedMediaGroup>? onContextMenu;

  final bool hasMore;
  final bool isLoadingMore;

  /// Called when the user reaches the last row and more pages exist. Hoofdstuk
  /// 28: no full-page spinner, no reflow — the loaded cards stay exactly where
  /// they are and new rows appear underneath.
  final VoidCallback onLoadMore;

  final MediaServerClient? Function(String serverId)? clientFor;

  /// UP out of the first row (hoofdstuk 7.4: "Up vanaf de eerste gridrij gaat
  /// naar de dichtstbijzijnde headeractie").
  final VoidCallback? onExitTop;

  /// LEFT out of the first column. On the current root shell that is the
  /// sidebar; fase 7 replaces what sits there without changing this contract.
  final VoidCallback? onExitLeft;

  /// Drawn under the last row — the count line and the partial-state notice.
  final Widget? footer;

  final ScrollController? controller;

  /// Restoration: the card to come back to, by the same stable `groupId` the
  /// nodes are keyed on (hoofdstuk 7.6). Ignored when that group is no longer
  /// in [groups] — a title a filter removed cannot be focused, and the first
  /// card is the honest fallback. Same shape as [TvDiscoveryRail]'s, because it
  /// is the same contract seen on a different surface.
  final String? initialFocusedGroupId;

  /// Reports the card the remote moved to, so a screen that will be torn down
  /// can hand it to whatever outlives it. Fires on focus, not on scroll: on
  /// this platform focus *is* the cursor.
  final ValueChanged<String>? onFocusedGroupChanged;

  /// Replaces the artwork warm-up call. Null in production, where the
  /// prefetcher uses `precacheImage`; a test injects its own to assert *which*
  /// posters a focus move warms, without a network.
  @visibleForTesting
  final UnifiedArtworkPrecache? precache;

  @override
  State<TvUnifiedMediaGrid> createState() => TvUnifiedMediaGridState();
}

class TvUnifiedMediaGridState extends State<TvUnifiedMediaGrid> {
  /// Focus nodes by `groupId`; see the library doc for why not by index.
  final Map<String, FocusNode> _nodes = {};

  /// The group that currently holds focus, so a rebuild that drops it knows
  /// where the user was standing. Seeded from
  /// [TvUnifiedMediaGrid.initialFocusedGroupId] so a freshly built grid already
  /// knows where DOWN out of the header belongs, before anything has been
  /// focused at all.
  String? _focusedGroupId;

  @override
  void initState() {
    super.initState();
    _focusedGroupId = _restoredGroupId();
  }

  /// The remembered card, but only while it is still in the list.
  String? _restoredGroupId() {
    final wanted = widget.initialFocusedGroupId;
    if (wanted == null) return null;
    return widget.groups.any((group) => group.groupId == wanted) ? wanted : null;
  }

  late final UnifiedArtworkPrefetcher _prefetcher = UnifiedArtworkPrefetcher(
    clientFor: (serverId) => widget.clientFor?.call(serverId),
    precache: widget.precache,
  );

  /// The last resolved grid, so a focus change can turn a card index into a
  /// visible range without re-deriving the column count from the viewport.
  TvCatalogGrid? _grid;

  @override
  void didUpdateWidget(TvUnifiedMediaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcileNodes(previous: oldWidget.groups);
    // The first page can land after this grid was built empty, which is the
    // ordinary case on a restored mount: the remembered card only becomes
    // resolvable once it is actually in the list.
    _focusedGroupId ??= _restoredGroupId();
  }

  @override
  void dispose() {
    _prefetcher.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Warms artwork around the row [index] sits in.
  ///
  /// Driven by focus rather than by scroll offset, because on this platform
  /// focus *is* the cursor: a remote moves the selection and the view follows
  /// it, so the focused card is a truer statement of where the user is than any
  /// pixel offset. The prefetcher adds its own margin on both sides, so a row's
  /// worth of range here is enough.
  void _warmAround(int index) {
    final grid = _grid;
    if (grid == null || widget.groups.isEmpty) return;
    final row = index ~/ grid.columns;
    final first = row * grid.columns;
    _prefetcher.prefetchAround(
      context: context,
      groups: widget.groups,
      firstVisibleIndex: first,
      lastVisibleIndex: first + grid.columns - 1,
      posterSize: Size(grid.cardWidth, grid.cardWidth / TvCatalogLayout.posterAspectRatio),
    );
  }

  /// Focuses the first card, for the header's DOWN exit (hoofdstuk 7.4: "Down
  /// vanaf header gaat naar het laatst gefocuste griditem").
  ///
  /// Prefers the remembered card and falls back to the first one, so returning
  /// from a detail page or closing a panel lands where the user was rather than
  /// at the top-left every time.
  void focusGrid() {
    final remembered = _focusedGroupId ?? _restoredGroupId();
    final node = (remembered != null ? _nodes[remembered] : null) ?? _nodes[widget.groups.firstOrNull?.groupId];
    if (node != null && node.canRequestFocus) node.requestFocus();
  }

  bool get hasFocusableCard => _nodes.values.any((node) => node.canRequestFocus);

  FocusNode _nodeFor(UnifiedMediaGroup group) =>
      _nodes.putIfAbsent(group.groupId, () => FocusNode(debugLabel: 'TvUnifiedCard(${group.groupId})'));

  /// Drops nodes for groups that are gone, and rescues focus if one of them had
  /// it (hoofdstuk 7.6: "kaart verdwijnt door filter/verwijdering →
  /// eerstvolgende buur").
  void _reconcileNodes({required List<UnifiedMediaGroup> previous}) {
    final live = {for (final group in widget.groups) group.groupId};
    final removed = _nodes.keys.where((id) => !live.contains(id)).toList();
    if (removed.isEmpty) return;

    final focusedId = _focusedGroupId;
    final losesFocus = focusedId != null && removed.contains(focusedId);
    // Measured against the *old* list: the neighbour a user expects is the card
    // that was next to theirs before the update, and the new list no longer
    // contains the position to measure from.
    final oldIndex = losesFocus ? previous.indexWhere((g) => g.groupId == focusedId) : -1;

    for (final id in removed) {
      _nodes.remove(id)?.dispose();
    }
    if (!losesFocus) return;

    final replacement = _nearestSurvivor(previous: previous, from: oldIndex);
    _focusedGroupId = replacement;
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

  /// The nearest still-present group to position [from] in the old list.
  ///
  /// Walks outward, forward first: a tie means the user filtered away a card
  /// with survivors on both sides, and the one *after* it is the one they had
  /// not reached yet — the same tie-break `nextFocusAfterAvailabilityChange`
  /// uses in the source picker, for the same reason.
  String? _nearestSurvivor({required List<UnifiedMediaGroup> previous, required int from}) {
    if (from < 0) return widget.groups.firstOrNull?.groupId;
    final live = {for (final group in widget.groups) group.groupId};
    for (var distance = 1; distance < previous.length; distance++) {
      final after = from + distance;
      if (after < previous.length && live.contains(previous[after].groupId)) return previous[after].groupId;
      final before = from - distance;
      if (before >= 0 && live.contains(previous[before].groupId)) return previous[before].groupId;
    }
    return widget.groups.firstOrNull?.groupId;
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final grid = TvCatalogGrid.forWidth(MediaQuery.sizeOf(context).width, scale: scale);
    _grid = grid;
    final rows = <Widget>[];

    for (var start = 0; start < widget.groups.length; start += grid.columns) {
      final end = (start + grid.columns).clamp(0, widget.groups.length);
      rows.add(_buildRow(grid: grid, start: start, end: end, isFirstRow: start == 0));
    }

    return SingleChildScrollView(
      controller: widget.controller,
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
      padding: EdgeInsets.fromLTRB(grid.inset, grid.focusRingHeadroom, grid.inset, grid.bottomSafeInset),
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
          _buildCard(grid: grid, index: index, isFirstRow: isFirstRow),
        ],
        // Keeps the last row left-aligned on the same rhythm as a full one
        // instead of stretching four cards across six columns.
        if (end - start < grid.columns)
          SizedBox(width: (grid.cardWidth + grid.gutter) * (grid.columns - (end - start)) - grid.gutter),
      ],
    );
  }

  Widget _buildCard({required TvCatalogGrid grid, required int index, required bool isFirstRow}) {
    final group = widget.groups[index];
    final column = index % grid.columns;
    final isFirstColumn = column == 0;
    final isLastRow = index + grid.columns >= widget.groups.length;

    return TvUnifiedMediaCard(
      key: ValueKey(group.groupId),
      group: group,
      width: grid.cardWidth,
      clientFor: widget.clientFor,
      focusNode: _nodeFor(group),
      onSelect: () => widget.onActivate(group),
      onContextMenu: widget.onContextMenu == null ? null : () => widget.onContextMenu!(group),
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        _focusedGroupId = group.groupId;
        widget.onFocusedGroupChanged?.call(group.groupId);
        _warmAround(index);
      },
      onNavigateUp: isFirstRow ? widget.onExitTop : null,
      // DOWN on the last row is what asks for the next page. It fires the load
      // and keeps focus exactly where it is: hoofdstuk 28 forbids a reflow, and
      // moving focus to a card that does not exist yet is the reset this whole
      // widget is built to avoid.
      onNavigateDown: isLastRow && widget.hasMore && !widget.isLoadingMore ? widget.onLoadMore : null,
      onNavigateLeft: isFirstColumn ? widget.onExitLeft : null,
      onNavigateRight: null,
    );
  }
}

/// The line under the grid: how much is loaded, and whether anything is
/// missing (hoofdstuk 10.7 and 29).
///
/// Hoofdstuk 10.7 forbids an exact total before every source stream is
/// exhausted — summing per-server totals would double-count duplicates, which
/// is the entire problem the unified catalog exists to solve. So the count is
/// "N titles loaded" while paging and only becomes "N titles" once the snapshot
/// says it is complete.
class TvUnifiedGridFooter extends StatelessWidget {
  const TvUnifiedGridFooter({
    super.key,
    required this.loadedCount,
    required this.isComplete,
    required this.isLoadingMore,
    required this.failedLibraryCount,
  });

  final int loadedCount;
  final bool isComplete;
  final bool isLoadingMore;

  /// Hoofdstuk 29's partial state. Deliberately a quiet line under the grid and
  /// not a banner over it: the content that *did* load is healthy and is what
  /// the user came for.
  final int failedLibraryCount;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final count = isComplete
        ? (loadedCount == 1 ? t.unifiedCatalog.oneTitle : t.unifiedCatalog.titleCount(count: loadedCount))
        : t.unifiedCatalog.titlesLoaded(count: loadedCount);

    return Padding(
      padding: EdgeInsets.only(bottom: TvCatalogLayout.headerContentGap * scale),
      child: Row(
        children: [
          Text(
            isLoadingMore ? t.unifiedCatalog.loadingMore : count,
            style: TextStyle(
              fontSize: TvCatalogLayout.cardMetaFontSize * scale,
              color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
            ),
          ),
          if (failedLibraryCount > 0) ...[
            SizedBox(width: TvCatalogLayout.actionGap * scale),
            Text(
              failedLibraryCount == 1
                  ? t.unifiedCatalog.states.partialOne
                  : t.unifiedCatalog.states.partialMany(count: failedLibraryCount),
              style: TextStyle(
                fontSize: TvCatalogLayout.cardMetaFontSize * scale,
                // Amber, which hoofdstuk 8.2 allows for exactly this: a status
                // worth noticing that is not an error. Red here would say the
                // page failed, and it did not.
                color: tk.accentAlt,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
