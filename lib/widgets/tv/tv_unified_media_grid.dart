/// The Films/Series poster grid (hoofdstuk 10.2 of
/// docs/tvos-unified-experience.md), on the shared [TvCatalogCardGrid].
///
/// Since [DEC-108](../../../docs/DECISIONS.md#dec-108) the traversal, the
/// focus-node bookkeeping, the paging threshold and the CAT10 scroll clamp all
/// live in that widget, because the kijklijst, Alle aanvragen and Zoeken need
/// exactly the same ones over items that are not [UnifiedMediaGroup]s. Read its
/// library doc for the contract; what is left here is the half only a unified
/// catalog has: the artwork prefetcher, and turning a group into a card.
///
/// The prefetcher is the reason this is still a widget rather than a call site.
/// Building every row eagerly means every card is mounted, so every poster is
/// requested as soon as the page is built — not when it comes into view. What
/// the prefetcher buys is therefore *not* laziness: it is ordering and a
/// ceiling. It warms the cards nearest the user first and holds itself to fewer
/// in-flight requests than `image_cache_service.dart` grants artwork globally,
/// so the warm-up can never occupy every slot and starve the row on screen.
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../services/unified_catalog/unified_artwork_prefetcher.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_catalog_card_grid.dart';
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
    this.onBack,
    this.footer,
    this.controller,
    this.initialFocusedGroupId,
    this.onFocusedGroupChanged,
    this.precache,
    this.reservedLeading = 0,
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

  /// Called when the user nears the last row and more pages exist. Hoofdstuk
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

  /// Menu on a card. Null on a surface where Back belongs to the shell, which
  /// is the resting state; a screen binds it while it has a surface of its own
  /// standing open that the press should close first (CAT17).
  final VoidCallback? onBack;

  /// Drawn under the last row — the count line and the partial-state notice.
  final Widget? footer;

  final ScrollController? controller;

  /// Restoration: the card to come back to, by the stable `groupId`
  /// (hoofdstuk 7.6).
  final String? initialFocusedGroupId;

  /// Reports the card the remote moved to, so a screen that will be torn down
  /// can hand it to whatever outlives it.
  final ValueChanged<String>? onFocusedGroupChanged;

  /// Replaces the artwork warm-up call. Null in production, where the
  /// prefetcher uses `precacheImage`; a test injects its own to assert *which*
  /// posters a focus move warms, without a network.
  @visibleForTesting
  final UnifiedArtworkPrecache? precache;

  /// Width held back before the first column, for CAT5's open controls rail.
  final double reservedLeading;

  @override
  State<TvUnifiedMediaGrid> createState() => TvUnifiedMediaGridState();
}

class TvUnifiedMediaGridState extends State<TvUnifiedMediaGrid> {
  final _gridKey = GlobalKey<TvCatalogCardGridState>();

  late final UnifiedArtworkPrefetcher _prefetcher = UnifiedArtworkPrefetcher(
    clientFor: (serverId) => widget.clientFor?.call(serverId),
    precache: widget.precache,
  );

  @override
  void dispose() {
    _prefetcher.dispose();
    super.dispose();
  }

  /// Warms artwork around the row [index] sits in.
  ///
  /// Driven by focus rather than by scroll offset, because on this platform
  /// focus *is* the cursor: a remote moves the selection and the view follows
  /// it, so the focused card is a truer statement of where the user is than any
  /// pixel offset. The prefetcher adds its own margin on both sides, so a row's
  /// worth of range here is enough.
  void _warmAround(int index, TvCatalogGrid grid) {
    if (widget.groups.isEmpty) return;
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

  /// Focuses the remembered card, or the first one. See
  /// [TvCatalogCardGridState.focusGrid].
  void focusGrid() => _gridKey.currentState?.focusGrid();

  bool get hasFocusableCard => _gridKey.currentState?.hasFocusableCard ?? false;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    return TvCatalogCardGrid(
      key: _gridKey,
      itemIds: [for (final group in widget.groups) group.groupId],
      cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
      controller: widget.controller,
      initialFocusedId: widget.initialFocusedGroupId,
      onFocusedIdChanged: widget.onFocusedGroupChanged,
      onFocusedCell: _warmAround,
      hasMore: widget.hasMore,
      isLoadingMore: widget.isLoadingMore,
      onLoadMore: widget.onLoadMore,
      onExitTop: widget.onExitTop,
      onExitLeft: widget.onExitLeft,
      onBack: widget.onBack,
      reservedLeading: widget.reservedLeading,
      footer: widget.footer,
      nodeDebugLabel: 'TvUnifiedCard',
      itemBuilder: (context, cell) {
        final group = widget.groups[cell.index];
        return TvUnifiedMediaCard(
          key: ValueKey(group.groupId),
          group: group,
          width: cell.width,
          clientFor: widget.clientFor,
          focusNode: cell.focusNode,
          onSelect: () => widget.onActivate(group),
          onContextMenu: widget.onContextMenu == null ? null : () => widget.onContextMenu!(group),
          onFocusChange: cell.onFocusChange,
          onNavigateUp: cell.onNavigateUp,
          onNavigateDown: cell.onNavigateDown,
          onNavigateLeft: cell.onNavigateLeft,
          onNavigateRight: cell.onNavigateRight,
          onBack: cell.onBack,
        );
      },
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
