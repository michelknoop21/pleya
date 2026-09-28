part of '../media_detail_screen.dart';

/// The mobile film/series detail presentation: one scrolling page in the
/// order of northstar 06 (`docs/assets/ios-unified/northstar/06-film-detail.png`)
/// for films and series alike. Northstar 07's tab strip for a series is
/// dropped on Michel's instruction (DEC-131); the episodes, extras, cast and
/// related rows follow the header inline, the way the TV detail stacks its
/// rails. iOS Unified 2026 workitem 5 (I6), `docs/unified-2026-closure.md`
/// §5 row 5. Since DEC-140 the page opens on the portrait poster over its
/// own blurred glow (mockups D-01 and D-03 in `docs/assets/ios-unified/detail-2026/`).
///
/// This is presentation only. Every action it triggers (play, download,
/// watchlist, rate, mark watched, source change) reuses the exact methods
/// `_buildActionButtons`/`_buildUnifiedSourceLine` (`action_buttons.dart`)
/// already call for the TV layout, so behaviour is unchanged and only the
/// composition is new. Season/episode state
/// (`_selectedSeasonIndex`, `_seasonEpisodePager`) stays owned by
/// `_MediaDetailScreenState`, same as today.
extension _MobileMediaDetailView on _MediaDetailScreenState {
  Widget _buildMobileDetailScreen(BuildContext context, MediaItem metadata) {
    final client = _getMediaClientForMetadata(context);
    _scheduleDetailAudioTracksLoad(metadata);
    // Same shell the pre-northstar mobile layout used: OverlaySheetHost owns
    // the back-pop suppression while a sheet (source picker, context menu,
    // rating) is open, and Focus(onKeyEvent: _handleMediaDetailBackKey) is
    // what media_detail_screen_test.dart's back/menu-suppression tests
    // attach to.
    final blockSystemBack = InputModeTracker.shouldBlockSystemBack(context);
    // With Liquid Glass on the CTAs are glass capsules (LG-02); the page
    // itself is the same either way (DEC-140).
    final glass = glassTierFor(context) != GlassTier.off;
    final posterUrl = _mobileImageUrl(context, client, metadata.thumbPath, ImageType.poster);
    final artUrl = _mobileImageUrl(context, client, metadata.artPath, ImageType.art);
    final ambientUrl = posterUrl ?? artUrl;
    final page = Column(
      crossAxisAlignment: .stretch,
      children: [
        MobilePosterHero(
          item: metadata,
          posterUrl: posterUrl,
          fallbackArtUrl: artUrl,
          scoreRow: DetailScoreRow(ratings: metadata.externalRatings),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              _buildMobilePrimaryActions(context, metadata, glass: glass),
              // The only way to change source from the detail page; draws
              // nothing unless the item has alternative sources
              // (`hasAlternativeSources`, action_buttons.dart).
              _buildUnifiedSourceLine(card: true),
              _buildMobileActivityCard(context, metadata),
              if (_detailAudioTracks.isNotEmpty) ...[const SizedBox(height: 10), _buildMobileAudioSelector()],
              const SizedBox(height: 16),
              _buildMobileSynopsisAndCredits(context, metadata),
              if (metadata.isShow) ...[const SizedBox(height: 24), _buildMobileEpisodesSection(context, metadata)],
              if (!widget.isOffline && _extras != null && _extras!.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildMobileSectionTitle(context, t.discover.extras, key: _extrasSectionKey),
                const SizedBox(height: 12),
                _buildExtrasSection(),
              ],
              if (metadata.roles != null && metadata.roles!.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildMobileSectionTitle(context, t.discover.cast, key: _castSectionKey),
                const SizedBox(height: 12),
                _buildCastSection(metadata),
              ],
              for (int i = 0; i < _relatedHubs.length; i++) ...[
                const SizedBox(height: 16),
                HubSection(
                  key: _relatedHubKeys[i],
                  hub: _relatedHubs[i],
                  icon: _getRelatedHubIcon(_relatedHubs[i]),
                  inset: true,
                  onVerticalNavigation: (isUp) => _handleRelatedHubNavigation(i, isUp),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final content = CustomScrollView(
      primary: true,
      slivers: [
        SliverToBoxAdapter(
          child: DetailAmbientBackground(
            image: ambientUrl == null
                ? null
                : CachedNetworkImageProvider(ambientUrl, cacheManager: PlexImageCacheManager.instance),
            child: page,
          ),
        ),
        SliverPadding(padding: .only(bottom: MediaQuery.paddingOf(context).bottom + 16)),
      ],
    );

    return PrimaryScrollController(
      controller: _scrollController,
      child: IosStatusBarTapScrollToTop(
        controller: _scrollController,
        child: OverlaySheetHost(
          canPop: !blockSystemBack,
          child: Focus(
            onKeyEvent: _handleMediaDetailBackKey,
            child: Scaffold(body: Stack(children: [content, _buildMobileGlassHeroBar(context, metadata)])),
          ),
        ),
      ),
    );
  }

  /// Watchers, the live viewer and play counts in one card (D-01/D-03). Reads
  /// what `_loadWatchers` and the Home poll already hold; the Plex, owner and
  /// Tautulli gates stay there, so Jellyfin never gets a card.
  Widget _buildMobileActivityCard(BuildContext context, MediaItem metadata) {
    final session = NowWatchingLine.sessionFor(context, metadata.id, serverIdOrNull(metadata.serverId));
    final onDeck = _onDeckEpisode;
    // Only once the user actually started the series; the on-deck fallback is
    // S1E1 for someone who never watched it.
    final ownProgress =
        metadata.isShow && (metadata.viewedLeafCount ?? 0) > 0 && onDeck?.parentIndex != null && onDeck?.index != null
        ? t.discover.activityOwnProgress(season: onDeck!.parentIndex!, episode: onDeck.index!)
        : null;
    return DetailActivityCard(
      watchers: _watchers?.watchers ?? const [],
      nowWatchingName: session?.userName,
      playCount: _watchStats?.totalPlays,
      viewerCount: _watchStats?.userCount,
      isSeries: metadata.isShow,
      ownProgressLabel: ownProgress,
    );
  }

  /// The URL for [path] at hero size, or null when there is none.
  String? _mobileImageUrl(BuildContext context, MediaServerClient? client, String? path, ImageType type) {
    final url = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: path,
      maxWidth: 1200,
      maxHeight: 1800,
      devicePixelRatio: MediaImageHelper.effectiveDevicePixelRatio(context),
      imageType: type,
    );
    return url.isEmpty ? null : url;
  }

  /// The app bar's more button opens the menu the action row's Meer owns
  /// (`_buildMobilePrimaryActions`, `_contextMenuKey`).
  Widget _buildMobileMoreButton(BuildContext context) {
    return Builder(
      builder: (buttonContext) => GlassCircleButton(
        icon: Icons.more_horiz_rounded,
        tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
        onPressed: () {
          final renderBox = buttonContext.findRenderObject() as RenderBox?;
          final position = renderBox?.localToGlobal(renderBox.size.center(Offset.zero));
          _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
        },
      ),
    );
  }

  /// The LG-02 back/more row, pinned over the page (see [MobileDetailHeroBar]).
  Widget _buildMobileGlassHeroBar(BuildContext context, MediaItem metadata) {
    return MobileDetailHeroBar(
      leading: GlassCircleButton(
        icon: Icons.arrow_back_rounded,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.pop(context, _watchStateChanged),
      ),
      trailing: [if (!widget.isOffline) _buildMobileMoreButton(context)],
    );
  }
}
