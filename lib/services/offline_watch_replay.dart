import '../database/app_database.dart';
import '../exceptions/media_server_exceptions.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../media/playback_report_metadata.dart';
import '../utils/app_logger.dart';
import '../utils/watch_state_notifier.dart';
import 'pleya_server_client.dart';
import 'trackers/tracker_coordinator.dart';

/// Whether a write to a copy that failed stays in the queue, for the replay and
/// for the first attempt alike. A copy that refuses or is gone will not change
/// its mind, and nobody is waiting on it: the source that played has the viewing.
///
/// A Pleya Server token round that failed is neither: on that client an auth
/// exception only comes from minting a token, so the write never went out. Which
/// kind says little: after a bare 401 the session answers as if its chain was
/// revoked. The row is scoped to this account and lands after the next sign-in.
bool copyWriteStaysQueued(MediaServerClient client, Object error) =>
    (client is PleyaServerClient && error is MediaServerAuthException) || isRetryableServerWriteFailure(error);

/// The profile changed while a row was being replayed. The row stays: a Plex
/// client takes the next profile's token in place, so anything sent now lands
/// on that account.
class ReplayInterrupted implements Exception {
  const ReplayInterrupted();
}

/// Sync a single action to the server. Answers whether the server got it: a
/// row can also turn out to have nothing to add.
///
/// [isCurrent] says the profile of this row is still the active one. Looked at
/// right before every write, because each read before it can take seconds.
///
/// Uses the neutral [MediaServerClient] surface so Jellyfin's
/// `/UserPlayedItems/{id}` and `/Sessions/Playing*` endpoints receive
/// the same queued state Plex's `/:/scrobble` and `/:/timeline` do.
Future<bool> replayOfflineWatchAction(
  MediaServerClient client,
  OfflineWatchProgressItem action, {
  bool Function()? isCurrent,
}) async {
  void beforeWrite() {
    if (isCurrent?.call() == false) throw const ReplayInterrupted();
  }

  if (action.actionType == OfflineActionType.mirroredProgress.id) {
    return _replayCopyProgress(client, action, beforeWrite);
  }
  if (action.actionType == OfflineActionType.mirroredWatched.id ||
      action.actionType == OfflineActionType.mirroredUnwatched.id) {
    return _replayCopyMark(client, action, beforeWrite);
  }

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
      (action.actionType == OfflineActionType.progress.id && action.shouldMarkWatched);
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
  beforeWrite();

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
        return false;
      }
      await client.removeFromContinueWatching(resolvedItem);
      break;

    case 'progress':
      // Last-writer-wins guard: if another device produced newer watch state
      // (marked watched, or viewed more recently than this queued offline
      // action), replaying our stale viewOffset would clobber it. Best-effort:
      // if the state fetch fails we proceed with the replay as before.
      try {
        // Watched as it stands now: `viewCount` on a plain read is `play_count`
        // on Pleya Server, and that outlives a mark as unwatched.
        final server = client is CopyStateClient
            ? await client.readCopyState(action.ratingKey)
            : await client.fetchItem(action.ratingKey);
        if (server != null) {
          final serverViewedMs = (server.lastViewedAt ?? 0) * 1000;
          final serverIsNewer =
              ((server.viewCount ?? 0) > 0 && !action.shouldMarkWatched) || serverViewedMs > action.updatedAt;
          if (serverIsNewer) {
            appLogger.i('Skipping stale offline progress for ${action.ratingKey}: server state is newer');
            return false;
          }
        }
      } catch (e) {
        appLogger.d('Offline progress: pre-replay state check failed (continuing)', error: e);
      }
      beforeWrite();
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
            // Without an open session Jellyfin and Emby accept the stop and
            // keep nothing: the row would go and the position with it.
            if (client.backend != MediaBackend.plex) rethrow;
            // Plex sometimes 5xxs the start when nothing follows; treat as
            // best-effort and continue to the stop call which is the one
            // that actually persists the resume position.
            appLogger.d('Offline progress: started call failed (continuing)', error: e);
          }
        }
        beforeWrite();
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
        beforeWrite();
        await client.markWatchedFromPlaybackStop(resolvedItem);
        await _scrobbleBestEffort(() => TrackerCoordinator.instance.markWatched(resolvedItem, client));
      }
      break;
  }
  return true;
}

