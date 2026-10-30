part of '../../media_detail_screen.dart';

/// What the TV rail shows and how it reports back to the page.
extension _MediaDetailTvRail on _MediaDetailScreenState {
  double _estimateTvBrowseRailHeight(
    Size size,
    List<MediaHub> hubs, {
    bool includeNextHubPeek = true,
    double tallPosterScale = _tvDetailTallPosterScale,
    double widePosterScaleMultiplier = 1.0,
  }) {
    final svc = SettingsService.instance;
    return TvBrowseRailLayout.estimateHeight(
      size: size,
      hubs: hubs,
      density: svc.read(SettingsService.libraryDensity),
      episodePosterMode: svc.read(SettingsService.episodePosterMode),
      episodePosterModeForHub: _tvDetailEpisodePosterModeForHub,
      widePosterScaleForHub: (hub) => _tvDetailWidePosterScaleForHub(hub) * widePosterScaleMultiplier,
      fullCardLayout: svc.read(SettingsService.tvFullCardLayout),
      tallPosterScale: tallPosterScale,
      includeNextHubPeek: includeNextHubPeek,
      scale: TvLayoutConstants.scaleOf(context),
    );
  }

  double _estimateTvDetailRailHeight(
    Size size,
    List<MediaHub> hubs, {
    required bool showSeasonChips,
    bool includeNextHubPeek = true,
    double tallPosterScale = _tvDetailTallPosterScale,
    double widePosterScaleMultiplier = 1.0,
  }) {
    final hubRailHeight = _estimateTvBrowseRailHeight(
      size,
      hubs,
      includeNextHubPeek: includeNextHubPeek,
      tallPosterScale: tallPosterScale,
      widePosterScaleMultiplier: widePosterScaleMultiplier,
    );
    final railHeight = hubRailHeight > 0 ? hubRailHeight : _estimateTvDetailEmptyRailReserveHeight(size);
    if (!showSeasonChips) return railHeight;
    // PB-4/VIS2: the chip row sits on the rail's header strip and only needs
    // what sticks out above it, at the panel scale the row renders at (SYS-3e).
    return railHeight + _tvDetailSeasonChipOverhang(TvLayoutConstants.scaleOf(context));
  }

  double _estimateTvDetailEmptyRailReserveHeight(Size size) {
    final svc = SettingsService.instance;
    final scale = TvLayoutConstants.scaleOf(context);
    final availableWidth = size.width - TvBrowseRailLayout.horizontalInsetForScale(scale);
    if (availableWidth <= 0) return 0;

    final metrics = TvBrowseRailLayout.metricsForHub(
      hub: MediaHub(
        id: 'detail_empty_rail_reserve',
        title: '',
        type: 'movie',
        items: [MediaItem(id: 'detail_empty_rail_reserve_item', backend: _metadata.backend, kind: MediaKind.movie)],
      ),
      availableWidth: availableWidth,
      density: svc.read(SettingsService.libraryDensity),
      episodePosterMode: svc.read(SettingsService.episodePosterMode),
      fullCardLayout: svc.read(SettingsService.tvFullCardLayout),
      scale: scale,
      tallPosterScale: _tvDetailTallPosterScale,
      widePosterScale: 1.0,
    );
    final sectionHeight = TvBrowseRailLayout.hubSectionHeightFor(scale: scale, activeRailHeight: metrics.height);
    return TvBrowseRailLayout.railTopPaddingForScale(scale) +
        TvBrowseRailLayout.viewportHeightFor(hubCount: 1, scale: scale, sectionHeight: sectionHeight) +
        TvBrowseRailLayout.railBottomPaddingForScale(scale);
  }

  bool _isTvDetailEpisodeHub(MediaHub hub) {
    return hub.id.startsWith(_tvDetailSeasonHubIdPrefix) || hub.id == 'detail_episodes';
  }

  /// The episode rail gets the shared [AutomationIds.mediaDetailEpisodeList]
  /// id, whether it is the flattened `'detail_episodes'` hub or the selected
  /// season's hub. Since PB-4 `_tvDetailHubs()` mounts one season hub at a
  /// time, so the id is never registered twice.
  String? _tvDetailAutomationIdForHub(MediaHub hub, int hubIndex) {
    return _isTvDetailEpisodeHub(hub) ? AutomationIds.mediaDetailEpisodeList : null;
  }

