import '../database/app_database.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../media/playback_report_metadata.dart';
import '../utils/app_logger.dart';
import 'trackers/tracker_coordinator.dart';

/// Sync a single action to the server.
///
/// Uses the neutral [MediaServerClient] surface so Jellyfin's
/// `/UserPlayedItems/{id}` and `/Sessions/Playing*` endpoints receive
/// the same queued state Plex's `/:/scrobble` and `/:/timeline` do.
Future<void> replayOfflineWatchAction(MediaServerClient client, OfflineWatchProgressItem action) async {
  // Fetch metadata so trackers (and the stop-path watch event) get enough
  // context — external ids, parent chain, library section. The plain
  // watched/unwatched replays deliberately emit no WatchStateEvent: the
  // offline provider already emitted it when the action was queued, and
  // client markWatched/markUnwatched are transport-only. Best-effort: a
  // missed metadata fetch falls back to a minimal MediaItem — the network
  // call still goes through.
  final needsRichItem =
      action.actionType == OfflineActionType.watched.id ||
      action.actionType == OfflineActionType.unwatched.id ||
      action.actionType == OfflineActionType.removedFromContinueWatching.id ||
      ((action.actionType == OfflineActionType.progress.id ||
              action.actionType == OfflineActionType.mirroredProgress.id) &&
          action.shouldMarkWatched);
  MediaItem? item;
  if (needsRichItem) {
    try {
      item = await client.fetchItem(action.ratingKey);
    } catch (_) {
      // Fall through to the synthetic item below.
    }
  }
  final resolvedItem =
      item ??
      MediaItem(id: action.ratingKey, backend: client.backend, kind: MediaKind.unknown, serverId: action.serverId);

  switch (action.actionType) {
    case 'watched':
      await client.markWatched(resolvedItem);
      await _scrobbleBestEffort(() => TrackerCoordinator.instance.markWatched(resolvedItem, client));
      break;

    case 'unwatched':
      await client.markUnwatched(resolvedItem);
      await _scrobbleBestEffort(() => TrackerCoordinator.instance.markUnwatched(resolvedItem, client));
      break;

    case 'removeFromContinueWatching':
      // Idempotent by construction: Plex's PUT
      // `/actions/removeFromContinueWatching` is a no-op for a rating key
      // that is already off the shelf, so a replay that races the user
      // removing it elsewhere costs one request and changes nothing. No
      // WatchStateEvent either — the surface suppressed the card when the
      // action was queued, and re-announcing it on replay would only
      // re-remove something already gone.
      //
      // A source that cannot remove server-side never gets one of these rows
      // any more (it is hidden on the device instead, DEC-144 fase 3), but a
      // row queued before that would throw `UnsupportedError` on every
      // reconnect. Drop it: there is nothing for the server to do.
      if (!client.capabilities.continueWatchingRemoval) {
        appLogger.i('Dropping queued Continue Watching removal for ${action.ratingKey}: unsupported on this server');
        break;
      }
      await client.removeFromContinueWatching(resolvedItem);
      break;

    case 'progress' || 'mirroredProgress':
      // Last-writer-wins guard: if another device produced newer watch state
      // (marked watched, or viewed more recently than this queued offline
      // action), replaying our stale viewOffset would clobber it. Best-effort:
      // if the state fetch fails we proceed with the replay as before.
      try {
        final server = await client.fetchItem(action.ratingKey);
        if (server != null) {
          final serverViewedMs = (server.lastViewedAt ?? 0) * 1000;
          final serverIsNewer =
              ((server.viewCount ?? 0) > 0 && !action.shouldMarkWatched) || serverViewedMs > action.updatedAt;
          if (serverIsNewer) {
            appLogger.i('Skipping stale offline progress for ${action.ratingKey}: server state is newer');
            return;
          }
        }
      } catch (e) {
        appLogger.d('Offline progress: pre-replay state check failed (continuing)', error: e);
      }
      // Push resumable progress, or a completed offline playback. Jellyfin's
      // `/Sessions/Playing/Stopped` ignores events without an open session
      // row, so non-Plex backends still get a lightweight Started call.
      if (action.viewOffset != null) {
        final duration = action.duration == null ? null : Duration(milliseconds: action.duration!);
        final position = action.shouldMarkWatched && duration != null
            ? duration
            : Duration(milliseconds: action.viewOffset!);
        if (!action.shouldMarkWatched || client.backend != MediaBackend.plex) {
          try {
            await client.reportPlaybackStarted(itemId: action.ratingKey, position: position, duration: duration);
          } catch (e) {
            // Plex sometimes 5xxs the start when nothing follows; treat as
            // best-effort and continue to the stop call which is the one
            // that actually persists the resume position.
            appLogger.d('Offline progress: started call failed (continuing)', error: e);
          }
        }
        await client.reportPlaybackStopped(
          itemId: action.ratingKey,
          position: position,
          duration: duration,
          report: PlaybackReportMetadata.offlineReplay(
            recordedAt: DateTime.fromMillisecondsSinceEpoch(action.updatedAt),
          ),
        );
      }

      // If progress exceeded threshold, also mark as watched. On backends
      // that mark played from the stopped report above (Jellyfin) this only
      // emits the local watch event — an explicit markWatched would
      // double-scrobble via the Trakt plugin (#1287).
      if (action.shouldMarkWatched) {
        if (action.actionType == OfflineActionType.mirroredProgress.id) {
          // The source that played told the trackers. This write only has
          // to reach the server, so no watched event either: Trakt keys on
          // that one and would count the viewing twice.
          if (!client.marksWatchedOnPlaybackStopped) await client.markWatched(resolvedItem);
        } else {
          await client.markWatchedFromPlaybackStop(resolvedItem);
          await _scrobbleBestEffort(() => TrackerCoordinator.instance.markWatched(resolvedItem, client));
        }
      }
      break;
  }
}

/// Tracker scrobbles are best-effort: a tracker-only failure must not
/// requeue the whole action — replaying it would re-report playback to the
/// media server and double-scrobble on the next attempt.
Future<void> _scrobbleBestEffort(Future<void> Function() scrobble) async {
  try {
    await scrobble();
  } catch (e) {
    appLogger.w('Offline sync: tracker scrobble failed (not retried)', error: e);
  }
}
