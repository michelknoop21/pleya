/// One filmography title on a TV-native person surface (MOC-25, PB-14,
/// mockup 25).
///
/// The adapter half of [TvCatalogCard] for a plain, single-server
/// [MediaItem]: `fetchPersonMediaPage` returns no per-item character/role and
/// no provider id to group across servers (PB-14's `CanonicalPersonIdentity`
/// needs a per-person provider-id lookup neither backend mapper does today),
/// so unlike [TvUnifiedMediaCard] there is no group to resolve and no source
/// badge, and unlike [TvCollectionItemCard] there is no position to draw.
/// What remains is the shared catalog language: poster, watched badge, resume
/// bar, title, meta line.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../utils/layout_constants.dart';
import '../optimized_media_image.dart';
import 'tv_catalog_card.dart';
import 'tv_catalog_meta.dart';

class TvPersonCreditCard extends StatelessWidget {
  const TvPersonCreditCard({
    super.key,
    required this.item,
    required this.width,
    required this.onSelect,
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
  final double width;
  final VoidCallback onSelect;

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
      topRightMarker: item.isWatched ? TvCatalogWatchedBadge(scale: scale) : null,
      progressFraction: _progressFraction(item),
      title: item.displayTitle,
      meta: tvCatalogMetaLine(item),
      onSelect: onSelect,
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

/// Same rule [TvCollectionItemCard] uses: a bar drawn against a guessed
/// duration would be a lie the user can measure against the row next to it.
double? _progressFraction(MediaItem item) {
  final offset = item.viewOffsetMs;
  final duration = item.durationMs;
  if (offset == null || offset <= 0) return null;
  if (duration == null || duration <= 0) return null;
  return (offset / duration).clamp(0.0, 1.0);
}
