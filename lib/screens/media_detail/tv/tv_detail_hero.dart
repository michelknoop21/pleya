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

  Widget _buildTvDetailHero(BuildContext context, MediaItem metadata, Size size, {required bool hideSpoilers}) {
    _scheduleDetailAudioTracksLoad(metadata);
    final pt = TvHig.of(context);
    final ink = _tvDetailForegroundColor(context);
    final muted = tokens(context).textMuted;
    final margin = TvDetailLayout.leftMargin(size.width);
    final description = _tvDetailItemDescription(metadata, hideSpoilers: hideSpoilers);
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
    final techLabels = _tvDetailTechLabels(metadata);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: size.height * TvDetailLayout.heroHeightFraction),
      child: Stack(
        alignment: .bottomLeft,
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: size.width * 0.62,
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
              top: MediaQuery.paddingOf(context).top,
            ),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                _buildDetailLogoOrTitle(
                  context,
                  metadata,
                  width: (metadata.clearLogoPath == null ? TvDetailLayout.titleWidth : TvDetailLayout.logoWidth) * pt,
                  height:
                      (metadata.clearLogoPath == null ? TvDetailLayout.titleHeight : TvDetailLayout.logoHeight) * pt,
                  titleBuilder: (context, title) => _buildDetailTitle(
                    context,
                    title,
                    fontSize: TvHig.title1 * pt,
                    fontWeight: .w800,
                    shadowBlur: 12,
                    color: ink,
                    shadowColor: _tvDetailTitleShadowColor(context),
                  ),
                ),
                SizedBox(height: 8 * pt),
                _buildTvDetailMetaRow(metadata, ink),
                if (scores != null) ...[SizedBox(height: 14 * pt), scores],
                if (description != null) ...[
                  SizedBox(height: 24 * pt),
                  SizedBox(
                    width: synopsisWidth,
                    child: Text(
                      description,
                      maxLines: TvDetailLayout.synopsisLines,
                      overflow: .ellipsis,
                      style: synopsisStyle,
                    ),
                  ),
                ],
                if (readMoreVisible) ...[
                  SizedBox(height: 6 * pt),
                  AutomationNode(
                    id: AutomationIds.mediaDetailReadMore,
                    role: 'button',
                    focusNode: _tvDetailReadMoreFocusNode,
                    child: TvViewAllAction(
                      label: t.discover.readMore,
                      semanticLabel: t.discover.readMoreSemantic,
                      focusNode: _tvDetailReadMoreFocusNode,
                      onSelect: () => _openTvDetailSynopsisPanel(description),
                      onNavigateUp: _focusTopNavigationFromDetail,
                      onNavigateDown: _focusTvDetailActionRow,
                    ),
                  ),
                ],
                if (directors.isNotEmpty) ...[
                  SizedBox(height: 14 * pt),
                  Text(
                    t.discover.directedBy(names: directors.join(', ')),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(color: muted, fontSize: TvHig.caption2 * pt),
                  ),
                ],
                SizedBox(height: 24 * pt),
                _buildTvDetailActionRow(metadata),
                _buildUnifiedSourceLine(),
                SizedBox(height: 28 * pt),
                // Nothing here is clipped: the hero grows with its rows, where
                // the old band cut off whatever came after the source line.
                Row(
                  crossAxisAlignment: .center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        mainAxisSize: .min,
                        children: [
                          NowWatchingLine(ratingKey: _metadata.id, serverId: serverIdOrNull(_metadata.serverId)),
                          if (_watchers?.watchers.isNotEmpty ?? false) ...[
                            SizedBox(height: 8 * pt),
                            WatchedByRow(
                              watchers: _watchers!.watchers,
                              scope: _watchers!.scope,
                              avatarSize: TvDetailLayout.actionSize * pt * 0.75,
                            ),
                          ],
                          if (_watchStats?.isNotEmpty ?? false) ...[
                            SizedBox(height: 8 * pt),
                            WatchStatsRow(stats: _watchStats!),
                          ],
                        ],
                      ),
                    ),
                    if (techLabels.isNotEmpty) ...[
                      SizedBox(width: 24 * pt),
                      Flexible(flex: 2, child: TvDetailTechLabels(labels: techLabels)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
