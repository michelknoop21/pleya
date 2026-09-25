/// MOC-24 (PB-13): the TV-native collection surface (mockup 24).
///
/// Presentational only — see `collection_detail_screen.dart` for the state
/// this renders (pagination, play/shuffle/delete) and for why the split
/// mirrors `MediaDetailScreen._buildTvDetailScreen` on the shared movie/show
/// screen: one owner of the data and the actions, a separate TV render tree
/// on top of it.
///
/// ## What the mockup shows that this deliberately does not build
///
/// * **"Vanaf het begin" (restart) and a standalone watched toggle.** Neither
///   exists as functionality anywhere in the app today, on any platform, and
///   PB-13's contract text only requires what already exists: Afspelen,
///   Willekeurig, verwijderen, item verwijderen, laden/fout/opnieuw proberen,
///   de lege staat, paginering.
/// * **The sort chips ("Collectievolgorde", "Jaar", "Titel").**
///   `MediaServerClient.fetchCollectionPage` has no sort parameter on either
///   backend — adding one is a separate, larger piece of work, not the
///   composition this item owns.
/// * **The aggregate runtime and year-range line** ("5u 21m · 2021 tot
///   2024"). Correct only once every item is loaded, which a paginated
///   collection does not guarantee; the loaded-count line
///   (`t.unifiedCatalog.titleCount`) is the honest substitute.
/// * **Missing titles / the "not yet on your servers" request card.** PB-13's
///   own text scopes this out until the backend delivers a real metadata
///   identity for a missing member.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../navigation/main_screen_scope.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_catalog_card_grid.dart';
import '../../widgets/tv/tv_catalog_empty_state.dart';
import '../../widgets/tv/tv_catalog_skeleton_grid.dart';
import '../../widgets/tv/tv_collection_item_card.dart';
import '../../widgets/tv/tv_hero_artwork.dart';
import '../../widgets/tv/tv_panel_primitives.dart';
import '../../widgets/tv/tv_unified_layout.dart';

class TvCollectionScreen extends StatefulWidget {
  const TvCollectionScreen({
    super.key,
    required this.collection,
    required this.items,
    required this.totalSize,
    required this.isLoading,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.client,
    required this.backendLabel,
    required this.onRetry,
    required this.onLoadMore,
    required this.onPlay,
    required this.onShuffle,
    required this.onSelectItem,
    this.onDelete,
    this.onRemoveItem,
  });

  final MediaItem collection;

  /// The contiguous loaded prefix, in server order. `PaginatedItemLoader`
  /// only ever fetches sequentially here (see the owner screen), so this is
  /// never sparse.
  final List<MediaItem> items;

  final int totalSize;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;

  /// For signing item artwork. Null renders the placeholder rather than a
  /// broken image.
  final MediaServerClient? client;

  /// "Plex" / "Jellyfin", for the breadcrumb's concrete-source line (PB-13:
  /// no cross-server merge, so the source is always nameable).
  final String backendLabel;

  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final ValueChanged<MediaItem> onSelectItem;

  /// Delete the collection and remove one item from it. Collections are
  /// canonical server data: null (no owner rights) draws neither action.
  final VoidCallback? onDelete;
  final ValueChanged<MediaItem>? onRemoveItem;

  @override
  State<TvCollectionScreen> createState() => _TvCollectionScreenState();
}

class _TvCollectionScreenState extends State<TvCollectionScreen> {
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'tvCollection_play');
  final FocusNode _shuffleFocusNode = FocusNode(debugLabel: 'tvCollection_shuffle');
  final FocusNode _deleteFocusNode = FocusNode(debugLabel: 'tvCollection_delete');

  @override
  void dispose() {
    _playFocusNode.dispose();
    _shuffleFocusNode.dispose();
    _deleteFocusNode.dispose();
    super.dispose();
  }

  void _focusTopNavigation() => MainScreenFocusScope.of(context, listen: false)?.focusSidebar();

  void _focusActionRow() => _playFocusNode.requestFocus();

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final heroHeight = (size.height * 0.62).clamp(280.0 * scale, 720.0 * scale).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: heroHeight,
              child: _CollectionHero(
                collection: widget.collection,
                size: Size(size.width, heroHeight),
                client: widget.client,
                backendLabel: widget.backendLabel,
                totalSize: widget.totalSize,
                scale: scale,
                playFocusNode: _playFocusNode,
                shuffleFocusNode: _shuffleFocusNode,
                deleteFocusNode: _deleteFocusNode,
                onPlay: widget.onPlay,
                onShuffle: widget.onShuffle,
                onDelete: widget.onDelete,
                onNavigateUp: _focusTopNavigation,
                onNavigateDown: widget.items.isEmpty ? null : _focusGridEntry,
              ),
            ),
            SizedBox(height: 12 * scale),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: TvDiscoveryLayout.pageInset * scale),
              child: Text(
                t.collections.inThisCollection,
                style: TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.w700, color: tk.text),
              ),
            ),
            SizedBox(height: 12 * scale),
            Expanded(child: _buildBody(scale)),
          ],
        );
      },
    );
  }

  /// DOWN out of the action row lands on the first card rather than nowhere:
  /// nothing here owns the grid's focus node directly (`TvCatalogCardGrid`
  /// does, keyed by item id), so this only matters as a signal that a
  /// listener could act on; the grid autofocuses its first card on mount by
  /// the same contract every other catalog surface uses.
  void _focusGridEntry() {}

  Widget _buildBody(double scale) {
    if (widget.errorMessage != null) {
      return TvCatalogEmptyState(
        title: t.unifiedCatalog.states.errorTitle,
        body: widget.errorMessage!,
        actionLabel: t.common.retry,
        onAction: widget.onRetry,
      );
    }

    if (widget.items.isEmpty && widget.isLoading) {
      return const TvCatalogSkeletonGrid();
    }

    if (widget.items.isEmpty) {
      return TvCatalogEmptyState(title: t.collections.empty, body: t.collections.emptyBody);
    }

    return TvCatalogCardGrid(
      itemIds: [for (final item in widget.items) item.id],
      cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
      hasMore: widget.items.length < widget.totalSize,
      isLoadingMore: widget.isLoadingMore,
      onLoadMore: widget.onLoadMore,
      onExitTop: _focusActionRow,
      nodeDebugLabel: 'TvCollectionItem',
      itemBuilder: (context, cell) {
        final item = widget.items[cell.index];
        return TvCollectionItemCard(
          key: ValueKey(item.id),
          item: item,
          position: cell.index + 1,
          width: cell.width,
          client: widget.client,
          onSelect: () => widget.onSelectItem(item),
          onRemove: switch (widget.onRemoveItem) {
            final remove? => () => remove(item),
            null => null,
          },
          focusNode: cell.focusNode,
          onFocusChange: cell.onFocusChange,
          onNavigateUp: cell.onNavigateUp,
          onNavigateDown: cell.onNavigateDown,
          onNavigateLeft: cell.onNavigateLeft,
          onNavigateRight: cell.onNavigateRight,
        );
      },
    );
  }
}

