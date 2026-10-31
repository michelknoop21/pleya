part of '../media_context_menu.dart';

/// What the rows and their handlers share: the facts about the item at the
/// moment the menu opens.
class _MenuFacts {
  const _MenuFacts({
    required this.mediaItem,
    required this.playlist,
    required this.mediaKind,
    required this.canManageCollections,
    required this.actions,
  });

  final MediaItem? mediaItem;
  final MediaPlaylist? playlist;
  final MediaKind? mediaKind;

  /// Owner of the server and a backend with collections to write to.
  final bool canManageCollections;
  final List<MediaMenuAction> actions;

  bool get isPlaylist => playlist != null;
  bool get isCollection => mediaKind == MediaKind.collection;
}

extension on MediaContextMenuState {
  /// The rows for this item. Every row is gated on what its server can really
  /// do, so a menu never offers something that fails when chosen.
  _MenuFacts _buildMenuFacts(BuildContext context) {
    final mediaItem = _mediaItem;
    final playlist = _playlist;
    final isPlaylist = playlist != null;
    final mediaKind = mediaItem?.kind;
    final isCollection = mediaKind == MediaKind.collection;

    // No fallback: items without a backend marker show only neutral actions,
    // because dispatching a Plex-only action against an unknown-backend item could
    // crash or hit the wrong server.
    final itemBackend = mediaItem?.backend ?? playlist?.backend;

    // The owner rule: canonical server data (metadata, match, deletes,
    // collections) is only offered to the server's owner. Everyone else does
    // not see those entries at all. See
    // `MultiServerManager.canManageServerMetadata` for the per-backend roles.
    final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);
    final isAdmin =
        _itemServerId != null && multiServerProvider.serverManager.canManageServerMetadata(ServerId(_itemServerId!));

    // Backend capabilities gate menu items so we don't expose actions the
    // active server cannot perform.
    final mediaClient = _itemServerId != null ? multiServerProvider.getClientForServer(ServerId(_itemServerId!)) : null;
    final canManageCollections = isAdmin && (mediaClient?.capabilities.serverSideCollections ?? false);

    final menuActions = <MediaMenuAction>[];

    if (isCollection || isPlaylist) {
      menuActions.add(MediaMenuAction(value: 'play', icon: Symbols.play_arrow_rounded, label: t.common.play));

      menuActions.add(MediaMenuAction(value: 'shuffle', icon: Symbols.shuffle_rounded, label: t.mediaMenu.shufflePlay));

      // Download + sync-rule management. Video playlists and any collection
      // qualify, collections can contain movies, episodes, and shows.
      final isVideoPlaylist = isPlaylist && playlist.playlistType == 'video';
      if ((isVideoPlaylist || isCollection) && !PlatformDetector.isAppleTV()) {
        final hasRule = Provider.of<DownloadProvider>(context, listen: false).hasSyncRule(_itemSyncRuleKey(context));
        if (hasRule) {
          menuActions.add(
            MediaMenuAction(value: 'manage_sync', icon: Symbols.sync_rounded, label: t.downloads.manageSyncRule),
          );
          menuActions.add(
            MediaMenuAction(
              value: 'remove_sync',
              icon: Symbols.sync_disabled_rounded,
              label: t.downloads.removeSyncRule,
            ),
          );
        } else {
          menuActions.add(
            MediaMenuAction(
              value: isPlaylist ? 'download_playlist' : 'download_collection',
              icon: Symbols.download_rounded,
              label: t.downloads.downloadNow,
            ),
          );
        }
      }

      // A playlist is the user's own; a collection is canonical server data.
      if (isPlaylist || isAdmin) {
        menuActions.add(
          MediaMenuAction(value: 'delete', icon: Symbols.delete_rounded, label: t.common.delete, destructive: true),
        );
      }
    } else {
      menuActions.addAll(
        _itemRows(
          context,
          mediaItem!,
          itemBackend: itemBackend,
          mediaClient: mediaClient,
          isAdmin: isAdmin,
          canManageCollections: canManageCollections,
        ),
      );
    }

    return _MenuFacts(
      mediaItem: mediaItem,
      playlist: playlist,
      mediaKind: mediaKind,
      canManageCollections: canManageCollections,
      actions: menuActions,
    );
  }

  List<AppMenuEntry<String>> _menuEntries(List<MediaMenuAction> actions) {
    return [
      for (final action in actions)
        AppMenuItem<String>(
          value: action.value,
          icon: action.icon,
          label: action.label,
          subtitle: action.subtitle,
          destructive: action.destructive,
        ),
    ];
  }

  /// Plex-only: an item is unmatched when its [MediaItem.guid] is missing or
  /// references the Plex no-agent marker.
  bool _isUnmatched(MediaItem item) {
    final g = item.guid;
    return g == null || g.isEmpty || g.contains('agents.none://');
  }
}
