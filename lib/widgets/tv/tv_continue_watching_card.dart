/// One card of the full Verder kijken overview on TV (mockup 38 D): the 16:9
/// picture of the thing you are about to resume, with the title and the status
/// line on it and the resume bar on its bottom edge.
///
/// The catalog card draws a 2:3 poster, and an episode's own picture is a 16:9
/// still: cropped into that slot it shows the middle of a scene, not the show.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item_types.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../utils/continue_watching_labels.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_image_helper.dart' show ImageType;
import '../../theme/mono_tokens.dart';
import '../optimized_media_image.dart';
import 'tv_catalog_card.dart';
import 'tv_expandable_media_tile.dart' show discoveryPosterPath, discoveryWideArtPath;
import 'tv_unified_layout.dart';
import 'tv_unified_media_card.dart' show resumeFractionFor, tvUnifiedMediaCardSourceBadgeKey;

class TvContinueWatchingCard extends StatelessWidget {
  const TvContinueWatchingCard({
    super.key,
    required this.group,
    required this.width,
    required this.onSelect,
    this.onContextMenu,
    this.clientFor,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onFocusChange,
  });

  final UnifiedMediaGroup group;
  final double width;
  final VoidCallback onSelect;
  final VoidCallback? onContextMenu;
  final MediaServerClient? Function(String serverId)? clientFor;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final item = group.representativeSource.item;
    final title = item.isEpisode ? (item.grandparentTitle ?? item.displayTitle) : item.displayTitle;
    final status = continueWatchingStatusLine(item);
    // A title with no wide artwork still gets its picture, not a grey tile.
    final widePath = discoveryWideArtPath(item);
    final artPath = widePath ?? discoveryPosterPath(item);

    return TvCatalogCard(
      width: width,
      aspectRatio: TvCatalogLayout.wideAspectRatio,
      artwork: TvCatalogArtworkFill(
        child: OptimizedMediaImage(
          client: clientFor?.call(group.representativeSource.serverId.value),
          imagePath: artPath,
          fit: BoxFit.cover,
          imageType: widePath == null ? ImageType.poster : (item.isEpisode ? ImageType.thumb : ImageType.art),
          fallbackIcon: Symbols.movie_rounded,
        ),
      ),
      topLeftMarker: group.hasMultipleSources
          ? TvCatalogArtworkBadge(
              key: tvUnifiedMediaCardSourceBadgeKey,
              label: t.unifiedCatalog.sources(count: group.sources.length),
            )
          : null,
      progressFraction: resumeFractionFor(group),
      title: title,
      meta: '',
      overlay: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14 * scale, 28 * scale, 14 * scale, 18 * scale),
          // The overlay is not budgeted in the card height, so a large system
          // text size must not grow it past the picture.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.w600, color: tk.text, height: 1.2),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16 * scale, color: tk.text.withValues(alpha: 0.78), height: 1.25),
                ),
              ],
            ),
          ),
        ),
      ),
      onSelect: onSelect,
      onContextMenu: onContextMenu,
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onFocusChange: onFocusChange,
      // What is drawn is what is read: the series title, then the status line.
      semanticLabel: [
        title,
        status,
        if (group.hasMultipleSources) t.unifiedCatalog.sources(count: group.sources.length),
      ].where((p) => p.isNotEmpty).join(', '),
    );
  }
}
