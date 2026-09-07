/// One source-concrete result in the catalog card language.
///
/// [TvUnifiedMediaCard] is the card for a [UnifiedMediaGroup], and most TV
/// surfaces have one. Zoeken does not, for four of its seven sections:
/// hoofdstuk 16.1 keeps collections, playlists, people and everything it does
/// not name source-concrete, because there is no identity rule to merge them
/// on. Those sections drew a `FocusableMediaCard` list until
/// [DEC-108](../../../docs/DECISIONS.md#dec-108) — the non-TV list widget, on a
/// 10-foot panel, which is the second half of what CAT11 reported.
///
/// So this is the same body with the group half taken out: no source badge,
/// because a concrete item has exactly one source and hoofdstuk 10.3 puts the
/// badge on `> 1` and nowhere else; and no resume bar, because these are
/// containers and people rather than things with a runtime.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../optimized_media_image.dart';
import 'tv_catalog_card.dart';
import 'tv_catalog_meta.dart';

class TvCatalogItemCard extends StatelessWidget {
  const TvCatalogItemCard({
    super.key,
    required this.item,
    required this.width,
    required this.onSelect,
    this.clientFor,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onFocusChange,
    this.semanticLabel,
  });

  final MediaItem item;

  /// Resolved by the rail from the viewport — see [TvCatalogGrid.forWidth].
  final double width;

  final VoidCallback onSelect;

  /// Signs the artwork URL. Null draws the placeholder, which is what an
  /// offline server should look like rather than a broken image.
  final MediaServerClient? Function(String serverId)? clientFor;

  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final ValueChanged<bool>? onFocusChange;
  final String? semanticLabel;

  /// The placeholder that says what kind of thing failed to load, rather than
  /// one generic glyph for a collection, a playlist and a folder alike.
  ///
  /// People have no kind of their own — the neutral model has no person type,
  /// which is why hoofdstuk 16.1's people section is passed through the
  /// projection separately — so they land on the default here.
  IconData get _fallbackIcon => switch (item.kind) {
    MediaKind.collection => Symbols.collections_bookmark_rounded,
    MediaKind.playlist => Symbols.playlist_play_rounded,
    MediaKind.folder => Symbols.folder_rounded,
    _ => Symbols.movie_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return TvCatalogCard(
      width: width,
      artwork: TvCatalogArtworkFill(
        child: OptimizedMediaImage(
          client: item.serverId == null ? null : clientFor?.call(item.serverId!),
          imagePath: item.thumbPath,
          fit: BoxFit.cover,
          fallbackIcon: _fallbackIcon,
        ),
      ),
      title: item.displayTitle,
      meta: tvCatalogMetaLine(item),
      onSelect: onSelect,
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onFocusChange: onFocusChange,
      semanticLabel: semanticLabel,
    );
  }
}
