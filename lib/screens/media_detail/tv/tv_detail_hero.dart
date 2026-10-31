part of '../../media_detail_screen.dart';

/// The first screen of the film detail page.
extension _MediaDetailTvHero on _MediaDetailScreenState {
  /// The metadata line, in the order 06 reads: year, runtime, genres, rating.
  Widget _buildTvDetailMetaRow(MediaItem metadata, Color ink) {
    final pt = TvHig.of(context);
    final style = TextStyle(color: ink, fontSize: TvHig.caption2 * pt);
    final genres = metadata.genres?.join(', ') ?? '';
    final rating = metadata.contentRating == null ? '' : formatContentRating(metadata.contentRating);
    final parts = [
      if (metadata.year != null) metadata.year.toString(),
      if (metadata.durationMs != null) formatDurationTextual(metadata.durationMs!),
    ];
    return Row(
      mainAxisSize: .min,
      children: [
        for (final part in parts) ...[Text(part, maxLines: 1, style: style), SizedBox(width: 24 * pt)],
        // Every genre, on a second line when they do not fit on one.
        if (genres.isNotEmpty) ...[
          Flexible(
            child: Text(genres, maxLines: 2, overflow: .ellipsis, style: style),
          ),
          SizedBox(width: 24 * pt),
        ],
        if (rating.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10 * pt, vertical: 2 * pt),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(6 * pt),
            ),
            child: Text(
              rating,
              maxLines: 1,
              style: style.copyWith(color: Colors.white, fontWeight: .w600),
            ),
          ),
      ],
    );
  }

  /// Scores from the source-tagged list, or the single flat rating a title
  /// without one still carries (a downloaded item, an older cache entry).
  Widget? _buildTvDetailScores(MediaItem metadata, Color ink) {
    if (metadata.externalRatings.isNotEmpty) {
      return TvDetailScoreRow(ratings: metadata.externalRatings, color: ink);
    }
    final pt = TvHig.of(context);
    return MediaRatingBadge.inlineForMedia(
      item: metadata,
      fallbackItem: metadata,
      foregroundColor: ink,
      iconSize: TvHig.caption2 * pt,
      spacing: 8 * pt,
      textStyle: TextStyle(color: ink, fontSize: TvHig.caption2 * pt, fontWeight: .w500),
    );
  }

  /// What the file holds. The first label is the prediction of what Play uses
  /// ([resolveDetailTracks]); before that loads, or on a server that does not
  /// answer, what the media versions say.
  List<({IconData? icon, String text})> _tvDetailTechLabels(MediaItem metadata) {
    final info = _detailFileInfo;
    final target = _detailAudioTarget;
    if (info == null || target == null) {
      return [for (final label in buildMediaQualityLabels(metadata)) (icon: null, text: label)];
    }
    final audio = _detailAudioTracks.where((track) => track.id == _selectedDetailAudioTrackId).firstOrNull;
    final subtitle = _detailSubtitleTracks.where((track) => track.id == _selectedDetailSubtitleTrackId).firstOrNull;
    return [
      if (detailVideoLabel(info, item: target) case final video?) (icon: null, text: video),
      if (audio != null) (icon: Symbols.volume_up_rounded, text: detailAudioLabel(audio)),
      (icon: Symbols.subtitles_rounded, text: subtitle?.label.primary ?? t.common.off),
    ];
  }

  /// The logo or the title, standing on the bottom of its slot so the metadata
  /// line follows at the same height for both.
  Widget _buildTvDetailHeading(MediaItem metadata, Color ink) {
    final pt = TvHig.of(context);
    return _buildDetailLogoOrTitle(
      context,
      metadata,
      width: (metadata.clearLogoPath == null ? TvDetailLayout.titleWidth : TvDetailLayout.logoWidth) * pt,
      height: TvDetailLayout.headingHeight * pt,
      alignment: Alignment.bottomLeft,
      // Two lines of type need more than a mark does, and they grow upwards:
      // what stands under the title stays where it is.
      titleBuilder: (context, title) => OverflowBox(
        maxHeight: TvDetailLayout.titleHeight * pt,
        alignment: Alignment.bottomLeft,
        child: _buildDetailTitle(
          context,
          title,
          fontSize: TvHig.title1 * pt,
          fontWeight: .w800,
          shadowBlur: 12,
          color: ink,
          shadowColor: _tvDetailTitleShadowColor(context),
          alignment: Alignment.bottomLeft,
        ),
      ),
    );
  }

  /// Who else is watching on the left, what the file is on the right. Nothing
  /// at all when neither has anything to say, so the first section moves up
  /// instead of leaving a hole.
  List<Widget> _buildTvDetailActivityRow(List<({IconData? icon, String text})> techLabels) {
    final pt = TvHig.of(context);
    final serverId = serverIdOrNull(_metadata.serverId);
    final watchers = _tvDetailActivity();
    final stats = _watchStats;
    final hasWatchers = watchers?.watchers.isNotEmpty ?? false;
    final hasStats = stats?.isNotEmpty ?? false;
    final hasActivity = hasWatchers || hasStats || NowWatchingLine.sessionFor(context, _metadata.id, serverId) != null;
    if (!hasActivity && techLabels.isEmpty) return const [];
    return [
      SizedBox(height: TvDetailLayout.activityGap * pt),
      // Nothing here is clipped: the hero grows with its rows, where the old
      // band cut off whatever came after the source line.
      Row(
        crossAxisAlignment: .center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                NowWatchingLine(ratingKey: _metadata.id, serverId: serverId),
                if (hasWatchers) ...[
                  SizedBox(height: 8 * pt),
                  AutomationNode(
                    id: AutomationIds.mediaDetailActivity,
                    role: 'text',
                    state: () => {'names': watchers.watchers.length},
                    child: WatchedByRow(
                      watchers: watchers!.watchers,
                      scope: watchers.scope,
                      avatarSize: TvDetailLayout.activityAvatarSize * pt,
                      avatarOverlap: TvDetailLayout.activityAvatarOverlap * pt,
                      textGap: TvDetailLayout.activityTextGap * pt,
                      ringWidth: TvDetailLayout.activityAvatarRing * pt,
                      maxLines: 1,
                      textStyle: TextStyle(color: tokens(context).textMuted, fontSize: TvHig.caption2 * pt),
                    ),
                  ),
                ],
                if (hasStats) ...[SizedBox(height: 8 * pt), WatchStatsRow(stats: stats!)],
              ],
            ),
          ),
          if (techLabels.isNotEmpty) ...[
            SizedBox(width: 24 * pt),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: TvDetailLayout.techLabelsMaxWidth * pt),
              child: TvDetailTechLabels(labels: techLabels),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _buildTvDetailHero(BuildContext context, MediaItem metadata, Size size, {required bool hideSpoilers}) {
    _scheduleDetailAudioTracksLoad(metadata);
    final pt = TvHig.of(context);
    final ink = _tvDetailForegroundColor(context);
    final muted = tokens(context).textMuted;
    final margin = TvDetailLayout.leftMargin(size.width);
    final hasTabs = metadata.isShow;
    final onSeason = hasTabs && _tvDetailSeasonTabActive;
    final season = onSeason ? _tvDetailOpenSeason : null;
    final description =
        _tvDetailDescription(season ?? metadata, hideSpoilers: hideSpoilers) ??
        _tvDetailItemDescription(metadata, hideSpoilers: hideSpoilers);
    final synopsisWidth = TvDetailLayout.synopsisWidth * pt;
    final synopsisStyle = TextStyle(
      color: ink,
      fontSize: TvHig.caption1 * pt,
      height: TvHig.caption1Leading / TvHig.caption1,
    );
    final readMoreVisible =
        description != null &&
        _tvDetailSynopsisOverflows(description, synopsisStyle, synopsisWidth, TvDetailLayout.synopsisLines);
    _tvDetailReadMoreVisible = readMoreVisible;
    final directors = metadata.directors ?? const <String>[];
    final scores = _buildTvDetailScores(metadata, ink);
    // Beside the text rather than under it: a long synopsis is the ordinary
    // case, and a row of its own would move everything under it off the height
    // of the northstar.
    final synopsis = description == null
        ? null
        : Row(
            mainAxisSize: .min,
            crossAxisAlignment: .end,
            children: [
              SizedBox(
                width: synopsisWidth,
                child: Text(
                  description,
                  maxLines: TvDetailLayout.synopsisLines,
                  overflow: .ellipsis,
                  style: synopsisStyle,
                ),
              ),
              if (readMoreVisible) ...[
                SizedBox(width: 12 * pt),
                AutomationNode(
                  id: AutomationIds.mediaDetailReadMore,
                  role: 'button',
                  focusNode: _tvDetailReadMoreFocusNode,
                  child: TvViewAllAction(
                    label: t.discover.readMore,
                    semanticLabel: t.discover.readMoreSemantic,
                    focusNode: _tvDetailReadMoreFocusNode,
                    onSelect: () => _openTvDetailSynopsisPanel(description),
                    onNavigateUp: _focusAboveTvDetailHero,
                    onNavigateDown: onSeason ? _focusBelowTvDetailTabs : _focusTvDetailActionRow,
                  ),
                ),
              ],
            ],
          );
    final rowHeadroom = TvCatalogGrid.focusHeadroom(
      cardHeight: TvDetailLayout.wideCardHeight * pt,
      focusScale: FocusTheme.fullCardFocusScale,
    );

    return Stack(
      // The artwork hangs on past the hero's foot, under the first row.
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: size.height,
          child: TvDetailHeroArt(
            item: metadata,
            client: _getArtworkMediaClient(context),
            localPath: widget.isOffline ? (path) => _offlineArtworkLocalPath(context, path) : null,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: margin,
            right: TvDetailLayout.rightMargin * pt,
            // The tabs sit in the band the collapsed bar leaves free: the shell's
            // inset is there to keep clear of a bar that is not on screen here.
            top: hasTabs
                ? TvDetailLayout.tabsTop * pt
                : (TvDetailLayout.headingTop * pt).clamp(MediaQuery.paddingOf(context).top, double.infinity),
            bottom: onSeason ? TvDetailLayout.seasonRowGap * pt - rowHeadroom : TvDetailLayout.sectionGap * pt,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              if (hasTabs)
                Padding(
                  padding: EdgeInsets.only(left: TvDetailLayout.tabInset * pt),
                  child: _buildTvDetailTabs(),
                ),
              if (onSeason)
                ..._buildTvDetailSeasonRows(
                  metadata: metadata,
                  season: season,
                  synopsis: synopsis,
                  ink: ink,
                  muted: muted,
                )
              else ...[
                if (hasTabs)
                  SizedBox(
                    height: (TvDetailLayout.headingTop - TvDetailLayout.tabsTop - TvDetailLayout.tabHeight) * pt,
                  ),
                _buildTvDetailHeading(metadata, ink),
                SizedBox(height: TvDetailLayout.metaGap * pt),
                _buildTvDetailMetaRow(metadata, ink),
                if (scores != null) ...[SizedBox(height: TvDetailLayout.scoreGap * pt), scores],
                if (synopsis != null) ...[SizedBox(height: TvDetailLayout.synopsisGap * pt), synopsis],
                if (directors.isNotEmpty) ...[
                  SizedBox(height: TvDetailLayout.directorGap * pt),
                  Text(
                    t.discover.directedBy(names: directors.join(', ')),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(color: muted, fontSize: TvHig.caption2 * pt),
                  ),
                ],
                SizedBox(height: TvDetailLayout.actionRowGap * pt),
                _buildTvDetailActionRow(metadata),
                _buildUnifiedSourceLine(),
                ..._buildTvDetailActivityRow(metadata.isMovie ? _tvDetailTechLabels(metadata) : const []),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