/// The backdrop, breadcrumb, title, description and action row — everything
/// above "In deze collectie".
class _CollectionHero extends StatelessWidget {
  const _CollectionHero({
    required this.collection,
    required this.size,
    required this.client,
    required this.backendLabel,
    required this.totalSize,
    required this.scale,
    required this.playFocusNode,
    required this.shuffleFocusNode,
    required this.deleteFocusNode,
    required this.onPlay,
    required this.onShuffle,
    required this.onNavigateUp,
    this.onDelete,
    required this.onNavigateDown,
  });

  final MediaItem collection;
  final Size size;
  final MediaServerClient? client;
  final String backendLabel;
  final int totalSize;
  final double scale;
  final FocusNode playFocusNode;
  final FocusNode shuffleFocusNode;
  final FocusNode deleteFocusNode;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onDelete;
  final VoidCallback onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final inset = TvDiscoveryLayout.pageInset * scale;
    final genre = (collection.genres ?? const <String>[]).firstOrNull;
    final titleCount = totalSize == 1 ? t.unifiedCatalog.oneTitle : t.unifiedCatalog.titleCount(count: totalSize);
    final breadcrumb = [
      t.collections.collection.toUpperCase(),
      backendLabel,
      if (collection.libraryTitle != null) collection.libraryTitle!,
    ].join('  ·  ');
    final metaLine = [titleCount, ?genre].join('  ·  ');

    return Stack(
      fit: StackFit.expand,
      children: [
        TvHeroArtwork(item: collection, size: size, client: client),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, tk.bg.withValues(alpha: 0.92)],
              stops: const [0.35, 1.0],
            ),
          ),
        ),
        Positioned(
          left: inset,
          right: size.width * 0.38,
          bottom: 28 * scale,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                breadcrumb,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: tk.text.withValues(alpha: 0.72),
                ),
              ),
              SizedBox(height: 8 * scale),
              Text(
                collection.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 40 * scale, fontWeight: FontWeight.w800, color: tk.text),
              ),
              SizedBox(height: 8 * scale),
              Text(
                metaLine,
                style: TextStyle(fontSize: 16 * scale, color: tk.text.withValues(alpha: 0.72)),
              ),
              if ((collection.summary ?? '').isNotEmpty) ...[
                SizedBox(height: 10 * scale),
                Text(
                  collection.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15 * scale, height: 1.35, color: tk.text.withValues(alpha: 0.85)),
                ),
              ],
              SizedBox(height: 20 * scale),
              Wrap(
                spacing: 12 * scale,
                runSpacing: 12 * scale,
                children: [
                  TvPanelButton(
                    scale: scale,
                    label: t.common.play,
                    icon: Symbols.play_arrow_rounded,
                    primary: true,
                    autofocus: true,
                    focusNode: playFocusNode,
                    onPressed: onPlay,
                    onNavigateUp: onNavigateUp,
                    onNavigateRight: () => shuffleFocusNode.requestFocus(),
                    onNavigateDown: onNavigateDown,
                  ),
                  TvPanelButton(
                    scale: scale,
                    label: t.common.shuffle,
                    icon: Symbols.shuffle_rounded,
                    primary: false,
                    focusNode: shuffleFocusNode,
                    onPressed: onShuffle,
                    onNavigateUp: onNavigateUp,
                    onNavigateLeft: () => playFocusNode.requestFocus(),
                    onNavigateRight: onDelete == null ? null : () => deleteFocusNode.requestFocus(),
                    onNavigateDown: onNavigateDown,
                  ),
                  if (onDelete case final delete?)
                    TvPanelButton(
                      scale: scale,
                      label: t.common.delete,
                      icon: Symbols.delete_rounded,
                      primary: false,
                      focusNode: deleteFocusNode,
                      onPressed: delete,
                      onNavigateUp: onNavigateUp,
                      onNavigateLeft: () => shuffleFocusNode.requestFocus(),
                      onNavigateDown: onNavigateDown,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
