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
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';
import 'tv_unified_media_card.dart';

class TvUnifiedMediaGrid extends StatefulWidget {
  const TvUnifiedMediaGrid({
    super.key,
    required this.groups,
    required this.onActivate,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.clientFor,
    this.onExitTop,
    this.onExitLeft,
    this.footer,
    this.controller,
  });

  final List<UnifiedMediaGroup> groups;

  /// Hands one group to the fase-4 activation coordinator. The grid never
  /// chooses a source and never navigates.
  final ValueChanged<UnifiedMediaGroup> onActivate;

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

  @override
  State<TvUnifiedMediaGrid> createState() => TvUnifiedMediaGridState();
}

class TvUnifiedMediaGridState extends State<TvUnifiedMediaGrid> {
  /// Focus nodes by `groupId`; see the library doc for why not by index.
  final Map<String, FocusNode> _nodes = {};

  /// The group that currently holds focus, so a rebuild that drops it knows
  /// where the user was standing.
  String? _focusedGroupId;

  @override
  void didUpdateWidget(TvUnifiedMediaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcileNodes(previous: oldWidget.groups);
  }

  @override
  void dispose() {
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
    final remembered = _focusedGroupId;
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
    final rows = <Widget>[];

    for (var start = 0; start < widget.groups.length; start += grid.columns) {
      final end = (start + grid.columns).clamp(0, widget.groups.length);
      rows.add(_buildRow(grid: grid, start: start, end: end, isFirstRow: start == 0));
    }

    return SingleChildScrollView(
      controller: widget.controller,
      padding: EdgeInsets.symmetric(horizontal: grid.inset),
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
      onFocusChange: (hasFocus) {
        if (hasFocus) _focusedGroupId = group.groupId;
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
