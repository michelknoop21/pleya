import '../../media/media_item.dart';
import '../../media/watchlist_entry.dart';
import '../../media/watchlist_scope.dart';
import '../../media/watchlist_source.dart';

/// Pleya Verify only: the fixture server's kijklijst as a watchlist source.
///
/// A real kijklijst comes from a Plex account or from Jellyfin favorites, and
/// the Pleya Server fixture has neither, so Mijn Pleya and Home never showed a
/// kijklijst in a simulator run. `WatchlistSourceFactory` adds this source in
/// a `PLEYA_VERIFY` build when the fixture serves a non-empty list
/// (`watchlist.studio.v1`); without that seed it stays out, and the path
/// without a kijklijst keeps working as in production.
///
/// Read-only: the scenarios photograph the list, they do not edit it.
class VerifyWatchlistSource implements WatchlistSource {
  VerifyWatchlistSource({required this.scope, required this.fetchIds, required this.fetchItem});

  @override
  final WatchlistScopeId scope;

  /// The fixture's ids, newest first.
  final Future<List<String>> Function() fetchIds;

  /// One catalogue item by id, from the same server.
  final Future<MediaItem?> Function(String id) fetchItem;

  /// The fixture items have no external ids, so the entry key is the item id
  /// in its own namespace; it can never collide with a `plex:`/`imdb:` key.
  static String keyFor(String itemId) => 'verify:$itemId';

  @override
  bool accepts(MediaItem item) => false;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    final entries = <WatchlistEntry>[];
    for (final id in await fetchIds()) {
      // One retry: a profile rebind can close the client mid-request, and the
      // second call reaches its replacement ([fetchItem] looks it up anew).
      final item = await fetchItem(id) ?? await fetchItem(id);
      if (item == null) continue;
      entries.add(
        WatchlistEntry(
          key: keyFor(id),
          kind: item.kind,
          item: item,
          posterRef: item.thumbPath,
          lastKnownMatch: item,
          memberships: [WatchlistMembership(scope: scope, remoteKey: id, sourcePosition: entries.length)],
        ),
      );
    }
    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) =>
      Future.error(const WatchlistScopeUnavailable('the Pleya Verify kijklijst is read-only'));

  @override
  Future<void> remove(WatchlistMembership membership) =>
      Future.error(const WatchlistScopeUnavailable('the Pleya Verify kijklijst is read-only'));

  @override
  Future<bool?> contains(MediaItem item) async => null;
}
