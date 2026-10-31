part of '../media_context_menu.dart';

extension on MediaContextMenuState {
  /// Runs the chosen row. [onNavigate] marks that the row left this screen, so
  /// the caller does not hand focus back to a card that is no longer in view.
  Future<void> _runMenuAction(
    BuildContext context,
    String? selected,
    _MenuFacts facts, {
    required VoidCallback onNavigate,
  }) async {
    final mediaItem = facts.mediaItem;
    final mediaKind = facts.mediaKind;
    final isAdmin = facts.isAdmin;
    final isCollection = facts.isCollection;
    final isPlaylist = facts.isPlaylist;

    switch (selected) {
      case 'play_from_beginning':
        onNavigate();
        if (context.mounted) await playFromBeginning(context, mediaItem!);
        break;

      case 'play_trailer':
        onNavigate();
        widget.onPlayTrailer?.call();
        break;

      case 'share':
        widget.onShare?.call();
        break;

      case 'request':
        widget.onRequest?.call();
        break;

      case 'watch':
      case 'unwatch':
        final watched = selected == 'watch';
        final item = mediaItem;
        if (item == null) break;
        // The offline/online decision belongs to [WatchActions]: it is per
        // server. Answering it here as well, app-wide, is how a mark for a
        // server that was down was sent to that server anyway and lost
        // whenever some other server happened to be up.
        try {
          final outcome = await WatchActions.setWatched(context, item, watched: watched);
          if (!context.mounted) break;
          switch (outcome) {
            case WatchMarkOutcome.queuedOffline:
              showAppSnackBar(
                context,
                watched ? t.messages.markedAsWatchedOffline : t.messages.markedAsUnwatchedOffline,
              );
              _notifyRefresh(item.id);
            case WatchMarkOutcome.marked:
              showSuccessSnackBar(context, watched ? t.messages.markedAsWatched : t.messages.markedAsUnwatched);
              _notifyRefresh(item.id);
            case WatchMarkOutcome.skipped:
              break;
          }
        } catch (e) {
          if (context.mounted) showErrorSnackBar(context, friendlyError(e));
        }
        break;

      case 'remove_from_continue_watching':
        // Remove from Continue Watching without affecting watch status or progress
        // This preserves the progression for partially watched items
        // and doesn't mark unwatched next episodes as watched
        try {
          final outcome = await WatchActions.removeFromContinueWatching(context, mediaItem!);
          if (context.mounted) {
            showSuccessSnackBar(
              context,
              outcome == ContinueWatchingRemoval.hiddenOnDevice
                  ? t.messages.hiddenFromContinueWatching
                  : t.messages.removedFromContinueWatching,
            );
            if (widget.onRemoveFromContinueWatching != null) {
              widget.onRemoveFromContinueWatching!();
            } else {
              _notifyRefresh(mediaItem.id);
            }
          }
        } catch (e) {
          if (context.mounted) {
            showErrorSnackBar(context, friendlyError(e));
          }
        }
        break;

      case 'details':
        onNavigate();
        if (context.mounted) {
          await navigateToMediaItemDetails(context, mediaItem!, onRefresh: _notifyRefresh);
        }
        break;

      case 'rate':
        if (context.mounted) {
          // Strictly this item's server, never `getMediaClientWithFallback`.
          // That helper falls back to the first online server, and a Plex
          // rating key is a per-server integer: with this item's server gone,
          // a fallback writes the rating onto whatever unrelated title holds
          // that key elsewhere. Invisible, permanent, and not what anybody
          // asked for.
          final client = context.tryGetMediaClientForServer(serverIdOrNull(mediaItem!.serverId));
          if (client == null) {
            showErrorSnackBar(context, t.errors.noClientAvailable);
            break;
          }
          await _showRatingSheet(context, mediaItem, client);
        }
        break;

      case 'watchlist_toggle':
        // Feedback lives in WatchlistUiActions so the snackbar and the
        // haptic read the same here as on the detail screen.
        await WatchlistUiActions.toggle(context, mediaItem!);
        break;

      case 'edit_metadata':
        onNavigate();
        if (context.mounted) {
          final item = mediaItem!;
          await Navigator.push(context, MaterialPageRoute(builder: (context) => MetadataEditScreen(metadata: item)));
          _notifyRefresh(item.id);
        }
        break;

      case 'match':
        onNavigate();
        if (context.mounted) {
          final item = mediaItem!;
          await Navigator.push(context, MaterialPageRoute(builder: (context) => PlexMatchScreen(metadata: item)));
          _notifyRefresh(item.id);
        }
        break;

      case 'unmatch':
        await _handleUnmatch(context, mediaItem!);
        break;

      case 'remove_from_collection':
        await _handleRemoveFromCollection(context, mediaItem!);
        break;

      case 'series':
        onNavigate();
        await _navigateToRelated(
          context,
          mediaItem!.kind == MediaKind.season ? mediaItem.parentId : mediaItem.grandparentId,
          (ctx, item) => navigateToMediaItemDetails(ctx, mediaItem, metadataOverride: item),
          t.messages.errorLoadingSeries,
        );
        break;

      case 'play_version':
        if (await _handlePlayVersion(context)) onNavigate();
        break;

      case 'fileinfo':
        await _showFileInfo(context);
        break;

      case 'add_to':
        await _showAddToSubmenu(context, canManageCollections: isAdmin);
        break;

      case 'shuffle_play':
        await _handleShufflePlayWithQueue(context);
        break;

      case 'play':
        await _handlePlay(context, isCollection, isPlaylist);
        break;

      case 'shuffle':
        await _handleShuffle(context, isCollection, isPlaylist);
        break;

      case 'delete':
        await _handleDelete(context, isCollection, isPlaylist);
        break;

      case 'play_external':
        await _handlePlayExternal(context);
        break;

      case 'download_playlist':
        await _handleDownloadPlaylist(context);
        break;

      case 'download_collection':
        await _handleDownloadCollection(context);
        break;

      case 'download':
        await _handleDownload(context);
        break;

      case 'delete_download':
        await _handleDeleteDownload(context);
        break;

      case 'manage_sync':
        await _handleManageSyncRule(context);
        break;

      case 'remove_sync':
        await _handleRemoveSyncRule(context);
        break;

      case 'delete_media':
        await _handleDeleteMediaItem(context, mediaKind);
        break;
    }
  }
}
