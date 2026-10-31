part of '../media_context_menu.dart';

extension on MediaContextMenuState {
  Future<void> _handleUnmatch(BuildContext context, MediaItem item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.matchScreen.unmatch,
      message: t.matchScreen.unmatchConfirm,
      confirmText: t.matchScreen.unmatch,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final client = _getClientForItem();
    try {
      final success = await client.unmatchItem(item.id);
      if (!context.mounted) return;
      if (success) {
        showSuccessSnackBar(context, t.matchScreen.unmatchSuccess);
        _notifyRefresh(item.id);
      } else {
        showErrorSnackBar(context, t.matchScreen.unmatchFailed);
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  /// Navigate to a related item (series or season)
  ///
  /// [open] rather than a `Route` builder since PB-1/SYS-1b: on TV a detail
  /// screen is a nested route inside the shell and has no `Route` at all, so a
  /// call site that builds one has already decided the wrong thing. Handing the
  /// decision to `navigateToMediaItemDetails` keeps this menu on whichever
  /// shape that one call site picks, and stops the target computation from
  /// living in two places.
  Future<void> _navigateToRelated(
    BuildContext context,
    String? id,
    Future<void> Function(BuildContext context, MediaItem metadata) open,
    String errorPrefix,
  ) async {
    if (id == null) return;

    final client = _getMediaClientForItem();
    final refreshItemId = _itemId();

    try {
      final metadata = await client.fetchItem(id);
      if (metadata != null && context.mounted) {
        await open(context, metadata);
        _notifyRefresh(refreshItemId);
      }
    } catch (e) {
      noticeController.show(noticeForError(e, context: errorPrefix));
    }
  }

  Future<void> _showFileInfo(BuildContext context) async {
    try {
      final client = _getMediaClientForItem();
      if (!context.mounted) return;

      // Fetch file info behind a spinner the user can always back out of.
      final item = _mediaItem!;
      final fileInfo = await showCancellableLoadingDialog(
        context: context,
        task: client.getFileInfo(item),
        timeout: MediaServerTimeouts.interactive,
        timeoutMessage: t.common.timedOut,
      );

      if (fileInfo != null && context.mounted) {
        // Show file info bottom sheet
        await OverlaySheetController.showAdaptive(
          context,
          isScrollControlled: true,
          builder: (context) => FileInfoBottomSheet(fileInfo: fileInfo, title: item.displayTitle),
        );
      } else if (context.mounted) {
        showErrorSnackBar(context, t.messages.fileInfoNotAvailable);
      }
    } catch (e) {
      // The helper closes its own dialog before rethrowing.
      noticeController.show(noticeForError(e, context: t.messages.fileInfoNotAvailable));
    }
  }

  Future<bool> _handlePlayVersion(BuildContext context) async {
    final item = _mediaItem!;
    final client = context.tryGetMediaClientForServer(serverIdOrNull(_itemServerId));
    // Same flag the in-player Version & Quality sheet reads, keeps both
    // surfaces honest about what the active backend can actually do.
    final canTranscode = client?.capabilities.videoTranscoding ?? false;
    final versions = client == null ? item.mediaVersions ?? const [] : await resolveMediaVersions(item, client);
    if (!context.mounted) return false;

    int selectedVersionIndex = 0;
    if (versions.length > 1) {
      final picked = await showVersionPickerDialog(context, versions, t.mediaMenu.playVersion);
      if (picked == null || !context.mounted) return false;
      selectedVersionIndex = picked;
    }

    final selectedVersion = selectedVersionIndex < versions.length ? versions[selectedVersionIndex] : null;
    TranscodeQualityPreset selectedQuality = TranscodeQualityPreset.original;
    if (canTranscode) {
      final picked = await showQualityPickerDialog(
        context,
        sourceBitrateKbps: selectedVersion?.bitrate,
        sourceDurationMs: item.durationMs,
        sourceSizeBytes: _versionSizeBytes(selectedVersion),
      );
      if (picked == null || !context.mounted) return false;
      selectedQuality = picked;
    }

    await navigateToVideoPlayer(
      context,
      metadata: item,
      selectedMediaIndex: selectedVersionIndex,
      selectedMediaSourceId: selectedVersion?.id,
      selectedQualityPreset: selectedQuality,
    );
    return true;
  }

  /// Sum of [MediaPart.sizeBytes] across all parts of [version]. Returns
  /// null when any part is missing a size (a partial sum would be misleading
  /// for the "Original" row in the quality picker).
  int? _versionSizeBytes(MediaVersion? version) {
    if (version == null || version.parts.isEmpty) return null;
    var total = 0;
    for (final p in version.parts) {
      final s = p.sizeBytes;
      if (s == null || s <= 0) return null;
      total += s;
    }
    return total > 0 ? total : null;
  }

  /// Handle shuffle play using play queues, dispatches via the
  /// neutral [MediaListPlaybackLauncher] so Jellyfin items get routed to
  /// [JellyfinSequentialLauncher] instead of falling through to the
  /// Plex-only `/playQueues` flow.
  Future<void> _handleShufflePlayWithQueue(BuildContext context) async {
    final mediaItem = _mediaItem;
    if (mediaItem == null) return;
    final launcher = MediaListPlaybackLauncher.forItem(context, mediaItem);
    await launcher.launchShuffledShow(metadata: mediaItem, showLoadingIndicator: true);
  }

  Future<void> _showRatingSheet(BuildContext context, MediaItem item, MediaServerClient client) async {
    final siblings = widget.siblingSourceKeys;
    final mirror = siblings == null || siblings.length < 2
        ? null
        : RatingMirror.fromSourceKeys(context, sourceKeys: siblings, originSourceKey: item.globalKey);

    await OverlaySheetController.showAdaptive(
      context,
      showDragHandle: true,
      builder: (context) => RatingBottomSheet(
        item: item,
        serverClient: client,
        onServerRatingChanged: (_) => _notifyRefresh(item.id),
        onServerRatingWritten: mirror?.write,
      ),
    );

    if (mirror == null) return;
    await mirror.settled;
    if (!mounted || mirror.doneCount >= mirror.intendedTargetCount) return;
    final message = unifiedActionOutcomeMessage(done: mirror.doneCount, total: mirror.intendedTargetCount, queued: 0);
    if (message != null) showAppSnackBar(this.context, message);
  }

  /// Handle play action for collections and playlists
  Future<void> _handlePlay(BuildContext context, bool _, bool _) async {
    await _launchCollectionOrPlaylist(context, shuffle: false);
  }

  /// Handle shuffle action for collections and playlists
  Future<void> _handleShuffle(BuildContext context, bool _, bool _) async {
    await _launchCollectionOrPlaylist(context, shuffle: true);
  }

  /// Launch playback for collection or playlist.
  ///
  /// Dispatches to the right launcher implementation based on the item's
  /// backend, Plex uses server-side `/playQueues`, Jellyfin builds an
  /// in-memory queue locally.
  Future<void> _launchCollectionOrPlaylist(BuildContext context, {required bool shuffle}) async {
    // Launcher accepts both MediaItem (for collections) and MediaPlaylist.
    final launcher = MediaListPlaybackLauncher.forItem(context, widget.item);
    await launcher.launchFromCollectionOrPlaylist(item: widget.item, shuffle: shuffle, showLoadingIndicator: false);
  }

  /// Handle delete action for collections and playlists
  Future<void> _handleDelete(BuildContext context, bool isCollection, bool isPlaylist) async {
    final client = _getMediaClientForItem();

    final itemTitle = _itemDisplayTitle();

    // Show confirmation dialog
    final confirmed = await showDeleteConfirmation(
      context,
      title: isCollection ? t.collections.deleteCollection : t.playlists.delete,
      message: isCollection
          ? t.collections.deleteConfirm(title: itemTitle)
          : t.playlists.deleteMessage(name: itemTitle),
    );

    if (!confirmed || !context.mounted) return;

    try {
      bool success = false;

      if (isCollection) {
        success = await client.deleteCollection(_mediaItem!);
      } else if (isPlaylist) {
        success = await client.deletePlaylist(_playlist!);
      }

      if (context.mounted) {
        if (success) {
          showSuccessSnackBar(context, isCollection ? t.collections.deleted : t.playlists.deleted);
          // Trigger list refresh
          _notifyListRefresh();
        } else {
          showErrorSnackBar(context, isCollection ? t.collections.deleteFailed : t.playlists.errorDeleting);
        }
      }
    } catch (e) {
      noticeController.show(noticeForError(e, context: itemTitle));
    }
  }

  /// Handle play in external player action
  Future<void> _handlePlayExternal(BuildContext context) async {
    if (!PlatformDetector.supportsExternalPlayers()) return;

    final item = _mediaItem!;

    // Check if the item is downloaded and use local file path if available
    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
    final offlineWatchService = Provider.of<OfflineWatchSyncService>(context, listen: false);
    final client = _getMediaClientForItem();
    final globalKey = item.globalKey;
    if (downloadProvider.isDownloaded(globalKey)) {
      final videoPath = await downloadProvider.getVideoFilePath(globalKey);
      if (videoPath != null && context.mounted) {
        final videoUrl = videoPath.contains('://') ? videoPath : 'file://$videoPath';
        await ExternalPlayerService.launch(
          context: context,
          videoUrl: videoUrl,
          metadata: item,
          client: client,
          offlineWatchService: offlineWatchService,
        );
        return;
      }
    }

    if (!context.mounted) return;
    await ExternalPlayerService.launch(
      context: context,
      metadata: item,
      client: client,
      offlineWatchService: offlineWatchService,
    );
  }

  /// Handle delete media item action
  /// This permanently removes the media item and its associated files from the server
  Future<void> _handleDeleteMediaItem(BuildContext context, MediaKind? mediaKind) async {
    final item = _mediaItem!;
    final isMultipleMediaItems = mediaKind == MediaKind.show || mediaKind == MediaKind.season;

    // Show confirmation dialog
    final confirmed = await showDeleteConfirmation(
      context,
      title: t.mediaMenu.deleteFromServer,
      message: "${t.mediaMenu.confirmDelete}${isMultipleMediaItems ? "\n\n${t.mediaMenu.deleteMultipleWarning}" : ""}",
      confirmText: t.mediaMenu.deleteFromServer,
    );

    if (!confirmed || !context.mounted) return;

    MediaServerClient? client;
    try {
      client = _getMediaClientForItem();
      final success = await client.deleteMediaItem(item);

      if (context.mounted) {
        if (success) {
          showSuccessSnackBar(context, t.mediaMenu.mediaDeletedSuccessfully);
          // Broadcast deletion event for cross-screen propagation
          DeletionNotifier().notifyDeletedItem(item: item);
          // Backward-compatible list refresh for screens that are not DeletionAware yet
          _notifyListRefresh();
        } else {
          showErrorSnackBar(context, t.mediaMenu.mediaFailedToDelete);
        }
      }
    } catch (e) {
      appLogger.e(t.mediaMenu.mediaFailedToDelete, error: e);
      final message = await resolveMediaDeletionFailureMessage(e, item.backend, client);
      if (context.mounted) {
        showErrorSnackBar(context, message);
      }
    }
  }
}
