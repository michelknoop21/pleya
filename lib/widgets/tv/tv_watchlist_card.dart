/// One kijklijst title on TV, in the catalog language
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108), mockup 34).
///
/// The adapter half of [TvCatalogCard]: it decides which poster, which markers
/// and which two lines a [WatchlistEntry] produces, and the card draws them.
///
/// ## Why a kijklijst card is not `WatchlistCard` on TV
///
/// `WatchlistCard` is a dispatcher: a playable title renders through
/// `FocusableMediaCard` with its real server item and an unresolved one through
/// `WatchlistUnavailableCard`. That is the right answer on a phone, where the
/// point is that a title behaves exactly like the same title anywhere else in
/// the app. It is the wrong one here, because it makes the card's *appearance*
/// depend on whether a lookup has landed: mid-sweep a row held two different
/// card designs, and the two branches were never the catalog's card at all.
///
/// So on TV a kijklijst title is one card in one shape, and availability is a
/// marker on it rather than a different widget. That is also what removes the
/// focus trap the old shape carried — a card that changes widget *type* under
/// the remote unmounts the `Focus` holding the node, which is the bug
/// `_reconcile` in `watchlist_screen.dart` exists to compensate for.
///
/// ## The three states, and the one marker
///
/// | state              | marker                                  |
/// | ------------------ | --------------------------------------- |
/// | unknown / checking | none — nothing is known yet             |
/// | available          | none — available is the normal state    |
/// | notFound           | "Niet beschikbaar" bottom left          |
///
/// There is no tick on an available title, for the reason `WatchlistCard`
/// already gives: in a media app a check reads as watched, finished or
/// selected. And "checking" gets no spinner here either — on a wall of forty
/// posters a scattering of spinners appearing and vanishing is motion the
/// viewer cannot act on, and hoofdstuk 10.2b asks this grid to hold still.
library;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/watchlist_entry.dart';
import '../../utils/media_image_helper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../optimized_media_image.dart';
import 'tv_catalog_empty_state.dart';
import 'tv_catalog_card.dart';
import 'tv_catalog_meta.dart';
import 'tv_unified_layout.dart';

class TvWatchlistCard extends StatelessWidget {
  const TvWatchlistCard({
    super.key,
    required this.entry,
    required this.width,
    required this.onSelect,
    this.clientFor,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onFocusChange,
  });

  final WatchlistEntry entry;
  final double width;

  /// Opens the kijklijst item sheet — request, remove, cancel. The card
  /// navigates nowhere itself.
  final VoidCallback onSelect;

  /// Resolves the client that can sign a resolved match's artwork. Only used
  /// when the entry carries no catalogue poster of its own.
  final MediaServerClient? Function(String serverId)? clientFor;

  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final notFound = entry.availability == WatchlistAvailability.notFound;
    final sources = entry.memberships.length;

    return TvCatalogCard(
      width: width,
      artwork: TvWatchlistArtwork(entry: entry, width: width, clientFor: clientFor),
      // The same rule hoofdstuk 10.3 states for the catalog, read on the
      // kijklijst's own idea of a source: a title on both the Plex watchlist
      // and the Jellyfin favourites is one title held twice. "1 bron" is not a
      // fact worth a capsule.
      topLeftMarker: sources > 1 ? TvCatalogArtworkBadge(label: t.unifiedCatalog.sources(count: sources)) : null,
      bottomLeftMarker: notFound ? TvCatalogArtworkBadge(label: t.watchlist.notAvailable, muted: true) : null,
      title: entry.item.displayTitle,
      meta: tvCatalogMetaLine(entry.item),
      onSelect: onSelect,
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onFocusChange: onFocusChange,
      semanticLabel: tvWatchlistSemanticLabel(entry),
    );
  }
}

/// What VoiceOver reads for one kijklijst card (hoofdstuk 25).
///
/// The same shape as the catalog's: title, then only the facts that are true of
/// this entry. Unavailability is announced because it changes what the viewer
/// can do with the card; "checking" is not, because it is a state of the app
/// rather than of the title, and it resolves on its own.
///
/// Public and pure so the contract is assertable without pumping a widget.
String tvWatchlistSemanticLabel(WatchlistEntry entry) {
  final item = entry.item;
  final sources = entry.memberships.length;
  final parts = <String>[
    item.displayTitle,
    if (item.year != null) '${item.year}',
    if (entry.availability == WatchlistAvailability.notFound) t.watchlist.notAvailable,
    if (sources > 1) t.unifiedCatalog.sources(count: sources),
  ];
  return parts.join(', ');
}

/// The poster of a kijklijst title, from whichever of the two places has one.
///
/// A watchlist entry is a *catalogue* title first: it comes off the Plex
/// discover watchlist or the Jellyfin favourites with an opaque [posterRef]
/// that resolves through the image proxy, and it has that long before any
/// server has been asked whether it holds the title. So the catalogue poster is
/// the primary, and the resolved server item is the fallback for the entries
/// whose source gave no reference at all.
///
/// [WatchlistEntry.posterRef] is deliberately not a ready-made URL — an account
/// token must not end up baked into a persistent image cache key — which is why
/// this goes through [MediaImageHelper.catalogPosterUrl] rather than holding a
/// string.
class TvWatchlistArtwork extends StatelessWidget {
  const TvWatchlistArtwork({super.key, required this.entry, required this.width, this.clientFor});

  final WatchlistEntry entry;
  final double width;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final height = width / TvCatalogLayout.posterAspectRatio;
    final url = MediaImageHelper.catalogPosterUrl(
      entry.posterRef,
      width: (width * dpr).round(),
      height: (height * dpr).round(),
    );

    if (url.isEmpty) {
      final match = entry.lastKnownMatch;
      final serverId = match?.serverId;
      return TvCatalogArtworkFill(
        child: OptimizedMediaImage(
          client: serverId == null ? null : clientFor?.call(serverId),
          imagePath: match?.thumbPath,
          fit: BoxFit.cover,
          fallbackIcon: Symbols.movie_rounded,
        ),
      );
    }

    return TvCatalogArtworkFill(
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        // No fade: the grid builds every card at once, so a per-card animation
        // turns opening the page into forty things moving, and hoofdstuk 10.2b
        // asks this grid to hold still. The fill underneath is the placeholder.
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorBuilder: (context, _, _) => const _ArtworkFallback(),
      ),
    );
  }
}

/// What a card shows when it has no poster to show — the same glyph
/// `OptimizedMediaImage` falls back to, so the two artwork paths above fail
/// alike.
class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Center(
      child: Icon(
        Symbols.movie_rounded,
        color: tk.text.withValues(alpha: TvCatalogLayout.inkTertiary),
        size: TvCatalogEmptyState.iconSize * TvLayoutConstants.scaleOf(context),
      ),
    );
  }
}
