import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/watchlist_entry.dart';
import '../../media/watchlist_key.dart';
import '../../media/watchlist_scope.dart';
import '../../media/watchlist_source.dart';
import '../../utils/external_ids.dart';

/// Jellyfin favorites as a watchlist source, one per online Jellyfin server.
///
/// Favorites are not a watchlist and the difference shows up in two places.
/// They are server-scoped, so the same title favorited on two servers is two
/// memberships. And the flag lives on any item at all, which is why the fetch
/// pins movies and series: a favorited channel is not something you meant to
/// watch later.
class JellyfinFavoritesSource implements WatchlistSource {
  final MediaServerClient client;
  final ServerId serverId;

  JellyfinFavoritesSource({required this.client, required this.serverId, required this.scope});

  @override
  final WatchlistScopeId scope;

  /// Maximum titles pulled per request. Favorites lists are small in practice;
  /// the loop below still walks every page rather than trusting that.
  static const int _pageSize = 100;

  @override
  bool accepts(MediaItem item) {
    if (item.backend != MediaBackend.jellyfin) return false;
    if (item.kind != MediaKind.movie && item.kind != MediaKind.show) return false;
    // A favorite is set on one server, so an item from another server cannot
    // be routed here.
    return item.serverId == serverId;
  }

  @override
  Future<List<WatchlistEntry>> fetch() async {
    final entries = <WatchlistEntry>[];
    var offset = 0;

    while (true) {
      final page = await client.fetchFavorites(offset: offset, limit: _pageSize);
      for (final item in page.items) {
        final entry = _toEntry(item);
        if (entry != null) entries.add(entry);
      }
      offset += page.items.length;
      if (page.items.isEmpty || offset >= page.totalCount) break;
    }

    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async {
    await client.setFavorite(item, true);
    return WatchlistMembership(scope: scope, remoteKey: item.id);
  }

  @override
  Future<void> remove(WatchlistMembership membership) async {
    await client.setFavorite(_itemForRemoval(membership.remoteKey), false);
  }

  @override
  Future<bool?> contains(MediaItem item) async => null;

  WatchlistEntry? _toEntry(MediaItem item) {
    final externalIds = _externalIdsOf(item);
    final key = watchlistKeyForItem(item, externalIds: externalIds);
    // No cross-server identity means the title cannot be matched anywhere
    // else, so it has no place on a list that spans servers.
    if (key == null || item.id.isEmpty) return null;

    return WatchlistEntry(
      key: key,
      kind: item.kind,
      item: item,
      guid: item.guid,
      externalIds: externalIds,
      posterRef: item.thumbPath,
      memberships: [WatchlistMembership(scope: scope, remoteKey: item.id)],
    );
  }

  /// Jellyfin ships external ids inline on every item, so no extra call is
  /// needed to identify a favorite across servers.
  static ExternalIds _externalIdsOf(MediaItem item) {
    final providerIds = item.raw?['ProviderIds'];
    if (providerIds is Map<String, Object?>) return ExternalIds.fromJellyfinProviderIds(providerIds);
    return const ExternalIds();
  }

  /// `setFavorite` only needs the item id. Reconstructing a minimal item keeps
  /// removal working from a stored membership, without holding the full item
  /// alive in the snapshot just to be able to undo.
  MediaItem _itemForRemoval(String id) =>
      MediaItem(id: id, backend: MediaBackend.jellyfin, kind: MediaKind.unknown, serverId: serverId);
}
