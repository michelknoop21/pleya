import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import '../utils/title_normalizer.dart';
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
    _instance?._statusSub?.cancel();
    _instance = LocalServerSyncBridge._(manager, offlineSync).._listenForServersOnline();
  }

  // ignore: cancel_subscriptions — app-lifetime singleton; cancelled on re-initialize.
  StreamSubscription<Map<String, bool>>? _statusSub;
  DateTime? _lastAutoSync;
  bool _syncing = false;

  /// The app-resumed hook is the other sync trigger, but iOS never delivers
  /// `resumed` on a cold start — so without this, local items show no poster
  /// until the user backgrounds and returns. Sync as soon as any server
  /// reports online, throttled so desktop's chatty status stream is cheap.
  void _listenForServersOnline() {
    _statusSub = _manager.statusStream.listen((status) {
      if (!status.values.any((online) => online)) return;
      final last = _lastAutoSync;
      if (last != null && DateTime.now().difference(last) < const Duration(minutes: 2)) return;
      _lastAutoSync = DateTime.now();
      unawaited(syncMatchedItemsFromServer());
    });
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
  static String normalizeTitle(String? title) => normalizeTitleForMatching(title);

  /// Pick the one server item that confidently matches [local], or null when
  /// zero or more-than-one candidates qualify (ambiguous → never guess).
  static MediaItem? pickConfidentMatch(MediaItem local, List<MediaItem> candidates) {
    bool titleMatches(String? a, String? b) => a != null && b != null && normalizeTitle(a) == normalizeTitle(b);

    List<MediaItem> qualifying;
    if (local.kind == MediaKind.show) {
      qualifying = candidates.where((c) => c.kind == MediaKind.show && titleMatches(c.title, local.title)).toList();
    } else if (local.kind == MediaKind.episode) {
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

  /// Catalogue servers only. Local folders and Pleya Share guests (backend
  /// local) are never match candidates (an item would match itself) and must
  /// not count as "online" for match decisions. A Pleya Server is a candidate:
  /// the match runs on titles through `searchItems`, which it serves, and not
  /// on external ids, which it has not got until PS-7.
  Iterable<MediaServerClient> get _matchableServers =>
      _manager.onlineClients.values.where((c) => c.backend != MediaBackend.local);

  Future<ServerMatch?> resolve(MediaItem local) async {
    await _loadCache();
    final key = local.globalKey;
    if (_cache.containsKey(key)) return _cache[key];

    // Don't cache a negative result when no real server was online during
    // the search (e.g. LAN-only startup where Plex binds later) — that would
    // permanently disable artwork/progress sync for this item.
    if (_matchableServers.isEmpty) return null;
    final match = await _search(local);
    _cache[key] = match;
    await _persistCache();
    return match;
  }

  Future<ServerMatch?> _search(MediaItem local) async {
    final clients = _matchableServers;
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
        } else if (local.kind == MediaKind.movie || local.kind == MediaKind.show) {
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
    if (_matchableServers.isEmpty) return;
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
  Future<void> syncMatchedItemsFromServer() async {
    if (_syncing) return;
    if (!await _enabled()) return;
    if (_matchableServers.isEmpty) return;
    _syncing = true;
    try {
      await _syncMatchedItemsFromServer();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncMatchedItemsFromServer() async {
    for (final localClient in _manager.serverMatchableClients) {
      final items = await localClient.scanAllItems();
      // Playable items sync watch-state + artwork; shows get artwork only so
      // the series poster/summary is real too.
      for (final item in items.where((i) => i.kind.isPlayable || i.kind == MediaKind.show)) {
        try {
          final match = await resolve(item);
          if (match == null) continue;
          final serverClient = _manager.getClient(match.serverId);
          if (serverClient == null) continue;
          final serverItem = await serverClient.fetchItem(match.ratingKey);
          if (serverItem == null) continue;
          if (item.kind.isPlayable) {
            await localClient.applyServerWatchState(
              item.id,
              viewOffsetMs: serverItem.viewOffsetMs,
              watched: serverItem.isWatched,
            );
          }
          // Overlay real artwork/summary from the matched server item.
          String? abs(String? path) => (path == null || path.isEmpty) ? null : serverClient.thumbnailUrl(path);
          localClient.applyServerMetadata(
            item.id,
            thumbUrl: abs(serverItem.thumbPath),
            artUrl: abs(serverItem.artPath),
            logoUrl: abs(serverItem.clearLogoPath),
            summary: serverItem.summary,
            year: serverItem.year,
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
