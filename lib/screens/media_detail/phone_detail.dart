part of '../media_detail_screen.dart';

/// The iPhone-only detail layout from northstar mockups 06/07: a plain 16:9
/// preview image (no Netflix-style text overlay), then title/metadata/actions
/// as normal page content. [PlatformDetector.isPhone] gates this — iPad and
/// desktop keep the existing overlay hero (DEC-103 regression boundary), and
/// TV keeps [_buildTvDetailScreen] untouched.
extension _PhoneDetailScreen on _MediaDetailScreenState {
  Widget _buildPhoneDetailScreen(
    BuildContext context,
    MediaItem metadata,
    KeyEventResult Function(FocusNode, KeyEvent) handleBack,
  ) {
    _schedulePhoneInitialEpisodePaging();
    final blockSystemBack = InputModeTracker.shouldBlockSystemBack(context);

    return PrimaryScrollController(
      controller: _scrollController,
      child: IosStatusBarTapScrollToTop(
        controller: _scrollController,
        child: OverlaySheetHost(
          canPop: !blockSystemBack,
          child: Focus(
            onKeyEvent: handleBack,
            child: Scaffold(
              // No title text here — the large heading in the body carries
              // that job, exactly like the legacy overlay hero's title does.
              // Rendering the title a second time here would make every
              // `find.text(displayTitle)` in the test suite ambiguous.
              appBar: AppBar(
                leading: AppBarBackButton(onPressed: () => Navigator.pop(context, _watchStateChanged)),
                actions: [_buildPhoneMoreMenuButton(metadata)],
              ),
              body: CustomScrollView(
                primary: true,
                slivers: [
                  SliverToBoxAdapter(child: _buildPhoneHeroImage(context, metadata)),
                  SliverToBoxAdapter(child: _buildPhoneDetailBody(context, metadata)),
                  SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneMoreMenuButton(MediaItem metadata) {
    if (widget.isOffline) return const SizedBox.shrink();
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
          void openMenu() {
            final renderBox = buttonContext.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final position = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
              _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
            }
          }

          return IconButton(onPressed: openMenu, icon: const AppIcon(Symbols.more_vert_rounded));
        },
      ),
    );
  }

  /// Plain 16:9 preview image (mockups 06/07), with a play overlay and
  /// "Trailer" label only when a trailer extra actually exists — otherwise a
  /// bare image, since an overlay that plays nothing would be misleading.
  Widget _buildPhoneHeroImage(BuildContext context, MediaItem metadata) {
    final primaryTrailer = _getPrimaryTrailer();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  final artPaths = metadata.heroArtCandidates(containerAspectRatio: width / height);
                  if (artPaths.isEmpty) return const PlaceholderContainer();

                  final localArtwork = _buildOfflineArtworkIfAvailable(
                    context,
                    artworkPaths: artPaths,
                    fit: BoxFit.cover,
                    imageType: ImageType.art,
                    errorWidget: (context, url, error) => const PlaceholderContainer(),
                  );
                  if (localArtwork != null) return localArtwork;

                  final client = _getArtworkMediaClient(context);
                  final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
                  final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
                    displayWidth: (width * dpr).round(),
                    displayHeight: (height * dpr).round(),
                    imageType: ImageType.art,
                  );
                  return _buildPhoneHeroArtwork(
                    client: client,
                    artworkPaths: artPaths,
                    maxWidth: width,
                    maxHeight: height,
                    dpr: dpr,
                    memCacheHeight: memHeight,
                  );
                },
              ),
              if (primaryTrailer != null) ...[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => unawaited(navigateToVideoPlayer(context, metadata: primaryTrailer)),
                      child: const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Text(
                    t.discover.trailerLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: .w600, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Same fallback-through-candidates shape as [_buildHeroNetworkArtwork], but
  /// sized for the real 16:9 box instead of that method's baked-in "60% of
  /// screen height" hero assumption, which would under-request this image.
  Widget _buildPhoneHeroArtwork({
    required MediaServerClient? client,
    required List<String> artworkPaths,
    required double maxWidth,
    required double maxHeight,
    required double dpr,
    required int memCacheHeight,
    int index = 0,
  }) {
    if (index >= artworkPaths.length) return const PlaceholderContainer();

    final imageUrl = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: artworkPaths[index],
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      devicePixelRatio: dpr,
      imageType: ImageType.art,
    );
    if (imageUrl.isEmpty) {
      return _buildPhoneHeroArtwork(
        client: client,
        artworkPaths: artworkPaths,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        dpr: dpr,
        memCacheHeight: memCacheHeight,
        index: index + 1,
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: PlexImageCacheManager.instance,
      fit: BoxFit.cover,
      memCacheHeight: memCacheHeight,
      placeholder: (context, url) => const PlaceholderContainer(),
      errorBuilder: (context, error, stackTrace) => _buildPhoneHeroArtwork(
        client: client,
        artworkPaths: artworkPaths,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        dpr: dpr,
        memCacheHeight: memCacheHeight,
        index: index + 1,
      ),
    );
  }

  Widget _buildPhoneDetailBody(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      if (metadata.year != null) _buildMetadataChip('${metadata.year}'),
      if (metadata case PlexMediaItem(:final editionTitle?)) _buildMetadataChip(editionTitle),
      if (metadata.contentRating != null) _buildMetadataChip(formatContentRating(metadata.contentRating!)),
      if (metadata.durationMs != null) _buildMetadataChip(formatDurationTextual(metadata.durationMs!)),
      for (final label in buildMediaQualityLabels(metadata)) _buildMetadataChip(label),
      ..._buildRatingChips(metadata),
    ];

    final isShow = metadata.isShow;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text(metadata.displayTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold)),
          if (chips.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: chips)],
          const SizedBox(height: 16),
          _buildPhonePrimaryButton(metadata),
          const SizedBox(height: 10),
          _buildPhoneDownloadButton(metadata),
          _buildUnifiedSourceLine(),
          const SizedBox(height: 16),
          _buildPhoneIconActionRow(metadata),
          const SizedBox(height: 20),
          if (isShow) _buildPhoneSeriesTabs(context, metadata) else _buildPhoneFlatDetailContent(context, metadata),
        ],
      ),
    );
  }

  /// Movies, episodes and seasons: no tabs, everything in one flowing column
  /// (mockup 06). Shows use [_buildPhoneSeriesTabs] instead.
  Widget _buildPhoneFlatDetailContent(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: .start,
      children: [
        if (metadata.summary != null && metadata.summary!.isNotEmpty) ...[
          CollapsibleText(
            text: metadata.summary!,
            maxLines: 6,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 16),
        ],
        _buildPhoneCreditsLine(metadata),
        const SizedBox(height: 20),
        // Gated on the item kind alone (not `_episodes.isNotEmpty`) so the
        // loading and error branches below stay reachable — the outer gate
        // used to require a non-empty list, which made both dead code and
        // left a slow or failed fetch rendering as a silently "complete"
        // season page with no episodes and no retry.
        if (metadata.isSeason) ...[
          Text(t.libraries.groupings.episodes, style: theme.textTheme.titleLarge?.copyWith(fontWeight: .bold)),
          const SizedBox(height: 12),
          if (_isLoadingEpisodes)
            _MediaDetailScreenState._sectionLoading
          else if (_allEpisodesPageError && _episodes.isEmpty)
            _sectionError(t.messages.episodesLoadFailed, () => unawaited(_fetchAllEpisodes()))
          else if (_episodes.isEmpty)
            _sectionEmpty(context, t.messages.noEpisodesFoundGeneral)
          else
            _buildEpisodesList(),
          const SizedBox(height: 20),
        ],
        ..._buildPhoneTrailingSections(context, metadata),
      ],
    );
  }

  /// Related hubs, extras, then [_buildPhoneWatchersAndInfoRows] — the flat
  /// (movie) layout's full tail. The series "Details" tab uses only
  /// [_buildPhoneWatchersAndInfoRows]: its related hubs and extras already
  /// have their own "Vergelijkbaar"/"Extra's" tabs, so repeating them here
  /// would show the same content twice.
  List<Widget> _buildPhoneTrailingSections(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);
    return [
      if (!widget.isOffline && _extras != null && _extras!.isNotEmpty) ...[
        Text(t.discover.extras, style: theme.textTheme.titleLarge?.copyWith(fontWeight: .bold)),
        const SizedBox(height: 12),
        _buildExtrasSectionContent(),
        const SizedBox(height: 20),
      ],
      for (int i = 0; i < _relatedHubs.length; i++) ...[
        HubSection(hub: _relatedHubs[i], icon: _getRelatedHubIcon(_relatedHubs[i]), inset: true),
        const SizedBox(height: 12),
      ],
      ..._buildPhoneWatchersAndInfoRows(context, metadata),
    ];
  }

  /// Now-watching/watchers/stats and the studio/rating info rows only — no
  /// extras or related hubs, see [_buildPhoneTrailingSections].
  List<Widget> _buildPhoneWatchersAndInfoRows(BuildContext context, MediaItem metadata) {
    return [
      NowWatchingLine(ratingKey: _metadata.id),
      if (_watchers?.watchers.isNotEmpty ?? false) WatchedByRow(watchers: _watchers!.watchers, scope: _watchers!.scope),
      if (_watchStats?.isNotEmpty ?? false) ...[const SizedBox(height: 8), WatchStatsRow(stats: _watchStats!)],
      if (_hasInfoRows) ...[
        const SizedBox(height: 16),
        if (metadata.studio != null) ...[
          _buildInfoRow(t.discover.studio, metadata.studio!),
          const SizedBox(height: 12),
        ],
        if (metadata.contentRating != null)
          _buildInfoRow(t.discover.rating, formatContentRating(metadata.contentRating!)),
      ],
    ];
  }

  /// "Cast: A, B, C ... meer" / "Regisseur: X" plain-text lines (mockups 06 /
  /// serie-detail-comp) — replaces the avatar [CastSection] row on the phone
  /// layout only; TV and the legacy iPad/desktop layout keep the avatar row.
  Widget _buildPhoneCreditsLine(MediaItem metadata) {
    final roles = metadata.roles;
    final directors = metadata.directors;
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final nameStyle = theme.textTheme.bodyMedium;

    Widget creditLine(String label, List<String> names, {VoidCallback? onMore}) {
      const maxNames = 3;
      final shown = names.take(maxNames).join(', ');
      final hasMore = names.length > maxNames;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: nameStyle,
            children: [
              TextSpan(text: '$label ', style: labelStyle),
              TextSpan(text: shown),
              if (hasMore) TextSpan(text: ' … ${t.common.more}', style: labelStyle),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: .start,
      children: [
        if (roles != null && roles.isNotEmpty) creditLine(t.discover.cast, [for (final r in roles) r.tag]),
        if (directors != null && directors.isNotEmpty) creditLine(t.metadataEdit.director, directors),
      ],
    );
  }

  /// Deep-linking to a specific episode (Continue Watching/Next Up) needs
  /// [_maybeLoadMoreForInitialEpisode] to page further batches in when the
  /// target isn't on the first page — [_scheduleInitialMobileDetailFocus]
  /// does that too, but only alongside a `FocusNode`-based scroll-into-view
  /// that has nothing to attach to on a touch UI, so the phone branch calls
  /// this data-only half directly instead of that whole method.
  void _schedulePhoneInitialEpisodePaging() {
    if (widget.initialEpisodeId == null || _episodesContainInitialTarget) return;
    _maybeLoadMoreForInitialEpisode();
  }
}
