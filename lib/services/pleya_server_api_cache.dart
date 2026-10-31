import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../models/pleya_server/pleya_wire_library.dart';
import '../utils/global_key_utils.dart';
import 'api_cache.dart';
import 'pleya_server_mappers.dart';

/// Pleya Server rows on top of the shared [ApiCache] substrate.
///
/// A dedicated cache rather than borrowing the Plex one. `ApiCache.forBackend`
/// falls back to Plex for any backend that has not registered, and while the
/// keys would not collide (they carry the server id), the Plex cache's
/// item-key patterns and watch-state rewriting are shaped like Plex responses.
/// Letting Pleya Server rows land there would make every one of those helpers
/// silently do nothing on them.
///
/// Cache keys are `{serverId}:{protocol path}`, so the endpoint half is the
/// same string the client asked for. That keeps a cached answer readable and
/// lets a future phase invalidate by path without a translation table.
class PleyaServerApiCache extends ApiCache {
  PleyaServerApiCache._(super.db);

  static PleyaServerApiCache? _instance;

  static PleyaServerApiCache get instance {
    final cache = _instance;
    if (cache == null) {
      throw StateError('PleyaServerApiCache not initialized. Call PleyaServerApiCache.initialize() first.');
    }
    return cache;
  }

  static void initialize(AppDatabase db) {
    _instance = PleyaServerApiCache._(db);
    ApiCache.registerInstance(MediaBackend.pleyaServer, _instance!);
  }

  /// The endpoint key one item is cached under.
  static String itemEndpoint(String itemId) => '/items/${Uri.encodeComponent(itemId)}';

  static final RegExp _itemKeyPattern = RegExp(r'/items/([^/?]+)$');

  @override
  Future<MediaItem?> getMetadata(ServerId serverId, String itemId) async {
    final data = await get(serverId, itemEndpoint(itemId));
    if (data == null) return null;
    final context = await _serverContext(serverId);
    return _mapCached(data, context.serverId, serverName: context.serverName);
  }

  @override
  Future<void> deleteForItem(ServerId serverId, String itemId) => delete(serverId, itemEndpoint(itemId));

  @override
  Future<void> pinForOffline(ServerId serverId, String itemId) => pin(serverId, itemEndpoint(itemId));

  Future<void> unpinForOffline(ServerId serverId, String itemId) => unpin(serverId, itemEndpoint(itemId));

  /// Rewrite the watched flag and position on a cached item.
  ///
  /// Pleya Server has no watch-state endpoints until PS-4 and answers
  /// `capabilities.watch_state: false`, so nothing calls this today. It is
  /// implemented rather than left to throw because the base class declares it
  /// and a cache that throws on a shared code path is worse than one that
  /// writes a field nobody reads yet.
  @override
  Future<void> applyWatchState({
    required ServerId serverId,
    required String itemId,
    required bool isWatched,
    int? viewOffsetMs,
    int? lastViewedAt,
    int? viewedLeafCount,
  }) async {
    final data = await get(serverId, itemEndpoint(itemId));
    if (data == null) return;
    final userState = Map<String, dynamic>.from(
      data['user_state'] is Map<String, dynamic> ? data['user_state'] as Map<String, dynamic> : const {},
    );
    userState['watched'] = isWatched;
    userState['position_ms'] = viewOffsetMs ?? 0;
    userState['play_count'] = isWatched ? ((userState['play_count'] as num?)?.toInt() ?? 0).clamp(1, 1 << 31) : 0;
    userState['updated_at'] =
        (lastViewedAt != null
                ? DateTime.fromMillisecondsSinceEpoch(lastViewedAt * 1000, isUtc: true)
                : DateTime.now().toUtc())
            .toIso8601String();
    await put(serverId, itemEndpoint(itemId), {...data, 'user_state': userState});
  }

  @override
  Future<Map<String, MediaItem>> getAllPinnedMetadata() async {
    final entries = await listPinnedRowsByPattern(_itemKeyPattern);
    final result = <String, MediaItem>{};
    final contexts = <String, ({ServerId serverId, String? serverName})>{};
    for (final entry in entries) {
      try {
        final data = jsonDecode(entry.data) as Map<String, dynamic>;
        final context = contexts[entry.serverId] ??= await _serverContext(ServerId(entry.serverId));
        final mapped = _mapCached(data, context.serverId, serverName: context.serverName);
        if (mapped != null) result[buildGlobalKey(context.serverId, entry.id)] = mapped;
      } catch (_) {
        // A row that no longer parses is a row from an older build. Skipping
        // it is right: the live fetch will replace it.
      }
    }
    return result;
  }

  // Account namespaces isolate cache state; media identity uses the physical server.
  Future<({ServerId serverId, String? serverName})> _serverContext(ServerId scope) async {
    final row = await (database.select(
      database.connections,
    )..where((table) => table.id.equals(scope) & table.kind.equals('pleyaServer'))).getSingleOrNull();
    if (row != null) {
      try {
        final config = jsonDecode(row.configJson) as Map<String, dynamic>;
        final serverId = config['serverId'];
        final name = config['serverName'];
        if (serverId is String && serverId.isNotEmpty) {
          return (serverId: ServerId(serverId), serverName: name is String ? name : null);
        }
      } catch (_) {
        // A retained download can still identify a removed or older connection.
      }
    }
    final download =
        await (database.select(database.downloadedMedia)
              ..where((table) => table.clientScopeId.equals(scope))
              ..limit(1))
            .getSingleOrNull();
    return (serverId: ServerId(download?.serverId ?? scope), serverName: null);
  }

  /// Cached rows carry the wire shape, so they go back through the same mapper
  /// the live path uses. A second, cache-only mapper is how the two drift.
  MediaItem? _mapCached(Map<String, dynamic> data, ServerId serverId, {String? serverName}) {
    try {
      final item = PleyaItem.fromJson(data);
      if (item.kind == null) return null;
      return PleyaServerMappers.mediaItem(item, serverId: serverId, serverName: serverName);
    } catch (_) {
      return null;
    }
  }
}
