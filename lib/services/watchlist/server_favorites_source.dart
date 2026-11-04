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

/// Server favorites as a watchlist source, scoped to one backend account.
///
/// Favorites are not a watchlist and the difference shows up in two places.
/// They are server-scoped, so the same title favorited on two servers is two
/// memberships. And the flag lives on any item at all, which is why the fetch
/// pins movies and series: a favorited channel is not something you meant to
/// watch later.
class ServerFavoritesSource implements WatchlistSource {
  final MediaServerClient _client;
  final MediaServerClient Function()? resolveClient;
  MediaServerClient get client => resolveClient?.call() ?? _client;
  final ServerId serverId;

  ServerFavoritesSource({
    required MediaServerClient client,
    required this.serverId,
    required this.scope,
    this.resolveClient,
  }) : _client = client;

  @override
  final WatchlistScopeId scope;

  /// Maximum titles pulled per request. Favorites lists are small in practice;
  /// the loop below still walks every page rather than trusting that.
  static const int _pageSize = 100;

  @override
  bool accepts(MediaItem item) {
    if (item.backend != scope.backend) return false;
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
        final entry = _toEntry(item, position: entries.length);
        if (entry != null) entries.add(entry);
      }
      offset += page.items.length;
      if (page.items.isEmpty || offset >= page.totalCount) break;
    }

    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async {
    if (!accepts(item)) throw const WatchlistScopeUnavailable('Favorite belongs to another server');
    await client.setFavorite(item, true);
    return WatchlistMembership(scope: scope, remoteKey: item.id);
  }

  @override
  Future<void> remove(WatchlistMembership membership) async {
    if (membership.scope != scope) throw const WatchlistScopeUnavailable('Favorite belongs to another account');
    await client.setFavorite(_itemForRemoval(membership.remoteKey), false);
  }

  @override
  Future<bool?> contains(MediaItem item) async => null;

  WatchlistEntry? _toEntry(MediaItem item, {required int position}) {
    final externalIds = _externalIdsOf(item);
    final key = watchlistKeyForItem(item, externalIds: externalIds);
    // Pleya keeps identity-free titles server-scoped; other sources still
    // require a canonical identity.
    if (key == null || item.id.isEmpty) return null;

    return WatchlistEntry(
      key: key,
      kind: item.kind,
      item: item,
      guid: item.guid,
      externalIds: externalIds,
      posterRef: item.thumbPath,
      availability: scope.backend == MediaBackend.pleyaServer
          ? WatchlistAvailability.available
          : WatchlistAvailability.unknown,
      lastKnownMatch: scope.backend == MediaBackend.pleyaServer ? item : null,
      // Preserve source order. Pleya orders by favorite time; Jellyfin does
      // not expose that time.
      memberships: [WatchlistMembership(scope: scope, remoteKey: item.id, sourcePosition: position)],
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
      MediaItem(id: id, backend: scope.backend, kind: MediaKind.unknown, serverId: serverId);
}
