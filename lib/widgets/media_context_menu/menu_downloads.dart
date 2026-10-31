part of '../media_context_menu.dart';

extension on MediaContextMenuState {
  /// Handle download collection action, opens the same sync/one-time dialog
  /// as playlists, wired to [showCollectionDownloadOptionsAndQueue].
  Future<void> _handleDownloadCollection(BuildContext context) async {
    final collection = _mediaItem!;
    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
    final client = _getMediaClientForItem();

    try {
      final items = await fetchAllCollectionItemsPaged(
        client,
        collection.id,
        libraryId: collection.libraryId,
        libraryTitle: collection.libraryTitle,
      );
      if (!context.mounted) return;

      final result = await showCollectionDownloadOptionsAndQueue(
        context,
        collectionMetadata: collection,
        items: items,
        client: client,
        downloadProvider: downloadProvider,
      );
      if (result == null || !context.mounted) return;

      showSuccessSnackBar(context, result.toSnackBarMessage());
    } on CellularDownloadBlockedException {
      if (context.mounted) {
        showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
      }
    } catch (e) {
      appLogger.e('Failed to queue collection download', error: e);
      if (context.mounted) {
        showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  /// Handle download playlist action
  Future<void> _handleDownloadPlaylist(BuildContext context) async {
    final playlist = _playlist!;
    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
    final client = _getMediaClientForItem();

    try {
      // Page through the playlist via the neutral interface so Jellyfin
      // playlists download too.
      final items = await fetchAllPlaylistItems(client, playlist.id);
      if (!context.mounted) return;

      final playlistMetadata = MediaItem(
        id: playlist.id,
        backend: playlist.backend,
        kind: MediaKind.playlist,
        title: playlist.title,
        thumbPath: playlist.thumbPath,
        serverId: playlist.serverId ?? client.serverId,
        serverName: playlist.serverName,
      );

      final result = await showPlaylistDownloadOptionsAndQueue(
        context,
        playlistMetadata: playlistMetadata,
        items: items,
        client: client,
        downloadProvider: downloadProvider,
      );
      if (result == null || !context.mounted) return;

      showSuccessSnackBar(context, result.toSnackBarMessage());
    } on CellularDownloadBlockedException {
      if (context.mounted) {
        showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
      }
    } catch (e) {
      appLogger.e('Failed to queue playlist download', error: e);
      if (context.mounted) {
        showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  /// Handle download action
  Future<void> _handleDownload(BuildContext context) async {
    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
    final item = _mediaItem!;

    try {
      // Backend-agnostic resolve so Jellyfin items can be downloaded too.
      final client = context.getMediaClientWithFallback(serverIdOrNull(_itemServerId));
      final result = await showDownloadOptionsAndQueue(
        context,
        metadata: item,
        client: client,
        downloadProvider: downloadProvider,
      );
      if (result == null || !context.mounted) return;

      showSuccessSnackBar(context, result.toSnackBarMessage());
    } on CellularDownloadBlockedException {
      if (context.mounted) {
        showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
      }
    } catch (e) {
      appLogger.e('Failed to queue download', error: e);
      if (context.mounted) {
        showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  /// Handle delete download action
  Future<void> _handleDeleteDownload(BuildContext context) async {
    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
    final item = _mediaItem!;
    final globalKey = item.globalKey;

    // Show confirmation dialog
    final confirmed = await showDeleteConfirmation(
      context,
      title: t.downloads.deleteDownload,
      message: t.downloads.deleteConfirm(title: item.displayTitle),
    );

    if (!confirmed || !context.mounted) return;

    try {
      // Use smart deletion handler (shows progress only if >500ms)
      await SmartDeletionHandler.deleteWithProgress(context: context, provider: downloadProvider, globalKey: globalKey);

      if (context.mounted) {
        showSuccessSnackBar(context, t.downloads.downloadDeleted);
        // DownloadProvider.deleteDownload now broadcasts the DeletionEvent,
        // so DeletionAware screens (e.g. offline season detail) update without
        // a duplicate notification here.
        _notifyRefresh(item.id);
      }
    } catch (e) {
      appLogger.e('Failed to delete download', error: e);
      if (context.mounted) {
        showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  Future<void> _handleManageSyncRule(BuildContext context) => manageSyncRule(
    context,
    downloadProvider: context.read<DownloadProvider>(),
    globalKey: _itemSyncRuleKey(context),
    displayTitle: _itemDisplayTitle(),
  );

  Future<void> _handleRemoveSyncRule(BuildContext context) => removeSyncRuleAndSnack(
    context,
    downloadProvider: context.read<DownloadProvider>(),
    globalKey: _itemSyncRuleKey(context),
    displayTitle: _itemDisplayTitle(),
  );
}
