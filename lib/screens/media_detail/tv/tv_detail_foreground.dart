part of '../../media_detail_screen.dart';

/// The info band over the backdrop: logo or title, metadata, synopsis, actions.
extension _MediaDetailTvForeground on _MediaDetailScreenState {
  Widget _buildTvDetailForeground(
    BuildContext context,
    MediaItem metadata, {
    required bool hideSpoilers,
    required double scale,
  }) {
    final theme = Theme.of(context);
    final description = _tvDetailDescription(metadata, hideSpoilers: hideSpoilers);
    final foregroundColor = _tvDetailForegroundColor(context);
    // This block sits on the fullscreen spotlight artwork. Dimmed ink reads as
    // secondary white-on-dark, but as washed-out black over bright artwork,
    // light mode keeps more of it.
    final mutedForegroundColor = foregroundColor.withValues(alpha: theme.brightness == Brightness.light ? 0.94 : 0.78);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 0 || constraints.maxWidth <= 0) return const SizedBox.shrink();

        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 264.0;
        final metrics = _tvDetailForegroundBaseMetrics(context, metadata, scale, constraints.maxWidth);
        final desiredLogoHeight = 220 * scale;
        final minLogoHeight = metrics.minLogoHeight;
        final desiredLogoWidth = 790 * scale;
        final metadataLineHeight = metrics.metadataLineHeight;
        final logoMetadataGap = metrics.logoMetadataGap;
        final summaryGap = metrics.summaryGap;
        // DENS1: HIG Body (29 pt), Caption 1 (25 pt) on a cramped band.
        final pt = TvHig.of(context);
        final summaryFontSize = availableHeight < 260 * scale ? TvHig.caption1 * pt : TvHig.body * pt;
        final summaryLineHeight = summaryFontSize * 1.35;
        final descriptionStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
          color: mutedForegroundColor,
          fontSize: summaryFontSize,
          height: 1.35,
        );
        // `_buildActionButtons` draws the row at `_tvDetailActionPt` HIG points
        // (same `TvLayoutConstants.scaleOf` now that `scale` is that value, see
        // DEC-109), so this reserve agrees with what actually gets drawn.
        final actionHeight = metrics.actionHeight;
        final actionGap = metrics.actionGap;
        final sourceLineHeight = metrics.sourceLineHeight;
        final hasDescription = description != null && description.isNotEmpty;
        // Genres come from the show/movie, not the focused episode, so the line
        // stays stable as episode rows gain focus.
        final genres = metadata.genres ?? const <String>[];
        final genreGap = 6 * scale;
        final genreLineHeight = TvHig.caption1Leading * pt;
        final genreLineCount = _tvDetailGenreLineCount(context, genres, scale, constraints.maxWidth);
        final genreBlockHeight = metrics.genreBlockHeight;
        // DEC-109: `TvViewAllAction`'s real rendered height, reserved only for
        // the lines where the synopsis actually truncates. Measured, not
        // guessed, a guessed line-height multiplier and the real render can
        // only drift apart (see `_unifiedSourceLineHeight` on the same point).
        final readMoreGap = metrics.summaryGap;
        final readMoreHeight = _tvDetailReadMoreHeight(context, scale);
        var summaryMaxLines = 0;
        var logoHeight = 0.0;
        var readMoreVisible = false;

        for (var lines = hasDescription ? 3 : 0; lines >= 0; lines--) {
          final descriptionHeight = lines > 0 ? summaryGap + (summaryLineHeight * lines) : 0.0;
          final overflowsAtLines =
              lines > 0 && _tvDetailSynopsisOverflows(description!, descriptionStyle, constraints.maxWidth, lines);
          final readMoreReserve = overflowsAtLines ? readMoreGap + readMoreHeight : 0.0;
          final reservedHeight =
              logoMetadataGap +
              metadataLineHeight +
              genreBlockHeight +
              descriptionHeight +
              readMoreReserve +
              actionGap +
              actionHeight +
              sourceLineHeight;
          final remainingForLogo = availableHeight - reservedHeight;
          // DET6 (Michel, 13 september, hardware): `_tvDetailIdealForegroundHeight`
          // is built from exactly these same terms, so at its own target this
          // comparison is an equality by construction, `remainingForLogo` and
          // `minLogoHeight` are the same real number computed two different
          // ways. Floating-point addition is not associative, so one of the
          // two came out a few ULPs below the other (observed: 50.99999999999997
          // vs 51.0) and tipped an exact-fit case into the one-line tier below
          // it. `_tvDetailEpsilon` absorbs that noise without hiding a real
          // shortfall, a genuine deficit is orders of magnitude bigger.
          if (remainingForLogo >= minLogoHeight - _tvDetailEpsilon || lines == 0) {
            summaryMaxLines = lines;
            readMoreVisible = overflowsAtLines;
            logoHeight = remainingForLogo <= 0 ? 0 : remainingForLogo.clamp(0, desiredLogoHeight).toDouble();
            break;
          }
        }

        // Read by `_focusAboveActionRow`, outside the build phase, to know
        // whether UP from the action row has anywhere to go (DEC-109).
        _tvDetailReadMoreVisible = readMoreVisible;
        final showLogo = logoHeight > 0;
        final descriptionHeight = summaryMaxLines > 0 ? summaryGap + (summaryLineHeight * summaryMaxLines) : 0.0;
        final readMoreBlockHeight = readMoreVisible ? readMoreGap + readMoreHeight : 0.0;
        final contentHeight =
            (showLogo ? logoHeight + logoMetadataGap : 0) +
            metadataLineHeight +
            genreBlockHeight +
            descriptionHeight +
            readMoreBlockHeight +
            actionGap +
            actionHeight +
            sourceLineHeight;
        final logoWidth = desiredLogoWidth < constraints.maxWidth ? desiredLogoWidth : constraints.maxWidth;

        return ClipRect(
          child: SizedBox(
            height: availableHeight,
            child: Align(
              alignment: .bottomLeft,
              child: SizedBox(
                height: contentHeight <= availableHeight ? contentHeight : availableHeight,
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    if (showLogo) ...[
                      _buildDetailLogoOrTitle(
                        context,
                        metadata,
                        width: logoWidth,
                        height: logoHeight,
                        titleBuilder: (context, title) => _buildDetailTitle(
                          context,
                          title,
                          // DENS1: HIG Title 1 (76 pt); `56 * scaleOf` was 88.
                          fontSize: TvHig.title1 * pt,
                          fontWeight: .w800,
                          shadowBlur: 12,
                          color: foregroundColor,
                          shadowColor: _tvDetailTitleShadowColor(context),
                        ),
                      ),
                      SizedBox(height: logoMetadataGap),
                    ],
                    SizedBox(
                      height: metadataLineHeight,
                      child: Align(alignment: .centerLeft, child: _buildTvDetailMetadataLine(context, metadata, scale)),
                    ),
                    if (genres.isNotEmpty) ...[
                      SizedBox(height: genreGap),
                      SizedBox(
                        height: genreLineHeight * genreLineCount,
                        child: Align(
                          alignment: .centerLeft,
                          child: Text(
                            genres.join('  •  '),
                            maxLines: genreLineCount,
                            overflow: .ellipsis,
                            style: _tvDetailGenreTextStyle(context).copyWith(color: mutedForegroundColor),
                          ),
                        ),
                      ),
                    ],
                    if (hasDescription && summaryMaxLines > 0) ...[
                      SizedBox(height: summaryGap),
                      SizedBox(
                        height: summaryLineHeight * summaryMaxLines,
                        child: Text(
                          description,
                          maxLines: summaryMaxLines,
                          overflow: .ellipsis,
                          style: descriptionStyle,
                        ),
                      ),
                      if (readMoreVisible) ...[
                        SizedBox(height: readMoreGap),
                        TvViewAllAction(
                          label: t.discover.readMore,
                          semanticLabel: t.discover.readMoreSemantic,
                          focusNode: _tvDetailReadMoreFocusNode,
                          onSelect: () => _openTvDetailSynopsisPanel(description),
                          // Own focus stop between the synopsis and the action
                          // row (DEC-109): UP from the action row lands here,
                          // UP again reaches the topnav, DOWN returns.
                          onNavigateUp: _focusTopNavigationFromDetail,
                          onNavigateDown: _focusTvDetailActionRow,
                        ),
                      ],
                    ],
                    SizedBox(height: actionGap),
                    SizedBox(height: actionHeight, child: _buildActionButtons(metadata)),
                    _buildUnifiedSourceLine(),
                    // Live viewer, then the "Watched by …" row (Plex, owned
                    // servers only).
                    NowWatchingLine(ratingKey: _metadata.id, serverId: serverIdOrNull(_metadata.serverId)),
                    if (_watchers?.watchers.isNotEmpty ?? false) ...[
                      const SizedBox(height: 20),
                      WatchedByRow(watchers: _watchers!.watchers, scope: _watchers!.scope, avatarSize: 36),
                    ],
                    if (_watchStats?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      WatchStatsRow(stats: _watchStats!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _tvDetailForegroundColor(BuildContext context) => Theme.of(context).colorScheme.onSurface;

  Color _tvDetailTitleShadowColor(BuildContext context) {
    final brightness = Theme.of(context).colorScheme.brightness;
    return brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.55);
  }

  Widget _buildDetailLogoOrTitle(
    BuildContext context,
    MediaItem metadata, {
    required double width,
    required double height,
    required Widget Function(BuildContext context, String title) titleBuilder,
  }) {
    Widget titleFallback(BuildContext context) => titleBuilder(context, metadata.displayTitle);

    if (metadata.clearLogoPath == null) {
      return SizedBox(width: width, height: height, child: titleFallback(context));
    }

    return SizedBox(
      width: width,
      height: height,
      child: Builder(
        builder: (context) {
          final localArtwork = _buildOfflineArtworkIfAvailable(
            context,
            artworkPaths: [metadata.clearLogoPath],
            fit: BoxFit.contain,
            alignment: .centerLeft,
            imageType: ImageType.logo,
            errorWidget: (context, url, error) => titleFallback(context),
          );
          if (localArtwork != null) return localArtwork;

          final client = _getArtworkMediaClient(context);
          final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
          final logoUrl = MediaImageHelper.getOptimizedImageUrl(
            client: client,
            thumbPath: metadata.clearLogoPath,
            maxWidth: width,
            maxHeight: height,
            devicePixelRatio: dpr,
            imageType: ImageType.logo,
          );

          if (logoUrl.isEmpty) return titleFallback(context);

          return blurArtwork(
            CachedNetworkImage(
              imageUrl: logoUrl,
              cacheManager: PlexImageCacheManager.instance,
              filterQuality: FilterQuality.medium,
              fit: BoxFit.contain,
              alignment: .centerLeft,
              memCacheWidth: (width * dpr).clamp(200, 1000).round(),
              placeholder: (context, url) => const SizedBox.shrink(),
              errorBuilder: (context, error, stackTrace) => titleFallback(context),
            ),
            sigma: 10,
            clip: false,
          );
        },
      ),
    );
  }

  Widget _buildTvDetailMetadataLine(BuildContext context, MediaItem metadata, double scale) {
    final lineMetadata = _tvDetailFocusedEpisode ?? metadata;
    final episodeLabel = formatSeasonEpisodeLabel(lineMetadata.parentIndex, lineMetadata.index);
    final qualityLabels = buildMediaQualityLabels(lineMetadata);
    final textStyle = TextStyle(
      color: _tvDetailForegroundColor(context),
      // DENS1: HIG Caption 1 (25 pt); `18 * scaleOf` bold was 28.
      fontSize: TvHig.caption1 * TvHig.of(context),
      fontWeight: .w600,
      letterSpacing: 0.1,
    );
    final children = <Widget>[];

    void addSeparator() {
      if (children.isNotEmpty) children.add(Text('  •  ', maxLines: 1, style: textStyle));
    }

    void addTextPart(String text) {
      addSeparator();
      children.add(Text(text, maxLines: 1, style: textStyle));
    }

    void addWidgetPart(Widget widget) {
      addSeparator();
      children.add(widget);
    }

    if (lineMetadata.isEpisode && episodeLabel != null) addTextPart(episodeLabel);
    if (lineMetadata.isMovie) {
      addTextPart(t.discover.movie);
    } else if (lineMetadata.isShow) {
      addTextPart(t.discover.tvShow);
    }
    final ratingBadge = MediaRatingBadge.inlineForMedia(
      item: lineMetadata,
      fallbackItem: metadata,
      foregroundColor: textStyle.color,
      iconSize: textStyle.fontSize,
      spacing: 4 * scale,
      textStyle: textStyle,
    );
    if (ratingBadge != null) {
      addWidgetPart(ratingBadge);
    }
    if (lineMetadata.contentRating != null) addTextPart(formatContentRating(lineMetadata.contentRating!));
    if (lineMetadata.durationMs != null) addTextPart(formatDurationTextual(lineMetadata.durationMs!));
    if (lineMetadata.isEpisode && lineMetadata.originallyAvailableAt != null) {
      addTextPart(formatAbbreviatedDate(lineMetadata.originallyAvailableAt!));
    } else if (lineMetadata.year != null) {
      addTextPart(lineMetadata.year.toString());
    }
    for (final label in qualityLabels) {
      addTextPart(label);
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  String? _tvDetailDescription(MediaItem metadata, {required bool hideSpoilers}) {
    final focusedEpisode = _tvDetailFocusedEpisode;
    if (focusedEpisode == null) return _tvDetailItemDescription(metadata, hideSpoilers: hideSpoilers);

    final episodeDescription = _tvDetailItemDescription(
      focusedEpisode,
      hideSpoilers: hideSpoilers,
      showSpoilerFallback: false,
    );
    if (episodeDescription != null) return episodeDescription;

    final season = _tvDetailSeasonForEpisode(focusedEpisode, metadata);
    final seasonDescription = season == null ? null : _tvDetailItemDescription(season, hideSpoilers: hideSpoilers);
    if (seasonDescription != null) return seasonDescription;

    final showDescription = _tvDetailItemDescription(metadata, hideSpoilers: hideSpoilers);
    if (showDescription != null) return showDescription;

    if (hideSpoilers && focusedEpisode.shouldHideSpoiler) return focusedEpisode.title;
    return null;
  }

  String? _tvDetailItemDescription(MediaItem item, {required bool hideSpoilers, bool showSpoilerFallback = true}) {
    final shouldHideSpoiler = hideSpoilers && item.shouldHideSpoiler;
    final summary = shouldHideSpoiler ? null : item.summary;
    if (summary != null && summary.isNotEmpty) return summary;
    if (showSpoilerFallback && shouldHideSpoiler && item.isEpisode) return item.title;
    return null;
  }

  MediaItem? _tvDetailSeasonForEpisode(MediaItem episode, MediaItem metadata) {
    for (final season in _seasons) {
      if (episode.parentId != null && season.id == episode.parentId) return season;
      if (episode.parentIndex != null && season.index == episode.parentIndex) return season;
    }
    if (metadata.isSeason &&
        ((episode.parentId != null && metadata.id == episode.parentId) ||
            (episode.parentIndex != null && metadata.index == episode.parentIndex))) {
      return metadata;
    }
    return null;
  }
}
