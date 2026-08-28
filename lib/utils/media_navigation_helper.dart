import 'package:flutter/material.dart';
import '../i18n/strings.g.dart';
import '../diagnostics/select_trace.dart';
import '../diagnostics/select_trace_recorder.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_playlist.dart';
import '../screens/collection_detail_screen.dart';
import '../screens/main_screen.dart';
import '../screens/media_detail_screen.dart';
import '../screens/playlist/playlist_detail_screen.dart';
import '../services/settings_service.dart';
import '../utils/global_key_utils.dart';
import 'plex_library_section_helpers.dart';
import 'video_player_navigation.dart';

/// Result of media navigation indicating what action was taken
enum MediaNavigationResult {
  /// Navigation completed successfully
  navigated,

  /// Navigation completed, parent list should be refreshed (e.g., collection deleted)
  listRefreshNeeded,

  /// Item type not supported (e.g., music content)
  unsupported,

  /// Item is a library section — navigated to that library
  librarySelected,
}

class MediaDetailNavigationTarget {
  final MediaItem metadata;
  final int? initialSeasonIndex;
  final String? initialSeasonId;
  final String? initialEpisodeId;

  const MediaDetailNavigationTarget({
    required this.metadata,
    this.initialSeasonIndex,
    this.initialSeasonId,
    this.initialEpisodeId,
  });
}

MediaDetailNavigationTarget mediaDetailNavigationTargetFor(MediaItem item, {MediaItem? metadataOverride}) {
  if (item.isEpisode && item.grandparentId != null) {
    return MediaDetailNavigationTarget(
      metadata:
          metadataOverride ??
          MediaItem(
            id: item.grandparentId!,
            backend: item.backend,
            kind: MediaKind.show,
            title: item.grandparentTitle ?? item.displayTitle,
            thumbPath: item.grandparentThumbPath,
            artPath: item.grandparentArtPath,
            libraryId: item.libraryId,
            libraryTitle: item.libraryTitle,
            serverId: item.serverId,
            serverName: item.serverName,
          ),
      initialSeasonIndex: item.parentIndex,
      initialSeasonId: item.parentId,
      initialEpisodeId: item.id,
    );
  }

  if (item.isEpisode && item.parentId != null) {
    return MediaDetailNavigationTarget(
      metadata:
          metadataOverride ??
          MediaItem(
            id: item.parentId!,
            backend: item.backend,
            kind: MediaKind.season,
            title: item.parentTitle ?? t.common.seasonNumber(number: item.parentIndex ?? ''),
            index: item.parentIndex,
            thumbPath: item.parentThumbPath,
            parentId: item.grandparentId,
            libraryId: item.libraryId,
            libraryTitle: item.libraryTitle,
            serverId: item.serverId,
            serverName: item.serverName,
          ),
      initialEpisodeId: item.id,
    );
  }

  if (item.isSeason && item.parentId != null) {
    return MediaDetailNavigationTarget(
      metadata:
          metadataOverride ??
          MediaItem(
            id: item.parentId!,
            backend: item.backend,
            kind: MediaKind.show,
            title: item.grandparentTitle ?? item.parentTitle ?? item.displayTitle,
            thumbPath: item.grandparentThumbPath ?? item.parentThumbPath,
            artPath: item.grandparentArtPath,
            libraryId: item.libraryId,
            libraryTitle: item.libraryTitle,
            serverId: item.serverId,
            serverName: item.serverName,
          ),
      initialSeasonIndex: item.index,
      initialSeasonId: item.id,
    );
  }

  return MediaDetailNavigationTarget(metadata: metadataOverride ?? item);
}

bool shouldOpenEpisodeDetailsForActivation({
  required bool playDirectly,
  required ContinueWatchingAction continueWatchingAction,
  required EpisodeAction episodeAction,
}) {
  if (playDirectly) return continueWatchingAction == ContinueWatchingAction.details;
  return episodeAction == EpisodeAction.details;
}

/// Decides what runs after a direct-to-player activation returns, for
/// [navigateToMediaItem]'s episode/clip and movie branches. Pure, like
/// [shouldOpenEpisodeDetailsForActivation], so the "[onPlaybackReturned]
/// supersedes [onRefresh]'s `result == true` gate" behavior is unit
/// testable without driving a real player route.
void handlePlaybackReturn(
  MediaItem playedItem, {
  required bool? playerPopResult,
  required void Function(String)? onRefresh,
  required ValueChanged<MediaItem>? onPlaybackReturned,
}) {
  if (onPlaybackReturned != null) {
    onPlaybackReturned(playedItem);
  } else if (playerPopResult == true) {
    onRefresh?.call(playedItem.id);
  }
}

