part of '../media_detail_screen.dart';

/// The mobile film/series detail presentation: one scrolling page in the
/// order of northstar 06 (`docs/assets/ios-unified/northstar/06-film-detail.png`)
/// for films and series alike. Northstar 07's tab strip for a series is
/// dropped on Michel's instruction (DEC-131); the episodes, extras, cast and
/// related rows follow the header inline, the way the TV detail stacks its
/// rails. iOS Unified 2026 workitem 5 (I6), `docs/unified-2026-closure.md`
/// §5 row 5.
///
/// This is presentation only. Every action it triggers (play, download,
/// watchlist, rate, mark watched, source change) reuses the exact methods
/// `_buildActionButtons`/`_buildUnifiedSourceLine` (`action_buttons.dart`)
/// already call for the pre-northstar mobile/TV layout, so behaviour is
/// unchanged and only the composition is new. Season/episode state
/// (`_selectedSeasonIndex`, `_seasonEpisodePager`) stays owned by
/// `_MediaDetailScreenState`, same as today.
extension _MobileMediaDetailView on _MediaDetailScreenState {
  Widget _buildMobileDetailScreen(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);
    final client = _getMediaClientForMetadata(context);
    _scheduleDetailAudioTracksLoad(metadata);
    // Same shell the pre-northstar mobile layout used: OverlaySheetHost owns
    // the back-pop suppression while a sheet (source picker, context menu,
    // rating) is open, and Focus(onKeyEvent: _handleMediaDetailBackKey) is
    // what media_detail_screen_test.dart's back/menu-suppression tests
    // attach to.
    final blockSystemBack = InputModeTracker.shouldBlockSystemBack(context);
    // Liquid Glass (LG-02): the page opens on a full-bleed hero behind the
    // status bar, with the back/more buttons, title, tags and CTAs on it.
    // Since DEC-131 a series shares the film's header, so it gets the hero
    // too. Glass off keeps the DEC-131 tree unchanged.
    final glassHero = glassTierFor(context) != GlassTier.off;
    // The round watchlist button sits next to the film's Download capsule;
    // a series has no Download capsule (download is per episode row), so
    // its toggle stays in the action row.
    final watchlistOnHero = glassHero && !metadata.isShow;
    final content = CustomScrollView(
      primary: true,
      slivers: [
        if (glassHero) SliverToBoxAdapter(child: _buildMobileGlassHero(context, metadata, client)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                // DEC-131: one scrolling page for film and series alike, the
                // order of mockup 06. Mockup 07's tabs (Afleveringen /
                // Vergelijkbaar / Extra's / Details) are gone; a series gets
                // the same header and its episodes, extras, cast and related
                // rows follow inline, like the TV detail. With glass on the
                // header (artwork, title, tags, CTAs) is the hero above.
                if (!glassHero) ...[
                  _buildMobilePreviewCard(context, metadata, client),
                  const SizedBox(height: 16),
                  Text(metadata.displayTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold)),
                  const SizedBox(height: 8),
                  _buildMobileTagsRow(context, metadata),
                  const SizedBox(height: 16),
                  _buildMobilePrimaryCta(context, metadata),
                  // Downloading a series happens per episode row; the
                  // full-width capsule is the film's.
                  if (!metadata.isShow) ...[const SizedBox(height: 10), _buildMobileDownloadCta(context, metadata)],
                ],
                // The only way to change source from the detail page; draws
                // nothing unless the item has alternative sources
                // (`hasAlternativeSources`, action_buttons.dart).
                _buildUnifiedSourceLine(),
                if (_detailAudioTracks.isNotEmpty) ...[const SizedBox(height: 10), _buildMobileAudioSelector()],
                const SizedBox(height: 16),
                _buildMobileSynopsisAndCredits(context, metadata),
                const SizedBox(height: 16),
                _buildMobileActionRow(context, metadata, includeWatchlist: !watchlistOnHero),
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
            child: Scaffold(
              body: glassHero
                  ? Stack(children: [content, _buildMobileGlassHeroBar(context, metadata)])
                  : SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          _buildMobileDetailAppBar(context, metadata),
                          Expanded(child: content),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileDetailAppBar(BuildContext context, MediaItem metadata) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          DesktopAppBarHelper.buildAdjustedLeading(
            // Mockups 06 and 07 draw a bare arrow on the page background, not
            // a disc: the circular style belongs over artwork (the hero
            // overlay, the player), not on this flat 44pt bar.
            AppBarBackButton(style: BackButtonStyle.plain, onPressed: () => Navigator.pop(context, _watchStateChanged)),
            context: context,
          )!,
          Expanded(
            child: Text(
              metadata.displayTitle,
              maxLines: 1,
              overflow: .ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: .w700),
            ),
          ),
          if (!widget.isOffline) _buildMobileMoreButton(context, metadata),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Same trigger `_buildMoreActionsButton` (`action_buttons.dart`) uses on TV
  /// and the pre-northstar mobile layout (`MediaContextMenu` + `_contextMenuKey`),
  /// styled for the app bar instead of the action row: everything the old
  /// row's `⋮` opened (shuffle, request, unmatch, playlist/collection, …)
  /// stays reachable from here rather than gaining a second entry point.
  Widget _buildMobileMoreButton(BuildContext context, MediaItem metadata, {bool glass = false}) {
    final primaryTrailer = _getPrimaryTrailer();
    final onPlayTrailer = primaryTrailer == null
        ? null
        : () => unawaited(navigateToVideoPlayer(context, metadata: primaryTrailer));

    return MediaContextMenu(
      key: _contextMenuKey,
      item: metadata,
      onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
      onPlayTrailer: onPlayTrailer,
      child: Builder(
        builder: (buttonContext) {
          void open() {
            final renderBox = buttonContext.findRenderObject() as RenderBox?;
            final position = renderBox?.localToGlobal(renderBox.size.center(Offset.zero));
            _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
          }

          if (glass) {
            return GlassCircleButton(
              icon: Icons.more_horiz_rounded,
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              onPressed: open,
            );
          }
          return IconButton(onPressed: open, icon: const AppIcon(Symbols.more_vert_rounded, fill: 1));
        },
      ),
    );
  }

  /// The 16:9 trailer preview (mockup 06/07's top card). Falls back to the
  /// item's own artwork when there is no trailer to preview.
  Widget _buildMobilePreviewCard(BuildContext context, MediaItem metadata, MediaServerClient? client) {
    final primaryTrailer = _getPrimaryTrailer();
    final artwork = _buildMobileArtwork(context, metadata, client, maxWidth: 800, maxHeight: 450);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            artwork,
            if (primaryTrailer != null)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => unawaited(navigateToVideoPlayer(context, metadata: primaryTrailer)),
                    child: const Center(
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0x66000000),
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                      ),
                    ),
                  ),
                ),
              ),
            if (primaryTrailer != null)
              Positioned(
                left: 12,
                bottom: 10,
                child: Text(
                  t.discover.extras,
                  style: const TextStyle(color: Colors.white, fontWeight: .w600, shadows: [Shadow(blurRadius: 4)]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The item's own backdrop (or poster), [PlaceholderContainer] while it
  /// loads or when there is none. Shared by the preview card and the glass
  /// hero.
  Widget _buildMobileArtwork(
    BuildContext context,
    MediaItem metadata,
    MediaServerClient? client, {
    required double maxWidth,
    required double maxHeight,
  }) {
    final artworkPath = metadata.artPath ?? metadata.thumbPath;
    if (artworkPath == null) return const PlaceholderContainer();
    final imageUrl = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: artworkPath,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      devicePixelRatio: MediaImageHelper.effectiveDevicePixelRatio(context),
      imageType: ImageType.art,
    );
    if (imageUrl.isEmpty) return const PlaceholderContainer();
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: PlexImageCacheManager.instance,
      fit: BoxFit.cover,
      placeholder: (context, url) => const PlaceholderContainer(),
      errorBuilder: (context, error, stackTrace) => const PlaceholderContainer(),
    );
  }

  /// Static tag pills (year, content rating, duration, quality labels) below
  /// the title. Reuses [_buildMetadataChip] and [buildMediaQualityLabels]
  /// unchanged; only the row composition is new.
  Widget _buildMobileTagsRow(BuildContext context, MediaItem metadata) {
    final chips = [
      for (final label in _mobileTagLabels(metadata)) _buildMetadataChip(label),
      // Critic and audience ratings, the chips the tablet header shows. The own
      // rating is not repeated here: "Beoordelen" sits in the action row.
      ..._buildRatingChips(metadata, includeUserRating: false),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  /// The text tags shared by the flat tags row and the glass hero.
  List<String> _mobileTagLabels(MediaItem metadata) {
    final seasonCount = metadata.isShow ? metadata.childCount : null;
    return [
      if (metadata.year != null) '${metadata.year}',
      if (metadata.contentRating != null) formatContentRating(metadata.contentRating),
      if (metadata.durationMs != null) formatDurationTextual(metadata.durationMs!),
      // A series says how many seasons it has where a film says how long it
      // is. Only from two up: the string is plural, and a single season is
      // already named by the season pill below.
      if (seasonCount != null && seasonCount > 1) '$seasonCount ${t.libraries.groupings.seasons.toLowerCase()}',
      ...buildMediaQualityLabels(metadata),
    ];
  }

  /// Full-width primary CTA: "Afspelen" or "Hervatten · nog Xu Ym", reusing
  /// [_handlePlayPressed] (extracted from `_buildActionButtons` for exactly
  /// this reuse) so both layouts drive the same resume/refresh behaviour.
  Widget _buildMobilePrimaryCta(BuildContext context, MediaItem metadata, {bool glass = false}) {
    final resumeTarget = metadata.isShow ? (_onDeckEpisode ?? metadata) : metadata;
    final viewOffsetMs = resumeTarget.viewOffsetMs ?? 0;
    final isResuming = viewOffsetMs > 0;
    final label = StringBuffer(isResuming ? t.common.resume : t.common.play);
    if (metadata.isShow && resumeTarget.parentIndex != null && resumeTarget.index != null) {
      label.write(
        ' ${t.discover.playEpisode(season: resumeTarget.parentIndex.toString(), episode: resumeTarget.index.toString())}',
      );
    }
    final remaining = isResuming ? formatRemainingTime(resumeTarget.durationMs, viewOffsetMs) : null;
    if (remaining != null) {
      label.write(' · $remaining');
    }

    // Same id the TV/desktop play action registers (`action_buttons.dart`).
    return AutomationNode(
      id: AutomationIds.mediaDetailPlay,
      role: 'button',
      child: glass
          ? GlassCapsuleButton(
              prominent: true,
              icon: Icons.play_arrow_rounded,
              label: label.toString(),
              onPressed: () => unawaited(_handlePlayPressed(metadata)),
            )
          : SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => unawaited(_handlePlayPressed(metadata)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(label.toString(), style: const TextStyle(fontWeight: .w700)),
              ),
            ),
    );
  }

  /// The LG-02 back/more row, pinned over the page (see [MobileDetailHeroBar]).
  Widget _buildMobileGlassHeroBar(BuildContext context, MediaItem metadata) {
    final trailer = _getPrimaryTrailer();
    return MobileDetailHeroBar(
      leading: GlassCircleButton(
        icon: Icons.arrow_back_rounded,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.pop(context, _watchStateChanged),
      ),
      trailing: [
        // The flat layout's preview card is the trailer's door; on the hero
        // it gets a glass circle of its own so it stays reachable.
        if (trailer != null) ...[
          GlassCircleButton(
            icon: Icons.movie_outlined,
            // The button starts the trailer straight away: say so, for
            // VoiceOver too.
            tooltip: t.tooltips.playTrailer,
            onPressed: () => unawaited(navigateToVideoPlayer(context, metadata: trailer)),
          ),
          const SizedBox(width: 12),
        ],
        if (!widget.isOffline) _buildMobileMoreButton(context, metadata, glass: true),
      ],
    );
  }

  /// The LG-02 hero: [MobileDetailHero] fed with this page's artwork, tags,
  /// rating chips and the same handlers the flat layout uses. For a film the
  /// watchlist toggle moves here from the action row, as a round glass button
  /// next to Download.
  Widget _buildMobileGlassHero(BuildContext context, MediaItem metadata, MediaServerClient? client) {
    final (onList, canOfferWatchlist) = _mobileWatchlistState(context, metadata);

    return MobileDetailHero(
      artwork: _buildMobileArtwork(context, metadata, client, maxWidth: 1200, maxHeight: 1600),
      title: metadata.displayTitle,
      chips: _mobileTagLabels(metadata),
      extraChips: _buildRatingChips(metadata, includeUserRating: false),
      actions: Column(
        children: [
          _buildMobilePrimaryCta(context, metadata, glass: true),
          // Offline there is neither a download nor a watchlist to offer; a
          // series downloads per episode and keeps its toggle in the action row.
          if (!widget.isOffline && !metadata.isShow) ...[
            const SizedBox(height: 12),
            GlassLayer(
              child: Row(
                children: [
                  Expanded(child: _buildMobileDownloadCta(context, metadata, glass: true)),
                  const SizedBox(width: 12),
                  GlassCircleButton(
                    size: GlassCapsuleButton.height,
                    icon: onList ? Icons.bookmark_added_rounded : Icons.add_rounded,
                    tooltip: onList ? t.watchlist.remove : t.watchlist.add,
                    onPressed: canOfferWatchlist ? () => unawaited(WatchlistUiActions.toggle(context, metadata)) : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
