part of '../../media_detail_screen.dart';

/// The order of the sections under the hero. Every section has its place here
/// even while it has nothing to show, so a section that comes later has a slot
/// to land in rather than a position to argue about.
enum _TvDetailSlot { cast, reviews, discussions, extras, collections, people, related }

const String _tvDetailViewAllId = '__view_all';

/// The film page's sections and the data they load on approach.
extension _MediaDetailTvSections on _MediaDetailScreenState {
  /// The film detail lives on [TvDetailPage]. A series and a season still have
  /// the rail page: their tabs arrive in a later round.
  bool _tvDetailUsesPage(MediaItem metadata) => metadata.isMovie;

  bool _tvDetailHasPendingSections(MediaItem metadata) => !widget.isOffline && !_tvDetailRelatedRequested;

  Future<void> _loadNextTvDetailSection(MediaItem metadata) async {
    if (_tvDetailSectionLoading || _tvDetailRelatedRequested) return;
    _tvDetailSectionLoading = true;
    _tvDetailRelatedRequested = true;
    try {
      await _loadRelatedHubs();
    } finally {
      _tvDetailSectionLoading = false;
    }
  }

  bool _isTvDetailCollectionHub(MediaHub hub) =>
      (hub.identifier ?? hub.id).toLowerCase().contains('collection') || hub.title.toLowerCase().contains('collection');

  Future<void> _openTvDetailItem(MediaItem item, String sectionId) async {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    await navigateToMediaItem(
      context,
      item,
      onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
      onPlaybackReturned: (played) => unawaited(refreshAfterPlayback(playedItemId: played.id)),
      restoreTarget: TvFocusRestoreTarget(itemId: item.id, containerId: sectionId),
    );
  }

  GlobalKey<MediaContextMenuState> _tvDetailMenuKey(String id) =>
      _tvDetailMenuKeys.putIfAbsent(id, GlobalKey<MediaContextMenuState>.new);

