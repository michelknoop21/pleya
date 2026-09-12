part of '../media_detail_screen.dart';

/// The download button's full state machine, split out of `action_buttons.dart`
/// (CLAUDE.md's file-size guideline) when the phone redesign (I6) touched
/// that file. Pure move, no behavior change.
extension _MediaDetailDownloadButton on _MediaDetailScreenState {
  Future<void> _handleDownloadButtonPressed(MediaItem metadata) async {
    final downloadProvider = context.read<DownloadProvider>();
    final globalKey = metadata.globalKey;
    final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
    final progress = downloadProvider.getProgress(globalKey);

    if (downloadProvider.isQueueing(globalKey) ||
        progress?.status == DownloadStatus.queued ||
        progress?.status == DownloadStatus.downloading) {
      return;
    }

    if (progress?.status == DownloadStatus.paused) {
      final client = _getMediaClientForMetadata(context);
      if (client == null) return;
      await downloadProvider.resumeDownload(globalKey, client);
      if (mounted) showAppSnackBar(context, t.downloads.downloadResumed);
      return;
    }

    if (progress?.status == DownloadStatus.failed) {
      final client = _getMediaClientForMetadata(context);
      if (client == null) return;

      final versionConfig = await _resolveDownloadVersion(context, metadata, client);
      if (versionConfig == null || !mounted) return;

      await downloadProvider.deleteDownload(globalKey);
      try {
        await downloadProvider.queueDownload(metadata, client, versionConfig: versionConfig);
        if (mounted) showSuccessSnackBar(context, t.downloads.downloadQueued);
      } on CellularDownloadBlockedException {
        if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
      }
      return;
    }

    if (progress?.status == DownloadStatus.cancelled) {
      final retry = await showConfirmDialog(
        context,
        title: t.downloads.cancelledDownloadTitle,
        message: t.downloads.cancelledDownloadMessage,
        cancelText: t.common.delete,
        confirmText: t.common.retry,
      );

      if (!retry && mounted) {
        await downloadProvider.deleteDownload(globalKey);
        if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
      } else if (retry && mounted) {
        final client = _getMediaClientForMetadata(context);
        if (client == null) return;

        final versionConfig = await _resolveDownloadVersion(context, metadata, client);
        if (versionConfig == null || !mounted) return;

        await downloadProvider.deleteDownload(globalKey);
        try {
          await downloadProvider.queueDownload(metadata, client, versionConfig: versionConfig);
          if (mounted) showSuccessSnackBar(context, t.downloads.downloadQueued);
        } on CellularDownloadBlockedException {
          if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
        }
      }
      return;
    }

    if (progress?.status == DownloadStatus.partial) {
      if (downloadProvider.hasSyncRule(ruleKey)) {
        await _showSyncRuleActions(context, downloadProvider, metadata, ruleKey: ruleKey, downloadGlobalKey: globalKey);
        return;
      }

      final client = _getMediaClientForMetadata(context);
      if (client == null) return;

      final versionConfig = await _resolveDownloadVersion(context, metadata, client);
      if (versionConfig == null || !mounted) return;

      final count = await downloadProvider.queueMissingEpisodes(metadata, client, versionConfig: versionConfig);
      if (mounted) {
        final message = count > 0 ? t.downloads.episodesQueued(count: count) : t.downloads.allEpisodesAlreadyDownloaded;
        showAppSnackBar(context, message);
      }
      return;
    }

    if (downloadProvider.isDownloaded(globalKey)) {
      if (downloadProvider.hasSyncRule(ruleKey)) {
        await _showSyncRuleActions(context, downloadProvider, metadata, ruleKey: ruleKey, downloadGlobalKey: globalKey);
        return;
      }

      final canDownloadMore = metadata.isShow || metadata.isSeason;
      Future<void> confirmAndDelete() async {
        final confirmed = await showDeleteConfirmation(
          context,
          title: t.downloads.deleteDownload,
          message: t.downloads.deleteConfirm(title: metadata.displayTitle),
        );
        if (confirmed && mounted) {
          await downloadProvider.deleteDownload(globalKey);
          if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
        }
      }

      if (!canDownloadMore) {
        await confirmAndDelete();
        return;
      }

      final client = _getMediaClientForMetadata(context);
      if (client == null) return;
      try {
        final result = await showDownloadOptionsAndQueue(
          context,
          metadata: metadata,
          client: client,
          downloadProvider: downloadProvider,
          onDelete: confirmAndDelete,
        );
        if (result == null || !mounted) return;
        showSuccessSnackBar(context, result.toSnackBarMessage());
      } on CellularDownloadBlockedException {
        if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
      }
      return;
    }

    final client = _getMediaClientForMetadata(context);
    if (client == null) return;

    try {
      final result = await showDownloadOptionsAndQueue(
        context,
        metadata: metadata,
        client: client,
        downloadProvider: downloadProvider,
      );
      if (result == null || !mounted) return;

      showSuccessSnackBar(context, result.toSnackBarMessage());
    } on CellularDownloadBlockedException {
      if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
    }
  }

