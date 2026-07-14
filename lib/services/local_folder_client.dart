import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../connection/connection.dart';
import '../media/download_resolution.dart';
import '../media/ids.dart';
import '../media/library_filter_result.dart';
import '../media/library_first_character.dart';
import '../media/library_query.dart';
import '../media/live_tv_support.dart';
import '../media/media_backend.dart';
import '../media/media_file_info.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_part.dart';
import '../media/media_playlist.dart';
import '../media/media_server_client.dart';
import '../media/media_sort.dart';
import '../media/media_source_info.dart';
import '../media/media_version.dart';
import '../media/noop_live_tv_support.dart';
import '../media/playback_report_metadata.dart';
import '../media/server_capabilities.dart';
import '../services/api_cache.dart';
import '../services/playback_initialization_types.dart';
import '../services/saf_storage_service.dart';
import '../services/secure_folder_service.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import '../utils/watch_state_notifier.dart';
import '../services/scrub_preview_source.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

/// Video file extensions recognised by the local scanner.
const _videoExtensions = {
  '.mkv',
  '.mp4',
  '.avi',
  '.mov',
  '.webm',
  '.m4v',
  '.ts',
  '.m2ts',
  '.wmv',
  '.flv',
  '.mpg',
  '.mpeg',
  '.vob',
  '.3gp',
  '.ogv',
};

/// Regex to extract title + year from movie filenames like "Movie Name (2024).mkv"
/// or "Movie.Name.2024.mkv". Greedy match up to the last 4-digit year in parens.
final _moviePattern = RegExp(r'^(.+?)[\s._]*\((\d{4})\)|^(.+?)[\s._]+(\d{4})\b');

/// Regex to extract SxxExx from episode filenames.
final _episodePattern = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');

/// A [MediaServerClient] that scans a local directory tree as a media library.
///
/// Implements the full [MediaServerClient] surface so the local folder source
/// appears alongside Plex/Jellyfin servers in all browsing, search, and
/// playback flows. Metadata is parsed from folder structure and filenames —
/// no posters, cast, or server-side metadata.
class LocalFolderClient implements MediaServerClient {
  final LocalFolderConnection connection;

  /// In-memory scan cache: file URI → MediaItem.
  final Map<String, MediaItem> _itemCache = {};

  /// In-memory library list (one library per configured root).
  late final List<MediaLibrary> _libraries;

  /// Watch state persisted to SharedPreferences as JSON map.
  final Map<String, bool> _watchedState = {};
  final Map<String, int> _progressState = {};
  bool _watchStateLoaded = false;

  @override
  final ApiCache cache;

  LocalFolderClient({required this.connection, required this.cache}) {
    _libraries = [
      MediaLibrary(
        id: connection.id,
        backend: MediaBackend.local,
        title: connection.displayName,
        kind: connection.libraryType == 'movies'
            ? MediaKind.movie
            : connection.libraryType == 'tvshows'
            ? MediaKind.show
            : MediaKind.unknown,
        serverId: connection.id,
        serverName: connection.displayName,
      ),
    ];
  }

  static const _watchedKeyPrefix = 'local_watched_';
  static const _progressKeyPrefix = 'local_progress_';

  String get _watchedPrefsKey => '$_watchedKeyPrefix${connection.id}';
  String get _progressPrefsKey => '$_progressKeyPrefix${connection.id}';

