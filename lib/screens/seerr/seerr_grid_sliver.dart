import 'package:flutter/material.dart';

import '../../focus/focus_theme.dart';
import '../../models/seerr/seerr_media.dart';
import '../../services/settings_service.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/media_grid_delegate.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/sliver_cross_axis_layout_builder.dart';

/// Poster grid shared by discover (search results, genre view) and the expanded
/// view of a single row. Column count follows the library density setting so a
/// seerr grid lines up with the rest of the app.
///
/// TV reserves extra room around each cell: a focused card scales up and draws
/// a ring, and a SliverGrid clips at its own bounds.
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
  final isTv = PlatformDetector.isTV();
  final topPad = isTv ? 8.0 + seerrGridFocusTopPad : 8.0;
  // One left margin on the page, not three (P7). The horizontal 8 here was the
  // worst of the three this screen used: the search field and the filter bar
  // above both sit on `TvLayoutConstants.horizontalInset`, so on TV the results
  // grid started 64 logical pixels to their left — inside the overscan band,
  // and visibly out of line with everything above it. Off TV nothing changes.
  final sideInset = isTv ? TvLayoutConstants.horizontalInset : 8.0;
  return SliverPadding(
    padding: EdgeInsets.fromLTRB(sideInset, topPad, sideInset, 24),
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
            final scaleExtra = FocusTheme.focusScale - 1;
            final ring = 2 * FocusTheme.focusBorderWidth;
            final hReserve = isTv ? geometry.itemWidth * scaleExtra + ring : 0.0;
            final hGap = geometry.spacing + hReserve;
            final w = (crossAxisExtent - hGap * (cols - 1)) / cols;
            final cellHeight = w * 3 / 2 + seerrCardTextExtent;
            final vReserve = isTv ? cellHeight * scaleExtra + ring : 0.0;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: geometry.spacing + vReserve,
                crossAxisSpacing: hGap,
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
                  // A guaranteed way out of the grid's top-left corner. Left
                  // from the first column reaches the top navigation, up from
                  // the first row reaches the search field above — neither of
                  // which the default geometric policy could be relied on to
                  // find (P7).
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