  Widget _buildDownloadButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    bool showFocus = false,
  }) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final iconSize = PlatformDetector.isTV() ? 21.0 * tvScale : 20.0;
        final globalKey = metadata.globalKey;
        final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
        final progress = downloadProvider.getProgress(globalKey);
        final isQueueing = downloadProvider.isQueueing(globalKey);

        // Debug logging
        if (progress != null) {
          appLogger.d('UI rebuilding for $globalKey: status=${progress.status}, progress=${progress.progress}%');
        }

        // State 1: Queueing (building download queue)
        if (isQueueing) {
          return IconButton.filledTonal(
            onPressed: null,
            icon: LoadingIndicatorBox(size: iconSize),
            iconSize: iconSize,
            style: actionButtonStyle(showFocus: showFocus),
          );
        }

        // State 2: Queued (waiting to download)
        if (progress?.status == DownloadStatus.queued) {
          final currentFile = progress?.currentFile;
          final tooltip = currentFile != null && currentFile.contains('episodes')
              ? t.downloads.queuedFilesTooltip(files: currentFile)
              : t.downloads.queuedTooltip;

          return IconButton.filledTonal(
            onPressed: null,
            tooltip: tooltip,
            icon: const AppIcon(Symbols.schedule_rounded, fill: 1),
            iconSize: iconSize,
            style: actionButtonStyle(showFocus: showFocus),
          );
        }

        // State 3: Downloading (active download)
        if (progress?.status == DownloadStatus.downloading) {
          // Show episode count in tooltip for shows/seasons
          final currentFile = progress?.currentFile;
          final tooltip = currentFile != null && currentFile.contains('episodes')
              ? t.downloads.downloadingFilesTooltip(files: currentFile)
              : t.downloads.downloadingTooltip;

          return IconButton.filledTonal(
            onPressed: null,
            tooltip: tooltip,
            icon: _buildRadialProgress(progress?.progressPercent),
            iconSize: iconSize,
            style: actionButtonStyle(showFocus: showFocus),
          );
        }

        // State 4: Paused (can resume)
        if (progress?.status == DownloadStatus.paused) {
          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.pause_circle_outline_rounded, fill: 1),
            tooltip: progress?.autoPaused == true ? t.downloads.waitingForNetwork : t.downloads.resumeDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.amber, showFocus: showFocus),
          );
        }

        // State 5: Failed (can retry)
        if (progress?.status == DownloadStatus.failed) {
          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.error_outline_rounded, fill: 1),
            tooltip: t.downloads.retryDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.red, showFocus: showFocus),
          );
        }

        // State 6: Cancelled (can delete or retry)
        if (progress?.status == DownloadStatus.cancelled) {
          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.cancel_rounded, fill: 1),
            tooltip: t.downloads.cancelledDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.grey, showFocus: showFocus),
          );
        }

        // State 7: Partial Download (some episodes downloaded, not all)
        if (progress?.status == DownloadStatus.partial) {
          final hasSyncRule = downloadProvider.hasSyncRule(ruleKey);
          final currentFile = progress?.currentFile;

          if (hasSyncRule) {
            // Synced partial — this is the normal state for sync rules
            final syncRule = downloadProvider.getSyncRule(ruleKey);
            final isEnabled = syncRule?.enabled ?? true;
            final tooltip = currentFile != null
                ? t.downloads.syncingFile(
                    file: currentFile,
                    status: t.downloads.keepNUnwatched(count: syncRule?.episodeCount.toString() ?? '?'),
                  )
                : t.downloads.keepSynced;

            return IconButton.filledTonal(
              onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
              tooltip: tooltip,
              icon: AppIcon(isEnabled ? Symbols.sync_rounded : Symbols.sync_disabled_rounded, fill: 1),
              iconSize: iconSize,
              style: actionButtonStyle(foregroundColor: isEnabled ? Colors.teal : Colors.grey, showFocus: showFocus),
            );
          }

          final tooltip = currentFile != null
              ? t.downloads.downloadedFileClickToComplete(file: currentFile)
              : t.downloads.partialDownloadClickToComplete;

          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            tooltip: tooltip,
            icon: const AppIcon(Symbols.downloading_rounded, fill: 1),
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.orange, showFocus: showFocus),
          );
        }

        // State 8: Downloaded/Completed (can delete)
        if (downloadProvider.isDownloaded(globalKey)) {
          final hasSyncRule = downloadProvider.hasSyncRule(ruleKey);

          if (hasSyncRule) {
            // Synced + complete — show sync icon
            final syncRule = downloadProvider.getSyncRule(ruleKey);
            final isEnabled = syncRule?.enabled ?? true;
            return IconButton.filledTonal(
              onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
              icon: AppIcon(isEnabled ? Symbols.sync_rounded : Symbols.sync_disabled_rounded, fill: 1),
              tooltip: t.downloads.keepNUnwatched(count: syncRule?.episodeCount.toString() ?? '?'),
              iconSize: iconSize,
              style: actionButtonStyle(foregroundColor: isEnabled ? Colors.teal : Colors.grey, showFocus: showFocus),
            );
          }

          // Shows/seasons may have more episodes to fetch; movies/episodes don't.
          final canDownloadMore = metadata.isShow || metadata.isSeason;

          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.download_rounded, fill: 1),
            tooltip: canDownloadMore ? t.downloads.manage : t.downloads.deleteDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.orange, showFocus: showFocus),
          );
        }

        // State 9: Not downloaded (default - can download)
        return IconButton.filledTonal(
          onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
          icon: const AppIcon(Symbols.download_rounded, fill: 1),
          tooltip: t.downloads.downloadNow,
          iconSize: iconSize,
          style: actionButtonStyle(showFocus: showFocus),
        );
      },
    );
  }
}