  /// A row of posters. The same card as a catalog row, one line of title.
  TvDetailSection _tvDetailPosterSection({
    required String id,
    required String title,
    required List<MediaItem> items,
    MediaHub? hub,
  }) {
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final width = TvDetailLayout.posterWidth * pt;
    final height = TvCatalogLayout.cardHeight(width, scale, titleLines: 1);
    final fresh = _freshAll(items);
    final client = _getArtworkMediaClient(context);
    final hasViewAll = hub?.more ?? false;
    return TvDetailSection(
      id: id,
      title: title,
      itemIds: [for (final item in fresh) item.id, if (hasViewAll) _tvDetailViewAllId],
      cardWidth: width,
      cardHeight: height,
      footerHeight: TvDetailLayout.cardFooterHeight(width, scale),
      itemBuilder: (context, cell) {
        if (cell.index >= fresh.length) {
          return TvDetailViewAllCard(
            cell: cell,
            height: width / TvCatalogLayout.posterAspectRatio,
            onSelect: () => unawaited(_openTvDetailHub(hub!)),
          );
        }
        final item = fresh[cell.index];
        final menuKey = _tvDetailMenuKey('$id/${item.id}');
        return AutomationNode(
          id: AutomationIds.mediaDetailSectionItem,
          instance: '$id.${cell.index}',
          role: 'list.item',
          focusNode: cell.focusNode,
          child: MediaContextMenu(
            key: menuKey,
            item: item,
            onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
            child: TvPersonCreditCard(
              item: item,
              width: cell.width,
              client: client,
              focusNode: cell.focusNode,
              titleLines: 1,
              autoScroll: false,
              onSelect: () => unawaited(_openTvDetailItem(item, id)),
              onContextMenu: () => menuKey.currentState?.showContextMenu(context),
              onNavigateUp: cell.onNavigateUp,
              onNavigateDown: cell.onNavigateDown,
              onNavigateLeft: cell.onNavigateLeft,
              onNavigateRight: cell.onNavigateRight,
              onFocusChange: cell.onFocusChange,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openTvDetailHub(MediaHub hub) async {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => HubDetailScreen(hub: hub)));
  }

  TvDetailSection _tvDetailCastSection(MediaItem metadata, List<MediaRole> roles) {
    final pt = TvHig.of(context);
    final client = getServerBoundMediaClient(context);
    const id = 'cast';
    return TvDetailSection(
      id: id,
      title: t.discover.cast,
      itemIds: [for (var i = 0; i < roles.length; i++) (roles[i].id ?? '').isEmpty ? 'role-$i' : roles[i].id!],
      cardWidth: TvDetailLayout.portraitSize * pt,
      cardHeight: TvDetailCastCard.height(pt),
      footerHeight: TvDetailCastCard.height(pt) - TvDetailLayout.portraitSize * pt,
      itemBuilder: (context, cell) {
        final role = roles[cell.index];
        return AutomationNode(
          id: AutomationIds.mediaDetailSectionItem,
          instance: '$id.${cell.index}',
          role: 'list.item',
          focusNode: cell.focusNode,
          child: TvDetailCastCard(
            cell: cell,
            role: role,
            client: client,
            onSelect: () {
              SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
              _navigateToActorMedia(
                role,
                restoreTarget: TvFocusRestoreTarget(itemId: role.id ?? '', containerId: id),
              );
            },
          ),
        );
      },
    );
  }

  TvDetailSection _tvDetailExtrasSection(List<MediaItem> extras) {
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final width = TvDetailLayout.wideCardWidth * pt;
    final client = getServerBoundMediaClient(context);
    const id = 'extras';
    return TvDetailSection(
      id: id,
      title: t.discover.extras,
      itemIds: [for (final extra in extras) extra.id],
      cardWidth: width,
      cardHeight: TvDetailLayout.cardHeight(width, scale, aspectRatio: 16 / 9),
      footerHeight: TvDetailLayout.cardFooterHeight(width, scale),
      itemBuilder: (context, cell) {
        final extra = extras[cell.index];
        return AutomationNode(
          id: AutomationIds.mediaDetailSectionItem,
          instance: '$id.${cell.index}',
          role: 'list.item',
          focusNode: cell.focusNode,
          child: TvCatalogCard(
            width: cell.width,
            aspectRatio: 16 / 9,
            titleLines: 1,
            autoScroll: false,
            artwork: TvCatalogArtworkFill(
              child: OptimizedMediaImage(
                client: client,
                imagePath: extra.thumbPath,
                fit: BoxFit.cover,
                fallbackIcon: Symbols.movie_rounded,
              ),
            ),
            title: extra.displayTitle,
            meta: tvCatalogMetaLine(extra),
            onSelect: () => unawaited(_openTvDetailItem(extra, id)),
            focusNode: cell.focusNode,
            onNavigateUp: cell.onNavigateUp,
            onNavigateDown: cell.onNavigateDown,
            onNavigateLeft: cell.onNavigateLeft,
            onNavigateRight: cell.onNavigateRight,
            onFocusChange: cell.onFocusChange,
            semanticLabel: extra.displayTitle,
          ),
        );
      },
    );
  }

  List<TvDetailSection> _tvDetailSections(MediaItem metadata) {
    final hubs = _relatedHubs.where((hub) => hub.items.isNotEmpty).toList();
    final roles = metadata.roles?.where((role) => role.tag.trim().isNotEmpty).toList() ?? const <MediaRole>[];
    TvDetailSection hubSection(MediaHub hub) =>
        _tvDetailPosterSection(id: 'hub:${hub.id}', title: hub.title, items: hub.items, hub: hub);
    return [
      for (final slot in _TvDetailSlot.values)
        ...switch (slot) {
          _TvDetailSlot.cast => [if (roles.isNotEmpty) _tvDetailCastSection(metadata, roles)],
          _TvDetailSlot.reviews => const <TvDetailSection>[],
          _TvDetailSlot.discussions => const <TvDetailSection>[],
          _TvDetailSlot.extras => [if (_extras?.isNotEmpty ?? false) _tvDetailExtrasSection(_extras!)],
          _TvDetailSlot.collections => hubs.where(_isTvDetailCollectionHub).map(hubSection),
          _TvDetailSlot.people => const <TvDetailSection>[],
          _TvDetailSlot.related => hubs.where((hub) => !_isTvDetailCollectionHub(hub)).map(hubSection),
        },
    ];
  }

  Widget _buildTvDetailPage(
    BuildContext context,
    MediaItem metadata,
    KeyEventResult Function(FocusNode, KeyEvent) handleBack,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_tvDetailRevealed && _isTvDetailReadyToReveal(metadata)) {
          _scheduleTvDetailReveal(0, focusPrimaryAction: true);
        }
        final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
        return _wrapTvDetailBody(
          context,
          handleBack,
          Scaffold(
            backgroundColor: Colors.transparent,
            body: TvDetailPage(
              key: _tvDetailPageKey,
              background: TvDetailBackdrop(
                item: metadata,
                client: _getArtworkMediaClient(context),
                localPath: widget.isOffline ? (path) => _offlineArtworkLocalPath(context, path) : null,
              ),
              hero: _buildTvDetailHero(context, metadata, constraints.biggest, hideSpoilers: hideSpoilers),
              sections: _tvDetailSections(metadata),
              onFocusHero: _focusTvDetailActionRow,
              contentGate: (content) => _buildTvDetailRevealGate(content, handleBack),
              hasPendingSections: _tvDetailHasPendingSections(metadata),
              onApproachEnd: () => unawaited(_loadNextTvDetailSection(metadata)),
            ),
          ),
        );
      },
    );
  }
}
