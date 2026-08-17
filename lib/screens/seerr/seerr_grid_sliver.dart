import 'package:flutter/material.dart';

import '../../focus/focus_theme.dart';
import '../../models/seerr/seerr_media.dart';
import '../../services/settings_service.dart';
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
}) {
  final isTv = PlatformDetector.isTV();
  final topPad = isTv ? 8.0 + seerrGridFocusTopPad : 8.0;
  return SliverPadding(
    padding: EdgeInsets.fromLTRB(8, topPad, 8, 24),
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
                );
              }, childCount: items.length + (hasMore ? 1 : 0)),
            );
          },
        );
      },
    ),
  );
}
