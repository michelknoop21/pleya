import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../utils/app_logger.dart';
import 'multi_server_manager.dart';
import 'offline_watch_sync_service.dart';
import 'settings_service.dart';

/// A resolved link from a local-folder item to the same title on a connected
/// Plex/Jellyfin server.
typedef ServerMatch = ({ServerId serverId, String ratingKey});

/// Bridges local-folder watch progress to the user's Plex/Jellyfin account.
///
/// Local files carry no GUID/ratingKey, so the same title is found by a
/// confident title(+year for movies, +season/episode for shows) match against
/// the connected servers. Once matched, local playback progress is pushed
/// through the existing [OfflineWatchSyncService] queue — which flushes on
/// reconnect with a last-writer-wins guard — so "watch locally on holiday, then
/// continue on Plex at home" resumes at the right spot.
///
/// Only a single high-confidence match is ever used; ambiguous or missing
/// matches do nothing (never write to the wrong server item).
class LocalServerSyncBridge {
  LocalServerSyncBridge._(this._manager, this._offlineSync);

  static LocalServerSyncBridge? _instance;
  static LocalServerSyncBridge? get instance => _instance;

  static void initialize({required MultiServerManager manager, required OfflineWatchSyncService offlineSync}) {
    _instance = LocalServerSyncBridge._(manager, offlineSync);
  }

  final MultiServerManager _manager;
  final OfflineWatchSyncService _offlineSync;

  static const _cachePrefsKey = 'local_server_match_v1';

  /// localGlobalKey → match, with an explicit null for "searched, no match" so
  /// a miss isn't re-searched every playback tick.
  final Map<String, ServerMatch?> _cache = {};
  bool _cacheLoaded = false;

  // ── Pure matching (unit-tested) ──

  /// Lower-cased, punctuation/whitespace-stripped title for comparison. A
  /// trailing `(2024)` year is dropped so "Movie (2024)" matches "Movie".
  static String normalizeTitle(String? title) {
    if (title == null) return '';
    var t = title.toLowerCase();
    t = t.replaceAll(RegExp(r'\(\d{4}\)'), ' ');
    t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return t;
  }

  /// Pick the one server item that confidently matches [local], or null when
  /// zero or more-than-one candidates qualify (ambiguous → never guess).
  static MediaItem? pickConfidentMatch(MediaItem local, List<MediaItem> candidates) {
    bool titleMatches(String? a, String? b) => a != null && b != null && normalizeTitle(a) == normalizeTitle(b);

    List<MediaItem> qualifying;
    if (local.kind == MediaKind.episode) {
      qualifying = candidates.where((c) {
        return c.kind == MediaKind.episode &&
            c.parentIndex == local.parentIndex &&
            c.index == local.index &&
            titleMatches(c.grandparentTitle, local.grandparentTitle);
      }).toList();
    } else if (local.kind == MediaKind.movie) {
      qualifying = candidates.where((c) {
        if (c.kind != MediaKind.movie || !titleMatches(c.title, local.title)) return false;
        // If both declare a year they must agree; a missing year on either side
        // is tolerated (some libraries omit it).
        if (local.year != null && c.year != null && local.year != c.year) return false;
        return true;
      }).toList();
    } else {
      return null;
    }

    return qualifying.length == 1 ? qualifying.first : null;
  }

  // ── Resolution (network) ──

  Future<ServerMatch?> resolve(MediaItem local) async {
    await _loadCache();
    final key = local.globalKey;
    if (_cache.containsKey(key)) return _cache[key];

    final match = await _search(local);
    _cache[key] = match;
    await _persistCache();
    return match;
  }

  Future<ServerMatch?> _search(MediaItem local) async {
    final clients = _manager.onlineClients.values;
    for (final client in clients) {
      try {
        final List<MediaItem> candidates;
        if (local.kind == MediaKind.episode) {
          final show = local.grandparentTitle;
          if (show == null || show.isEmpty) continue;
          final results = await client.searchItems(show, limit: 20);
          final shows = results.where(
            (r) => r.kind == MediaKind.show && normalizeTitle(r.title) == normalizeTitle(show),
          );
          candidates = [for (final s in shows) ...await client.fetchPlayableDescendants(s.id)];
        } else if (local.kind == MediaKind.movie) {
          final title = local.title;
          if (title == null || title.isEmpty) continue;
          candidates = await client.searchItems(title, limit: 20);
        } else {
          continue;
        }

        final match = pickConfidentMatch(local, candidates);
        if (match != null) {
          appLogger.i('LocalServerSync: matched "${local.title}" → ${client.serverId}:${match.id}');
          return (serverId: ServerId(client.serverId), ratingKey: match.id);
        }
      } catch (e) {
        appLogger.w('LocalServerSync: search failed on ${client.serverId}', error: e);
      }
    }
    return null;
  }

  // ── Push ──

  /// Mirror local playback progress onto the matched server item. No-op when the
  /// feature is disabled, no confident match exists, or no servers are online.
  Future<void> pushLocalProgress(MediaItem local, {required int viewOffsetMs, int? durationMs}) async {
    if (!await _enabled()) return;
    if (_manager.onlineClients.isEmpty) return;
    try {
      final match = await resolve(local);
      if (match == null) return;
      await _offlineSync.queueProgressUpdate(
        serverId: match.serverId,
        itemId: match.ratingKey,
        viewOffset: viewOffsetMs,
        duration: durationMs,
      );
    } catch (e) {
      appLogger.w('LocalServerSync: push failed for "${local.title}"', error: e);
    }
  }

  /// Pull the other direction: for every local file that matches a server item,
  /// copy the server's current progress/watched state into the local view, so a
  /// title continued on Plex/Jellyfin also resumes correctly locally. Merges
  /// (never lowers local progress). Safe no-op when disabled or offline.
  Future<void> pullServerProgressToLocal() async {
    if (!await _enabled()) return;
    if (_manager.onlineClients.isEmpty) return;
    for (final localClient in _manager.localFolderClients) {
      final items = await localClient.scanAllItems();
      for (final item in items.where((i) => i.kind.isPlayable)) {
        try {
          final match = await resolve(item);
          if (match == null) continue;
          final serverClient = _manager.getClient(match.serverId);
          if (serverClient == null) continue;
          final serverItem = await serverClient.fetchItem(match.ratingKey);
          if (serverItem == null) continue;
          await localClient.applyServerWatchState(
            item.id,
            viewOffsetMs: serverItem.viewOffsetMs,
            watched: serverItem.isWatched,
          );
        } catch (e) {
          appLogger.w('LocalServerSync: pull failed for "${item.title}"', error: e);
        }
      }
    }
  }

  Future<bool> _enabled() async {
    final settings = await SettingsService.getInstance();
    return settings.read(SettingsService.syncLocalWatchState);
  }

  // ── Cache persistence ──

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) {
        _cache[k] = v == null ? null : (serverId: ServerId(v['s'] as String), ratingKey: v['r'] as String);
      });
    } catch (e) {
      appLogger.w('LocalServerSync: failed to load match cache', error: e);
    }
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cachePrefsKey,
        jsonEncode(
          _cache.map((k, v) => MapEntry(k, v == null ? null : {'s': v.serverId.toString(), 'r': v.ratingKey})),
        ),
      );
    } catch (e) {
      appLogger.w('LocalServerSync: failed to persist match cache', error: e);
    }
  }
}
