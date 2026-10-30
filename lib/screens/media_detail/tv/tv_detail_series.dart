part of '../../media_detail_screen.dart';

/// What a series adds to the page: the row of seasons on the Serie tab, the row
/// of episodes on a season tab.
extension _MediaDetailTvSeries on _MediaDetailScreenState {
  /// A season poster, with its name and how many episodes it holds under it.
  TvDetailSection? _tvDetailSeasonsSection() {
    final seasons = _tvDetailHasSeasonTabs ? _freshAll(_seasons) : const <MediaItem>[];
    if (seasons.isEmpty && !_seasonsLoadFailed) return null;
    if (seasons.isEmpty) return _tvDetailSeasonsRetrySection();
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final inset = TvCatalogLayout.cardContentInset(scale);
    final width = TvDetailLayout.posterWidth * pt + inset * 2;
    final client = _getArtworkMediaClient(context);
    return TvDetailSection(
      id: _tvDetailSeasonsSectionId,
      title: t.discover.seasonsHeading(n: seasons.length),
      itemIds: [for (final season in seasons) season.id],
      cardWidth: width,
      cardHeight: TvCatalogLayout.cardHeight(width, scale, titleLines: 1),
      artworkInset: inset,
      itemBuilder: (context, cell) {
        final season = seasons[cell.index];
        final menuKey = _tvDetailMenuKey('$_tvDetailSeasonsSectionId/${season.id}');
        return AutomationNode(
          id: AutomationIds.mediaDetailSectionItem,
          instance: '$_tvDetailSeasonsSectionId.${cell.index}',
          role: 'list.item',
          focusNode: cell.focusNode,
          child: MediaContextMenu(
            key: menuKey,
            item: season,
            onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
            child: TvCatalogCard(
              width: cell.width,
              artwork: TvCatalogArtworkFill(
                child: OptimizedMediaImage(
                  client: client,
                  imagePath: season.thumbPath ?? _metadata.thumbPath,
                  fit: BoxFit.cover,
                  fallbackIcon: Symbols.tv_rounded,
                ),
              ),
              topRightMarker: season.isWatched ? TvCatalogWatchedBadge(scale: scale) : null,
              title: season.title?.isNotEmpty == true ? season.title! : season.displayTitle,
              meta: season.leafCount == null ? '' : t.discover.seasonEpisodes(n: season.leafCount!),
              titleLines: 1,
              autoScroll: false,
              centerFooter: true,
              onSelect: () => _tvDetailOpenSeasonFromPoster(cell.index),
              onContextMenu: () => menuKey.currentState?.showContextMenu(context),
              focusNode: cell.focusNode,
              onNavigateUp: cell.onNavigateUp,
              onNavigateDown: cell.onNavigateDown,
              onNavigateLeft: cell.onNavigateLeft,
              onNavigateRight: cell.onNavigateRight,
              onFocusChange: cell.onFocusChange,
              semanticLabel: season.displayTitle,
            ),
          ),
        );
      },
    );
  }

  /// The seasons did not load: one card that tries again, or the series would
  /// have no way into its episodes.
  TvDetailSection _tvDetailSeasonsRetrySection() {
    final pt = TvHig.of(context);
    return TvDetailSection(
      id: _tvDetailSeasonsSectionId,
      title: t.messages.seasonsLoadFailed,
      itemIds: const ['retry'],
      cardWidth: TvDetailLayout.posterWidth * pt,
      cardHeight: TvDetailLayout.reviewCardHeight * pt,
      itemBuilder: (context, cell) => TvDetailViewAllCard(
        cell: cell,
        label: t.common.retry,
        height: TvDetailLayout.reviewCardHeight * pt,
        onSelect: () => unawaited(_loadSeasons()),
      ),
    );
  }

  double? _tvDetailEpisodeProgress(MediaItem episode) {
    final offset = episode.viewOffsetMs ?? 0;
    final duration = episode.durationMs ?? 0;
    if (offset <= 0 || duration <= 0 || episode.isWatched) return null;
    return (offset / duration).clamp(0.0, 1.0).toDouble();
  }

  void _tvDetailOnEpisodeFocused(MediaItem? episode) {
    if (_tvDetailFocusedEpisode?.id == episode?.id) return;
    setStateIfMounted(() => _tvDetailFocusedEpisode = episode);
  }

  /// Select on an episode of the page you are on. Always plays: Episode Action
  /// "details" asks to see an episode before playing it, and this page is where
  /// it is seen. Handing it to [navigateToMediaItem] opened a second page of
  /// this same series on top of the first.
  void _tvDetailPlayEpisode(MediaItem episode) {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    if (MediaDetailScreen.debugOnPlayEpisode case final hook?) {
      hook(episode);
    } else if (widget.isOffline) {
      unawaited(_handlePlayPressed(episode));
    } else {
      unawaited(_playWithDetailPick(episode));
    }
  }

  /// The season's card and its episodes, or the episodes of a series without
  /// seasons. The first page can still be on its way: the season's own card is
  /// there at once, so a Select on its poster always has somewhere to land.
  TvDetailSection _tvDetailEpisodesSection(MediaItem metadata) {
    final pt = TvHig.of(context);
    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    final episodes = _freshAll(_episodes);
    final failed = _episodeListPageError || _seasonEpisodesFirstPageError;
    final client = _getArtworkMediaClient(context);
    final season = _tvDetailOpenSeason;
    final lead = season == null ? 0 : 1;
    return TvDetailSection(
      id: _tvDetailEpisodesSectionId,
      title: '',
      heldAtTop: true,
      gapBelow: TvDetailLayout.seasonFooterGap,
      itemIds: [?season?.id, for (final episode in episodes) episode.id, if (failed) 'retry'],
      cardWidth: TvDetailLayout.wideCardWidth * pt,
      cardHeight: TvDetailLayout.wideCardHeight * pt,
      hasMore: _episodeListHasMore && !failed,
      isLoadingMore: _episodeListLoadingMore,
      onLoadMore: () => unawaited(_loadMoreEpisodeList()),
      itemBuilder: (context, cell) {
        if (season != null && cell.index == 0) return _buildTvDetailSeasonCard(metadata, season, cell);
        final position = cell.index - lead;
        if (position >= episodes.length) {
          return TvDetailViewAllCard(
            cell: cell,
            label: t.common.retry,
            height: TvDetailLayout.wideCardHeight * pt,
            onSelect: () => unawaited(_fetchSeasonEpisodes(_selectedSeasonIndex)),
          );
        }
        final episode = episodes[position];
        final menuKey = _tvDetailMenuKey('$_tvDetailEpisodesSectionId/${episode.id}');
        return AutomationNode(
          id: AutomationIds.mediaDetailSectionItem,
          instance: '$_tvDetailEpisodesSectionId.${cell.index}',
          role: 'list.item',
          focusNode: cell.focusNode,
          child: MediaContextMenu(
            key: menuKey,
            item: episode,
            onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
            child: TvDetailEpisodeCard(
              cell: cell,
              imagePath: episode.thumbPath,
              client: client,
              badge: t.discover.episodeBadge(number: episode.index ?? position + 1),
              watched: episode.isWatched,
              progress: _tvDetailEpisodeProgress(episode),
              blurred: hideSpoilers && episode.shouldHideSpoiler,
              semanticLabel: episode.title ?? episode.displayTitle,
              onSelect: () => _tvDetailPlayEpisode(episode),
              onContextMenu: () => menuKey.currentState?.showContextMenu(context),
              onFocused: () => _tvDetailOnEpisodeFocused(episode),
            ),
          ),
        );
      },
    );
  }
}