  EpisodePosterMode _tvDetailEpisodePosterModeForHub(MediaHub hub) {
    if (_isTvDetailEpisodeHub(hub)) return EpisodePosterMode.episodeThumbnail;
    return SettingsService.instance.read(SettingsService.episodePosterMode);
  }

  double _tvDetailWidePosterScaleForHub(MediaHub hub) {
    return _tvDetailEpisodeThumbnailScale;
  }

  List<MediaHub> _tvDetailHubs(MediaItem metadata) {
    final hubs = <MediaHub>[];
    if (metadata.isShow && !_showEpisodesDirectly && _seasonsLoadFailed) {
      hubs.add(
        MediaHub(
          id: _tvDetailSeasonsErrorHubId,
          title: t.libraries.groupings.seasons,
          type: 'episode',
          items: const [],
          size: 0,
        ),
      );
    } else if (metadata.isShow && !_showEpisodesDirectly && _seasons.isNotEmpty) {
      // PB-4/DEC-109: one active rail for the selected season, not a hub per
      // season stacked vertically. The season-chips row (`_buildTvDetailSeasonChips`)
      // owns the choice; `_selectedSeasonIndex` is the same field the pre-chips
      // hub-per-season design already used, so this hub's id is stable across a
      // season switch back and forth and `TvBrowseRail`'s own `HubFocusMemory`
      // restores the episode that had focus there.
      final i = _selectedSeasonIndex.clamp(0, _seasons.length - 1);
      final season = _seasons[i];
      final state = _seasonEpisodePager.stateFor(season.id);
      final total = state.totalCount > _episodes.length ? state.totalCount : (season.leafCount ?? _episodes.length);
      // With chips the chip row is this rail's header line (VIS2/37 C): it
      // draws "Afleveringen" itself, so the strip under it stays empty.
      // Without chips (single season) there is nothing else naming it, so the
      // rail keeps the season's own title exactly as it did before PB-4.
      final title = _tvDetailShowsSeasonChips(metadata)
          ? ''
          : (season.title?.isNotEmpty == true ? season.title! : (season.displaySubtitle ?? season.displayTitle));
      hubs.add(
        MediaHub(id: '$_tvDetailSeasonHubIdPrefix$i', title: title, type: 'episode', items: _episodes, size: total),
      );
    } else if (_episodes.isNotEmpty) {
      final total = _allEpisodesTotal > _episodes.length ? _allEpisodesTotal : _episodes.length;
      hubs.add(
        MediaHub(
          id: 'detail_episodes',
          title: t.libraries.groupings.episodes,
          type: 'episode',
          items: _episodes,
          size: total,
        ),
      );
    } else if ((metadata.isShow && _showEpisodesDirectly) || metadata.isSeason) {
      if (_allEpisodesPageError || _isLoadingEpisodes) {
        hubs.add(
          MediaHub(
            id: 'detail_episodes',
            title: t.libraries.groupings.episodes,
            type: 'episode',
            items: const [],
            size: 0,
          ),
        );
      }
    }
    final actors = _tvDetailActorItems(metadata);
    if (actors.isNotEmpty) {
      hubs.add(
        MediaHub(id: _tvDetailActorsHubId, title: t.discover.cast, type: 'person', items: actors, size: actors.length),
      );
    }
    if (_extras != null && _extras!.isNotEmpty) {
      hubs.add(
        MediaHub(
          id: _tvDetailExtrasHubId,
          title: t.discover.extras,
          type: 'clip',
          items: _extras!,
          size: _extras!.length,
        ),
      );
    }
    hubs.addAll(_relatedHubs.where((hub) => hub.items.isNotEmpty));
    return hubs;
  }

  String? _tvDetailInitialHubId(MediaItem metadata) {
    if (metadata.isShow && !_showEpisodesDirectly && _seasons.isNotEmpty) {
      return '$_tvDetailSeasonHubIdPrefix$_selectedSeasonIndex';
    }
    if ((metadata.isShow && _showEpisodesDirectly) || metadata.isSeason) {
      return 'detail_episodes';
    }
    return null;
  }

