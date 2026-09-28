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
/// already call for the pre-northstar mobile/TV layout, so behaviour is
/// unchanged and only the composition is new. Season/episode state
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
              _buildMobilePrimaryCta(context, metadata, glass: glass),
              // Downloading a series happens per episode row; the
              // full-width capsule is the film's.
              if (!metadata.isShow) ...[
                const SizedBox(height: 10),
                GlassLayer(child: _buildMobileDownloadCta(context, metadata, glass: glass)),
              ],
              // The only way to change source from the detail page; draws
              // nothing unless the item has alternative sources
              // (`hasAlternativeSources`, action_buttons.dart).
              _buildUnifiedSourceLine(),
              if (_detailAudioTracks.isNotEmpty) ...[const SizedBox(height: 10), _buildMobileAudioSelector()],
              const SizedBox(height: 16),
              _buildMobileSynopsisAndCredits(context, metadata),
              const SizedBox(height: 16),
              _buildMobileActionRow(context, metadata),
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
        // The trailer's door until the action row gets its own (DEC-140).
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
}
