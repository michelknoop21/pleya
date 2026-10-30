part of '../../media_detail_screen.dart';

/// The first screen of the film detail page.
extension _MediaDetailTvHero on _MediaDetailScreenState {
  Widget _buildTvDetailHero(BuildContext context, MediaItem metadata, Size size, {required bool hideSpoilers}) {
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final ink = _tvDetailForegroundColor(context);
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
    final genres = metadata.genres ?? const <String>[];

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
              left: TvDetailLayout.leftMargin(size.width),
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
                _buildTvDetailMetadataLine(context, metadata, scale),
                if (genres.isNotEmpty) ...[
                  SizedBox(height: 8 * pt),
                  Text(
                    genres.join('  •  '),
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: _tvDetailGenreTextStyle(context).copyWith(color: ink),
                  ),
                ],
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
                  TvViewAllAction(
                    label: t.discover.readMore,
                    semanticLabel: t.discover.readMoreSemantic,
                    focusNode: _tvDetailReadMoreFocusNode,
                    onSelect: () => _openTvDetailSynopsisPanel(description),
                    onNavigateUp: _focusTopNavigationFromDetail,
                    onNavigateDown: _focusTvDetailActionRow,
                  ),
                ],
                SizedBox(height: 24 * pt),
                SizedBox(height: _tvDetailActionPt * pt, child: _buildActionButtons(metadata)),
                _buildUnifiedSourceLine(),
                SizedBox(height: 28 * pt),
                // Nothing here is clipped: the hero grows with its rows, where
                // the old band cut off whatever came after the source line.
                NowWatchingLine(ratingKey: _metadata.id, serverId: serverIdOrNull(_metadata.serverId)),
                if (_watchers?.watchers.isNotEmpty ?? false) ...[
                  SizedBox(height: 8 * pt),
                  WatchedByRow(watchers: _watchers!.watchers, scope: _watchers!.scope, avatarSize: 48 * pt),
                ],
                if (_watchStats?.isNotEmpty ?? false) ...[SizedBox(height: 8 * pt), WatchStatsRow(stats: _watchStats!)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