/// Navigates to the appropriate screen based on the item type.
///
/// Accepts a [MediaItem] or a [MediaPlaylist] (typed as [Object] because Dart
/// has no nominal union type).
///
/// For episodes, normal card activation follows the Episode Action setting;
/// [playDirectly] surfaces instead follow the Continue Watching action setting.
/// For movies, starts playback directly if [playDirectly] is true and the
/// Continue Watching details setting is disabled; otherwise navigates to media
/// detail screen.
/// For seasons, navigates to season detail screen.
/// For playlists, navigates to playlist detail screen.
/// For collections, navigates to collection detail screen.
/// For other types (shows), navigates to media detail screen.
/// For music types (artist, album, track), returns [MediaNavigationResult.unsupported].
///
/// The [onRefresh] callback is invoked with the item's id after returning from
/// the detail screen, allowing the caller to refresh state.
///
/// [onPlaybackReturned] runs after the two direct-to-player branches
/// (episode/clip, movie) regardless of what the player route popped with,
/// unlike [onRefresh], which only fires there when the result is `true`.
/// `VideoPlayerScreen` only ever pops `true` from its own `_handleBack`; any
/// other exit (system back, a route replaced under it) pops `false`/`null`
/// and would otherwise leave a caller relying on `onRefresh` alone unrefreshed.
/// When both are supplied, [onPlaybackReturned] supersedes [onRefresh] in
/// those two branches so a caller doesn't pay for two refreshes of the same
/// return; [onRefresh] keeps its exact current behaviour everywhere else.
///
/// Set [isOffline] to true for downloaded content without server access.
///
/// Set [playDirectly] to true for Continue Watching / Next Up / On Deck
/// activation; those surfaces use the Continue Watching action setting instead
/// of the normal Episode Action setting.
///
/// Returns a [MediaNavigationResult] indicating what action was taken:
/// - [MediaNavigationResult.navigated]: Navigation completed, item refresh handled
/// - [MediaNavigationResult.listRefreshNeeded]: Caller should refresh entire list
/// - [MediaNavigationResult.unsupported]: Item type not supported, caller should handle
Future<MediaNavigationResult> navigateToMediaItem(
  BuildContext context,
  Object item, {
  void Function(String)? onRefresh,
  bool isOffline = false,
  bool playDirectly = false,
  Object? heroTag,
  String? traceId,
  ValueChanged<MediaItem>? onPlaybackReturned,
}) async {
  final recorder = SelectTraceRecorder.instance;
  if (item is MediaPlaylist) {
    recorder.close(traceId, SelectTraceOutcome.hubDetail);
    await Navigator.push(context, MaterialPageRoute(builder: (context) => PlaylistDetailScreen(playlist: item)));
    return MediaNavigationResult.navigated;
  }

  if (item is! MediaItem) {
    recorder.close(traceId, SelectTraceOutcome.none);
    return MediaNavigationResult.unsupported;
  }
  final mi = item;
  final settings = SettingsService.instanceOrNull;
  final continueWatchingAction = settings?.read(SettingsService.continueWatchingAction) ?? ContinueWatchingAction.play;
  final episodeAction = settings?.read(SettingsService.episodeAction) ?? EpisodeAction.play;
  final shouldOpenContinueWatchingDetails = playDirectly && continueWatchingAction == ContinueWatchingAction.details;
  final shouldOpenEpisodeDetails = shouldOpenEpisodeDetailsForActivation(
    playDirectly: playDirectly,
    continueWatchingAction: continueWatchingAction,
    episodeAction: episodeAction,
  );

  // Handle library section items (shared whole-library entries) — Plex-only;
  // [PlexLibrarySection.isLibrarySection] reads the stashed `key` from `raw`.
  if (mi.isLibrarySection) {
    final sectionKey = mi.librarySectionKey;
    if (sectionKey != null && mi.serverId != null) {
      final libraryGlobalKey = buildGlobalKey(ServerId(mi.serverId!), sectionKey);
      MainScreenFocusScope.of(context, listen: false)?.selectLibrary?.call(libraryGlobalKey);
      recorder.close(traceId, SelectTraceOutcome.none);
      return MediaNavigationResult.librarySelected;
    }
    recorder.close(traceId, SelectTraceOutcome.none);
    return MediaNavigationResult.unsupported;
  }

  switch (mi.kind) {
    case MediaKind.collection:
      recorder.close(traceId, SelectTraceOutcome.hubDetail);
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => CollectionDetailScreen(collection: mi)),
      );
      // If collection was deleted, signal that list refresh is needed
      if (result == true) {
        return MediaNavigationResult.listRefreshNeeded;
      }
      return MediaNavigationResult.navigated;

    case MediaKind.artist:
    case MediaKind.album:
    case MediaKind.track:
      // Music types not supported
      recorder.close(traceId, SelectTraceOutcome.none);
      return MediaNavigationResult.unsupported;

    case MediaKind.clip:
    case MediaKind.episode:
      if (mi.kind == MediaKind.episode && shouldOpenEpisodeDetails) {
        return navigateToMediaItemDetails(
          context,
          mi,
          onRefresh: onRefresh,
          isOffline: isOffline,
          heroTag: heroTag,
          traceId: traceId,
        );
      }
      recorder.close(traceId, SelectTraceOutcome.player);
      final result = await navigateToVideoPlayer(context, metadata: mi, isOffline: isOffline);
      if (context.mounted) {
        handlePlaybackReturn(mi, playerPopResult: result, onRefresh: onRefresh, onPlaybackReturned: onPlaybackReturned);
      }
      return MediaNavigationResult.navigated;

    case MediaKind.movie:
      if (playDirectly && !shouldOpenContinueWatchingDetails) {
        recorder.close(traceId, SelectTraceOutcome.player);
        final result = await navigateToVideoPlayer(context, metadata: mi, isOffline: isOffline);
        if (context.mounted) {
          handlePlaybackReturn(
            mi,
            playerPopResult: result,
            onRefresh: onRefresh,
            onPlaybackReturned: onPlaybackReturned,
          );
        }
        return MediaNavigationResult.navigated;
      }
      return navigateToMediaItemDetails(
        context,
        mi,
        isOffline: isOffline,
        onRefresh: onRefresh,
        heroTag: heroTag,
        traceId: traceId,
      );

    case MediaKind.season:
      return navigateToMediaItemDetails(
        context,
        mi,
        isOffline: isOffline,
        onRefresh: onRefresh,
        heroTag: heroTag,
        traceId: traceId,
      );

    default:
      return navigateToMediaItemDetails(
        context,
        mi,
        isOffline: isOffline,
        onRefresh: onRefresh,
        heroTag: heroTag,
        traceId: traceId,
      );
  }
}

