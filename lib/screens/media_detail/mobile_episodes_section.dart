part of '../media_detail_screen.dart';

/// The episodes block on the phone detail page. Since DEC-140 a series
/// shows its seasons as a poster rail and each season opens its own page with
/// the "Afleveringen" list (DEC-131's row style); the season pill is gone.
/// The inline list stays for a series whose seasons have not loaded, failed
/// to load, or are only Specials, so those episodes remain reachable.
extension _MobileEpisodesSection on _MediaDetailScreenState {
  Widget _buildMobileSeasonsOrEpisodes(BuildContext context, MediaItem metadata) {
    if (metadata.isShow && _seasons.any((season) => season.index != 0)) {
      return DetailSeasonsRail(
        seasons: _seasons,
        client: _getMediaClientForMetadata(context),
        // Back from a season page that changed watch state refreshes the
        // posters' progress.
        onOpen: (season) => unawaited(
          navigateToMediaItemDetails(
            context,
            season,
            isOffline: widget.isOffline,
            onRefresh: widget.isOffline ? null : (_) => unawaited(_loadSeasons()),
          ),
        ),
      );
    }
    return _buildMobileEpisodesSection(context, metadata);
  }

  /// First episode of this season not yet watched, else the first one: what
  /// the season page's main button and tech table are about.
  MediaItem? get _seasonNextEpisode =>
      _episodes.where((episode) => !episode.isWatched).firstOrNull ?? _episodes.firstOrNull;

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
}
