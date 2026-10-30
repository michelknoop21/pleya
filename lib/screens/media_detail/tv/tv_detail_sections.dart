part of '../../media_detail_screen.dart';

/// The order of the sections under the hero. Every section has its place here
/// even while it has nothing to show, so a section that comes later has a slot
/// to land in rather than a position to argue about.
enum _TvDetailSlot { seasons, cast, reviews, discussions, extras, collections, people, related }

const String _tvDetailViewAllId = '__view_all';

/// How many actors get a "Meer met" row of their own, as in 09 and 10.
const int _tvDetailPersonRows = 2;
const int _tvDetailPersonRowSize = 20;

/// The film page's sections and the data they load on approach.
extension _MediaDetailTvSections on _MediaDetailScreenState {
  /// Film and series live on [TvDetailPage]. What is left on the rail page is a
  /// season or an episode that was opened without a series to hang under.
  bool _tvDetailUsesPage(MediaItem metadata) => metadata.isMovie || metadata.isShow;

  List<MediaRole> _tvDetailPersonRoles(MediaItem metadata) => [
    for (final role in metadata.roles ?? const <MediaRole>[])
      if ((role.id ?? '').trim().isNotEmpty) role,
  ].take(_tvDetailPersonRows).toList();

  bool _tvDetailHasPendingSections(MediaItem metadata) {
    if (widget.isOffline) return false;
    if (!_tvDetailRelatedRequested) return true;
    return _tvDetailPersonRoles(metadata).any((role) => !_tvDetailPersonMedia.containsKey(role.id));
  }

  /// One step at a time, in page order: each result moves the end of the page,
  /// and that decides whether the next one is near yet.
  Future<void> _loadNextTvDetailSection(MediaItem metadata) async {
    if (_tvDetailSectionLoading) return;
    _tvDetailSectionLoading = true;
    try {
      if (!_tvDetailRelatedRequested) {
        _tvDetailRelatedRequested = true;
        await _loadRelatedHubs();
        return;
      }
      final client = context.tryGetMediaClientForServer(serverIdOrNull(_metadata.serverId));
      for (final role in _tvDetailPersonRoles(metadata)) {
        final id = role.id!;
        if (_tvDetailPersonMedia.containsKey(id)) continue;
        var items = const <MediaItem>[];
        try {
          final page = await client?.fetchPersonMediaPage(id, start: 0, size: _tvDetailPersonRowSize);
          items = [
            for (final item in page?.items ?? const <MediaItem>[])
              if (item.id != metadata.id) item.copyWith(serverId: _metadata.serverId, serverName: _metadata.serverName),
          ];
        } catch (e) {
          appLogger.d('Person media for the detail page failed', error: e);
        }
        setStateIfMounted(() => _tvDetailPersonMedia[id] = items);
        return;
      }
    } finally {
      _tvDetailSectionLoading = false;
    }
  }

  bool _isTvDetailCollectionHub(MediaHub hub) =>
      (hub.identifier ?? hub.id).toLowerCase().contains('collection') || hub.title.toLowerCase().contains('collection');

