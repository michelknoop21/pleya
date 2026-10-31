part of '../media_detail_screen.dart';

/// What the download control says for a title. Phone, desktop and the round
/// row on Android TV draw this one reading, each in its own button.
class _DetailDownloadState {
  const _DetailDownloadState({required this.icon, this.tooltip, this.color, this.pressable = true});

  final Widget icon;
  final String? tooltip;
  final Color? color;

  /// Whether a press does anything: a running or waiting download has nothing to
  /// offer until it is done.
  final bool pressable;
}

extension _MediaDetailDownloadButton on _MediaDetailScreenState {
  _DetailDownloadState _detailDownloadState(MediaItem metadata, DownloadProvider downloadProvider, double iconSize) {
    final globalKey = metadata.globalKey;
    final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
    final progress = downloadProvider.getProgress(globalKey);
    final currentFile = progress?.currentFile;
    final hasSyncRule = downloadProvider.hasSyncRule(ruleKey);
    final syncRule = hasSyncRule ? downloadProvider.getSyncRule(ruleKey) : null;
    final syncEnabled = syncRule?.enabled ?? true;
    final syncIcon = AppIcon(syncEnabled ? Symbols.sync_rounded : Symbols.sync_disabled_rounded, fill: 1);
    final syncColor = syncEnabled ? Colors.teal : Colors.grey;

    if (downloadProvider.isQueueing(globalKey)) {
      return _DetailDownloadState(icon: LoadingIndicatorBox(size: iconSize), pressable: false);
    }

    switch (progress?.status) {
      case DownloadStatus.queued:
        return _DetailDownloadState(
          icon: const AppIcon(Symbols.schedule_rounded, fill: 1),
          // Episode count for shows and seasons.
          tooltip: currentFile != null && currentFile.contains('episodes')
              ? t.downloads.queuedFilesTooltip(files: currentFile)
              : t.downloads.queuedTooltip,
          pressable: false,
        );
      case DownloadStatus.downloading:
        return _DetailDownloadState(
          icon: _buildRadialProgress(progress?.progressPercent),
          tooltip: currentFile != null && currentFile.contains('episodes')
              ? t.downloads.downloadingFilesTooltip(files: currentFile)
              : t.downloads.downloadingTooltip,
          pressable: false,
        );
      case DownloadStatus.paused:
        return _DetailDownloadState(
          icon: const AppIcon(Symbols.pause_circle_outline_rounded, fill: 1),
          tooltip: progress?.autoPaused == true ? t.downloads.waitingForNetwork : t.downloads.resumeDownload,
          color: Colors.amber,
        );
      case DownloadStatus.failed:
        return _DetailDownloadState(
          icon: const AppIcon(Symbols.error_outline_rounded, fill: 1),
          tooltip: t.downloads.retryDownload,
          color: Colors.red,
        );
      case DownloadStatus.cancelled:
        return _DetailDownloadState(
          icon: const AppIcon(Symbols.cancel_rounded, fill: 1),
          tooltip: t.downloads.cancelledDownload,
          color: Colors.grey,
        );
      case DownloadStatus.partial:
        // Partial is the normal state of a sync rule.
        if (hasSyncRule) {
          final keep = t.downloads.keepNUnwatched(count: syncRule?.episodeCount.toString() ?? '?');
          return _DetailDownloadState(
            icon: syncIcon,
            tooltip: currentFile != null
                ? t.downloads.syncingFile(file: currentFile, status: keep)
                : t.downloads.keepSynced,
            color: syncColor,
          );
        }
        return _DetailDownloadState(
          icon: const AppIcon(Symbols.downloading_rounded, fill: 1),
          tooltip: currentFile != null
              ? t.downloads.downloadedFileClickToComplete(file: currentFile)
              : t.downloads.partialDownloadClickToComplete,
          color: Colors.orange,
        );
      default:
        break;
    }

    if (downloadProvider.isDownloaded(globalKey)) {
      if (hasSyncRule) {
        return _DetailDownloadState(
          icon: syncIcon,
          tooltip: t.downloads.keepNUnwatched(count: syncRule?.episodeCount.toString() ?? '?'),
          color: syncColor,
        );
      }
      // Shows and seasons may have more episodes to fetch; movies don't.
      final canDownloadMore = metadata.isShow || metadata.isSeason;
      return _DetailDownloadState(
        icon: const AppIcon(Symbols.download_rounded, fill: 1),
        tooltip: canDownloadMore ? t.downloads.manage : t.downloads.deleteDownload,
        color: Colors.orange,
      );
    }

    return _DetailDownloadState(
      icon: const AppIcon(Symbols.download_rounded, fill: 1),
      tooltip: t.downloads.downloadNow,
    );
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
        final state = _detailDownloadState(metadata, downloadProvider, iconSize);
        return IconButton.filledTonal(
          onPressed: state.pressable ? () => unawaited(_handleDownloadButtonPressed(metadata)) : null,
          icon: state.icon,
          tooltip: state.tooltip,
          iconSize: iconSize,
          style: actionButtonStyle(foregroundColor: state.color, showFocus: showFocus),
        );
      },
    );
  }

  /// The round row (06) on Android TV. Apple TV has no downloads.
  FocusableAction _tvDetailDownloadAction(MediaItem metadata, double iconSize) => FocusableAction(
    debugLabel: 'detail_${_DetailActionKind.download.name}',
    onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
    builder: (context, focus) => Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final state = _detailDownloadState(metadata, downloadProvider, iconSize);
        return _tvDetailRoundAction(
          focus,
          _DetailActionKind.download.name,
          icon: IconTheme.merge(
            data: IconThemeData(color: state.color, size: iconSize),
            child: state.icon,
          ),
          label: state.tooltip,
          onPressed: state.pressable ? () => unawaited(_handleDownloadButtonPressed(metadata)) : null,
        );
      },
    ),
  );
}
