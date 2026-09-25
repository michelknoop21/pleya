part of '../media_detail_screen.dart';

/// The mobile film/series detail presentation (northstar 06/07,
/// `docs/assets/ios-unified/northstar/06-film-detail.png` and
/// `07-serie-afleveringen.png`). iOS Unified 2026 workitem 5 (I6),
/// `docs/unified-2026-closure.md` §5 row 5.
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
    // Liquid Glass (LG-02): a film opens on a full-bleed hero behind the
    // status bar, with the back/more buttons, title, tags and both CTAs on
    // it. A series keeps mockup 07's layout; glass off keeps today's tree.
    final glassHero = !metadata.isShow && glassTierFor(context) != GlassTier.off;
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
                // Mockup 07 opens a series on the Hervatten capsule and goes
                // straight into the tabs: no 16:9 preview, no second title
                // under the app bar's, no tags row, and no full-width
                // Downloaden CTA (download lives per episode row instead).
                // Those belong to 06, the film detail, which keeps them
                // unchanged below (or on the glass hero).
                if (!metadata.isShow && !glassHero) ...[
                  _buildMobilePreviewCard(context, metadata, client),
                  const SizedBox(height: 16),
                  Text(metadata.displayTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold)),
                  const SizedBox(height: 8),
                  _buildMobileTagsRow(context, metadata),
                  const SizedBox(height: 16),
                ],
                if (!glassHero) _buildMobilePrimaryCta(context, metadata),
                if (!metadata.isShow && !glassHero) ...[
                  const SizedBox(height: 10),
                  _buildMobileDownloadCta(context, metadata),
                ],
                // Kept for a series too: this is the only way to change
                // source from the detail page, and it already draws nothing
                // unless the item actually has alternative sources
                // (`hasAlternativeSources`, action_buttons.dart).
                _buildUnifiedSourceLine(),
                if (_detailAudioTracks.isNotEmpty) ...[const SizedBox(height: 10), _buildMobileAudioSelector()],
                const SizedBox(height: 16),
                if (metadata.isShow)
                  _buildMobileEpisodesTabs(context, metadata)
                else ...[
                  _buildMobileSynopsisAndCredits(context, metadata),
                  const SizedBox(height: 16),
                  _buildMobileActionRow(context, metadata, includeWatchlist: !glassHero),
                ],
                // For a show, "Meer zoals dit" lives in the Vergelijkbaar tab
                // instead (_buildMobileEpisodesTabs) so it isn't rendered twice.
                if (!metadata.isShow)
                  for (int i = 0; i < _relatedHubs.length; i++) ...[
                    const SizedBox(height: 8),
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
                  ? content
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
    final chips = [for (final label in _mobileTagLabels(metadata)) _buildMetadataChip(label)];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  List<String> _mobileTagLabels(MediaItem metadata) => [
    if (metadata.year != null) '${metadata.year}',
    if (metadata.contentRating != null) formatContentRating(metadata.contentRating),
    if (metadata.durationMs != null) formatDurationTextual(metadata.durationMs!),
    ...buildMediaQualityLabels(metadata),
  ];

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

  /// Full-width secondary CTA: "Downloaden", reusing
  /// [_handleDownloadButtonPressed] for the full state machine (queue,
  /// pause/resume, retry, delete) unchanged; only the label mapping below is
  /// new, matching the northstar's text button instead of an icon-only one.
  Widget _buildMobileDownloadCta(BuildContext context, MediaItem metadata, {bool glass = false}) {
    if (widget.isOffline || PlatformDetector.isAppleTV()) return const SizedBox.shrink();

    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final globalKey = metadata.globalKey;
        final progress = downloadProvider.getProgress(globalKey);
        final isDownloaded = downloadProvider.isDownloaded(globalKey);

        final (icon, label) = switch (progress?.status) {
          _ when downloadProvider.isQueueing(globalKey) => (Icons.schedule_rounded, t.downloads.queuedTooltip),
          DownloadStatus.queued => (Icons.schedule_rounded, t.downloads.queuedTooltip),
          DownloadStatus.downloading => (Icons.downloading_rounded, t.downloads.downloadingTooltip),
          DownloadStatus.paused => (Icons.pause_circle_outline_rounded, t.downloads.resumeDownload),
          DownloadStatus.failed => (Icons.error_outline_rounded, t.downloads.retryDownload),
          DownloadStatus.cancelled => (Icons.cancel_rounded, t.downloads.cancelledDownload),
          _ when isDownloaded => (Icons.check_circle_outline_rounded, t.downloads.downloadAction),
          _ => (Icons.download_rounded, _mobileDownloadActionLabel(metadata)),
        };

        if (glass) {
          return GlassCapsuleButton(
            icon: icon,
            label: label,
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.tonalIcon(
              onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
              // The tonal variant's own defaults never reach this button:
              // monoTheme's `filledButtonTheme` sets `backgroundColor: c.text`
              // for every FilledButton, and a theme style outranks a variant
              // default, so this rendered pure white — the same capsule as the
              // primary CTA right above it. The mockup has a grey secondary
              // under a white primary, so name the surface explicitly.
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                backgroundColor: tokens(context).surfaceElevated,
                foregroundColor: tokens(context).text,
              ),
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontWeight: .w700)),
            ),
          ),
        );
      },
    );
  }

  /// "Downloaden S7:E18" for a show with an on-deck episode (comp), plain
  /// "Downloaden" otherwise.
  String _mobileDownloadActionLabel(MediaItem metadata) {
    final onDeck = _onDeckEpisode;
    if (!metadata.isShow || onDeck == null || onDeck.parentIndex == null || onDeck.index == null) {
      return t.downloads.downloadAction;
    }
    final episodeLabel = t.discover.playEpisode(
      season: onDeck.parentIndex.toString(),
      episode: onDeck.index.toString(),
    );
    return '${t.downloads.downloadAction} $episodeLabel';
  }

  /// The LG-02 hero: [MobileDetailHero] fed with this page's artwork, tags
  /// and the same handlers the flat layout uses. The watchlist toggle moves
  /// here from the action row, as a round glass button next to Download.
  Widget _buildMobileGlassHero(BuildContext context, MediaItem metadata, MediaServerClient? client) {
    final trailer = _getPrimaryTrailer();
    final (onList, canOfferWatchlist) = _mobileWatchlistState(context, metadata);

    return MobileDetailHero(
      artwork: _buildMobileArtwork(context, metadata, client, maxWidth: 1200, maxHeight: 1600),
      title: metadata.displayTitle,
      chips: _mobileTagLabels(metadata),
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
            tooltip: t.discover.extras,
            onPressed: () => unawaited(navigateToVideoPlayer(context, metadata: trailer)),
          ),
          const SizedBox(width: 12),
        ],
        if (!widget.isOffline) _buildMobileMoreButton(context, metadata, glass: true),
      ],
      actions: Column(
        children: [
          _buildMobilePrimaryCta(context, metadata, glass: true),
          // Offline there is neither a download nor a watchlist to offer.
          if (!widget.isOffline) ...[
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