/// The copy as its server has it now, for a row that may not write blind. Only a
/// server saying the copy is gone ends the row: null, and the caller stops.
/// Without an answer the row stays.
Future<MediaItem?> _readCopy(CopyStateClient client, OfflineWatchProgressItem action) async {
  try {
    return await client.readCopyState(action.ratingKey);
  } catch (e) {
    // Whatever went wrong, it says nothing about the copy: the refusals that
    // end a row are for a write, and a rejected token or a failed token round
    // on this read is not one.
    throw StateError('No answer about ${action.ratingKey}: $e');
  }
}

/// Someone viewed the copy after this row was written. Newest wins, so the row
/// has nothing to say any more.
bool _copyMovedOn(MediaItem copy, OfflineWatchProgressItem action) =>
    (copy.lastViewedAt ?? 0) * 1000 > action.updatedAt;

/// A mark that waited for this copy. A mark rewrites what stands there: it clears
/// a viewing on Jellyfin and Emby, and sets the position to zero on Pleya Server.
/// So it reads first, like a position does.
Future<bool> _replayCopyMark(
  MediaServerClient client,
  OfflineWatchProgressItem action,
  void Function() beforeWrite,
) async {
  if (client is! CopyStateClient) return false;
  final copy = await _readCopy(client, action);
  // Before the row can end: this answer may be the next profile's.
  beforeWrite();
  if (copy == null || _copyMovedOn(copy, action)) {
    appLogger.i('Skipping held mark for ${action.ratingKey}: the copy moved on');
    return false;
  }
  final watched = action.actionType == OfflineActionType.mirroredWatched.id;
  if (watched) {
    await client.markWatched(copy);
  } else {
    await client.markUnwatched(copy);
  }
  _announceCopy(client, copy, watched: watched);
  return true;
}

/// A viewing on another server, written to this copy. Never with the playback
/// reports: nobody is watching here (see [CopyStateClient]). The state of the
/// copy is read first, because a row can wait a long time.
Future<bool> _replayCopyProgress(
  MediaServerClient client,
  OfflineWatchProgressItem action,
  void Function() beforeWrite,
) async {
  if (client is! CopyStateClient) return false;
  final finished = action.shouldMarkWatched;
  final copy = await _readCopy(client, action);
  // Before the row can end: this answer may be the next profile's.
  beforeWrite();
  if (copy == null || _copyHasNothingToGain(client, copy, action)) {
    appLogger.i('Skipping mirrored progress for ${action.ratingKey}: nothing to add');
    return false;
  }
  final duration = action.duration == null ? null : Duration(milliseconds: action.duration!);
  final position = finished && duration != null ? duration : Duration(milliseconds: action.viewOffset ?? 0);
  final landed = await client.writeCopyState(copy, position: position, duration: duration, watched: finished);
  if (landed) {
    // The source that played told the trackers, so this write only has to
    // reach the server. A copy event and no plain one: Trakt keys on that and
    // would count the viewing twice.
    if (finished) _announceCopy(client, copy, watched: true);
    return true;
  }
  // A viewing holds the title, and what it reports is newer than this position.
  // A finished viewing is not: that one waits for its turn.
  if (finished) throw StateError('${action.ratingKey} is being played elsewhere');
  return false;
}

bool _copyHasNothingToGain(CopyStateClient client, MediaItem copy, OfflineWatchProgressItem action) {
  if (_copyMovedOn(copy, action)) return true;
  final seen = (copy.viewCount ?? 0) > 0;
  // One viewing counts once: a stop that failed brings the same one back when
  // its own row lands, and a server's plugin would scrobble the second write. A
  // position still on the copy is a rewatch, and that one gets to finish.
  if (action.shouldMarkWatched) return seen && (copy.viewOffsetMs ?? 0) == 0;
  if (seen && !client.movesCopyWithoutViewing) return true;
  return (copy.viewOffsetMs ?? 0) >= (action.viewOffset ?? 0);
}

/// The copy changed: surfaces and the download cache hear it, and a later pull
/// finds no transition to report as a viewing of its own.
void _announceCopy(MediaServerClient client, MediaItem item, {required bool watched}) {
  WatchStateNotifier().notifyWatched(
    item: item,
    isNowWatched: watched,
    cacheServerId: client.cacheServerId,
    isCopy: true,
  );
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
