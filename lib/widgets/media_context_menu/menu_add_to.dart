part of '../media_context_menu.dart';

extension on MediaContextMenuState {
  /// Show submenu for Add to... (Playlist or Collection). Collections are
  /// canonical server data, so without owner rights this goes straight to
  /// the playlist picker.
  Future<void> _showAddToSubmenu(BuildContext context, {required bool canManageCollections}) async {
    if (!canManageCollections) {
      await _showAddToPlaylistDialog(context);
      return;
    }
    final selected = await showOptionPickerDialog<String>(
      context,
      title: t.common.addTo,
      options: [
        (icon: Symbols.playlist_play_rounded, label: t.playlists.playlist, value: 'playlist'),
        (icon: Symbols.collections_rounded, label: t.collections.collection, value: 'collection'),
      ],
    );

    if (selected == 'playlist' && context.mounted) {
      await _showAddToPlaylistDialog(context);
    } else if (selected == 'collection' && context.mounted) {
      await _showAddToCollectionDialog(context);
    }
  }

  Future<void> _showAddToPlaylistDialog(BuildContext context) async {
    final client = _getMediaClientForItem();

    try {
      final item = _mediaItem!;

      final result = await showScopedDialog<String>(
        context: context,
        builder: (context) => PlaylistSelectionDialog(client: client),
      );

      if (result == null || !context.mounted) return;

      if (result == '_create_new') {
        final playlistName = await showTextInputDialog(
          context,
          title: t.playlists.create,
          labelText: t.playlists.playlistName,
          hintText: t.playlists.enterPlaylistName,
        );

        if (playlistName == null || playlistName.isEmpty || !context.mounted) {
          return;
        }

        appLogger.d('Creating playlist "$playlistName" seeded with item ${item.id}');
        final newPlaylist = await client.createPlaylist(title: playlistName, items: [item]);

        if (!context.mounted) return;

        if (context.mounted) {
          if (newPlaylist != null) {
            appLogger.d('Successfully created playlist: ${newPlaylist.title}');
            showSuccessSnackBar(context, t.playlists.created);
            // Trigger refresh of playlists tab
            LibraryRefreshNotifier().notifyPlaylistsChanged();
          } else {
            appLogger.e('Failed to create playlist - API returned null');
            showErrorSnackBar(context, t.playlists.errorCreating);
          }
        }
      } else {
        appLogger.d('Adding item ${item.id} to playlist $result');
        final success = await client.addToPlaylist(playlistId: result, items: [item]);

        if (!context.mounted) return;

        if (context.mounted) {
          if (success) {
            appLogger.d('Successfully added item(s) to playlist $result');
            showSuccessSnackBar(context, t.playlists.itemAdded);
            // Trigger refresh of playlists tab
            LibraryRefreshNotifier().notifyPlaylistsChanged();
            _triggerEagerSyncIfRuleExists(context, client.serverId, result);
          } else {
            appLogger.e('Failed to add item(s) to playlist $result - API returned false');
            showErrorSnackBar(context, t.playlists.errorAdding);
          }
        }
      }
    } catch (e, stackTrace) {
      appLogger.e('Error in add to playlist flow', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        showErrorSnackBar(context, '${t.playlists.errorLoading}: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _showAddToCollectionDialog(BuildContext context) async {
    final client = _getMediaClientForItem();

    try {
      final item = _mediaItem!;
      final itemKind = item.kind;

      // Resolve the library/section id from the item itself, falling back to
      // a metadata round-trip and the show's library if missing. Both
      // backends store this on [MediaItem.libraryId].
      String? libraryId = item.libraryId;
      appLogger.d('Resolving libraryId for ${item.title} (initial: $libraryId)');

      if (libraryId == null || libraryId.isEmpty) {
        try {
          final fullMetadata = await client.fetchItem(item.id);
          libraryId = fullMetadata?.libraryId;
          appLogger.d('  - libraryId from full metadata: $libraryId');
        } catch (e) {
          appLogger.w('Failed to get full metadata for libraryId: $e');
        }
      }

      if ((libraryId == null || libraryId.isEmpty) && item.grandparentId != null) {
        try {
          final parentMeta = await client.fetchItem(item.grandparentId!);
          libraryId = parentMeta?.libraryId;
          appLogger.d('  - libraryId from grandparent: $libraryId');
        } catch (e) {
          appLogger.w('Failed to get parent metadata for libraryId: $e');
        }
      }

      if (libraryId == null || libraryId.isEmpty) {
        if (context.mounted) {
          showErrorSnackBar(context, t.messages.unableToDetermineLibrarySection);
        }
        return;
      }
      final resolvedLibraryId = libraryId;
      if (!context.mounted) return;

      final result = await showScopedDialog<String>(
        context: context,
        builder: (context) => CollectionSelectionDialog(client: client, libraryId: resolvedLibraryId),
      );

      if (result == null || !context.mounted) return;

      if (result == '_create_new') {
        final collectionName = await showTextInputDialog(
          context,
          title: t.common.createNew,
          labelText: t.collections.collectionName,
          hintText: t.collections.enterCollectionName,
        );

        if (collectionName == null || collectionName.isEmpty || !context.mounted) {
          return;
        }

        appLogger.d('Creating collection "$collectionName" seeded with item ${item.id}');
        final newCollectionId = await client.createCollection(
          libraryId: resolvedLibraryId,
          title: collectionName,
          items: [item],
          itemKind: itemKind,
        );

        if (!context.mounted) return;

        if (context.mounted) {
          if (newCollectionId != null) {
            appLogger.d('Successfully created collection with ID: $newCollectionId');
            showSuccessSnackBar(context, t.collections.created);
            // Trigger refresh of collections tab
            LibraryRefreshNotifier().notifyCollectionsChanged();
            _triggerEagerSyncIfRuleExists(context, client.serverId, newCollectionId);
          } else {
            appLogger.e('Failed to create collection - API returned null');
            showErrorSnackBar(context, t.collections.errorAddingToCollection);
          }
        }
      } else {
        appLogger.d('Adding item ${item.id} to collection $result');
        final success = await client.addToCollection(collectionId: result, items: [item]);

        if (!context.mounted) return;

        if (context.mounted) {
          if (success) {
            appLogger.d('Successfully added item(s) to collection $result');
            showSuccessSnackBar(context, t.collections.addedToCollection);
            // Trigger refresh of collections tab
            LibraryRefreshNotifier().notifyCollectionsChanged();
            _triggerEagerSyncIfRuleExists(context, client.serverId, result);
          } else {
            appLogger.e('Failed to add item(s) to collection $result - API returned false');
            showErrorSnackBar(context, t.collections.errorAddingToCollection);
          }
        }
      }
    } catch (e, stackTrace) {
      appLogger.e('Error in add to collection flow', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        showErrorSnackBar(context, '${t.collections.errorAddingToCollection}: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _handleRemoveFromCollection(BuildContext context, MediaItem item) async {
    final client = _getMediaClientForItem();

    if (widget.collectionId == null) {
      appLogger.e('Cannot remove from collection: collectionId is null');
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDeleteConfirmation(
      context,
      title: t.collections.removeFromCollection,
      message: t.collections.removeFromCollectionConfirm(title: item.displayTitle),
    );

    if (!confirmed || !context.mounted) return;

    try {
      appLogger.d('Removing item ${item.id} from collection ${widget.collectionId}');
      final success = await client.removeFromCollection(collectionId: widget.collectionId!, item: item);

      if (context.mounted) {
        if (success) {
          showSuccessSnackBar(context, t.collections.removedFromCollection);
          // Trigger refresh of collections tab
          LibraryRefreshNotifier().notifyCollectionsChanged();
          // Trigger list refresh to remove the item from the view
          _notifyListRefresh();
        } else {
          showErrorSnackBar(context, t.collections.removeFromCollectionFailed);
        }
      }
    } catch (e) {
      noticeController.show(noticeForError(e, context: item.displayTitle));
    }
  }
}

/// Fire-and-forget: if a sync rule exists for the target list, run it now so
/// newly-added items download immediately instead of waiting for the next
/// cooldown-gated general pass. Fails silently, errors are logged only.
void _triggerEagerSyncIfRuleExists(BuildContext context, ServerId serverId, String listId) {
  try {
    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
    final client = Provider.of<MultiServerProvider>(context, listen: false).getClientForServer(serverId);
    final globalKey = client == null
        ? buildGlobalKey(ServerId(serverId), listId)
        : downloadProvider.syncRuleKeyForClient(client, listId, serverId: serverId);
    if (!downloadProvider.hasSyncRule(globalKey)) return;
    final serverManager = Provider.of<MultiServerProvider>(context, listen: false).serverManager;
    unawaited(
      downloadProvider.executeSyncRuleFor(globalKey, serverManager).catchError((e) {
        appLogger.w('Eager sync-rule run failed for $globalKey: $e');
        return null;
      }),
    );
  } catch (e) {
    appLogger.w('Failed to schedule eager sync-rule run: $e');
  }
}