Future<MediaNavigationResult> navigateToMediaItemDetails(
  BuildContext context,
  MediaItem mi, {
  bool isOffline = false,
  void Function(String)? onRefresh,
  MediaItem? metadataOverride,
  Object? heroTag,
  String? traceId,
}) async {
  final target = mediaDetailNavigationTargetFor(mi, metadataOverride: metadataOverride);
  // The route boundary, not the activation site: comparing this against the
  // expected target recorded back at the row is what catches a swap in between.
  SelectTraceRecorder.instance.link(
    traceId,
    SelectTraceLink.actualNavigationTarget,
    target.metadata,
    note: metadataOverride == null ? null : 'override',
  );
  final result = await Navigator.push<bool>(
    context,
    mediaDetailRoute(
      metadata: target.metadata,
      isOffline: isOffline,
      initialSeasonIndex: target.initialSeasonIndex,
      initialSeasonId: target.initialSeasonId,
      initialEpisodeId: target.initialEpisodeId,
      heroTag: heroTag,
      traceId: traceId,
    ),
  );
  // Backstop for a screen that never got as far as its metadata: a fast back,
  // a route replaced under it, a server that never answered. Closing here as
  // `detail` rather than abandoning keeps that from reading as a defect, while
  // any mismatch among the links it did collect still shows up.
  SelectTraceRecorder.instance.close(traceId, SelectTraceOutcome.detail);
  if (result == true && context.mounted) {
    onRefresh?.call(mi.id);
  }
  return MediaNavigationResult.navigated;
}
