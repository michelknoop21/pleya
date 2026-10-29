import 'dart:async';
import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart' show FileInfo;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../media/ids.dart';
import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/image_cache_service.dart';
import '../services/download_artwork_helpers.dart';
import '../services/local_library/local_library_query.dart';
import '../services/local_library/local_library_store.dart';
import '../services/pleya_server_client.dart';
import '../services/local_library/local_library_sync.dart';
import '../utils/app_logger.dart';
import '../utils/deletion_notifier.dart';
import '../utils/external_ids.dart';
import '../utils/media_image_helper.dart';

enum LocalLibraryState { disabled, syncing, ready, wifi, offline, storage, storageUnavailable, paused, error }

/// Profile lifetime and device-local policy for the existing unified catalog.
/// Reads are permitted independently of prefetch being enabled.
class LocalLibraryProvider extends ChangeNotifier with DisposableChangeNotifierMixin, WidgetsBindingObserver {
  LocalLibraryProvider({
    required this.profileId,
    required this.librariesForSync,
    required this.clientFor,
    required this.mayReadServer,
    required this.mayReadLibrary,
    this.authoritativeLibraries,
    this.authoritativeServerAccess,
    required this.networkConnected,
    required this.wifiConnected,
    required Listenable changes,
    Directory? directory,
    Future<int?> Function()? availableBytes,
    LocalPosterLoader? posterLoader,
  }) : _changes = changes,
       _directory = directory,
       _availableBytes = availableBytes ?? _readAvailableBytes,
       _posterLoader = posterLoader ?? _loadPoster {
    _changes.addListener(_changed);
    _deletions = DeletionNotifier().stream.listen((event) => unawaited(_confirmedDeletion(event)));
    WidgetsBinding.instance.addObserver(this);
    ready = _initialize();
    unawaited(ready);
  }

  late final Future<void> ready;
  final String? profileId;
  final List<MediaLibrary> Function() librariesForSync;
  final MediaServerClient? Function(ServerId) clientFor;
  final bool Function(String) mayReadServer;
  final bool Function(MediaLibrary) mayReadLibrary;
  final Map<String, Set<String>> Function()? authoritativeLibraries;
  final Map<String, bool> Function()? authoritativeServerAccess;
  final bool Function() networkConnected;
  final bool Function() wifiConnected;
  final Listenable _changes;
  final Directory? _directory;
  final Future<int?> Function() _availableBytes;
  final LocalPosterLoader _posterLoader;
  LocalLibraryStore? _store;
  Timer? _timer;
  StreamSubscription<DeletionEvent>? _deletions;
  int _generation = 0;
  String? _lastDependencySignature;
  bool _running = false;
  bool _foreground = true;
  bool initialized = false;
  int revision = 0;
  int done = 0;
  String currentTitle = '';
  int bytes = 0;
  LocalLibraryState state = LocalLibraryState.disabled;
  final Map<({String library, LibraryQuery query}), List<MediaItem>> _queryCache = {};

  bool get enabled => _store?.enabled ?? false;
  bool get wifiOnly => _store?.wifiOnly ?? true;
  DateTime? get lastSync => _store?.lastSync;
  List<MediaLibrary> _visibleLibraries = [];
  List<MediaItem> _visibleItems = [];
  final Set<String> _posterReferences = {};
  List<MediaLibrary> get libraries => _visibleLibraries;
  List<MediaItem> get items => _visibleItems;
  void _refreshReadIndex() {
    _visibleLibraries = _store?.libraries.where(_allowedLibrary).toList() ?? [];
    final keys = _visibleLibraries.map((l) => l.globalKey).toSet();
    _visibleItems =
        _store?.items
            .where((i) => i.serverId != null && i.libraryId != null && keys.contains('${i.serverId}:${i.libraryId}'))
            .toList() ??
        [];
    _posterReferences.clear();
    for (final item in _visibleItems) {
      for (final path in [item.thumbPath, item.parentThumbPath, item.grandparentThumbPath]) {
        if (path != null) _posterReferences.add('${item.serverId}|${artworkStorageKey(path)}');
      }
    }
  }

  bool get hasContent => items.isNotEmpty;
  bool get _allowedNetwork => networkConnected() && (!wifiOnly || wifiConnected());
  bool canReadLibrary(MediaLibrary library) => _allowedLibrary(library);

