part of '../media_context_menu.dart';

extension on MediaContextMenuState {
  /// The rows for a movie, show, season or episode.
  List<MediaMenuAction> _itemRows(
    BuildContext context,
    MediaItem mediaItem, {
    required MediaBackend? itemBackend,
    required MediaServerClient? mediaClient,
    required bool isAdmin,
    required bool canManageCollections,
  }) {
    final mediaKind = mediaItem.kind;
    // A few rows stay Plex-only because the server-side feature has no
    // equivalent elsewhere (match/unmatch).
    final isPlex = itemBackend == MediaBackend.plex;
    final isPartiallyWatched = mediaItem.isPartiallyWatched;
    final isPlayableKind =
        mediaKind == MediaKind.movie ||
        mediaKind == MediaKind.episode ||
        mediaKind == MediaKind.show ||
        mediaKind == MediaKind.season;
    final hasActiveProgress =
        (mediaKind == MediaKind.movie || mediaKind == MediaKind.episode) && mediaItem.hasActiveProgress;
    final canTranscode = mediaClient?.capabilities.videoTranscoding ?? false;
    final canRemoveFromContinueWatching = mediaClient?.capabilities.continueWatchingRemoval ?? false;
    final canEditMetadata = isAdmin && supportsMetadataEdit(mediaClient, mediaKind);
    final isOfflineNow = context.read<OfflineModeProvider?>()?.isOffline ?? false;
    final watchlistProvider = context.read<WatchlistProvider?>();
    final ancestorMediaDetail = context.findAncestorWidgetOfExactType<MediaDetailScreen>();
    final isTV = PlatformDetector.isTV();

    final menuActions = <MediaMenuAction>[];

    // Watch: a card opens its detail page, so without this row a title starts
    // two taps away. The detail page of this very item has its own play button.
    if (isPlayableKind &&
        !isTV &&
        !isOfflineNow &&
        mediaClient != null &&
        ancestorMediaDetail?.metadata.id != mediaItem.id) {
      menuActions.add(MediaMenuAction(value: 'play_item', icon: Symbols.play_arrow_rounded, label: t.mediaMenu.watch));
    }

    if (hasActiveProgress) {
      menuActions.add(
        MediaMenuAction(
          value: 'play_from_beginning',
          icon: Symbols.replay_rounded,
          label: t.mediaMenu.playFromBeginning,
        ),
      );
    }

    // Trailer playback. The detail row may hide its trailer button on small
    // screens, so surface it here whenever the screen wires up onPlayTrailer.
    if (widget.onPlayTrailer != null) {
      menuActions.add(
        MediaMenuAction(value: 'play_trailer', icon: Symbols.theaters_rounded, label: t.tooltips.playTrailer),
      );
    }

    // Delen is the title and year, which every backend has. A surface may bring
    // its own (the phone detail page anchors it to its button). A TV has no
    // share sheet.
    if (widget.onShare != null || (isPlayableKind && !isTV)) {
      menuActions.add(MediaMenuAction(value: 'share', icon: Symbols.ios_share_rounded, label: t.common.share));
    }

    if (widget.onRequest != null) {
      menuActions.add(MediaMenuAction(value: 'request', icon: Symbols.playlist_add_rounded, label: t.seerr.request));
    }

    if (!mediaItem.isWatched || isPartiallyWatched || hasActiveProgress) {
      menuActions.add(
        MediaMenuAction(value: 'watch', icon: Symbols.check_circle_outline_rounded, label: t.mediaMenu.markAsWatched),
      );
    }

    if (mediaItem.isWatched || isPartiallyWatched || hasActiveProgress) {
      menuActions.add(
        MediaMenuAction(
          value: 'unwatch',
          icon: Symbols.remove_circle_outline_rounded,
          label: t.mediaMenu.markAsUnwatched,
        ),
      );
    }

    // DEC-144 fase 3: always offered. A source that cannot remove
    // server-side hides the title on this device and the row says so.
    if (widget.isInContinueWatching && mediaClient != null) {
      final removal = continueWatchingRemovalPresentation([
        (serverName: mediaItem.serverName, removesOnServer: canRemoveFromContinueWatching, reachable: true),
      ]);
      menuActions.add(
        MediaMenuAction(
          value: 'remove_from_continue_watching',
          icon: removal.hidesOnly ? Symbols.visibility_off_rounded : Symbols.close_rounded,
          label: removal.label,
          subtitle: removal.scope,
        ),
      );
    }

    final isVideoKind = mediaItem.isVideoContent;

    if (widget.isInContinueWatching && isVideoKind) {
      menuActions.add(MediaMenuAction(value: 'details', icon: Symbols.info_rounded, label: t.mediaMenu.viewDetails));
    }

    // A backend that keeps no rating (a local folder) gets no row.
    if (isVideoKind && (mediaClient?.capabilities.userRating ?? false)) {
      menuActions.add(MediaMenuAction(value: 'rate', icon: Symbols.star_rounded, label: t.mediaMenu.rate));
    }

    // Watchlist, for movies and shows only, backend-neutral, online only. A
    // watchlist write is refused offline rather than queued (see
    // `WatchlistActions.remove`), so offering it there would promise
    // something the layer underneath will not do. Hidden, not failing.
    if (!isOfflineNow && (mediaKind == MediaKind.movie || mediaKind == MediaKind.show)) {
      final onWatchlist = WatchlistUiActions.isOnList(
        store: context.read<WatchlistStore?>(),
        provider: watchlistProvider,
        item: mediaItem,
      );
      if (WatchlistUiActions.canOffer(provider: watchlistProvider, item: mediaItem, onList: onWatchlist)) {
        menuActions.add(
          MediaMenuAction(
            value: 'watchlist_toggle',
            icon: onWatchlist ? Symbols.bookmark_remove_rounded : Symbols.bookmark_add_rounded,
            label: onWatchlist ? t.watchlist.remove : t.watchlist.add,
            active: onWatchlist,
          ),
        );
      }
    }

    // Edit Metadata, admin-only and backend-capability gated.
    if (canEditMetadata) {
      menuActions.add(
        MediaMenuAction(value: 'edit_metadata', icon: Symbols.edit_rounded, label: t.metadataEdit.editMetadata),
      );
    }

    // Match / Unmatch, Plex-only (Jellyfin doesn't expose match agents).
    if (isPlex && isAdmin && (mediaKind == MediaKind.movie || mediaKind == MediaKind.show)) {
      final isUnmatched = _isUnmatched(mediaItem);
      menuActions.add(
        MediaMenuAction(
          value: 'match',
          icon: Symbols.search_rounded,
          label: isUnmatched ? t.matchScreen.match : t.matchScreen.fixMatch,
        ),
      );
      if (!isUnmatched) {
        menuActions.add(
          MediaMenuAction(value: 'unmatch', icon: Symbols.link_off_rounded, label: t.matchScreen.unmatch),
        );
      }
    }

    // Remove from Collection (only when viewing items within a collection).
    if (canManageCollections && widget.collectionId != null) {
      menuActions.add(
        MediaMenuAction(
          value: 'remove_from_collection',
          icon: Symbols.delete_outline_rounded,
          label: t.collections.removeFromCollection,
        ),
      );
    }

    // Go to Series (for episodes and seasons), hide if already on that series' detail screen
    final ancestorMeta = ancestorMediaDetail?.metadata;
    final ancestorSeriesKey = ancestorMeta != null && ancestorMeta.kind == MediaKind.season
        ? ancestorMeta.parentId
        : ancestorMeta?.id;
    // For episodes, the show key is grandparentId; for seasons, it's parentId
    final itemSeriesKey = mediaKind == MediaKind.episode ? mediaItem.grandparentId : mediaItem.parentId;
    if ((mediaKind == MediaKind.episode || mediaKind == MediaKind.season) &&
        itemSeriesKey != null &&
        !widget.isInContinueWatching &&
        ancestorSeriesKey != itemSeriesKey) {
      menuActions.add(MediaMenuAction(value: 'series', icon: Symbols.tv_rounded, label: t.mediaMenu.goToSeries));
    }

    if (mediaKind == MediaKind.show || mediaKind == MediaKind.season) {
      menuActions.add(
        MediaMenuAction(value: 'shuffle_play', icon: Symbols.shuffle_rounded, label: t.mediaMenu.shufflePlay),
      );
    }

    // Play Version (for episodes and movies). Hidden when there's
    // nothing to choose: a single source on a backend that can't
    // transcode (Jellyfin v1, or Plex installs without a working
    // transcoder) would just bounce straight to playback with default
    // settings, which is what the regular Play action already does.
    // Both backends inline their version list in browse responses
    // (`Media[]` for Plex, `MediaSources` for Jellyfin), so the count
    // is known up front.
    final versionCount = (mediaItem.mediaVersions ?? const []).length;
    final hasVersionChoice = versionCount > 1;
    if ((mediaKind == MediaKind.episode || mediaKind == MediaKind.movie) && (hasVersionChoice || canTranscode)) {
      menuActions.add(
        MediaMenuAction(value: 'play_version', icon: Symbols.video_file_rounded, label: t.mediaMenu.playVersion),
      );
    }

    // File Info (for episodes and movies). Backend-neutral, both
    // PlexClient and JellyfinClient implement [getFileInfo], reading
    // codec/stream metadata from `Media`/`MediaSources` respectively.
    // Hidden when the item has no backend marker so we don't fan out
    // to an arbitrary client.
    if (itemBackend != null && (mediaKind == MediaKind.episode || mediaKind == MediaKind.movie)) {
      menuActions.add(MediaMenuAction(value: 'fileinfo', icon: Symbols.info_rounded, label: t.mediaMenu.fileInfo));
    }

    if (PlatformDetector.supportsExternalPlayers() &&
        (mediaKind == MediaKind.episode || mediaKind == MediaKind.movie)) {
      menuActions.add(
        MediaMenuAction(
          value: 'play_external',
          icon: Symbols.open_in_new_rounded,
          label: t.externalPlayer.playInExternalPlayer,
        ),
      );
    }

    // Download options (for episodes, movies, shows, and seasons).
    // Apple TV has no user-accessible file storage, skip entirely.
    if (!PlatformDetector.isAppleTV() &&
        (mediaKind == MediaKind.episode ||
            mediaKind == MediaKind.movie ||
            mediaKind == MediaKind.show ||
            mediaKind == MediaKind.season)) {
      final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
      final globalKey = mediaItem.globalKey;
      final hasSyncRule = downloadProvider.hasSyncRule(_itemSyncRuleKey(context));
      final hasAnyDownload = downloadProvider.getProgress(globalKey) != null;

      if (hasSyncRule) {
        menuActions.add(
          MediaMenuAction(value: 'manage_sync', icon: Symbols.sync_rounded, label: t.downloads.manageSyncRule),
        );
        menuActions.add(
          MediaMenuAction(value: 'remove_sync', icon: Symbols.sync_disabled_rounded, label: t.downloads.removeSyncRule),
        );
        if (hasAnyDownload) {
          menuActions.add(
            MediaMenuAction(
              value: 'delete_download',
              icon: Symbols.delete_rounded,
              label: t.downloads.deleteDownload,
              destructive: true,
            ),
          );
        }
      } else if (hasAnyDownload) {
        menuActions.add(
          MediaMenuAction(
            value: 'delete_download',
            icon: Symbols.delete_rounded,
            label: t.downloads.deleteDownload,
            destructive: true,
          ),
        );
      } else {
        menuActions.add(
          MediaMenuAction(value: 'download', icon: Symbols.download_rounded, label: t.downloads.downloadNow),
        );
      }
    }

    // Add to... (for episodes, movies, shows, and seasons). A playlist needs
    // the backend's own list, a collection is decided in [_showAddToSubmenu].
    if ((mediaClient?.capabilities.serverSidePlaylists ?? false) &&
        (mediaKind == MediaKind.episode ||
            mediaKind == MediaKind.movie ||
            mediaKind == MediaKind.show ||
            mediaKind == MediaKind.season)) {
      menuActions.add(
        MediaMenuAction(
          value: 'add_to',
          icon: Symbols.add_rounded,
          label: t.common.addTo,
          panelLabel: canManageCollections ? t.mediaMenu.addToPlaylistOrCollection : t.mediaMenu.addToPlaylist,
        ),
      );
    }

    // Delete media item (for episodes, movies, shows, and seasons), admin
    // only. Backend-neutral: routed through `MediaServerClient.deleteMediaItem`,
    // which both Plex and Jellyfin implement (DELETE /library/metadata/{id}
    // and DELETE /Items/{id} respectively).
    if (isAdmin &&
        (mediaKind == MediaKind.episode ||
            mediaKind == MediaKind.movie ||
            mediaKind == MediaKind.show ||
            mediaKind == MediaKind.season)) {
      menuActions.add(
        MediaMenuAction(
          value: 'delete_media',
          icon: Symbols.delete_forever_rounded,
          label: t.mediaMenu.deleteFromServer,
          destructive: true,
        ),
      );
    }

    return menuActions;
  }
}
