part of '../media_detail_screen.dart';

/// The series-detail tabs (mockup 07): Afleveringen / Vergelijkbaar / Extra's
/// / Details. Season selection reuses the exact
/// `setState(() => _selectedSeasonIndex = index); _fetchSeasonEpisodes(index);`
/// contract `_buildSeasonTabsContent` (`media_detail_screen.dart`) already
/// uses for its horizontal tab row, so per-season pagination state
/// (`_seasonEpisodePager`) stays intact when switching seasons here.
extension _MobileEpisodesTab on _MediaDetailScreenState {
  Widget _buildMobileEpisodesTabs(BuildContext context, MediaItem metadata) {
    final tabs = [t.libraries.groupings.episodes, t.discover.moreLikeThis, t.discover.extras, t.common.details];

    return DefaultTabController(
      length: tabs.length,
      // A Builder so `context` below is a *descendant* of DefaultTabController
      // (`.of(context)` on the outer context, from _buildMobileDetailScreen,
      // would never find it); AnimatedBuilder listens to the controller
      // itself so the IndexedStack actually rebuilds on every tab switch, not
      // just once when the controller is first created.
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          return Column(
            crossAxisAlignment: .start,
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final label in tabs) Tab(text: label)],
              ),
              const SizedBox(height: 12),
              // The tab views size themselves; a fixed-height shell keeps this
              // sliver-hosted CustomScrollView from getting an unbounded height.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 400),
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => IndexedStack(
                    index: controller.index,
                    children: [
                      _buildMobileEpisodesTabContent(context, metadata),
                      _buildMobileSimilarTabContent(context),
                      _buildMobileExtrasTabContent(context),
                      _buildMobileDetailsTabContent(context, metadata),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMobileEpisodesTabContent(BuildContext context, MediaItem metadata) {
    final showFlattened = _showEpisodesDirectly || metadata.isSeason;

    return Column(
      crossAxisAlignment: .start,
      children: [
        if (!showFlattened && _seasons.length > 1) ...[_buildMobileSeasonPicker(context), const SizedBox(height: 12)],
        if (showFlattened) ...[
          if (_isLoadingSeasons || _isLoadingEpisodes)
            _MediaDetailScreenState._sectionLoading
          else if (_allEpisodesPageError && _episodes.isEmpty)
            _sectionError(t.messages.episodesLoadFailed, () => unawaited(_fetchAllEpisodes()))
          else if (_episodes.isNotEmpty)
            _buildEpisodesList()
          else
            _sectionEmpty(context, t.messages.noEpisodesFoundGeneral),
        ] else ...[
          if (_isLoadingSeasons)
            _MediaDetailScreenState._sectionLoading
          else if (_seasonsLoadFailed)
            _sectionError(t.messages.seasonsLoadFailed, () => unawaited(_loadSeasons()))
          else if (_seasons.isEmpty)
            _sectionEmpty(context, t.messages.noSeasonsFound)
          else if (_isLoadingSeasonEpisodes)
            _MediaDetailScreenState._sectionLoading
          else if (_seasonEpisodesFirstPageError && _episodes.isEmpty)
            _sectionError(t.messages.episodesLoadFailed, () => unawaited(_fetchSeasonEpisodes(_selectedSeasonIndex)))
          else if (_episodes.isNotEmpty)
            _buildEpisodesList()
          else
            _sectionEmpty(context, t.messages.noEpisodesFoundGeneral),
        ],
      ],
    );
  }

  /// "Seizoen 2 ⌄" chip, opening the same season list the horizontal tab row
  /// offers, as a menu instead of tabs so it stays compact on a phone width.
  Widget _buildMobileSeasonPicker(BuildContext context) {
    final theme = Theme.of(context);
    final current = _seasons[_selectedSeasonIndex];
    final watchedCount = current.viewedLeafCount ?? 0;
    final totalCount = current.leafCount ?? _episodes.length;

    void selectSeason(int index) {
      if (index == _selectedSeasonIndex) return;
      setStateIfMounted(() => _selectedSeasonIndex = index);
      _fetchSeasonEpisodes(index);
    }

    return Row(
      mainAxisAlignment: .spaceBetween,
      children: [
        PopupMenuButton<int>(
          initialValue: _selectedSeasonIndex,
          onSelected: selectSeason,
          itemBuilder: (context) => [
            for (int i = 0; i < _seasons.length; i++)
              PopupMenuItem<int>(value: i, child: Text(_seasons[i].title ?? '')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: .min,
              children: [
                Text(
                  current.title ?? '',
                  style: TextStyle(fontWeight: .w700, color: theme.colorScheme.onSecondaryContainer),
                ),
                Icon(Icons.expand_more_rounded, color: theme.colorScheme.onSecondaryContainer, size: 20),
              ],
            ),
          ),
        ),
        if (totalCount > 0)
          Flexible(
            child: Text(
              t.discover.episodeCountWatched(count: totalCount, watched: watchedCount),
              maxLines: 1,
              overflow: .ellipsis,
              textAlign: .end,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileSimilarTabContent(BuildContext context) {
    if (_relatedHubs.isEmpty) return _sectionEmpty(context, t.messages.noEpisodesFoundGeneral);
    return Column(
      crossAxisAlignment: .start,
      children: [
        for (int i = 0; i < _relatedHubs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          HubSection(
            key: _relatedHubKeys[i],
            hub: _relatedHubs[i],
            icon: _getRelatedHubIcon(_relatedHubs[i]),
            inset: true,
            onVerticalNavigation: (isUp) => _handleRelatedHubNavigation(i, isUp),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileExtrasTabContent(BuildContext context) {
    if (widget.isOffline || _extras == null || _extras!.isEmpty) {
      return _sectionEmpty(context, t.messages.noEpisodesFoundGeneral);
    }
    return _buildExtrasSection();
  }

  Widget _buildMobileDetailsTabContent(BuildContext context, MediaItem metadata) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        _buildMobileSynopsisAndCredits(context, metadata),
        if (metadata.roles != null && metadata.roles!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildCastSection(metadata),
        ],
        if (metadata.studio != null || metadata.contentRating != null) ...[
          const SizedBox(height: 16),
          if (metadata.studio != null) ...[
            _buildInfoRow(t.discover.studio, metadata.studio!),
            const SizedBox(height: 12),
          ],
          if (metadata.contentRating != null)
            _buildInfoRow(t.discover.rating, formatContentRating(metadata.contentRating)),
        ],
        const SizedBox(height: 16),
        _buildMobileActionRow(context, metadata),
      ],
    );
  }
}
