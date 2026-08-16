import '../../media/ids.dart';
import '../../media/watchlist_entry.dart';
import '../../media/watchlist_scope.dart';
import '../../utils/app_logger.dart';
import '../api_cache.dart';

/// The last list each source handed over, kept so the kijklijst still exists
/// when the network does not.
///
/// One row per scope, not one per profile. Sources fail independently, and a
/// combined row would mean a Plex hiccup wiping the Jellyfin favorites out of
/// the offline list as a side effect.
///
/// Rows are pinned. `clearVolatile` exists to free ordinary cached responses,
/// and taking the offline watchlist with it would empty the screen exactly
/// when there is no way to refill it.
class WatchlistSnapshotStore {
  WatchlistSnapshotStore({required this.cache});

  final ApiCache cache;

  static final ServerId cacheServerId = ServerId('watchlist-snapshot');

  static String endpointFor(WatchlistScopeId scope) => 'entries/${scope.storageKey}';

  /// Replace the snapshot for [scope].
  ///
  /// An empty list is written, not skipped: "this user cleared their
  /// watchlist" has to survive a restart just as much as a full list does.
  Future<void> write(WatchlistScopeId scope, List<WatchlistEntry> entries) async {
    try {
      await cache.put(cacheServerId, endpointFor(scope), {
        'version': 1,
        'entries': entries.map((e) => e.toJson()).toList(),
      });
      await cache.pin(cacheServerId, endpointFor(scope));
    } catch (e, st) {
      appLogger.w('Watchlist snapshot write failed for ${scope.storageKey}', error: e, stackTrace: st);
    }
  }

  /// What [scope] last held, or null when nothing was ever stored.
  ///
  /// Null and an empty list mean different things here. Null is "no snapshot",
  /// which hides the kijklijst section offline; empty is "the list was empty",
  /// which shows the empty state.
  Future<List<WatchlistEntry>?> read(WatchlistScopeId scope) async {
    final Map<String, dynamic>? row;
    try {
      row = await cache.get(cacheServerId, endpointFor(scope));
    } catch (e) {
      appLogger.w('Watchlist snapshot read failed for ${scope.storageKey}', error: e);
      return null;
    }
    if (row == null) return null;

    final raw = row['entries'];
    if (raw is! List) return null;

    final entries = <WatchlistEntry>[];
    for (final item in raw) {
      final entry = WatchlistEntry.fromJson(item);
      // A row that no longer parses is dropped rather than repaired. Every
      // reason it could fail (no memberships, no key, an item shape from an
      // older schema) leaves a title the user cannot act on.
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  Future<void> clear(WatchlistScopeId scope) async {
    try {
      await cache.unpin(cacheServerId, endpointFor(scope));
      await cache.delete(cacheServerId, endpointFor(scope));
    } catch (e) {
      appLogger.w('Watchlist snapshot clear failed for ${scope.storageKey}', error: e);
    }
  }
}
