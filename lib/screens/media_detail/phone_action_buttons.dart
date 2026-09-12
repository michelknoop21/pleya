part of '../media_detail_screen.dart';

/// The phone-only full-width action controls from mockups 06/07: a stacked
/// primary play button and download button, plus a labeled icon row
/// (watchlist/rate/watched/share) below the source line. The compact,
/// shared-with-TV icon row in [_MediaDetailActionButtons] is unaffected.
extension _PhoneActionButtons on _MediaDetailScreenState {
  Widget _buildPhonePrimaryButton(MediaItem metadata) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: () => unawaited(_handlePlayPressed(metadata)),
        icon: AppIcon(_getPlayButtonIcon(metadata), fill: 1, size: 20),
        label: Text(_phonePlayButtonLabel(metadata), style: const TextStyle(fontWeight: .w700, fontSize: 16)),
      ),
    );
  }

  /// "Hervatten S2:A4 · nog 18 min" / "Hervatten · nog 1u 12m" / "Afspelen".
  String _phonePlayButtonLabel(MediaItem metadata) {
    final isShow = metadata.isShow;
    final progressTarget = isShow ? _onDeckEpisode : metadata;
    final hasProgress = (progressTarget?.viewOffsetMs ?? 0) > 0;
    final verb = hasProgress ? t.common.resume : t.common.play;

    String? episodeCode;
    if (isShow) {
      final episode = _onDeckEpisode;
      if (episode != null) {
        episodeCode = t.discover.playEpisode(season: episode.parentIndex ?? 1, episode: episode.index ?? 1);
      } else {
        final seasonNum = defaultPlaybackSeason(_seasons)?.index ?? 1;
        episodeCode = t.discover.playEpisode(season: seasonNum, episode: 1);
      }
    }

    String? remainingText;
    final durationMs = progressTarget?.durationMs;
    final viewOffsetMs = progressTarget?.viewOffsetMs;
    if (hasProgress && durationMs != null && viewOffsetMs != null && viewOffsetMs < durationMs) {
      remainingText = t.nowWatching.remaining(time: formatDurationTextual(durationMs - viewOffsetMs));
    }

    final head = episodeCode != null ? '$verb $episodeCode' : verb;
    return remainingText != null ? '$head · $remainingText' : head;
  }

  Widget _buildPhoneDownloadButton(MediaItem metadata) {
    if (widget.isOffline || PlatformDetector.isAppleTV()) return const SizedBox.shrink();

    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final globalKey = metadata.globalKey;
        final progress = downloadProvider.getProgress(globalKey);
        final isQueueing = downloadProvider.isQueueing(globalKey);
        final isDownloaded = downloadProvider.isDownloaded(globalKey);
        final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
        final hasSyncRule = downloadProvider.hasSyncRule(ruleKey);

        IconData icon = Symbols.download_rounded;
        String label = t.downloads.downloadNow;
        Widget? leading;
        VoidCallback? onPressed = () => unawaited(_handleDownloadButtonPressed(metadata));

        if (isQueueing || progress?.status == DownloadStatus.queued) {
          icon = Symbols.schedule_rounded;
          label = t.downloads.queuedTooltip;
          onPressed = null;
        } else if (progress?.status == DownloadStatus.downloading) {
          leading = _buildRadialProgress(progress?.progressPercent);
          final percent = progress?.progressPercent;
          label = percent != null && percent > 0
              ? '${t.downloads.downloadingTooltip} · ${(percent * 100).round()}%'
              : t.downloads.downloadingTooltip;
          onPressed = null;
        } else if (progress?.status == DownloadStatus.paused) {
          icon = Symbols.pause_circle_outline_rounded;
          label = t.downloads.resumeDownload;
        } else if (progress?.status == DownloadStatus.failed) {
          icon = Symbols.error_outline_rounded;
          label = t.downloads.retryDownload;
        } else if (progress?.status == DownloadStatus.cancelled) {
          icon = Symbols.cancel_rounded;
          label = t.downloads.cancelledDownload;
        } else if (progress?.status == DownloadStatus.partial) {
          icon = hasSyncRule ? Symbols.sync_rounded : Symbols.downloading_rounded;
          label = hasSyncRule
              ? t.downloads.keepNUnwatched(count: downloadProvider.getSyncRule(ruleKey)?.episodeCount.toString() ?? '?')
              : t.downloads.partialDownloadClickToComplete;
        } else if (isDownloaded) {
          final canDownloadMore = metadata.isShow || metadata.isSeason;
          icon = hasSyncRule ? Symbols.sync_rounded : Symbols.file_download_done_rounded;
          label = hasSyncRule
              ? t.downloads.keepNUnwatched(count: downloadProvider.getSyncRule(ruleKey)?.episodeCount.toString() ?? '?')
              : (canDownloadMore ? t.downloads.manage : t.downloads.deleteDownload);
        }

        // The theme's FilledButtonThemeData forces a single white-on-black
        // style onto every FilledButton variant (mono_theme.dart's own
        // comment: "Secondary actions get a translucent grey fill
        // elsewhere") — `.tonalIcon` would render identically to the primary
        // play button above it, losing the mockup's two-tier hierarchy. Style
        // this one explicitly off secondaryContainer instead, the same colors
        // the shared TV/legacy action row already uses for its own tonal look.
        final colorScheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.secondaryContainer,
                foregroundColor: colorScheme.onSecondaryContainer,
                disabledBackgroundColor: colorScheme.secondaryContainer,
                disabledForegroundColor: colorScheme.onSecondaryContainer,
              ),
              icon: leading ?? AppIcon(icon, fill: 1, size: 20),
              label: Text(label, style: const TextStyle(fontWeight: .w700, fontSize: 16)),
            ),
          ),
        );
      },
    );
  }

  /// Mijn lijst / Beoordelen / Bekeken / Delen (mockup 06's bottom icon row).
  Widget _buildPhoneIconActionRow(MediaItem metadata) {
    final watchlistProvider = context.watch<WatchlistProvider?>();
    final watchlistStore = context.watch<WatchlistStore?>();
    final isWatchlistKind = metadata.isMovie || metadata.isShow;
    final onWatchlist = WatchlistUiActions.isOnList(store: watchlistStore, provider: watchlistProvider, item: metadata);

    final items = <Widget>[];

    if (!widget.isOffline &&
        isWatchlistKind &&
        WatchlistUiActions.canOffer(provider: watchlistProvider, item: metadata, onList: onWatchlist)) {
      items.add(
        _phoneIconAction(
          icon: onWatchlist ? Symbols.bookmark_remove_rounded : Symbols.bookmark_add_rounded,
          label: t.watchlist.title,
          onTap: () => unawaited(WatchlistUiActions.toggle(context, metadata)),
        ),
      );
    }

    if (!widget.isOffline) {
      items.add(
        _phoneIconAction(
          icon: Symbols.thumb_up_rounded,
          label: t.mediaMenu.rate,
          onTap: () => unawaited(_showRatingDialog(context, metadata)),
        ),
      );
    }

    items.add(
      _phoneIconAction(
        icon: metadata.isWatched ? Symbols.remove_done_rounded : Symbols.check_rounded,
        label: t.discover.watched,
        onTap: () => unawaited(_handleWatchedTogglePressed(metadata)),
      ),
    );

    items.add(
      _phoneIconAction(
        icon: Symbols.share_rounded,
        label: t.discover.share,
        onTap: () => _sharePhoneMetadata(metadata),
      ),
    );

    return Row(mainAxisAlignment: .spaceAround, children: items);
  }

  Widget _phoneIconAction({required IconData icon, required String label, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: .min,
          children: [
            AppIcon(icon, fill: 0, size: 24, color: theme.colorScheme.onSurface),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  void _sharePhoneMetadata(MediaItem metadata) {
    final year = metadata.year;
    final text = year != null ? '${metadata.displayTitle} ($year)' : metadata.displayTitle;
    unawaited(SharePlus.instance.share(ShareParams(text: text)));
  }
}
