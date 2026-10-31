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
    return hubRailHeight > 0 ? hubRailHeight : _estimateTvDetailEmptyRailReserveHeight(size);
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

  bool _isTvDetailEpisodeHub(MediaHub hub) => hub.id == 'detail_episodes';

  /// The episode rail gets the shared [AutomationIds.mediaDetailEpisodeList] id.
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
    if (_episodes.isNotEmpty) {
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
    } else if (metadata.isSeason) {
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

  String? _tvDetailInitialHubId(MediaItem metadata) => metadata.isSeason ? 'detail_episodes' : null;

  String? _tvDetailInitialItemId(MediaItem metadata) => widget.initialEpisodeId;

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
    requestFocusClearingDirectionalHistory(_playButtonFocusNode);
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
    if (!_allEpisodesPageError && _episodes.isNotEmpty && item.id == _episodes.last.id) {
      unawaited(_loadMoreAllEpisodes());
    }
  }

  void _handleTvDetailHubChanged(MediaHub hub, int index) {
    if (!_isTvDetailEpisodeHub(hub) || hub.items.isEmpty) _clearTvDetailFocusedEpisode();
  }

  /// What the rail should show in a hub's trailing slot: a spinner while the
  /// episodes page in or a retry tile if that failed. Episode hubs do not use
  /// the legacy "View All" slot; they page in-place on focus.
  TvRailTrailing _tvDetailTrailingState(MediaHub hub) {
    if (hub.id != 'detail_episodes') return hub.more ? TvRailTrailing.viewAll : TvRailTrailing.none;
    if (_allEpisodesPageError) return TvRailTrailing.error;
    if (_isLoadingEpisodes || _isLoadingAllEpisodes) return TvRailTrailing.loading;
    return TvRailTrailing.none;
  }

  void _retryTvDetailHub(MediaHub hub) {
    if (hub.id == 'detail_episodes') unawaited(_episodes.isEmpty ? _fetchAllEpisodes() : _loadMoreAllEpisodes());
  }

  IconData? _getTvDetailHubIcon(MediaHub hub, int index) {
    if (hub.id == 'detail_episodes') return Symbols.tv_rounded;
    if (hub.id == _tvDetailExtrasHubId) return Symbols.theaters_rounded;
    if (hub.id == _tvDetailActorsHubId) return Symbols.group_rounded;
    return _getRelatedHubIcon(hub);
  }
}
