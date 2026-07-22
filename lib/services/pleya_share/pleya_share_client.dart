import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../connection/connection.dart';
import '../../media/download_resolution.dart';
import '../../media/ids.dart';
import '../../media/library_filter_result.dart';
import '../../media/library_first_character.dart';
import '../../media/library_query.dart';
import '../../media/live_tv_support.dart';
import '../../media/media_backend.dart';
import '../../media/media_file_info.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_part.dart';
import '../../media/media_version.dart';
import '../../media/media_playlist.dart';
import '../../media/media_server_client.dart';
import '../../media/media_sort.dart';
import '../../media/media_source_info.dart';
import '../../media/noop_live_tv_support.dart';
import '../../media/playback_report_metadata.dart';
import '../../media/server_capabilities.dart';
import '../../services/api_cache.dart';
import '../../services/playback_initialization_types.dart';
import '../../services/scrub_preview_source.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import '../../utils/media_server_http_client.dart' show AbortController;
import '../../utils/watch_state_notifier.dart';
import 'pleya_share_channel.dart';

/// Guest-side [MediaServerClient] for a paired Pleya Share host.
///
/// Mirrors [LocalFolderClient] (the host serves those items 1:1), but the
/// catalog is fetched over HTTP and `videoUrl`/downloads point at the host's
/// Range-supported `/stream/…` endpoint. Watch state is pushed to the host
/// (which namespaces it per guest) and cached locally so browsing keeps
/// working while the host is unreachable.
class PleyaShareClient implements MediaServerClient {
  final PleyaShareConnection connection;
  final PleyaShareChannel channel;

  final Map<String, MediaItem> _itemCache = {};
  List<MediaLibrary> _libraries = [];
  DateTime? _lastSync;

  @override
  final ApiCache cache;

  PleyaShareClient({required this.connection, required this.cache}) : channel = PleyaShareChannel(connection);

  static const _syncInterval = Duration(minutes: 2);

  /// After a failed sync, don't retry the network for this long — every
  /// browse call funnels through [_ensureSynced] and a full reconnect attempt
  /// (stale IPs + discovery) costs seconds.
  static const _offlineRetryInterval = Duration(seconds: 20);
  DateTime? _lastSyncFailure;

  String get _cachePrefsKey => 'pleya_share_catalog_${connection.id}';

  // ── Catalog sync ──