  Future<void> _loadWatchState() async {
    if (_watchStateLoaded) return;
    _watchStateLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final watchedJson = prefs.getString(_watchedPrefsKey);
      if (watchedJson != null) {
        final decoded = jsonDecode(watchedJson) as Map<String, dynamic>;
        _watchedState.addAll(decoded.map((k, v) => MapEntry(k, v as bool)));
      }
      final progressJson = prefs.getString(_progressPrefsKey);
      if (progressJson != null) {
        final decoded = jsonDecode(progressJson) as Map<String, dynamic>;
        _progressState.addAll(decoded.map((k, v) => MapEntry(k, v as int)));
      }
    } catch (e) {
      appLogger.w('LocalFolderClient: failed to load watch state', error: e);
    }
  }

  Future<void> _persistWatchState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_watchedPrefsKey, jsonEncode(_watchedState));
      await prefs.setString(_progressPrefsKey, jsonEncode(_progressState));
    } catch (e) {
      appLogger.w('LocalFolderClient: failed to persist watch state', error: e);
    }
  }

  @override
  ServerId get serverId => ServerId(connection.id);

  @override
  String? get serverName => connection.displayName;

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
    _itemCache.clear();
    _watchedState.clear();
    _progressState.clear();
  }

  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;

  @override
  Future<bool> isHealthy() async => true;

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

  // ---------------------------------------------------------------------------
  // Library browsing
  // ---------------------------------------------------------------------------

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => List.unmodifiable(_libraries);

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
    final items = await _scanLibrary(libraryId);
    final filtered = _applyFilters(items, query);
    final sorted = _applySort(filtered, query);
    final total = sorted.length;
    final offset = query.offset.clamp(0, total > 0 ? total : 1);
    final limit = query.limit;
    final paged = sorted.skip(offset).take(limit).toList();
    return LibraryPage(items: paged, totalCount: total, offset: offset);
  }

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async {
    return LibraryFilterResult.empty;
  }

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async => [];

  @override
  Future<List<LibraryFirstCharacter>> fetchFirstCharacters(String libraryId, {Map<String, String>? filters}) async {
    return [];
  }

  @override
  Future<void> refreshLibraryMetadata(String libraryId) async {
    _itemCache.clear();
  }

  // ---------------------------------------------------------------------------
  // Item fetching
  // ---------------------------------------------------------------------------

  @override
  Future<MediaItem?> fetchItem(String id) async {
    return _itemCache[id];
  }

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async {
    final item = _itemCache[id];
    return (item: item, onDeckEpisode: null);
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    return _itemCache.values.where((item) => item.parentId == parentId).toList();
  }

  @override
  Future<List<MediaItem>> fetchLibraryFolders(
    String libraryId, {
    void Function(List<MediaItem> itemsSoFar)? onPage,
  }) async {
    final items = await _scanLibrary(libraryId);
    final folders = items.where((item) => item.kind == MediaKind.folder || item.kind == MediaKind.show).toList();
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
    final limit = size ?? 50;
    final paged = children.skip(offset).take(limit).toList();
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

  // ---------------------------------------------------------------------------
  // Search & hubs
  // ---------------------------------------------------------------------------

  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async {
    final q = query.toLowerCase();
    final results = _itemCache.values
        .where((item) => (item.title ?? '').toLowerCase().contains(q))
        .take(limit)
        .toList();
    return results;
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async {
    final all = _itemCache.values
        .where((item) => item.kind == MediaKind.movie || item.kind == MediaKind.episode)
        .toList();
    all.sort((a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));
    return all.take(limit).toList();
  }

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async {
    await _loadWatchState();
    final result = <MediaItem>[];
    for (final item in _itemCache.values) {
      if (item.kind != MediaKind.movie && item.kind != MediaKind.episode) continue;
      final progress = _progressState[item.globalKey];
      if (progress != null && progress > 0) {
        final watched = _watchedState[item.globalKey] ?? false;
        if (!watched) {
          result.add(item.copyWith(viewOffsetMs: progress));
        }
      }
      if (result.length >= (count ?? 20)) break;
    }
    return result;
  }

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async {
    return _itemCache.values.where((item) => item.isWatched).take(limit).toList();
  }

  @override
  Future<List<MediaHub>> fetchGlobalHubs({int limit = 20, bool includePlaybackHubs = true}) async {
    final recent = await fetchRecentlyAdded(limit: limit);
    if (recent.isEmpty) return [];
    return [
      MediaHub(
        id: 'local-recent',
        title: 'Recently Added',
        type: 'mixed',
        items: recent,
        more: false,
        serverId: connection.id,
        serverName: connection.displayName,
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
        id: 'local-lib-recent-$libraryId',
        title: 'Recently Added in $libraryName',
        type: 'mixed',
        items: recent,
        more: false,
        serverId: connection.id,
        serverName: connection.displayName,
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

  // ---------------------------------------------------------------------------
  // Watch state & ratings
  // ---------------------------------------------------------------------------

  @override
  Future<void> markWatched(MediaItem item) async {
    await _loadWatchState();
    _watchedState[item.globalKey] = true;
    _updateItemWatchState(item, watched: true);
    await _persistWatchState();
    WatchStateNotifier().notifyWatched(item: item, isNowWatched: true, cacheServerId: connection.id);
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    await _loadWatchState();
    _watchedState[item.globalKey] = false;
    _progressState.remove(item.globalKey);
    _updateItemWatchState(item, watched: false);
    await _persistWatchState();
    WatchStateNotifier().notifyWatched(item: item, isNowWatched: false, cacheServerId: connection.id);
  }

  void _updateItemWatchState(MediaItem item, {required bool watched}) {
    final cached = _itemCache[item.id];
    if (cached == null) return;
    final updated = cached.copyWith(viewCount: watched ? 1 : 0);
    _itemCache[item.id] = updated;
  }

  @override
  Future<void> removeFromContinueWatching(MediaItem item) async {}

  @override
  Future<void> rate(MediaItem item, double rating) async {}

  // ---------------------------------------------------------------------------
  // Playlists & collections
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // File info & thumbnails
  // ---------------------------------------------------------------------------

  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    return MediaFileInfo(container: _extension(item.id), filePath: item.id);
  }

  @override
  String thumbnailUrl(String? path, {int? width, int? height}) => '';

  @override
  String externalImageUrl(String url, {int? width, int? height}) => url;

  // ---------------------------------------------------------------------------
  // External IDs & playback extras
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Playback reporting
  // ---------------------------------------------------------------------------

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
    await _loadWatchState();
    final globalKey = '$connection.id:$itemId';
    _progressState[globalKey] = position.inMilliseconds;
    _watchedState[globalKey] = false;
    await _persistWatchState();
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
    await _loadWatchState();
    final globalKey = '$connection.id:$itemId';
    _progressState[globalKey] = position.inMilliseconds;
    if (duration != null && position.inMilliseconds > duration.inMilliseconds * watchedThreshold) {
      _watchedState[globalKey] = true;
    }
    await _persistWatchState();
  }

  // ---------------------------------------------------------------------------
  // Playback initialization
  // ---------------------------------------------------------------------------

  @override
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    final item = options.metadata;
    final fileUri = item.id;

    final version = MediaVersion(
      id: fileUri,
      container: _extension(fileUri),
      parts: [
        MediaPart(id: fileUri, streamPath: fileUri, sizeBytes: null, container: _extension(fileUri), streams: const []),
      ],
    );

    final mediaInfo = MediaSourceInfo(
      videoUrl: fileUri,
      mediaSourceId: fileUri,
      audioTracks: const [],
      subtitleTracks: const [],
      chapters: const [],
      trickplayByWidth: null,
    );

    return PlaybackInitializationResult(
      availableVersions: [version],
      videoUrl: fileUri,
      mediaInfo: mediaInfo,
      externalSubtitles: const [],
      isOffline: true,
      isTranscoding: false,
      selectedMediaIndex: 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Download resolution
  // ---------------------------------------------------------------------------

  @override
  Future<DownloadResolution> resolveDownload(MediaItem item, {int mediaIndex = 0}) async {
    return DownloadResolution(videoUrl: item.id, mediaSourceId: item.id);
  }

  @override
  List<DownloadArtworkSpec> resolveDownloadArtwork(MediaItem item) => [];

  @override
  Future<String?> resolveExternalPlaybackUrl(MediaItem item, {int mediaIndex = 0, String? mediaSourceId}) async {
    return item.id;
  }

  // ---------------------------------------------------------------------------
  // Scanning & parsing
  // ---------------------------------------------------------------------------

  /// All scanned items, scanning on first call. Used by Pleya Share hosting
  /// to serialize this source's full catalog for a guest device.
  Future<List<MediaItem>> scanAllItems() => _scanLibrary(connection.id);

  /// Scan the configured directory and populate [_itemCache].
  Future<List<MediaItem>> _scanLibrary(String libraryId) async {
    if (_itemCache.isNotEmpty) return _itemCache.values.toList();

    await _loadWatchState();

    try {
      // iOS/macOS: open the security scope from the stored bookmark first —
      // without it the sandbox denies every read and the library stays empty.
      final rootUri = await SecureFolderService.instance.ensureAccess(connection);
      final children = await SafStorageService.instance.list(rootUri);
      if (children == null) {
        // Unreadable root: likely a stale/expired security scope. Drop the
        // cached resolve so the next scan re-resolves the bookmark instead of
        // permanently serving an empty library from a dead path.
        SecureFolderService.instance.forget(connection.id);
        return [];
      }

      final isMovies = connection.libraryType == 'movies';
      final isTv = connection.libraryType == 'tvshows';

      for (final child in children) {
        if (child.isDir) {
          if (isMovies) {
            await _scanMovieFolder(child);
          } else if (isTv) {
            await _scanShowFolder(child);
          } else {
            await _scanGenericFolder(child, libraryId);
          }
        } else if (_isVideoFile(child.name)) {
          final item = _parseMovieFile(child, libraryId);
          _cacheItem(item);
        }
      }

      _applyWatchStateToCache();
    } catch (e, st) {
      appLogger.w('LocalFolderClient: scan failed for $libraryId', error: e, stackTrace: st);
      // A mid-scan failure would otherwise freeze a partial catalog for the
      // whole session (the isNotEmpty guard above). Drop the partial cache and
      // the resolved scope so the next call retries a full scan.
      _itemCache.clear();
      SecureFolderService.instance.forget(connection.id);
      return const [];
    }

    return _itemCache.values.toList();
  }

  /// Apply persisted watched state to all cached items.
  void _applyWatchStateToCache() {
    for (final item in _itemCache.values) {
      final globalKey = item.globalKey;
      final watched = _watchedState[globalKey] ?? false;
      if (watched && item.viewCount == null) {
        _itemCache[item.id] = item.copyWith(viewCount: 1);
      }
      final progress = _progressState[globalKey];
      if (progress != null && progress > 0) {
        _itemCache[item.id] = _itemCache[item.id]!.copyWith(viewOffsetMs: progress);
      }
    }
  }

  Future<void> _scanMovieFolder(SafDocumentFile folder) async {
    final children = await SafStorageService.instance.list(folder.uri);
    if (children == null) return;

    for (final child in children) {
      if (!child.isDir && _isVideoFile(child.name)) {
        final item = _parseMovieFile(child, connection.id, folderName: folder.name);
        _cacheItem(item);
      }
    }
  }

  Future<void> _scanShowFolder(SafDocumentFile showFolder) async {
    final showItem = MediaItem(
      id: showFolder.uri,
      backend: MediaBackend.local,
      kind: MediaKind.show,
      title: _cleanName(showFolder.name),
      libraryId: connection.id,
      libraryTitle: connection.displayName,
      serverId: connection.id,
      serverName: connection.displayName,
      addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    _cacheItem(showItem);

    final seasonDirs = await SafStorageService.instance.list(showFolder.uri);
    if (seasonDirs == null) return;

    int seasonNum = 0;
    for (final seasonDir in seasonDirs) {
      if (!seasonDir.isDir) continue;
      seasonNum++;
      final seasonIndex = _parseSeasonNumber(seasonDir.name) ?? seasonNum;

      final seasonItem = MediaItem(
        id: seasonDir.uri,
        backend: MediaBackend.local,
        kind: MediaKind.season,
        title: seasonDir.name,
        parentId: showFolder.uri,
        parentTitle: showFolder.name,
        index: seasonIndex,
        libraryId: connection.id,
        libraryTitle: connection.displayName,
        serverId: connection.id,
        serverName: connection.displayName,
      );
      _cacheItem(seasonItem);

      final episodeFiles = await SafStorageService.instance.list(seasonDir.uri);
      if (episodeFiles == null) continue;

      int epNum = 0;
      for (final epFile in episodeFiles) {
        if (epFile.isDir || !_isVideoFile(epFile.name)) continue;
        epNum++;
        final parsed = _parseEpisodeInfo(epFile.name);
        final episodeItem = MediaItem(
          id: epFile.uri,
          backend: MediaBackend.local,
          kind: MediaKind.episode,
          title: _cleanName(epFile.name),
          parentId: seasonDir.uri,
          parentTitle: seasonDir.name,
          parentIndex: seasonIndex,
          grandparentId: showFolder.uri,
          grandparentTitle: showFolder.name,
          index: parsed?.episode ?? epNum,
          libraryId: connection.id,
          libraryTitle: connection.displayName,
          serverId: connection.id,
          serverName: connection.displayName,
          addedAt: _addedAt(epFile),
          mediaVersions: [
            MediaVersion(
              id: epFile.uri,
              container: _extension(epFile.name),
              parts: [
                MediaPart(
                  id: epFile.uri,
                  streamPath: epFile.uri,
                  sizeBytes: epFile.length,
                  container: _extension(epFile.name),
                  streams: const [],
                ),
              ],
            ),
          ],
        );
        _cacheItem(episodeItem);
      }

      // Update season/show leaf counts
      final updatedSeason = seasonItem.copyWith(leafCount: epNum, viewedLeafCount: 0);
      _cacheItem(updatedSeason);
    }

    final updatedShow = showItem.copyWith(childCount: seasonNum, leafCount: epNumTotal(showFolder.uri));
    _cacheItem(updatedShow);
  }

  int epNumTotal(String showUri) {
    return _itemCache.values.where((item) => item.kind == MediaKind.episode && item.grandparentId == showUri).length;
  }

  Future<void> _scanGenericFolder(SafDocumentFile folder, String libraryId) async {
    final children = await SafStorageService.instance.list(folder.uri);
    if (children == null) return;

    for (final child in children) {
      if (!child.isDir && _isVideoFile(child.name)) {
        final item = _parseMovieFile(child, libraryId, folderName: folder.name);
        _cacheItem(item);
      } else if (child.isDir) {
        await _scanGenericFolder(child, libraryId);
      }
    }
  }

  MediaItem _parseMovieFile(SafDocumentFile file, String libraryId, {String? folderName}) {
    final fileName = file.name;
    final match = _moviePattern.firstMatch(fileName);
    String title;
    int? year;
    if (match != null) {
      if (match.group(1) != null) {
        title = _cleanName(match.group(1)!);
        year = int.tryParse(match.group(2)!);
      } else {
        title = _cleanName(match.group(3)!);
        year = int.tryParse(match.group(4)!);
      }
    } else {
      title = _cleanName(fileName);
    }

    return MediaItem(
      id: file.uri,
      backend: MediaBackend.local,
      kind: MediaKind.movie,
      title: title,
      year: year,
      libraryId: libraryId,
      libraryTitle: connection.displayName,
      serverId: connection.id,
      serverName: connection.displayName,
      addedAt: _addedAt(file),
      mediaVersions: [
        MediaVersion(
          id: file.uri,
          container: _extension(fileName),
          parts: [
            MediaPart(
              id: file.uri,
              streamPath: file.uri,
              sizeBytes: file.length,
              container: _extension(fileName),
              streams: const [],
            ),
          ],
        ),
      ],
    );
  }

  void _cacheItem(MediaItem item) {
    _itemCache[item.id] = item;
  }

  /// File modification time (seconds) so "Recently Added" reflects the actual
  /// library instead of the scan moment; falls back to now for SAF entries
  /// without a timestamp.
  int _addedAt(SafDocumentFile file) =>
      file.lastModified > 0 ? file.lastModified ~/ 1000 : DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ---------------------------------------------------------------------------
  // Filtering & sorting
  // ---------------------------------------------------------------------------

  List<MediaItem> _applyFilters(List<MediaItem> items, LibraryQuery query) {
    var filtered = items.where((item) => item.kind == MediaKind.movie || item.kind == MediaKind.show).toList();

    if (!query.includeWatched) {
      filtered = filtered.where((item) => !item.isWatched).toList();
    }

    if (query.search != null && query.search!.isNotEmpty) {
      final q = query.search!.toLowerCase();
      filtered = filtered.where((item) => (item.title ?? '').toLowerCase().contains(q)).toList();
    }

    if (query.nameStartsWith != null && query.nameStartsWith!.isNotEmpty) {
      final prefix = query.nameStartsWith!.toLowerCase();
      filtered = filtered.where((item) => (item.title ?? '').toLowerCase().startsWith(prefix)).toList();
    }

    return filtered;
  }

  List<MediaItem> _applySort(List<MediaItem> items, LibraryQuery query) {
    final sorted = List<MediaItem>.from(items);
    final sort = query.sort;

    if (sort == null) return sorted;

    final field = sort.field;
    final descending = sort.direction == LibrarySortDirection.descending;

    int compare(MediaItem a, MediaItem b) {
      int result;
      switch (field) {
        case 'title':
          result = (a.title ?? '').compareTo(b.title ?? '');
          break;
        case 'addedAt':
          result = (a.addedAt ?? 0).compareTo(b.addedAt ?? 0);
          break;
        case 'year':
          result = (a.year ?? 0).compareTo(b.year ?? 0);
          break;
        case 'lastViewedAt':
          result = (a.lastViewedAt ?? 0).compareTo(b.lastViewedAt ?? 0);
          break;
        case 'rating':
          result = (a.rating ?? 0).compareTo(b.rating ?? 0);
          break;
        case 'viewCount':
          result = (a.viewCount ?? 0).compareTo(b.viewCount ?? 0);
          break;
        default:
          result = (a.title ?? '').compareTo(b.title ?? '');
      }
      return descending ? -result : result;
    }

    sorted.sort(compare);
    return sorted;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isVideoFile(String name) {
    final ext = _extension(name).toLowerCase();
    return _videoExtensions.contains(ext);
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  String _cleanName(String name) {
    var cleaned = name;
    final dot = cleaned.lastIndexOf('.');
    if (dot >= 0) cleaned = cleaned.substring(0, dot);
    cleaned = cleaned.replaceAll('.', ' ').replaceAll('_', ' ').replaceAll('-', ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  int? _parseSeasonNumber(String name) {
    final match = RegExp(r'[Ss]eason\s*(\d{1,2})').firstMatch(name);
    if (match != null) return int.tryParse(match.group(1)!);
    final numMatch = RegExp(r'^(\d{1,2})$').firstMatch(name.trim());
    if (numMatch != null) return int.tryParse(numMatch.group(1)!);
    return null;
  }

  ({int season, int episode})? _parseEpisodeInfo(String name) {
    final match = _episodePattern.firstMatch(name);
    if (match == null) return null;
    final season = int.tryParse(match.group(1)!) ?? 1;
    final episode = int.tryParse(match.group(2)!) ?? 1;
    return (season: season, episode: episode);
  }
}
