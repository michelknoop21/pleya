import 'package:flutter/material.dart';

import '../../models/seerr/seerr_media.dart';
import '../../services/settings_service.dart';
import '../../widgets/media_grid_delegate.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/sliver_cross_axis_layout_builder.dart';

/// Poster grid shared by discover (search results, genre view) and the expanded
/// view of a single row. Column count follows the library density setting so a
/// seerr grid lines up with the rest of the app.
///
/// **Off TV only, since [DEC-108](../../../docs/DECISIONS.md#dec-108).** The
/// density setting means something on a desktop window someone resizes and
/// nothing on a fixed 10-foot panel, and following it here is precisely why an
/// item on Aanvragen was a different size from the same item on Alle films
/// (CAT11). On TV both callers now render `TvSeerrDiscoverView`, which resolves
/// its columns from `TvCatalogGrid.forWidth` like every other TV surface.
///
/// The TV branch is gone rather than left standing: an unreachable
/// `PlatformDetector.isTV()` here is how the next reader concludes that TV still
/// runs on `MediaGridGeometry`.
Widget buildSeerrGridSliver({
  required List<SeerrMedia> items,
  required ValueChanged<SeerrMedia> onTap,
  bool hasMore = false,
  bool loadingMore = false,
  VoidCallback? onLoadMore,
  FocusNode? firstItemFocusNode,
  VoidCallback? onExitLeft,
  VoidCallback? onExitTop,
}) {
  return SliverPadding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
    sliver: SettingsBuilder(
      prefs: const [SettingsService.libraryDensity],
      builder: (context) {
        final density = SettingsService.instance.read(SettingsService.libraryDensity);
        return SliverCrossAxisLayoutBuilder(
          builder: (context, crossAxisExtent) {
            final geometry = MediaGridGeometry.resolve(
              context: context,
              crossAxisExtent: crossAxisExtent,
              density: density,
              usePaddingAware: true,
              horizontalPadding: 16,
            );
            final cols = geometry.columnCount;
            final w = (crossAxisExtent - geometry.spacing * (cols - 1)) / cols;
            final cellHeight = w * 3 / 2 + seerrCardTextExtent;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: geometry.spacing,
                crossAxisSpacing: geometry.spacing,
                childAspectRatio: w / cellHeight,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index >= items.length) {
                  return SeerrLoadMoreTile(loading: loadingMore, onActivate: onLoadMore ?? () {}, width: w);
                }
                final media = items[index];
                return SeerrPosterCard(
                  media: media,
                  width: w,
                  focusNode: index == 0 ? firstItemFocusNode : null,
                  onTap: () => onTap(media),
                  // A guaranteed way out of the grid's top-left corner, kept
                  // for the keyboard-driven desktop layouts this still serves.
                  onNavigateLeft: index % cols == 0 ? onExitLeft : null,
                  onNavigateUp: index < cols ? onExitTop : null,
                );
              }, childCount: items.length + (hasMore ? 1 : 0)),
            );
          },
        );
      },
    ),
  );
}
