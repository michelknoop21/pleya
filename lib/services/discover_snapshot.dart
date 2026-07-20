import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import 'api_cache.dart';

/// Persists the last successfully loaded Discover payload (Continue Watching,
/// hubs, latest movies) so a cold start can render the previous session's home
/// screen instantly while the network refresh runs in the background.
///
/// Stored as one pinned row in the existing [ApiCache] Drift table under a
/// synthetic server id, so it survives [ApiCache.clearVolatile].
class DiscoverSnapshot {
  static final ServerId _serverId = ServerId('discover-snapshot');
  static const String _endpoint = 'home';

  final List<MediaItem> onDeck;
  final List<MediaHub> hubs;
  final List<MediaItem> latestMovies;

  const DiscoverSnapshot({required this.onDeck, required this.hubs, required this.latestMovies});

  static Future<DiscoverSnapshot?> load() async {
    try {
      final json = await ApiCache.instance.get(_serverId, _endpoint);
      if (json == null) return null;
      return DiscoverSnapshot(
        onDeck: _items(json['onDeck']),
        hubs: [for (final hub in (json['hubs'] as List? ?? const [])) _hubFromJson(hub as Map<String, dynamic>)],
        latestMovies: _items(json['latestMovies']),
      );
    } catch (_) {
      return null; // Corrupt/stale snapshot: fall back to the normal load path.
    }
  }

  Future<void> save() async {
    final cache = ApiCache.instance;
    await cache.put(_serverId, _endpoint, {
      'onDeck': [for (final item in onDeck) item.toJson()],
      'hubs': [for (final hub in hubs) _hubToJson(hub)],
      'latestMovies': [for (final item in latestMovies) item.toJson()],
    });
    await cache.pin(_serverId, _endpoint);
  }

  static List<MediaItem> _items(Object? list) => [
    for (final item in (list as List? ?? const [])) MediaItem.fromJson(item as Map<String, dynamic>),
  ];

  static Map<String, dynamic> _hubToJson(MediaHub hub) => {
    'id': hub.id,
    'identifier': hub.identifier,
    'title': hub.title,
    'type': hub.type,
    'size': hub.size,
    'more': hub.more,
    'libraryId': hub.libraryId,
    'serverId': hub.serverId,
    'serverName': hub.serverName,
    'items': [for (final item in hub.items) item.toJson()],
  };

  static MediaHub _hubFromJson(Map<String, dynamic> json) => MediaHub(
    id: json['id'] as String,
    identifier: json['identifier'] as String?,
    title: json['title'] as String,
    type: json['type'] as String,
    size: json['size'] as int? ?? 0,
    more: json['more'] as bool? ?? false,
    libraryId: json['libraryId'] as String?,
    serverId: json['serverId'] as String?,
    serverName: json['serverName'] as String?,
    items: _items(json['items']),
  );
}