  String? _tvDetailInitialItemId(MediaItem metadata) {
    if (widget.initialEpisodeId != null) return widget.initialEpisodeId;
    if (!metadata.isShow) return null;
    return _onDeckEpisode?.id;
  }

  List<MediaItem> _tvDetailActorItems(MediaItem metadata) {
    final roles = metadata.roles;
    if (roles == null || roles.isEmpty) return const [];

    return [
      for (var i = 0; i < roles.length; i++)
        if (roles[i].tag.trim().isNotEmpty) _tvDetailActorItem(metadata, roles[i], i),
    ];
  }

  MediaItem _tvDetailActorItem(MediaItem metadata, MediaRole actor, int index) {
    final personId = actor.id?.trim();
    return MediaItem(
      id: personId != null && personId.isNotEmpty ? '${metadata.id}_actor_$personId' : '${metadata.id}_actor_$index',
      backend: metadata.backend,
      kind: MediaKind.unknown,
      title: actor.tag,
      parentTitle: actor.role,
      thumbPath: actor.thumbPath,
      serverId: metadata.serverId,
      serverName: metadata.serverName,
      raw: {if (personId != null && personId.isNotEmpty) _tvDetailActorPersonIdRawKey: personId},
    );
  }

  bool _handleTvDetailRailItemActivated(MediaHub hub, MediaItem item) {
    if (hub.id != _tvDetailActorsHubId) return false;
    final personId = item.raw?[_tvDetailActorPersonIdRawKey];
    if (personId is String && personId.isNotEmpty) {
      _navigateToActorMedia(
        MediaRole(id: personId, tag: item.displayTitle, role: item.parentTitle, thumbPath: item.thumbPath),
      );
    }
    return true;
  }

  void _clearTvDetailFocusedEpisode() {
    if (_tvDetailFocusedEpisode == null) return;
    setStateIfMounted(() {
      _tvDetailFocusedEpisode = null;
    });
  }

  void _setTvDetailActionRowFocus(bool hasFocus) {
    _tvDetailActionRowHasFocus = hasFocus;
    if (hasFocus) _clearTvDetailFocusedEpisode();
  }

  void _focusTvDetailActionRow() {
    _tvDetailActionRowHasFocus = true;
    _clearTvDetailFocusedEpisode();
    _playButtonFocusNode.requestFocus();
  }

  void _handleTvDetailFocusedRailItemChanged(MediaHub hub, MediaItem item) {
    if (_tvDetailActionRowHasFocus) {
      _clearTvDetailFocusedEpisode();
      return;
    }
    if (!_isTvDetailEpisodeHub(hub) || !item.isEpisode) {
      _clearTvDetailFocusedEpisode();
      return;
    }
    if (_tvDetailFocusedEpisode?.id == item.id) return;
    setStateIfMounted(() {
      _tvDetailFocusedEpisode = item;
    });
    if (hub.id == 'detail_episodes') {
      if (!_allEpisodesPageError && _episodes.isNotEmpty && item.id == _episodes.last.id) {
        unawaited(_loadMoreAllEpisodes());
      }
      return;
    }
    if (hub.id == '$_tvDetailSeasonHubIdPrefix$_selectedSeasonIndex' &&
        !_seasonEpisodesPageError &&
        _episodes.isNotEmpty &&
        item.id == _episodes.last.id) {
      unawaited(_loadMoreSeasonEpisodes());
    }
  }

