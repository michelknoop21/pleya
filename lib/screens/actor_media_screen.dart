import 'package:flutter/material.dart';
import '../media/ids.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../mixins/paginated_item_loader.dart';
import '../utils/app_logger.dart';
import '../utils/error_message_utils.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/media_server_http_client.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/optimized_media_image.dart';
import '../utils/media_image_helper.dart';
import '../i18n/strings.g.dart';
import 'base_media_list_detail_screen.dart';
import 'focusable_detail_screen_mixin.dart';
import '../mixins/grid_focus_node_mixin.dart';
import '../focus/focusable_action_bar.dart';
import 'tv/tv_person_screen.dart';

/// Screen to browse all media featuring a specific actor.
class ActorMediaScreen extends StatefulWidget {
  final String actorName;
  final String personId;
  final String? actorThumb;
  final String? characterName;
  final String serverId;
  final String? serverName;
  final MediaBackend backend;

  const ActorMediaScreen({
    super.key,
    required this.actorName,
    required this.personId,
    this.actorThumb,
    this.characterName,
    required this.serverId,
    this.serverName,
    required this.backend,
  });

  @override
  State<ActorMediaScreen> createState() => _ActorMediaScreenState();
}

class _ActorMediaScreenState extends BaseMediaListDetailScreen<ActorMediaScreen>
    with
        GridFocusNodeMixin<ActorMediaScreen>,
        FocusableDetailScreenMixin<ActorMediaScreen>,
        PaginatedItemLoader<MediaItem, ActorMediaScreen> {
  static const int _pageSize = 200;

  /// Tracked separately from [PaginatedItemLoader]'s private loading state,
  /// same split MOC-24's `CollectionDetailScreen` uses: `ensureIndexLoaded`
  /// is fire-and-forget, so this is reset from [onPageLoaded] rather than
  /// awaited.
  bool _isLoadingMoreOnTv = false;

  @override
  void onPageLoaded(int start, List<MediaItem> items) {
    if (_isLoadingMoreOnTv) setState(() => _isLoadingMoreOnTv = false);
  }

  @override
  MediaItem get mediaItem => MediaItem(
    id: '',
    backend: widget.backend,
    kind: MediaKind.unknown,
    serverId: widget.serverId,
    serverName: widget.serverName,
  );

  @override
  String? get itemServerId => widget.serverId;

  @override
  String get title => widget.actorName;

  @override
  String get emptyMessage => t.discover.noContentAvailable;

  @override
  bool get hasItems => totalSize > 0;

  @override
  void dispose() {
    disposePagination();
    disposeFocusResources();
    super.dispose();
  }

  MediaServerClient get _mediaClient => context.getMediaClientForServer(ServerId(widget.serverId));

  @override
  Future<LibraryPage<MediaItem>> fetchPage(int start, int size, AbortController? abort) {
    return _mediaClient.fetchPersonMediaPage(widget.personId, start: start, size: size, abort: abort);
  }

  @override
  void updateItemInLists(String itemId, MediaItem updatedItem) {
    for (final entry in loadedItems.entries) {
      if (entry.value.id == itemId) {
        loadedItems[entry.key] = updatedItem;
        return;
      }
    }
  }

  @override
  Future<void> loadItems() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      items = [];
      resetPaginationState();
    });

    try {
      final initialPage = await loadInitialPageWithStatus(_pageSize);
      if (!initialPage.applied || !mounted) return;
      setState(() {
        items = loadedItems.values.toList();
        isLoading = false;
      });
      appLogger.d('Loaded ${loadedItems.length} of $totalSize items for actor: ${widget.actorName}');
      autoFocusFirstItemAfterLoad();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = friendlyError(e, context: widget.actorName);
        isLoading = false;
      });
    }
  }

  @override
  List<FocusableAction> getAppBarActions() {
    return [];
  }

  Widget _buildActorHeader() {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: OptimizedMediaImage(
                client: _mediaClient,
                imagePath: widget.actorThumb,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                imageType: ImageType.avatar,
                fallbackIcon: Symbols.person_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    widget.actorName,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold),
                    maxLines: 2,
                    overflow: .ellipsis,
                  ),
                  if (widget.characterName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.characterName!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ],
                  if (totalSize > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      totalSize == 1 ? t.unifiedCatalog.oneTitle : t.unifiedCatalog.titleCount(count: totalSize),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformDetector.isAppleTV()) return _buildTvPerson(context);

    return buildDetailScaffold(
      slivers: [
        CustomAppBar(title: Text(widget.actorName), pinned: true, actions: buildFocusableAppBarActions()),
        _buildActorHeader(),
        ...buildStateSlivers(),
        if (hasItems)
          buildSparseFocusableGrid(
            totalItems: totalSize,
            itemAt: (index) => loadedItems[index],
            onRefresh: updateItem,
            onSkeletonVisible: (index) => ensureIndexLoaded(index, pageSize: _pageSize),
          ),
      ],
    );
  }

  /// MOC-25 (PB-14): see `tv/tv_person_screen.dart` for the composition and
  /// for what it deliberately leaves out. This screen keeps owning the data
  /// (paginated filmography); only presentation moves to the TV widget, the
  /// same split MOC-24's `CollectionDetailScreen._buildTvCollection` uses.
  Widget _buildTvPerson(BuildContext context) {
    // PaginatedItemLoader only ever fetches sequentially here (initial page,
    // then `_loadMoreOnTv` appending at the end), so `loadedItems` is dense
    // from 0 and this is never sparse.
    final loadedList = [for (var i = 0; i < loadedItems.length; i++) loadedItems[i]!];

    return TvPersonScreen(
      actorName: widget.actorName,
      actorThumb: widget.actorThumb,
      characterName: widget.characterName,
      items: loadedList,
      totalSize: totalSize,
      isLoading: isLoading,
      isLoadingMore: _isLoadingMoreOnTv,
      errorMessage: errorMessage,
      client: _mediaClient,
      onRetry: loadItems,
      onLoadMore: _loadMoreOnTv,
      onSelectItem: (item) => navigateToMediaItem(context, item, onRefresh: updateItem),
    );
  }

  void _loadMoreOnTv() {
    if (_isLoadingMoreOnTv || loadedItems.length >= totalSize) return;
    setState(() => _isLoadingMoreOnTv = true);
    ensureIndexLoaded(loadedItems.length, pageSize: _pageSize);
  }
}
