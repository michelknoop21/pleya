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

    return PrimaryScrollController(
      controller: _scrollController,
      child: IosStatusBarTapScrollToTop(
        controller: _scrollController,
        child: OverlaySheetHost(
          canPop: !blockSystemBack,
          child: Focus(
            onKeyEvent: _handleMediaDetailBackKey,
            child: Scaffold(
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildMobileDetailAppBar(context, metadata),
                    Expanded(
                      child: CustomScrollView(
                        primary: true,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              child: Column(
                                crossAxisAlignment: .start,
                                children: [
                                  // Mockup 07 opens a series on the Hervatten
                                  // capsule and goes straight into the tabs:
                                  // no 16:9 preview, no second title under the
                                  // app bar's, no tags row, and no full-width
                                  // Downloaden CTA (download lives per episode
                                  // row instead). Those belong to 06, the film
                                  // detail, which keeps them unchanged below.
                                  if (!metadata.isShow) ...[
                                    _buildMobilePreviewCard(context, metadata, client),
                                    const SizedBox(height: 16),
                                    Text(
                                      metadata.displayTitle,
                                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildMobileTagsRow(context, metadata),
                                    const SizedBox(height: 16),
                                  ],
                                  _buildMobilePrimaryCta(context, metadata),
                                  if (!metadata.isShow) ...[
                                    const SizedBox(height: 10),
                                    _buildMobileDownloadCta(context, metadata),
                                  ],
                                  // Kept for a series too: this is the only way
                                  // to change source from the detail page, and
                                  // it already draws nothing unless the item
                                  // actually has alternative sources
                                  // (`hasAlternativeSources`, action_buttons.dart).
                                  _buildUnifiedSourceLine(),
                                  if (_detailAudioTracks.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    _buildMobileAudioSelector(),
                                  ],
                                  const SizedBox(height: 16),
                                  if (metadata.isShow)
                                    _buildMobileEpisodesTabs(context, metadata)
                                  else ...[
                                    _buildMobileSynopsisAndCredits(context, metadata),
                                    const SizedBox(height: 16),
                                    _buildMobileActionRow(context, metadata),
                                  ],
                                  // For a show, "Meer zoals dit" lives in the
                                  // Vergelijkbaar tab instead (_buildMobileEpisodesTabs)
                                  // so it isn't rendered twice.
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
                      ),
                    ),
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
  Widget _buildMobileMoreButton(BuildContext context, MediaItem metadata) {
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
        builder: (buttonContext) => IconButton(
          onPressed: () {
            final renderBox = buttonContext.findRenderObject() as RenderBox?;
            final position = renderBox?.localToGlobal(renderBox.size.center(Offset.zero));
            _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
          },
          icon: const AppIcon(Symbols.more_vert_rounded, fill: 1),
        ),
      ),
    );
  }

  /// The 16:9 trailer preview (mockup 06/07's top card). Falls back to the
  /// item's own artwork when there is no trailer to preview.
  Widget _buildMobilePreviewCard(BuildContext context, MediaItem metadata, MediaServerClient? client) {
    final primaryTrailer = _getPrimaryTrailer();
    final artworkPath = metadata.artPath ?? metadata.thumbPath;
    final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);

    Widget artwork;
    if (artworkPath == null) {
      artwork = const PlaceholderContainer();
    } else {
      final imageUrl = MediaImageHelper.getOptimizedImageUrl(
        client: client,
        thumbPath: artworkPath,
        maxWidth: 800,
        maxHeight: 450,
        devicePixelRatio: dpr,
        imageType: ImageType.art,
      );
      artwork = imageUrl.isEmpty
          ? const PlaceholderContainer()
          : CachedNetworkImage(
              imageUrl: imageUrl,
              cacheManager: PlexImageCacheManager.instance,
              fit: BoxFit.cover,
              placeholder: (context, url) => const PlaceholderContainer(),
              errorBuilder: (context, error, stackTrace) => const PlaceholderContainer(),
            );
    }

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

  /// Static tag pills (year, content rating, duration, quality labels) below
  /// the title. Reuses [_buildMetadataChip] and [buildMediaQualityLabels]
  /// unchanged; only the row composition is new.
  Widget _buildMobileTagsRow(BuildContext context, MediaItem metadata) {
    final chips = <Widget>[
      if (metadata.year != null) _buildMetadataChip('${metadata.year}'),
      if (metadata.contentRating != null) _buildMetadataChip(formatContentRating(metadata.contentRating)),
      if (metadata.durationMs != null) _buildMetadataChip(formatDurationTextual(metadata.durationMs!)),
      for (final label in buildMediaQualityLabels(metadata)) _buildMetadataChip(label),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  /// Full-width primary CTA: "Afspelen" or "Hervatten · nog Xu Ym", reusing
  /// [_handlePlayPressed] (extracted from `_buildActionButtons` for exactly
  /// this reuse) so both layouts drive the same resume/refresh behaviour.
  Widget _buildMobilePrimaryCta(BuildContext context, MediaItem metadata) {
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

    return SizedBox(
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
    );
  }

  /// Full-width secondary CTA: "Downloaden", reusing
  /// [_handleDownloadButtonPressed] for the full state machine (queue,
  /// pause/resume, retry, delete) unchanged; only the label mapping below is
  /// new, matching the northstar's text button instead of an icon-only one.
  Widget _buildMobileDownloadCta(BuildContext context, MediaItem metadata) {
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

  /// Synopsis (reuses [CollapsibleText] unchanged, DEC-109: mobile/desktop
  /// keep this in-place expand rather than the TV "Meer lezen" panel) plus
  /// the compact "Cast: … / Regie: …" text lines from mockup 06/the
  /// serie-detail comp.
  Widget _buildMobileSynopsisAndCredits(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);
    final summary = metadata.summary;
    final roles = metadata.roles;
    final directors = metadata.directors;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: .start,
      children: [
        if (summary != null && summary.isNotEmpty) ...[
          CollapsibleText(text: summary, maxLines: 6, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
        ],
        if (roles != null && roles.isNotEmpty)
          Text.rich(
            TextSpan(
              style: mutedStyle,
              children: [
                TextSpan(
                  text: '${t.discover.cast}: ',
                  style: mutedStyle?.copyWith(fontWeight: .w600),
                ),
                TextSpan(text: roles.take(3).map((r) => r.tag).join(', ')),
              ],
            ),
          ),
        if (directors != null && directors.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: mutedStyle,
              children: [
                TextSpan(
                  text: '${t.metadataEdit.director}: ',
                  style: mutedStyle?.copyWith(fontWeight: .w600),
                ),
                TextSpan(text: directors.join(', ')),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Fixed action icon row (add to list / rate / mark watched / share).
  /// Every icon but share reuses an existing, already-tested handler:
  /// [WatchlistUiActions.toggle], [_showRatingDialog] and
  /// [_handleWatchedTogglePressed] are exactly what the pre-northstar action
  /// row and the long-press context menu already call. Share is genuinely
  /// new (no prior share capability existed anywhere in the app).
  Widget _buildMobileActionRow(BuildContext context, MediaItem metadata) {
    final watchlistProvider = context.watch<WatchlistProvider?>();
    final watchlistStore = context.watch<WatchlistStore?>();
    final isWatchlistKind = metadata.isMovie || metadata.isShow;
    final onWatchlist = WatchlistUiActions.isOnList(store: watchlistStore, provider: watchlistProvider, item: metadata);
    final canOfferWatchlist =
        !widget.isOffline &&
        isWatchlistKind &&
        WatchlistUiActions.canOffer(provider: watchlistProvider, item: metadata, onList: onWatchlist);

    final mediaClient = _getMediaClientForMetadata(context);
    final isNumericRating = mediaClient?.capabilities.numericUserRating ?? true;
    final hasRating = metadata.userRating != null && metadata.userRating! > 0;

    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool active = false,
    }) {
      final color = active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface;
      final effectiveColor = onPressed == null ? color.withValues(alpha: 0.4) : color;
      return Expanded(
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: effectiveColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: TextStyle(fontSize: 12, color: effectiveColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        action(
          icon: onWatchlist ? Icons.bookmark_added_rounded : Icons.add_rounded,
          label: onWatchlist ? t.watchlist.remove : t.watchlist.add,
          onPressed: canOfferWatchlist ? () => unawaited(WatchlistUiActions.toggle(context, metadata)) : null,
        ),
        action(
          icon: isNumericRating ? Icons.star_rounded : Icons.thumb_up_rounded,
          label: t.mediaMenu.rate,
          active: hasRating,
          onPressed: widget.isOffline ? null : () => unawaited(_showRatingDialog(context, metadata)),
        ),
        action(
          icon: metadata.isWatched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
          label: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
          active: metadata.isWatched,
          onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
        ),
        action(
          icon: Icons.send_rounded,
          label: t.common.share,
          onPressed: () => unawaited(SharePlus.instance.share(ShareParams(text: metadata.displayTitle))),
        ),
      ],
    );
  }
}
