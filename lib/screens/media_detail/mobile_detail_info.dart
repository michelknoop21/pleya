part of '../media_detail_screen.dart';

/// Synopsis, credits, the play button with its icon row and the section
/// headings of the mobile detail page (northstar 06, DEC-131; D-01, DEC-140).
extension _MobileMediaDetailInfo on _MediaDetailScreenState {
  /// Synopsis (reuses [CollapsibleText] unchanged, DEC-109: mobile/desktop
  /// keep this in-place expand rather than the TV "Meer lezen" panel) plus
  /// the compact "Cast: … / Regie: …" text lines from mockup 06/the
  /// serie-detail comp.
  Widget _buildMobileSynopsisAndCredits(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);
    final summary = metadata.summary;
    final roles = metadata.roles;
    final directors = metadata.directors;
    final genres = metadata.genres;
    final studio = metadata.studio;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget labelled(String label, String value) => Text.rich(
      TextSpan(
        style: mutedStyle,
        children: [
          TextSpan(
            text: '$label: ',
            style: mutedStyle?.copyWith(fontWeight: .w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: .start,
      children: [
        // The genre line the TV detail draws under its metadata.
        if (genres != null && genres.isNotEmpty) ...[
          Text(genres.join(' · '), style: mutedStyle?.copyWith(fontWeight: .w600)),
          const SizedBox(height: 8),
        ],
        if (summary != null && summary.isNotEmpty) ...[
          CollapsibleText(text: summary, maxLines: 6, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
        ],
        if (roles != null && roles.isNotEmpty) labelled(t.discover.cast, roles.take(3).map((r) => r.tag).join(', ')),
        if (directors != null && directors.isNotEmpty) ...[
          const SizedBox(height: 4),
          labelled(t.metadataEdit.director, directors.join(', ')),
        ],
        if (studio != null && studio.isNotEmpty) ...[const SizedBox(height: 4), labelled(t.discover.studio, studio)],
      ],
    );
  }

  /// Play, "play from start" and the icon row (D-01/D-03, DEC-140). Every
  /// tap reuses the handler the TV row and the context menu already call;
  /// Delen and Aanvragen moved into the Meer menu, which this owns
  /// ([_contextMenuKey]) so the app bar's more button opens the same menu.
  Widget _buildMobilePrimaryActions(BuildContext context, MediaItem metadata, {bool glass = false}) {
    final resumeTarget = metadata.isShow
        ? (_onDeckEpisode ?? metadata)
        : metadata.isSeason
        ? (_seasonNextEpisode ?? metadata)
        : metadata;
    final viewOffsetMs = resumeTarget.viewOffsetMs ?? 0;
    final isResuming = viewOffsetMs > 0;
    final detail = StringBuffer();
    if ((metadata.isShow || metadata.isSeason) && resumeTarget.parentIndex != null && resumeTarget.index != null) {
      detail.write(
        '· ${t.discover.playEpisode(season: resumeTarget.parentIndex.toString(), episode: resumeTarget.index.toString())} ',
      );
    }
    final remaining = isResuming ? formatRemainingTime(resumeTarget.durationMs, viewOffsetMs) : null;
    if (remaining != null) detail.write('· $remaining');
    final playDetail = detail.toString().trim();

    final (onWatchlist, canOfferWatchlist) = _mobileWatchlistState(context, metadata);
    final isNumericRating = _getMediaClientForMetadata(context)?.capabilities.numericUserRating ?? true;
    final trailer = _getPrimaryTrailer();
    final seerrConfigured = context.watch<SeerrProvider?>()?.isConfigured ?? false;
    final canDownload = !metadata.isShow && !widget.isOffline && !PlatformDetector.isAppleTV();
    final downloadProvider = canDownload ? context.watch<DownloadProvider>() : null;

    void openMore() {
      final box = _contextMenuKey.currentContext?.findRenderObject() as RenderBox?;
      final position = box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
      _contextMenuKey.currentState?.showContextMenu(context, position: position);
    }

    return MediaContextMenu(
      key: _contextMenuKey,
      item: metadata,
      onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
      onPlayTrailer: trailer == null ? null : () => unawaited(navigateToVideoPlayer(context, metadata: trailer)),
      onShare: () {
        final anchor = _contextMenuKey.currentContext;
        if (anchor != null) unawaited(_shareMobileItem(anchor, metadata));
      },
      onRequest: (seerrConfigured && !widget.isOffline && (metadata.isMovie || metadata.isShow))
          ? () => unawaited(_handleRequestPressed(metadata))
          : null,
      child: DetailPrimaryActions(
        glass: glass,
        playLabel: isResuming ? t.common.resume : t.common.play,
        playDetail: playDetail.isEmpty ? null : playDetail,
        // A season plays its next episode, not its first (DEC-140).
        onPlay: () => unawaited(_handlePlayPressed(metadata.isSeason ? resumeTarget : metadata)),
        onPlayFromStart: isResuming ? () => unawaited(_handlePlayFromStartPressed(resumeTarget)) : null,
        actions: [
          if (canOfferWatchlist)
            DetailActionItem(
              key: const Key('media-detail.action.watchlist'),
              icon: onWatchlist ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              label: t.detailActions.watchlist,
              semanticLabel: onWatchlist ? t.watchlist.remove : t.watchlist.add,
              active: onWatchlist,
              onTap: () => unawaited(WatchlistUiActions.toggle(context, metadata)),
            ),
          if (trailer != null)
            DetailActionItem(
              key: const Key('media-detail.action.trailer'),
              icon: Icons.movie_outlined,
              label: t.detailActions.trailer,
              semanticLabel: t.tooltips.playTrailer,
              onTap: () => unawaited(navigateToVideoPlayer(context, metadata: trailer)),
            ),
          if (!widget.isOffline)
            DetailActionItem(
              key: const Key('media-detail.action.rate'),
              icon: isNumericRating ? Icons.star_border_rounded : Icons.thumb_up_outlined,
              label: t.detailActions.rate,
              semanticLabel: t.mediaMenu.rate,
              onTap: () => unawaited(_showRatingDialog(context, metadata)),
            ),
          DetailActionItem(
            key: const Key('media-detail.action.watched'),
            icon: Icons.check_circle_outline_rounded,
            label: t.detailActions.watched,
            semanticLabel: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
            active: metadata.isWatched,
            onTap: () => unawaited(_handleWatchedTogglePressed(metadata)),
          ),
          if (downloadProvider != null) _mobileDownloadAction(downloadProvider, metadata),
          if (!widget.isOffline)
            DetailActionItem(
              key: const Key('media-detail.action.more'),
              icon: Icons.more_vert_rounded,
              label: t.detailActions.more,
              semanticLabel: MaterialLocalizations.of(context).moreButtonTooltip,
              onTap: openMore,
            ),
        ],
      ),
    );
  }

  /// "Downloaden" with the state of the download as icon and spoken label;
  /// [_handleDownloadButtonPressed] runs the whole state machine (queue,
  /// pause/resume, retry, delete) unchanged.
  DetailActionItem _mobileDownloadAction(DownloadProvider downloadProvider, MediaItem metadata) {
    final globalKey = metadata.globalKey;
    final (icon, semanticLabel) = switch (downloadProvider.getProgress(globalKey)?.status) {
      _ when downloadProvider.isQueueing(globalKey) => (Icons.schedule_rounded, t.downloads.queuedTooltip),
      DownloadStatus.queued => (Icons.schedule_rounded, t.downloads.queuedTooltip),
      DownloadStatus.downloading => (Icons.downloading_rounded, t.downloads.downloadingTooltip),
      DownloadStatus.paused => (Icons.pause_circle_outline_rounded, t.downloads.resumeDownload),
      DownloadStatus.failed => (Icons.error_outline_rounded, t.downloads.retryDownload),
      DownloadStatus.cancelled => (Icons.cancel_rounded, t.downloads.cancelledDownload),
      _ when downloadProvider.isDownloaded(globalKey) => (Icons.download_done_rounded, t.downloads.downloadAction),
      _ => (Icons.download_rounded, t.downloads.downloadAction),
    };
    return DetailActionItem(
      key: const Key('media-detail.action.download'),
      icon: icon,
      label: t.detailActions.download,
      semanticLabel: semanticLabel,
      onTap: () => unawaited(_handleDownloadButtonPressed(metadata)),
    );
  }

  /// The restart button: the context menu's "Play from beginning" core
  /// ([playFromBeginning]), then the same refresh a normal play gets.
  Future<void> _handlePlayFromStartPressed(MediaItem target) async {
    final pick = _detailTrackPickFor(target);
    await playFromBeginning(
      context,
      target,
      isOffline: widget.isOffline,
      preferredAudioTrack: pick.audio,
      preferredSubtitleTrack: pick.subtitle,
    );
    if (!widget.isOffline && mounted) unawaited(refreshAfterPlayback(playedItemId: target.id));
  }

  /// The iOS share sheet anchored to the tapped button. share_plus needs
  /// `sharePositionOrigin` for the popover (required on iPad, and without it
  /// the sheet could fail to appear or leave the UI unresponsive); Michel saw
  /// exactly that on 24 September ("delen werkt niet"). A failure to present
  /// the sheet is shown, a dismissed sheet is not.
  Future<void> _shareMobileItem(BuildContext buttonContext, MediaItem metadata) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final year = metadata.year;
    final text = year == null ? metadata.displayTitle : '${metadata.displayTitle} ($year)';
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: metadata.displayTitle, sharePositionOrigin: origin),
      );
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, t.errors.failedToLoad(context: t.common.share));
    }
  }

  /// Section heading over the inline episodes, extras and cast blocks: the
  /// same `titleLarge` bold the tablet/desktop layout uses for its sections.
  Widget _buildMobileSectionTitle(BuildContext context, String title, {Key? key}) {
    return Text(
      key: key,
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: .bold),
    );
  }

  /// Whether the film is on the kijklijst, and whether a toggle can be
  /// offered (online, a movie or show, a source that takes it).
  (bool onList, bool canOffer) _mobileWatchlistState(BuildContext context, MediaItem metadata) {
    final watchlistProvider = context.watch<WatchlistProvider?>();
    final watchlistStore = context.watch<WatchlistStore?>();
    final isWatchlistKind = metadata.isMovie || metadata.isShow;
    final onWatchlist = WatchlistUiActions.isOnList(store: watchlistStore, provider: watchlistProvider, item: metadata);
    final canOffer =
        !widget.isOffline &&
        isWatchlistKind &&
        WatchlistUiActions.canOffer(provider: watchlistProvider, item: metadata, onList: onWatchlist);
    return (onWatchlist, canOffer);
  }
}
