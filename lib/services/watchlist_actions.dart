import '../media/media_item.dart';
import '../media/watchlist_entry.dart';
import '../media/watchlist_key.dart';
import '../media/watchlist_source.dart';
import '../utils/app_logger.dart';
import '../utils/watchlist_notifier.dart';
import 'watchlist/watchlist_repository.dart';

/// How a watchlist mutation ended.
enum WatchlistOutcome {
  added,
  removed,

  /// No source will take this title (a Plex item without a guid, a local file,
  /// a shared item).
  unsupported,

  /// Refused because the device is offline. Watchlist writes are not queued,
  /// see [WatchlistActions.remove].
  offlineRejected,

  /// The whole operation failed and the local state was put back.
  failed,

  /// Some sources were changed and others were not, and the app could not undo
  /// the ones that succeeded. The caller must refetch and tell the user; the
  /// list is in a state neither side chose.
  partiallyFailed,
}

/// The single entry point for putting titles on the kijklijst and taking them
/// off again.
///
/// Same contract as `WatchActions`: UI never calls a source or a client
/// directly. Everything that has to happen around a mutation (the optimistic
/// patch, the event, the compensation when a multi-source removal goes half
/// way) lives here so no screen has to remember it.
class WatchlistActions {
  WatchlistActions._();

  /// Put [item] on the list.
  ///
  /// Adding is single-source by construction: [WatchlistRepository.targetFor]
  /// picks the one place the title belongs, so there is nothing to compensate.
  static Future<WatchlistOutcome> add({
    required WatchlistRepository repository,
    required MediaItem item,
    required bool isOffline,
    WatchlistNotifier? notifier,
  }) async {
    final key = watchlistKeyForItem(item);
    if (key == null) return WatchlistOutcome.unsupported;
    if (isOffline) return WatchlistOutcome.offlineRejected;

    final source = repository.targetFor(item);
    if (source == null) return WatchlistOutcome.unsupported;

    final events = notifier ?? WatchlistNotifier();
    events.notify(WatchlistEvent(key: key, changeType: WatchlistChangeType.added, optimistic: true));

    try {
      await source.add(item);
      events.notify(WatchlistEvent(key: key, changeType: WatchlistChangeType.added));
      return WatchlistOutcome.added;
    } catch (e, st) {
      appLogger.w('Watchlist add failed for $key', error: e, stackTrace: st);
      events.notify(WatchlistEvent(key: key, changeType: WatchlistChangeType.removed));
      return WatchlistOutcome.failed;
    }
  }

  /// Take [entry] off **every** list Pleya merged it from.
  ///
  /// There is no source picker. A title that sits on the Plex watchlist and in
  /// Jellyfin favorites is one title to the user, and asking which copy to
  /// remove would be asking about an implementation detail.
  ///
  /// **The operation is not atomic, and this does not pretend otherwise.** If
  /// Plex succeeds and Jellyfin fails, a local rollback does not undo the Plex
  /// write. So:
  ///
  /// 1. Remove membership by membership.
  /// 2. On the first failure, put the already-removed ones back.
  /// 3. If that compensation succeeds the end state equals the start state and
  ///    the optimistic patch can be reverted honestly.
  /// 4. If the compensation also fails, nothing pretends the rollback worked.
  ///    The caller gets [WatchlistOutcome.partiallyFailed] and has to refetch.
  ///
  /// Offline is refused rather than queued. A queued mutation has no merge
  /// rule against what the same account did on plex.tv in the meantime, and
  /// replaying it later could delete a title the user re-added by hand.
  static Future<WatchlistOutcome> remove({
    required List<WatchlistSource> sources,
    required WatchlistEntry entry,
    required bool isOffline,
    WatchlistNotifier? notifier,
  }) async {
    if (isOffline) return WatchlistOutcome.offlineRejected;

    final byScope = {for (final source in sources) source.scope: source};
    final targets = entry.memberships.where((m) => byScope.containsKey(m.scope)).toList();
    if (targets.isEmpty) return WatchlistOutcome.unsupported;

    final events = notifier ?? WatchlistNotifier();
    events.notify(WatchlistEvent(key: entry.key, changeType: WatchlistChangeType.removed, optimistic: true));

    final removed = <WatchlistMembership>[];
    for (final membership in targets) {
      try {
        await byScope[membership.scope]!.remove(membership);
        removed.add(membership);
      } catch (e, st) {
        appLogger.w('Watchlist remove failed on ${membership.scope.storageKey}', error: e, stackTrace: st);
        final compensated = await _compensate(byScope, removed, entry);
        events.notify(
          WatchlistEvent(
            key: entry.key,
            changeType: compensated ? WatchlistChangeType.added : WatchlistChangeType.removed,
          ),
        );
        return compensated ? WatchlistOutcome.failed : WatchlistOutcome.partiallyFailed;
      }
    }

    events.notify(WatchlistEvent(key: entry.key, changeType: WatchlistChangeType.removed));
    return WatchlistOutcome.removed;
  }

  /// Put back what was already removed. Returns whether the start state was
  /// fully restored.
  ///
  /// Every step is attempted even after one fails, because a partial
  /// compensation still leaves fewer titles missing than giving up on the
  /// first error would.
  static Future<bool> _compensate(
    Map<Object, WatchlistSource> byScope,
    List<WatchlistMembership> removed,
    WatchlistEntry entry,
  ) async {
    var restored = true;
    for (final membership in removed) {
      final source = byScope[membership.scope];
      if (source == null) {
        restored = false;
        continue;
      }
      try {
        await source.add(entry.item);
      } catch (e, st) {
        restored = false;
        appLogger.e(
          'Watchlist compensation failed on ${membership.scope.storageKey}; the list is now in a mixed state',
          error: e,
          stackTrace: st,
        );
      }
    }
    return restored;
  }
}