  Future<void> _ensureSynced({bool force = false}) async {
    if (!force && _itemCache.isNotEmpty && _lastSync != null && DateTime.now().difference(_lastSync!) < _syncInterval) {
      return;
    }
    if (!force && _lastSyncFailure != null && DateTime.now().difference(_lastSyncFailure!) < _offlineRetryInterval) {
      if (_itemCache.isEmpty) await _loadPersistedCatalog();
      return;
    }
    final response = await channel.request('GET', '/library');
    if (response == null) {
      // Host unreachable — fall back to the last persisted catalog.
      _lastSyncFailure = DateTime.now();
      if (_itemCache.isEmpty) await _loadPersistedCatalog();
      return;
    }
    _lastSyncFailure = null;
    final items = (response['items'] as List? ?? const [])
        .map((raw) => MediaItem.fromJson(raw as Map<String, dynamic>))
        .map(_localize)
        .toList();
    _itemCache
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.id, i)));
    _rebuildLibraries();
    _lastSync = DateTime.now();
    unawaited(_persistCatalog());
  }

  /// Rewrite host-side identity fields to this guest connection so routing,
  /// caching, and the download resolver all address this client.
  MediaItem _localize(MediaItem item) => item.copyWith(serverId: connection.id, serverName: connection.hostName);

  void _rebuildLibraries() {
    final byLibrary = <String, MediaLibrary>{};
    for (final item in _itemCache.values) {
      final libraryId = item.libraryId;
      if (libraryId == null || byLibrary.containsKey(libraryId)) continue;
      byLibrary[libraryId] = MediaLibrary(
        id: libraryId,
        backend: MediaBackend.local,
        title: item.libraryTitle ?? connection.hostName,
        kind: switch (item.kind) {
          MediaKind.movie => MediaKind.movie,
          MediaKind.show || MediaKind.season || MediaKind.episode => MediaKind.show,
          _ => MediaKind.unknown,
        },
        serverId: connection.id,
        serverName: connection.hostName,
      );
    }
    _libraries = byLibrary.values.toList();
  }

  Future<void> _persistCatalog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachePrefsKey, jsonEncode([for (final i in _itemCache.values) i.toJson()]));
    } catch (e) {
      appLogger.w('PleyaShareClient: failed to persist catalog', error: e);
    }
  }

  Future<void> _loadPersistedCatalog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefsKey);
      if (raw == null) return;
      for (final entry in (jsonDecode(raw) as List)) {
        final item = MediaItem.fromJson(entry as Map<String, dynamic>);
        _itemCache[item.id] = item;
      }
      _rebuildLibraries();
    } catch (e) {
      appLogger.w('PleyaShareClient: failed to load persisted catalog', error: e);
    }
  }

  // ── Identity & capabilities ──

  @override
  ServerId get serverId => ServerId(connection.id);

  @override
  String? get serverName => connection.hostName;

  @override
  MediaBackend get backend => MediaBackend.local;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.local;

  @override
  bool get isOfflineMode => false;

  @override
  setOfflineMode(bool offline) {}

  @override
  void close() {
    channel.close();
    _itemCache.clear();
  }

  HealthStatus? _lastHealth;

  @override
  Future<HealthStatus> checkHealth() async {
    final response = await channel.request('GET', '/ping');
    final health = response != null ? HealthStatus.online : HealthStatus.offline;
    if (health == HealthStatus.online && _lastHealth == HealthStatus.offline) {
      // Host just came back — refill the catalog right away so libraries and
      // hubs are populated by the time the status stream wakes the providers.
      _lastSyncFailure = null;
      unawaited(_ensureSynced(force: true));
    }
    if (health == HealthStatus.online && _pendingWatch.isNotEmpty) {
      unawaited(flushPendingWatch());
    }
    _lastHealth = health;
    return health;
  }

  @override
  Future<bool> isHealthy() async => (await checkHealth()) == HealthStatus.online;

  @override
  Future<String?> getMachineIdentifier() async => connection.id;

  @override
  double get watchedThreshold => 0.9;

  @override
  bool get marksWatchedOnPlaybackStopped => false;

  @override
  Map<String, String> get streamHeaders => const {};

  @override
  LiveTvSupport get liveTv => const NoopLiveTvSupport();

  // ── Library browsing ──

  @override
  Future<List<MediaLibrary>> fetchLibraries() async {
    await _ensureSynced();
    return List.unmodifiable(_libraries);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryContent(String libraryId, LibraryQuery query) async {
    return fetchLibraryPagedContent(libraryId, query: query);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    await _ensureSynced();
    final items = _itemCache.values.where((i) => i.libraryId == libraryId).toList();
    var filtered = items.where((item) => item.kind == MediaKind.movie || item.kind == MediaKind.show).toList();
    if (!query.includeWatched) {
      filtered = filtered.where((item) => !item.isWatched).toList();
    }
    final search = query.search;
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      filtered = filtered.where((item) => (item.title ?? '').toLowerCase().contains(q)).toList();
    }
    final prefix = query.nameStartsWith;
    if (prefix != null && prefix.isNotEmpty) {
      final p = prefix.toLowerCase();
      filtered = filtered.where((item) => (item.title ?? '').toLowerCase().startsWith(p)).toList();
    }
    final sorted = _applySort(filtered, query);
    final total = sorted.length;
    final offset = query.offset.clamp(0, total);
    final paged = sorted.skip(offset).take(query.limit).toList();
    return LibraryPage(items: paged, totalCount: total, offset: offset);
  }

  List<MediaItem> _applySort(List<MediaItem> items, LibraryQuery query) {
    final sorted = List<MediaItem>.from(items);
    final sort = query.sort;
    if (sort == null) return sorted;
    final descending = sort.direction == LibrarySortDirection.descending;
    int compare(MediaItem a, MediaItem b) {
      final result = switch (sort.field) {
        'addedAt' => (a.addedAt ?? 0).compareTo(b.addedAt ?? 0),
        'year' => (a.year ?? 0).compareTo(b.year ?? 0),
        'lastViewedAt' => (a.lastViewedAt ?? 0).compareTo(b.lastViewedAt ?? 0),
        'rating' => (a.rating ?? 0).compareTo(b.rating ?? 0),
        'viewCount' => (a.viewCount ?? 0).compareTo(b.viewCount ?? 0),
        _ => (a.title ?? '').compareTo(b.title ?? ''),
      };
      return descending ? -result : result;
    }

    sorted.sort(compare);
    return sorted;
  }

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async => LibraryFilterResult.empty;

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async => [];

  @override
  Future<List<LibraryFirstCharacter>> fetchFirstCharacters(String libraryId, {Map<String, String>? filters}) async =>
      [];

  @override
  Future<void> refreshLibraryMetadata(String libraryId) async {
    await _ensureSynced(force: true);
  }

  // ── Item fetching ──

  @override
  Future<MediaItem?> fetchItem(String id) async {
    await _ensureSynced();
    return _itemCache[id];
  }

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async {
    return (item: await fetchItem(id), onDeckEpisode: null);
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    await _ensureSynced();
    return _itemCache.values.where((item) => item.parentId == parentId).toList();
  }

  @override
  Future<List<MediaItem>> fetchLibraryFolders(
    String libraryId, {
    void Function(List<MediaItem> itemsSoFar)? onPage,
  }) async {
    await _ensureSynced();
    final folders = _itemCache.values
        .where((i) => i.libraryId == libraryId && (i.kind == MediaKind.folder || i.kind == MediaKind.show))
        .toList();
    onPage?.call(folders);
    return folders;
  }

  @override
  Future<List<MediaItem>> fetchFolderChildren(
    MediaItem folder, {
    String? libraryId,
    String? libraryTitle,
    void Function(List<MediaItem> itemsSoFar)? onPage,
  }) async {
    return fetchChildren(folder.id);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final children = await fetchChildren(parentId);
    final offset = start ?? 0;
    final paged = children.skip(offset).take(size ?? 50).toList();
    return LibraryPage(items: paged, totalCount: children.length, offset: offset);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    return fetchChildrenPage(parentId, start: start, size: size, abort: abort);
  }

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    final children = await fetchChildren(parentId);
    return children.where((item) => item.kind.isPlayable).toList();
  }

  @override
  Future<List<MediaItem>?> fetchClientSideEpisodeQueue(String seriesId) async {
    await _ensureSynced();
    final episodes = _itemCache.values
        .where((item) => item.kind == MediaKind.episode && item.grandparentId == seriesId)
        .toList();
    episodes.sort((a, b) {
      final aKey = '${a.parentIndex ?? 0}:${a.index ?? 0}';
      final bKey = '${b.parentIndex ?? 0}:${b.index ?? 0}';
      return aKey.compareTo(bKey);
    });
    return episodes;
  }

  // ── Search & hubs ──

  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async {
    await _ensureSynced();
    final q = query.toLowerCase();
    return _itemCache.values.where((item) => (item.title ?? '').toLowerCase().contains(q)).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async {
    await _ensureSynced();
    final all = _itemCache.values
        .where((item) => item.kind == MediaKind.movie || item.kind == MediaKind.episode)
        .toList();
    all.sort((a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));
    return all.take(limit).toList();
  }

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async {
    await _ensureSynced();
    final result = <MediaItem>[];
    for (final item in _itemCache.values) {
      if (item.kind != MediaKind.movie && item.kind != MediaKind.episode) continue;
      final progress = item.viewOffsetMs;
      if (progress != null && progress > 0 && !item.isWatched) {
        result.add(item);
      }
      if (result.length >= (count ?? 20)) break;
    }
    return result;
  }

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async {
    await _ensureSynced();
    return _itemCache.values.where((item) => item.isWatched).take(limit).toList();
  }

  @override
  Future<List<MediaHub>> fetchGlobalHubs({int limit = 20, bool includePlaybackHubs = true}) async {
    final recent = await fetchRecentlyAdded(limit: limit);
    if (recent.isEmpty) return [];
    return [
      MediaHub(
        id: 'pleya-share-recent',
        title: connection.hostName,
        type: 'mixed',
        items: recent,
        more: false,
        serverId: connection.id,
        serverName: connection.hostName,
      ),
    ];
  }

  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    required String libraryName,
    int limit = 20,
    bool includePlaybackHubs = true,
    MediaKind? libraryKind,
  }) async {
    final recent = await fetchRecentlyAdded(limit: limit);
    if (recent.isEmpty) return [];
    return [
      MediaHub(
        id: 'pleya-share-lib-recent-$libraryId',
        title: 'Recently Added in $libraryName',
        type: 'mixed',
        items: recent.where((i) => i.libraryId == libraryId).toList(),
        more: false,
        serverId: connection.id,
        serverName: connection.hostName,
        libraryId: libraryId,
      ),
    ];
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => [];

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => [];

  @override
  Future<List<MediaItem>> fetchPersonMedia(String personId) async => [];

  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage(items: [], totalCount: 0);

  @override
  Future<List<MediaItem>> fetchMoreHubItems(String hubId, {int? limit}) async => [];

  @override
  Future<LibraryPage<MediaItem>> fetchMoreHubItemsPage(
    String hubId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage(items: [], totalCount: 0);

  // ── Watch state ──

  /// Watch updates that failed to reach the host; latest state per item.
  /// Flushed before the next push and on the next successful health check so
  /// progress made during a host blip isn't lost. In-memory only — the local
  /// catalog already persists the state, so a restart just re-diverges until
  /// the next play/progress event pushes again.
  final Map<String, ({int progressMs, bool watched})> _pendingWatch = {};

  Future<void> _pushWatchState(String itemId, {required int progressMs, required bool watched}) async {
    _pendingWatch[itemId] = (progressMs: progressMs, watched: watched);
    await flushPendingWatch();
    if (_pendingWatch.containsKey(itemId)) {
      appLogger.d('PleyaShareClient: watch update for $itemId not delivered (host offline), queued');
    }
  }

  /// Retry queued watch updates; keeps whatever still fails.
  Future<void> flushPendingWatch() async {
    for (final entry in _pendingWatch.entries.toList()) {
      final ok = await channel.request(
        'POST',
        '/watch',
        body: {'itemId': entry.key, 'progressMs': entry.value.progressMs, 'watched': entry.value.watched},
      );
      if (ok == null) return; // Host unreachable — stop, keep the rest queued.
      // Only clear if no newer state was queued for this item meanwhile.
      if (_pendingWatch[entry.key] == entry.value) _pendingWatch.remove(entry.key);
    }
  }

  void _updateCachedItem(String itemId, {int? progressMs, bool? watched}) {
    final cached = _itemCache[itemId];
    if (cached == null) return;
    _itemCache[itemId] = cached.copyWith(
      viewOffsetMs: progressMs ?? cached.viewOffsetMs,
      viewCount: watched == null ? cached.viewCount : (watched ? 1 : 0),
    );
    unawaited(_persistCatalog());
  }

  @override
  Future<void> markWatched(MediaItem item) async {
    _updateCachedItem(item.id, watched: true);
    await _pushWatchState(item.id, progressMs: 0, watched: true);
    WatchStateNotifier().notifyWatched(item: item, isNowWatched: true, cacheServerId: connection.id);
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    _updateCachedItem(item.id, progressMs: 0, watched: false);
    await _pushWatchState(item.id, progressMs: 0, watched: false);
    WatchStateNotifier().notifyWatched(item: item, isNowWatched: false, cacheServerId: connection.id);
  }

  @override
  Future<void> removeFromContinueWatching(MediaItem item) async {}

  @override
  Future<void> rate(MediaItem item, double rating) async {}

  // ── Playlists & collections (unsupported, same contract as local) ──

  @override
  Future<List<MediaPlaylist>> fetchPlaylists({String playlistType = 'video', bool? smart}) async => [];

  @override
  Future<LibraryPage<MediaPlaylist>> fetchPlaylistsPage({
    String playlistType = 'video',
    bool? smart,
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage(items: [], totalCount: 0);

  @override
  Future<MediaPlaylist?> fetchPlaylistMetadata(String id) async => null;

  @override
  Future<List<MediaItem>> fetchPlaylistItems(String id, {int offset = 0, int limit = 100}) async => [];

  @override
  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, AbortController? abort}) async =>
      LibraryPage(items: [], totalCount: 0);

  @override
  Future<MediaPlaylist?> createPlaylist({required String title, required List<MediaItem> items}) async => null;

  @override
  Future<bool> addToPlaylist({required String playlistId, required List<MediaItem> items}) async => false;

  @override
  Future<bool> deletePlaylist(MediaPlaylist playlist) async => false;

  @override
  Future<bool> movePlaylistItem({
    required String playlistId,
    required MediaItem item,
    required int newIndex,
    required MediaItem? afterItem,
  }) async => false;

  @override
  Future<bool> removeFromPlaylist({required String playlistId, required MediaItem item}) async => false;

  @override
  Future<List<MediaItem>> fetchCollections(String libraryId) async => [];

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionsPage(
    String libraryId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage(items: [], totalCount: 0);

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    AbortController? abort,
    String? libraryId,
    String? libraryTitle,
  }) async => LibraryPage(items: [], totalCount: 0);

  @override
  Future<String?> createCollection({
    required String libraryId,
    required String title,
    required List<MediaItem> items,
    MediaKind? itemKind,
  }) async => null;

  @override
  Future<bool> addToCollection({required String collectionId, required List<MediaItem> items}) async => false;

  @override
  Future<bool> removeFromCollection({required String collectionId, required MediaItem item}) async => false;

  @override
  Future<bool> deleteCollection(MediaItem collection) async => false;

  @override
  Future<bool> deleteMediaItem(MediaItem item) async => false;

  // ── File info & thumbnails ──

  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    return MediaFileInfo(container: _extension(item.id), filePath: item.id);
  }

  @override
  String thumbnailUrl(String? path, {int? width, int? height}) => '';

  @override
  String externalImageUrl(String url, {int? width, int? height}) => url;

  // ── External IDs & playback extras ──

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  Future<PlaybackExtras> fetchPlaybackExtras(
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
    bool forceRefresh = false,
  }) async => PlaybackExtras(chapters: [], markers: []);

  @override
  Future<PlaybackExtras?> fetchPlaybackExtrasFromCacheOnly(
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
  }) async => null;

  @override
  Future<MediaSourceInfo?> fetchCachedMediaSourceInfo(String itemId) async => null;

  @override
  Future<ScrubPreviewSource?> createScrubPreviewSource({
    required MediaItem item,
    required MediaSourceInfo mediaSource,
  }) async => null;

  // ── Playback reporting ──

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    bool isPaused = false,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    _updateCachedItem(itemId, progressMs: position.inMilliseconds);
    await _pushWatchState(itemId, progressMs: position.inMilliseconds, watched: false);
  }

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    final watched = duration != null && position.inMilliseconds > duration.inMilliseconds * watchedThreshold;
    _updateCachedItem(itemId, progressMs: position.inMilliseconds, watched: watched ? true : null);
    await _pushWatchState(itemId, progressMs: position.inMilliseconds, watched: watched);
  }

  // ── Playback initialization ──

  @override
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    final item = options.metadata;
    // /ping via request() refreshes the session on 401 (host restart wipes
    // tokens) so the stream URL below never carries a stale token.
    if (await channel.request('GET', '/ping') == null) {
      throw StateError('Pleya Share host "${connection.hostName}" is unreachable');
    }
    final url = channel.streamUrl(item.id);
    final container = _extension(item.id);

    final version = MediaVersion(
      id: item.id,
      container: container,
      parts: [MediaPart(id: item.id, streamPath: url, sizeBytes: null, container: container, streams: const [])],
    );

    final mediaInfo = MediaSourceInfo(
      videoUrl: url,
      mediaSourceId: item.id,
      audioTracks: const [],
      subtitleTracks: const [],
      chapters: const [],
      trickplayByWidth: null,
    );

    return PlaybackInitializationResult(
      availableVersions: [version],
      videoUrl: url,
      mediaInfo: mediaInfo,
      externalSubtitles: const [],
      isOffline: false,
      isTranscoding: false,
      selectedMediaIndex: 0,
    );
  }

  // ── Downloads ──

  @override
  Future<DownloadResolution> resolveDownload(MediaItem item, {int mediaIndex = 0}) async {
    if (await channel.request('GET', '/ping') == null) {
      throw StateError('Pleya Share host "${connection.hostName}" is unreachable');
    }
    return DownloadResolution(videoUrl: channel.streamUrl(item.id), mediaSourceId: item.id);
  }

  @override
  List<DownloadArtworkSpec> resolveDownloadArtwork(MediaItem item) => [];

  @override
  Future<String?> resolveExternalPlaybackUrl(MediaItem item, {int mediaIndex = 0, String? mediaSourceId}) async {
    if (await channel.request('GET', '/ping') == null) return null;
    return channel.streamUrl(item.id);
  }

  // ── Helpers ──

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }
}