  void _handleTvDetailHubChanged(MediaHub hub, int index) {
    final seasonHubActive = hub.id.startsWith(_tvDetailSeasonHubIdPrefix);
    if (seasonHubActive != _tvDetailSeasonHubActive) {
      setStateIfMounted(() => _tvDetailSeasonHubActive = seasonHubActive);
    }
    if (!_isTvDetailEpisodeHub(hub)) {
      _clearTvDetailFocusedEpisode();
      return;
    }
    if (hub.items.isEmpty) _clearTvDetailFocusedEpisode();
    if (!hub.id.startsWith(_tvDetailSeasonHubIdPrefix)) return;
    final seasonIndex = int.tryParse(hub.id.substring(_tvDetailSeasonHubIdPrefix.length));
    if (seasonIndex == null || seasonIndex < 0 || seasonIndex >= _seasons.length) return;
    final season = _seasons[seasonIndex];
    final state = _seasonEpisodePager.stateFor(season.id);
    final hasLoadedState =
        _seasonEpisodePager.hasState(season.id) && !state.isInitialLoading && !state.initialLoadFailed;
    if (_selectedSeasonIndex == seasonIndex &&
        (hasLoadedState || _episodes.isNotEmpty || _isLoadingSeasonEpisodes || _seasonEpisodesFirstPageError)) {
      return;
    }

    if (hasLoadedState) {
      _seasonEpisodePager.completeFirstPage(season.id, state.items, state.totalCount);
      setStateIfMounted(() {
        _selectedSeasonIndex = seasonIndex;
        _episodes = List.of(_seasonEpisodePager.stateFor(season.id).items);
      });
      unawaited(_prefetchAdjacentSeasonEpisodePages(seasonIndex));
      return;
    }

    setStateIfMounted(() {
      _selectedSeasonIndex = seasonIndex;
      _episodes = const <MediaItem>[];
      _seasonEpisodePager.markFirstPageLoading(season.id);
    });
    unawaited(_fetchSeasonEpisodes(seasonIndex));
    unawaited(_prefetchAdjacentSeasonEpisodePages(seasonIndex));
  }

  /// What the rail should show in a hub's trailing slot: a spinner while the
  /// selected season page loads or a retry tile if it failed. Episode hubs do
  /// not use the legacy "View All" slot; they page in-place on focus.
  TvRailTrailing _tvDetailTrailingState(MediaHub hub) {
    if (hub.id == _tvDetailSeasonsErrorHubId) return TvRailTrailing.error;
    final isFlatten = hub.id == 'detail_episodes';
    final isSeason = hub.id.startsWith(_tvDetailSeasonHubIdPrefix);
    if (!isFlatten && !isSeason) return hub.more ? TvRailTrailing.viewAll : TvRailTrailing.none;
    if (isFlatten) {
      if (_allEpisodesPageError) return TvRailTrailing.error;
      if (_isLoadingEpisodes || _isLoadingAllEpisodes) return TvRailTrailing.loading;
      return TvRailTrailing.none;
    }
    final isSelectedSeason = hub.id == '$_tvDetailSeasonHubIdPrefix$_selectedSeasonIndex';
    if (isSelectedSeason) {
      if (_seasonEpisodesFirstPageError || _seasonEpisodesPageError) return TvRailTrailing.error;
      if (_isLoadingSeasonEpisodes || _isLoadingMoreSeasonEpisodes) return TvRailTrailing.loading;
    }
    return TvRailTrailing.none;
  }

  void _retryTvDetailHub(MediaHub hub) {
    if (hub.id == _tvDetailSeasonsErrorHubId) {
      unawaited(_loadSeasons());
      return;
    }
    if (hub.id == 'detail_episodes') {
      unawaited(_episodes.isEmpty ? _fetchAllEpisodes() : _loadMoreAllEpisodes());
      return;
    }
    if (hub.id.startsWith(_tvDetailSeasonHubIdPrefix)) {
      final seasonIndex = int.tryParse(hub.id.substring(_tvDetailSeasonHubIdPrefix.length));
      if (seasonIndex != null && seasonIndex >= 0 && seasonIndex < _seasons.length) {
        final state = _seasonEpisodePager.stateFor(_seasons[seasonIndex].id);
        unawaited(state.items.isNotEmpty ? _loadMoreSeasonEpisodes() : _fetchSeasonEpisodes(seasonIndex));
      }
    }
  }

  IconData? _getTvDetailHubIcon(MediaHub hub, int index) {
    if (hub.id == _tvDetailSeasonsErrorHubId) return Symbols.error_outline_rounded;
    // An empty title is the chip row's header line; an icon alone would float.
    if (hub.id.startsWith(_tvDetailSeasonHubIdPrefix)) return hub.title.isEmpty ? null : Symbols.tv_rounded;
    if (hub.id == 'detail_episodes') return Symbols.tv_rounded;
    if (hub.id == _tvDetailExtrasHubId) return Symbols.theaters_rounded;
    if (hub.id == _tvDetailActorsHubId) return Symbols.group_rounded;
    return _getRelatedHubIcon(hub);
  }
}
