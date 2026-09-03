/// The complete catalogue's three-column poster grid. iOS Unified 2026 fase 3,
/// mockup `03-alle-films.png`.
///
/// Three columns fixed, not derived from the width. Every one of the 26 frozen
/// images is an iPhone 15 Pro, the grid is only ever mounted behind
/// `PlatformDetector.isPhone` (DEC-094), and across the phone range that
/// matters — 320pt to 430pt — three columns is what the northstar draws.
/// Deriving a count would let a 430pt phone quietly render four and stop
/// matching the authority it is measured against.
///
/// Paging is a group count, not an item count: [MobileCatalogGrid] asks for
/// more when the last row comes into view, and `UnifiedCatalogService` decides
/// what "more" means (hoofdstuk 12.3). The footer says which of the three
/// states the merge is in — loading, exhausted, or neither — because a
/// catalogue that just stops has no way of telling a user that it is finished
/// rather than broken.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../media_card_grid_layout.dart';
import 'mobile_media_card.dart';
import 'mobile_media_card_cell.dart';

/// Mockup 03's grid metrics: the page inset and the gap between columns.
const double mobileCatalogGridInset = 16;
const double mobileCatalogGridGutter = 12;
const int mobileCatalogGridColumns = 3;

/// Card width for a [width]-wide viewport.
double mobileCatalogCardWidth(double width) =>
    (width - mobileCatalogGridInset * 2 - mobileCatalogGridGutter * (mobileCatalogGridColumns - 1)) /
    mobileCatalogGridColumns;

class MobileCatalogGrid extends StatelessWidget {
  final List<UnifiedMediaGroup> groups;
  final void Function(UnifiedMediaGroup group) onCardTap;

  const MobileCatalogGrid({super.key, required this.groups, required this.onCardTap});

  @override
  Widget build(BuildContext context) {
    final cardWidth = mobileCatalogCardWidth(MediaQuery.sizeOf(context).width);
    // The same height the rails compute for the same card, rather than
    // `MediaCardGridLayout.cellHeightFor`: that one measures a `MediaCard`,
    // which insets its poster inside the cell, while `MobileMediaCard` draws
    // the poster at its full width. Reusing it here would reserve six points
    // this card never uses and leave a visible gap under every row.
    final cellHeight = cardWidth * 3 / 2 + MediaCardGridLayout.textExtentFor(context);

    return AutomationNode(
      id: AutomationIds.catalogGrid,
      role: 'grid',
      // How many groups the merge has produced so far — the same `child_count`
      // `library.grid` exposes, and the only thing this node can usefully
      // answer. It wraps a sliver, so it has no `RenderBox` and therefore no
      // bounds; a scenario that wants geometry asserts on `catalog.grid.item`,
      // which is a box.
      state: () => {'child_count': groups.length},
      child: SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: mobileCatalogGridInset),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: mobileCatalogGridColumns,
            crossAxisSpacing: mobileCatalogGridGutter,
            mainAxisSpacing: mobileCatalogGridGutter + 6,
            mainAxisExtent: cellHeight,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final group = groups[index];
            return AutomationNode(
              id: AutomationIds.catalogGridItem,
              instance: '$index',
              role: 'grid.item',
              child: MobileMediaCardCell(
                group: group,
                shape: MobileCardShape.portrait,
                width: cardWidth,
                onTap: () => onCardTap(group),
              ),
            );
          }, childCount: groups.length),
        ),
      ),
    );
  }
}

/// What sits under the last row: a spinner while the next page is in flight,
/// nothing once the merge is complete, and a manual "Load more" in between.
///
/// The manual button is not dead weight next to the scroll trigger. It is the
/// recovery path for the one case scrolling cannot reach: a page that came back
/// with too few new groups to fill the viewport, so the grid never scrolls and
/// the trigger never fires again.
class MobileCatalogFooter extends StatelessWidget {
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;

  /// How many participating libraries failed their most recent fetch. The
  /// catalogue keeps working with what the others gave (hoofdstuk 12.6); this
  /// line is what stops a short list from reading as the whole truth.
  final int failedLibraryCount;

  const MobileCatalogFooter({
    super.key,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
    required this.failedLibraryCount,
  });

  @override
  Widget build(BuildContext context) {
    final muted = tokens(context).textMuted;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          if (failedLibraryCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                failedLibraryCount == 1
                    ? t.unifiedCatalog.states.partialOne
                    : t.unifiedCatalog.states.partialMany(count: failedLibraryCount),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
          if (isLoadingMore)
            Semantics(
              label: t.unifiedCatalog.semantics.loadingMore,
              child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (hasMore)
            TextButton(onPressed: onLoadMore, child: Text(t.unifiedCatalog.loadMore)),
        ],
      ),
    );
  }
}