  bool _allowedLibrary(MediaLibrary l) =>
      l.serverId != null &&
      mayReadServer(l.serverId!) &&
      _store?.serverAccess[l.serverId] != false &&
      !l.hidden &&
      mayReadLibrary(l) &&
      !((_store?.libraryAccess[l.serverId]?.contains(l.globalKey) == false));
  bool _allowedItem(MediaItem i) =>
      i.serverId != null &&
      mayReadServer(i.serverId!) &&
      libraries.any((l) => l.id == i.libraryId && l.serverId == i.serverId);

  Future<void> _initialize() async {
    if (profileId == null) {
      initialized = true;
      safeNotifyListeners();
      return;
    }
    try {
      final base =
          _directory ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}/local_library/${LocalLibraryStore.digest(profileId!)}',
          );
      final store = LocalLibraryStore(base);
      await store.load();
      if (isDisposed) return;
      _store = store;
      await _updateAccess();
      _refreshReadIndex();
      bytes = await store.storageBytes();
      initialized = true;
      _lastDependencySignature = _dependencySignature;
      revision++;
      _timer = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(synchronize()));
      safeNotifyListeners();
      unawaited(synchronize());
    } catch (error, stack) {
      state = LocalLibraryState.error;
      initialized = true;
      appLogger.w('Local library could not be opened', error: error, stackTrace: stack);
      safeNotifyListeners();
    }
  }

  Future<void> setEnabled(bool value) async {
    _generation++;
    await _store?.setOptions(enabled: value);
    _lastDependencySignature = _dependencySignature;
    state = value ? LocalLibraryState.paused : LocalLibraryState.disabled;
    safeNotifyListeners();
    if (value) unawaited(synchronize());
  }

  Future<void> setWifiOnly(bool value) async {
    _generation++;
    await _store?.setOptions(wifiOnly: value);
    _lastDependencySignature = _dependencySignature;
    safeNotifyListeners();
    unawaited(synchronize());
  }

  /// Confirmation is owned by the UI. Afterwards prefetch stays off until the
  /// user explicitly selects refill. Clearing never touches another profile.
  Future<void> clear() async {
    _generation++;
    await _store?.clear();
    revision++;
    _refreshReadIndex();
    _queryCache.clear();
    bytes = 0;
    done = 0;
    currentTitle = '';
    state = LocalLibraryState.disabled;
    safeNotifyListeners();
  }

  Future<void> _confirmedDeletion(DeletionEvent event) async {
    final store = _store;
    if (store == null || event.isDownloadOnly || !mayReadServer(event.serverId)) return;
    _generation++;
    try {
      await store.removeConfirmed(event.serverId, event.itemId, isCurrent: () => !isDisposed);
      if (isDisposed) return;
      revision++;
      _refreshReadIndex();
      _queryCache.clear();
      bytes = await store.storageBytes();
      safeNotifyListeners();
    } catch (error, stack) {
      state = LocalLibraryState.error;
      appLogger.w('Local library removal could not be persisted', error: error, stackTrace: stack);
      safeNotifyListeners();
    }
  }

  String get _dependencySignature => [
    networkConnected(),
    wifiConnected(),
    wifiOnly,
    for (final l in librariesForSync()) '${l.globalKey}:${l.updatedAt}:${_allowedLibrary(l)}',
    for (final l in _store?.libraries ?? <MediaLibrary>[]) '${l.globalKey}:${_allowedLibrary(l)}',
  ].join('|');

  Future<void> _updateAccess() async {
    final store = _store;
    if (store == null) return;
    var changed = false;
    for (final entry in (authoritativeServerAccess?.call() ?? <String, bool>{}).entries) {
      if (store.serverAccess[entry.key] != entry.value) {
        store.serverAccess[entry.key] = entry.value;
        changed = true;
      }
    }
    for (final entry in (authoritativeLibraries?.call() ?? <String, Set<String>>{}).entries) {
      if (!setEquals(store.libraryAccess[entry.key], entry.value)) {
        store.libraryAccess[entry.key] = Set.of(entry.value);
        changed = true;
      }
    }
    if (changed) await store.saveAccess();
  }

  void _changed() {
    // Update the in-memory access boundary synchronously before notifying reads.
    unawaited(_updateAccess());
    final signature = _dependencySignature;
    if (signature == _lastDependencySignature) return;
    _lastDependencySignature = signature;
    revision++;
    _generation++;
    _queryCache.clear();
    _refreshReadIndex();
    safeNotifyListeners(); // immediately hides revoked/hidden sources
    if (!_running) unawaited(synchronize());
  }

  Future<void> synchronize() async {
    final store = _store;
    if (_running || store == null || isDisposed) return;
    if (!enabled) {
      state = LocalLibraryState.disabled;
      safeNotifyListeners();
      return;
    }
    if (!_foreground || !_allowedNetwork) {
      state = !_foreground
          ? LocalLibraryState.paused
          : !networkConnected()
          ? LocalLibraryState.offline
          : LocalLibraryState.wifi;
      safeNotifyListeners();
      return;
    }
    _running = true;
    final generation = _generation;
    bool valid() => !isDisposed && generation == _generation && enabled && _foreground && _allowedNetwork;
    state = LocalLibraryState.syncing;
    done = 0;
    safeNotifyListeners();
    var failed = false;
    var paused = false;
    var checked = DateTime.fromMillisecondsSinceEpoch(0);
    Future<bool> space() async {
      if (!valid()) return false;
      if (DateTime.now().difference(checked) < const Duration(seconds: 2)) return true;
      final free = await _availableBytes();
      if (!valid()) return false;
      checked = DateTime.now();
      if (free == null || free < 256 * 1024 * 1024) {
        state = free == null ? LocalLibraryState.storageUnavailable : LocalLibraryState.storage;
        return false;
      }
      return true;
    }

    try {
      for (final library in librariesForSync().where(_allowedLibrary)) {
        if (!valid()) throw LocalLibraryPaused();
        final client = clientFor(ServerId(library.serverId!));
        if (client == null || client.isOfflineMode) {
          failed = true;
          continue;
        }
        try {
          final priorDone = done;
          await LocalLibrarySync(
            store: store,
            mayContinue: space,
            posterLoader: _posterLoader,
            onCheckpoint: () {
              if (!valid()) return;
              _refreshReadIndex();
              safeNotifyListeners();
            },
            onProgress: (count, title) {
              done = priorDone + count;
              currentTitle = title;
              // Update progress at most every ten items, not every IO/gesture.
              if (count % 10 == 0) safeNotifyListeners();
            },
          ).syncLibrary(library, client, isCurrent: () => valid() && _allowedLibrary(library));
          if (!valid()) throw LocalLibraryPaused();
          revision++;
          _refreshReadIndex();
          _queryCache.clear();
          safeNotifyListeners();
        } on LocalLibraryPaused {
          rethrow;
        } catch (error, stack) {
          failed = true;
          appLogger.w('Local library scan incomplete; retaining previous snapshot', error: error, stackTrace: stack);
        }
      }
    } on LocalLibraryPaused {
      paused = true;
    } finally {
      if (!isDisposed) {
        try {
          bytes = await store.storageBytes();
        } catch (_) {
          failed = true;
        }
      }
      _running = false;
      if (!isDisposed) {
        if (generation != _generation) {
          state = enabled ? LocalLibraryState.paused : LocalLibraryState.disabled;
          if (enabled && _foreground && _allowedNetwork) scheduleMicrotask(() => unawaited(synchronize()));
        } else if (!paused) {
          state = failed ? LocalLibraryState.error : LocalLibraryState.ready;
        }
        safeNotifyListeners();
      }
    }
  }

  String? posterPath(String? serverId, String? path) {
    if (serverId == null || path == null || !mayReadServer(serverId)) return null;
    // Image reads obey the same library boundary as metadata reads.
    if (!_posterReferences.contains('$serverId|${artworkStorageKey(path)}')) return null;
    return _store?.posterPath(serverId, path);
  }

  MediaItem? item(String serverId, String id) {
    final item = _store?.item(serverId, id);
    return item != null && _allowedItem(item) ? item : null;
  }

  List<MediaItem> children(MediaItem parent) =>
      items.where((i) => i.serverId == parent.serverId && i.parentId == parent.id).toList()
        ..sort((a, b) => (a.index ?? 0).compareTo(b.index ?? 0));
  List<MediaItem> episodes(MediaItem parent) =>
      items
          .where(
            (i) =>
                i.serverId == parent.serverId &&
                (i.parentId == parent.id || i.grandparentId == parent.id) &&
                i.kind.id == 'episode',
          )
          .toList()
        ..sort((a, b) {
          final season = (a.parentIndex ?? 0).compareTo(b.parentIndex ?? 0);
          return season != 0 ? season : (a.index ?? 0).compareTo(b.index ?? 0);
        });
  List<MediaItem> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return items
        .where(
          (i) =>
              i.displayTitle.toLowerCase().contains(needle) ||
              (i.summary?.toLowerCase().contains(needle) ?? false) ||
              (i.roles?.any((r) => r.tag.toLowerCase().contains(needle)) ?? false),
        )
        .toList();
  }

  LibraryPage<MediaItem>? page(String libraryKey, LibraryQuery query) {
    final store = _store;
    if (store == null || !store.isComplete(libraryKey) || !libraries.any((l) => l.globalKey == libraryKey)) return null;
    final key = (library: libraryKey, query: query.copyWith(offset: 0, limit: 0));
    var result = _queryCache[key];
    if (result == null) {
      result = queryLocalLibrary(store.libraryItems(libraryKey), query);
      if (result == null) return null;
      _queryCache[key] = result;
    }
    return LibraryPage(
      items: result.skip(query.offset).take(query.limit).toList(),
      totalCount: result.length,
      offset: query.offset,
    );
  }

  ExternalIds? externalIds(String serverId, String targetId) {
    final cached = item(serverId, targetId);
    if (cached == null) return null;
    final raw = cached.raw;
    final local = raw?['pleyaLocalExternalIds'];
    if (local is Map<String, Object?>) {
      final ids = ExternalIds.fromJson(local);
      // A Pleya Server answer is final only when the scan marked it so: the
      // server knew the field and said what it has, numbers or none. A snapshot
      // from before that, or from a server that predates the field, may be empty
      // for the wrong reason, so null sends the caller to the server. A final
      // empty answer is kept: no network on every screen build for unmatched
      // titles.
      if (cached.backend == MediaBackend.pleyaServer && raw?['pleyaLocalExternalIdsFinal'] != true) return null;
      return ids;
    }
    // A Pleya Server snapshot without a stored answer (the lookup failed during
    // the scan) is unknown, not empty.
    if (cached.backend == MediaBackend.pleyaServer) return null;
    final ids = raw?['ProviderIds'];
    if (ids is Map<String, Object?>) return ExternalIds.fromJellyfinProviderIds(ids);
    final guids = raw?['Guid'];
    return guids is List ? ExternalIds.fromGuids(guids) : const ExternalIds();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _generation++;
    if (_foreground) unawaited(synchronize());
  }

  @override
  void dispose() {
    _generation++;
    _changes.removeListener(_changed);
    unawaited(_deletions?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  static Future<int?> _readAvailableBytes() async {
    try {
      return await const MethodChannel('com.pleya/local_library').invokeMethod<int>('availableBytes');
    } on MissingPluginException {
      // Desktop fallback reads capacity only; it never deletes files.
      if (Platform.isLinux) {
        final folder = await getApplicationSupportDirectory();
        final result = await Process.run('df', ['-Pk', folder.path]);
        final lines = result.stdout.toString().trim().split('\n');
        if (result.exitCode == 0 && lines.length > 1) {
          final columns = lines.last.trim().split(RegExp(r'\s+'));
          return int.tryParse(columns[3]).mapBytes;
        }
      }
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<Uint8List> _loadPoster(MediaServerClient client, MediaItem item) async {
    final path = item.thumbPath!;
    final url = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: path,
      maxWidth: 720,
      maxHeight: item.kind.id == 'episode' ? 405 : 1080,
      devicePixelRatio: 1,
      imageType: item.kind.id == 'episode' ? ImageType.thumb : ImageType.poster,
    );
    final uri = Uri.tryParse(url);
    if (uri?.scheme == 'file') return File.fromUri(uri!).readAsBytes();
    final response = await PlexImageCacheManager.instance
        .getFileStream(url, headers: {'User-Agent': 'Pleya', if (client is PleyaServerClient) ...client.streamHeaders})
        .firstWhere((r) => r is FileInfo);
    return (response as FileInfo).file.readAsBytes();
  }
}

extension on int? {
  int? get mapBytes => this == null ? null : this! * 1024;
}
