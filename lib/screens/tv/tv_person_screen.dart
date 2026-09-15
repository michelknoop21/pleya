/// MOC-25 (PB-14): the TV-native person surface (mockup 25).
///
/// Presentational only — see `actor_media_screen.dart` for the state this
/// renders (paginated filmography) and for why the split mirrors
/// `CollectionDetailScreen._buildTvCollection`: one owner of the data and the
/// actions, a separate TV render tree on top of it.
///
/// ## What the mockup and PB-14's text show that this deliberately does not
/// build yet
///
/// * **`CanonicalPersonIdentity` and any cross-server grouping** — the "over
///   alle servers" meta line, the "N bronnen" badge, unified credits, and the
///   Films/Series rail split. PB-14 itself requires this to rest on
///   "betrouwbare backend- of provider-ids"; neither `PlexMappers.role` nor
///   `JellyfinMappers`'s role mapping carries one today (`MediaRole` only has
///   a server-local `id`), so there is nothing reliable to match on yet. Per
///   PB-14's own fallback — "bewijzen twee bronnen niet betrouwbaar dezelfde
///   persoon, dan blijven ze gescheiden" — every person stays server-scoped
///   this round, which is what the app already does. Building the id lookup
///   is a separate, larger piece of work on both backend mappers, not the
///   composition this item owns.
/// * **Biografie, geboortedatum, beroep.** No client call fetches person
///   detail on either backend today (`MediaServerClient` has only
///   `fetchPersonMediaPage`); PB-14's text gates these fields on the backend
///   "werkelijk" delivering them.
/// * **Per-credit role overlay** ("als Paul Atreides"). `fetchPersonMediaPage`
///   returns plain `MediaItem`s with no character/role field attached.
/// * **The "Volgen" button.** PB-14: a real Follow needs its own
///   persistence/sync contract; until it exists the button doesn't render at
///   all, not even disabled — "er staat geen dood bedieningselement".
/// * **The mockup's "Willekeurig afspelen" button.** `BaseMediaListDetailScreen
///   ._playWithShuffle` (`shufflePlayItems`) only knows how to build a play
///   queue from a collection or a playlist (`MediaListPlaybackLauncher
///   .classifyItem` returns `null` for anything else, including a person's
///   synthetic placeholder `MediaItem`), which is exactly why the desktop
///   `ActorMediaScreen.getAppBarActions()` already renders no play controls
///   today. Wiring the inherited method here would be a dead/erroring button
///   with the same look as the fake "Volgen" this item explicitly rules out.
///   Not in PB-14's contract text either, only in the mockup's decoration.
library;

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../navigation/main_screen_scope.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_image_helper.dart';
import '../../widgets/optimized_media_image.dart';
import '../../widgets/tv/tv_catalog_card_grid.dart';
import '../../widgets/tv/tv_catalog_empty_state.dart';
import '../../widgets/tv/tv_catalog_skeleton_grid.dart';
import '../../widgets/tv/tv_person_credit_card.dart';
import '../../widgets/tv/tv_unified_layout.dart';

class TvPersonScreen extends StatefulWidget {
  const TvPersonScreen({
    super.key,
    required this.actorName,
    required this.actorThumb,
    required this.characterName,
    required this.items,
    required this.totalSize,
    required this.isLoading,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.client,
    required this.onRetry,
    required this.onLoadMore,
    required this.onSelectItem,
  });

  final String actorName;
  final String? actorThumb;
  final String? characterName;

  /// The contiguous loaded prefix, in server order — `PaginatedItemLoader`
  /// only ever fetches sequentially here, same as the collection surface.
  final List<MediaItem> items;

  final int totalSize;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;

  /// For signing item artwork. Null renders the placeholder rather than a
  /// broken image.
  final MediaServerClient? client;

  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final ValueChanged<MediaItem> onSelectItem;

  @override
  State<TvPersonScreen> createState() => _TvPersonScreenState();
}

class _TvPersonScreenState extends State<TvPersonScreen> {
  void _focusTopNavigation() => MainScreenFocusScope.of(context, listen: false)?.focusSidebar();

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
      return TvCatalogEmptyState(title: t.discover.noContentAvailable, body: '');
    }

    return TvCatalogCardGrid(
      itemIds: [for (final item in widget.items) item.id],
      cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
      hasMore: widget.items.length < widget.totalSize,
      isLoadingMore: widget.isLoadingMore,
      onLoadMore: widget.onLoadMore,
      onExitTop: _focusTopNavigation,
      nodeDebugLabel: 'TvPersonCredit',
      itemBuilder: (context, cell) {
        final item = widget.items[cell.index];
        return TvPersonCreditCard(
          key: ValueKey(item.id),
          item: item,
          width: cell.width,
          client: widget.client,
          onSelect: () => widget.onSelectItem(item),
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

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final inset = TvDiscoveryLayout.pageInset * scale;
    final avatarSize = 180.0 * scale;
    final titleCount = widget.totalSize == 1
        ? t.unifiedCatalog.oneTitle
        : t.unifiedCatalog.titleCount(count: widget.totalSize);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 24 * scale, inset, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipOval(
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: OptimizedMediaImage(
                    client: widget.client,
                    imagePath: widget.actorThumb,
                    fit: BoxFit.cover,
                    imageType: ImageType.avatar,
                    fallbackIcon: Symbols.person_rounded,
                  ),
                ),
              ),
              SizedBox(width: 32 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.actorName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 40 * scale, fontWeight: FontWeight.w800, color: tk.text),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      [?widget.characterName, titleCount].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16 * scale, color: tk.text.withValues(alpha: 0.72)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 28 * scale),
        Expanded(child: _buildBody(scale)),
      ],
    );
  }
}
