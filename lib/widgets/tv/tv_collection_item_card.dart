/// One title inside a TV-native collection surface (MOC-24, PB-13, mockup 24).
///
/// The adapter half of [TvCatalogCard] for a concrete, single-server
/// [MediaItem]: a collection never merges across servers (PB-13's "geen
/// cross-server merge"), so unlike [TvUnifiedMediaCard] there is no group to
/// resolve and no source badge to draw. What is specific here is the position
/// number the mockup draws in the top-left corner, and that removing a title
/// is the one per-item action the contract keeps — a bare callback rather
/// than a full context menu, since it is the only option on offer.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../utils/layout_constants.dart';
import '../optimized_media_image.dart';
import 'tv_catalog_card.dart';
import 'tv_catalog_meta.dart';

class TvCollectionItemCard extends StatelessWidget {
  const TvCollectionItemCard({
    super.key,
    required this.item,
    required this.position,
    required this.width,
    required this.onSelect,
    this.onRemove,
    this.client,
    this.focusNode,
    this.autofocus = false,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onFocusChange,
  });

  final MediaItem item;

  /// 1-based order in the collection, drawn as the mockup's corner number.
  final int position;

  final double width;
  final VoidCallback onSelect;

  /// PB-13's "item uit de collectie verwijderen": the only per-item action
  /// this surface offers. Null without owner rights on the server.
  final VoidCallback? onRemove;

  final MediaServerClient? client;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);

    return TvCatalogCard(
      width: width,
      artwork: TvCatalogArtworkFill(
        child: OptimizedMediaImage(
          client: client,
          imagePath: item.thumbPath,
          fit: BoxFit.cover,
          fallbackIcon: Symbols.movie_rounded,
        ),
      ),
      topLeftMarker: TvCatalogArtworkBadge(label: '$position'),
      topRightMarker: item.isWatched ? TvCatalogWatchedBadge(scale: scale) : null,
      progressFraction: _progressFraction(item),
      title: item.displayTitle,
      meta: tvCatalogMetaLine(item),
      onSelect: onSelect,
      onContextMenu: onRemove,
      focusNode: focusNode,
      autofocus: autofocus,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      semanticLabel: item.displayTitle,
      onFocusChange: onFocusChange,
    );
  }
}

/// Resume progress, or null when there is none worth drawing. Same rule
/// [tv_source_row_descriptor.dart]'s private helper uses: a bar drawn against
/// a guessed duration would be a lie the user can measure against the row
/// next to it.
double? _progressFraction(MediaItem item) {
  final offset = item.viewOffsetMs;
  final duration = item.durationMs;
  if (offset == null || offset <= 0) return null;
  if (duration == null || duration <= 0) return null;
  return (offset / duration).clamp(0.0, 1.0);
}