  Future<void> _openTvDetailItem(MediaItem item, String sectionId) async {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    // An episode of this very series, on a row of its own page: the page opens
    // the tab it belongs to, a route on top would be this page a second time.
    if (item.isEpisode && item.grandparentId == _metadata.id && _tvDetailOpenEpisode(item)) return;
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
    final inset = TvCatalogLayout.cardContentInset(scale);
    final width = TvDetailLayout.posterWidth * pt + inset * 2;
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
      artworkInset: inset,
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
              centerFooter: true,
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
      title: t.discover.castAndCrew,
      itemIds: [for (var i = 0; i < roles.length; i++) (roles[i].id ?? '').isEmpty ? 'role-$i' : roles[i].id!],
      cardWidth: TvDetailLayout.portraitSize * pt,
      cardHeight: TvDetailCastCard.height(pt),
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

  TvDetailSection _tvDetailReviewSection(List<MediaReview> reviews) {
    final pt = TvHig.of(context);
    const id = 'reviews';
    return TvDetailSection(
      id: id,
      title: t.discover.ratingsAndReviews,
      itemIds: [for (var i = 0; i < reviews.length; i++) '$i'],
      cardWidth: TvDetailLayout.wideCardWidth * pt,
      cardHeight: TvDetailLayout.reviewCardHeight * pt,
      itemBuilder: (context, cell) {
        final review = reviews[cell.index];
        return AutomationNode(
          id: AutomationIds.mediaDetailSectionItem,
          instance: '$id.${cell.index}',
          role: 'list.item',
          focusNode: cell.focusNode,
          child: TvDetailReviewCard(
            cell: cell,
            review: review,
            onSelect: () {
              SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
              _openTvDetailSynopsisPanel(review.text, title: review.source ?? review.author);
            },
          ),
        );
      },
    );
  }

  TvDetailSection _tvDetailExtrasSection(List<MediaItem> extras) {
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final inset = TvCatalogLayout.cardContentInset(scale);
    final width = TvDetailLayout.wideCardWidth * pt + inset * 2;
    final client = getServerBoundMediaClient(context);
    const id = 'extras';
    return TvDetailSection(
      id: id,
      title: t.discover.extras,
      itemIds: [for (final extra in extras) extra.id],
      cardWidth: width,
      cardHeight: TvDetailLayout.cardHeight(width, scale, aspectRatio: 16 / 9),
      artworkInset: inset,
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
            centerFooter: true,
            artwork: TvCatalogArtworkFill(
              child: OptimizedMediaImage(
                client: client,
                imagePath: extra.thumbPath,
                fit: BoxFit.cover,
                fallbackIcon: Symbols.movie_rounded,
              ),
            ),
            title: extra.displayTitle,
            meta: _isTrailerExtra(extra) ? t.discover.trailer : t.discover.extra,
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
          _TvDetailSlot.seasons => [if (metadata.isShow) ?_tvDetailSeasonsSection()],
          _TvDetailSlot.cast => [if (roles.isNotEmpty) _tvDetailCastSection(metadata, roles)],
          _TvDetailSlot.reviews => [if (metadata.reviews.isNotEmpty) _tvDetailReviewSection(metadata.reviews)],
          _TvDetailSlot.discussions => const <TvDetailSection>[],
          _TvDetailSlot.extras => [if (_extras?.isNotEmpty ?? false) _tvDetailExtrasSection(_extras!)],
          _TvDetailSlot.collections => hubs.where(_isTvDetailCollectionHub).map(hubSection),
          _TvDetailSlot.people => [
            for (final role in _tvDetailPersonRoles(metadata))
              // A related hub can already be that actor's row (Plex's "More
              // with …"), and two of those would read as a bug.
              if (!hubs.any((hub) => hub.title.toLowerCase().contains(role.tag.toLowerCase())))
                _tvDetailPosterSection(
                  id: 'person:${role.id}',
                  title: t.discover.moreWithActor(name: role.tag),
                  items: _tvDetailPersonMedia[role.id] ?? const [],
                ),
          ],
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
        if (widget.initialEpisodeId != null && !_initialEpisodePagingDone) _maybeLoadMoreForInitialEpisode();
        if (!_tvDetailRevealed && _isTvDetailReadyToReveal(metadata)) {
          _scheduleTvDetailReveal(0, onRevealed: () => _focusTvDetailOpening(metadata));
        }
        _tvDetailFinishInitialFocus();
        final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
        final onSeason = metadata.isShow && _tvDetailSeasonTabActive;
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
              sections: onSeason ? [_tvDetailEpisodesSection()] : _tvDetailSections(metadata),
              onFocusHero: _focusTvDetailActionRow,
              contentGate: (content) => _buildTvDetailRevealGate(content, handleBack),
              hasPendingSections: !onSeason && _tvDetailHasPendingSections(metadata),
              onApproachEnd: () => unawaited(_loadNextTvDetailSection(metadata)),
            ),
          ),
        );
      },
    );
  }
}
