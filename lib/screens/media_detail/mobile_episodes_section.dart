part of '../media_detail_screen.dart';

/// The series' episodes block on the phone detail page (DEC-131): an
/// "Afleveringen" heading, the season pill with its watched count, and the
/// episode rows, inline under the header instead of behind mockup 07's tabs.
/// Season selection reuses the exact
/// `setState(() => _selectedSeasonIndex = index); _fetchSeasonEpisodes(index);`
/// contract `_buildSeasonTabsContent` (`media_detail_screen.dart`) already
/// uses for its horizontal tab row, so per-season pagination state
/// (`_seasonEpisodePager`) stays intact when switching seasons here.
extension _MobileEpisodesSection on _MediaDetailScreenState {
  Widget _buildMobileEpisodesSection(BuildContext context, MediaItem metadata) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        _buildMobileSectionTitle(context, t.libraries.groupings.episodes),
        const SizedBox(height: 12),
        _buildMobileEpisodesContent(context, metadata),
      ],
    );
  }

  Widget _buildMobileEpisodesContent(BuildContext context, MediaItem metadata) {
    final showFlattened = _showEpisodesDirectly || metadata.isSeason;

    return Column(
      crossAxisAlignment: .start,
      children: [
        // Mockup 07 always shows the season pill with its "x afleveringen ·
        // y bekeken" count, also for a series with a single season, which
        // this screen otherwise flattens (`_showEpisodesDirectly`). Michel,
        // 24 September: it went missing on a one-season show.
        if (!metadata.isSeason && _seasons.isNotEmpty) ...[
          _buildMobileSeasonPicker(context),
          const SizedBox(height: 12),
        ],
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
          // Mono tokens, not the Material container roles: monoTheme maps
          // secondaryContainer (and primaryContainer, surfaceContainerHighest,
          // surfaceBright) onto c.surface, the exact colour of the page behind
          // this chip, so the pill the mockup shows was drawn in the
          // background colour and could not be seen at all. Same trap as
          // DEC-053.
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: tokens(context).surfaceElevated, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: .min,
              children: [
                Text(
                  current.title ?? '',
                  style: TextStyle(fontWeight: .w700, color: tokens(context).text),
                ),
                Icon(Icons.expand_more_rounded, color: tokens(context).text, size: 20),
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
}
