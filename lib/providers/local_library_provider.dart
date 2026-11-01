import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' show sha256;
import 'package:cached_network_image_ce/cached_network_image.dart' show CacheManager;
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
import '../utils/stored_identity_trust.dart';
import '../media/unified/carried_external_ids.dart';
import '../utils/media_image_helper.dart';

int _nextArtworkWriter = 0;

class VisibleArtworkRequest {
  VisibleArtworkRequest({
    required this.client,
    required this.path,
    required this.url,
    required this.baseKey,
    this.permanent = false,
  });
  final MediaServerClient client;
  final String path;
  final String url;
  final String baseKey;
  final bool permanent;
  String get serverId => client.serverId;
  String get identity => LocalLibraryStore.digest(
    permanent ? '$serverId|permanent|${artworkStorageKey(path)}' : '$serverId|${artworkStorageKey(url)}|$baseKey',
  );
}

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
    LocalPosterRevalidator? posterRevalidator,
    CacheManager? artworkCache,
    Future<LocalPosterResult> Function(String, Map<String, dynamic>)? artworkRevalidator,
    DateTime Function()? artworkClock,
  }) : _changes = changes,
       _directory = directory,
       _availableBytes = availableBytes ?? _readAvailableBytes,
       _artworkCache = artworkCache ?? PlexImageCacheManager.instance,
       _artworkRevalidator = artworkRevalidator ?? revalidateLocalPoster,
       _artworkClock = artworkClock ?? DateTime.now,
       _posterRevalidator =
           posterRevalidator ??
           (posterLoader == null
               ? loadPoster
               : (client, item, _) async =>
                     LocalPosterResult(bytes: await posterLoader(client, item), variant: item.thumbPath!)) {
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
  final LocalPosterRevalidator _posterRevalidator;
  final CacheManager _artworkCache;
  final Future<LocalPosterResult> Function(String, Map<String, dynamic>) _artworkRevalidator;
  final DateTime Function() _artworkClock;
  // Mounted leases only, bounded like the existing prefetch window. A rebuild
  // reuses its lease; disposal unregisters it; duplicate variants share IO.
  final Map<Object, VisibleArtworkRequest> _visibleArtwork = {};
  bool _visibleDirty = false;
  final String _artworkOwner = LocalLibraryStore.digest(
    '${DateTime.now().microsecondsSinceEpoch}|${_nextArtworkWriter++}',
  );
  int artworkRevision = 0;
  int artworkRegistrationEpoch = 0;
  CacheManager get artworkCache => _artworkCache;
  @visibleForTesting
  int get visibleArtworkCount => _visibleArtwork.length;
  @visibleForTesting
  bool get artworkRevalidationRunning => _running;
  @visibleForTesting
  Future<void> get pendingStoreWrites => _store?.pendingWrites ?? Future.value();

  String artworkCacheKey(String serverId, String url, String baseKey) {
    if (isDisposed || !mayReadServer(serverId) || _pendingReadInvalidations != 0) return baseKey;
    final identity = LocalLibraryStore.digest('$serverId|${artworkStorageKey(url)}|$baseKey');
    return _store?.artworkVariant(identity)['key'] as String? ?? baseKey;
  }

  bool hasVisibleArtworkLease(Object lease) => _visibleArtwork.containsKey(lease);

  bool _mayMaintainArtwork(VisibleArtworkRequest request) {
    if (isDisposed ||
        _pendingReadInvalidations != 0 ||
        !mayReadServer(request.serverId) ||
        _store?.serverAccess[request.serverId] == false ||
        !identical(clientFor(ServerId(request.serverId)), request.client))
      return false;
    final reference = '${request.serverId}|${artworkStorageKey(request.path)}';
    if (_posterReferences.contains(reference)) return true;
    // A known revoked library cannot borrow another library's permission.
    final known =
        _store?.artworkItems.any(
          (i) =>
              i.serverId == request.serverId &&
              [
                i.thumbPath,
                i.parentThumbPath,
                i.grandparentThumbPath,
              ].whereType<String>().any((path) => artworkStorageKey(path) == artworkStorageKey(request.path)),
        ) ??
        false;
    if (known) return false;
    return librariesForSync().any((l) => l.serverId == request.serverId && _allowedLibrary(l));
  }

  void registerVisibleArtwork(Object lease, VisibleArtworkRequest request) {
    if (!_mayMaintainArtwork(request)) return;
    _visibleArtwork.remove(lease);
    _visibleArtwork[lease] = request;
    if (_visibleArtwork.length > 60) _visibleArtwork.remove(_visibleArtwork.keys.first);
    _visibleDirty = true;
    scheduleMicrotask(() => unawaited(revalidateVisibleArtwork()));
  }

  void unregisterVisibleArtwork(Object lease) => _visibleArtwork.remove(lease);

  Future<void> revalidateVisibleArtwork() async {
    if (_running || _store == null || isDisposed || !_foreground || !_allowedNetwork) return;
    _running = true;
    final generation = _generation;
    bool valid() => !isDisposed && generation == _generation && _foreground && _allowedNetwork;
    try {
      await _syncVisibleArtwork(valid);
    } on LocalLibraryPaused {
      // Lifecycle/access changes revoke pending publication immediately.
    } finally {
      _running = false;
      if (valid()) safeNotifyListeners();
      if (_visibleDirty && valid()) scheduleMicrotask(() => unawaited(revalidateVisibleArtwork()));
    }
  }

  Future<void> _syncVisibleArtwork(bool Function() current) async {
    final store = _store!;
    _visibleDirty = false;
    final unique = {for (final r in _visibleArtwork.values) r.identity: r};
    final requests = unique.values.toList()
      ..sort((a, b) {
        final x =
            (a.permanent ? store.posterFreshness(a.serverId, a.path) : store.artworkVariant(a.identity))['attempted']
                as String? ??
            '';
        final y =
            (b.permanent ? store.posterFreshness(b.serverId, b.path) : store.artworkVariant(b.identity))['attempted']
                as String? ??
            '';
        return x.compareTo(y);
      });
    for (final request in requests) {
      bool valid() =>
          current() &&
          _pendingReadInvalidations == 0 &&
          mayReadServer(request.serverId) &&
          !request.client.isOfflineMode &&
          identical(clientFor(ServerId(request.serverId)), request.client) &&
          _visibleArtwork.values.any((r) => r.identity == request.identity);
      void check() {
        if (!valid()) throw LocalLibraryPaused();
      }

      check();
      final now = _artworkClock().toUtc();
      final budget = store.posterBudget(now);
      if (budget.total >= 60 || budget.priority >= 20) break;
      final item = request.permanent
          ? store.artworkItems
                .where(
                  (i) =>
                      i.serverId == request.serverId &&
                      i.thumbPath != null &&
                      artworkStorageKey(i.thumbPath!) == artworkStorageKey(request.path) &&
                      _allowedItem(i),
                )
                .firstOrNull
          : null;
      if (request.permanent && item == null) continue;
      final state = request.permanent
          ? store.posterFreshness(request.serverId, request.path)
          : store.artworkVariant(request.identity);
      Future<void> persist(Map<String, dynamic> state) => request.permanent
          ? store.savePosterFreshness(request.serverId, request.path, state, isCurrent: valid)
          : store.saveArtworkVariant(request.identity, state, isCurrent: valid);
      final attempted = DateTime.tryParse(state['attempted'] as String? ?? '');
      final retry = DateTime.tryParse(state['retry'] as String? ?? '');
      if ((attempted != null && now.difference(attempted) < const Duration(minutes: 10)) ||
          (retry != null && now.isBefore(retry)))
        continue;
      final free = await _availableBytes();
      check();
      if (free == null || free < 256 * 1024 * 1024) return;
      state['attempted'] = now.toIso8601String();
      store.reservePosterAttempt(now, priority: true);
      await persist(state);
      check();
      String? staged;
      try {
        if (request.permanent) {
          final before = store.posterPath(request.serverId, request.path);
          final result = await _posterRevalidator(request.client, item!, before == null ? {} : state);
          check();
          if (result.bytes == null && store.posterPath(request.serverId, request.path) == null) {
            throw StateError('304 without local poster');
          }
          if (result.bytes != null) {
            await store.savePoster(
              request.serverId,
              request.path,
              result.bytes!,
              isCurrent: valid,
              retirePrevious: true,
            );
            check();
          }
          state.addAll({
            'variant': result.variant,
            'etag': result.etag,
            'lastModified': result.lastModified,
            'validated': now.toIso8601String(),
            'failures': 0,
            'retry': null,
          });
          await persist(state);
          check();
          if (before != store.posterPath(request.serverId, request.path)) artworkRevision++;
          safeNotifyListeners();
        } else {
          final oldKey = state['key'] as String? ?? request.baseKey;
          final old = await _artworkCache.getFileFromCache(oldKey);
          check();
          final result = await _artworkRevalidator(request.url, old == null ? {} : state);
          check();
          if (result.bytes == null && old == null) throw StateError('304 without cached artwork');
          var nextKey = oldKey;
          if (result.bytes != null) {
            final content = sha256.convert(result.bytes!).toString();
            nextKey = state['content'] == content && old != null
                ? oldKey
                : 'artwork_${LocalLibraryStore.digest('$profileId|${request.identity}|$_artworkOwner')}.$content';
            state['content'] = content;
            final existing = await _artworkCache.getFileFromCache(nextKey);
            check();
            if (existing == null) {
              staged = nextKey;
              await _artworkCache.putFile(
                request.url,
                result.bytes!,
                key: nextKey,
                eTag: result.etag,
                maxAge: const Duration(days: 14),
              );
              check();
            }
          }
          state.addAll({
            'key': nextKey,
            'variant': result.variant,
            'etag': result.etag,
            'lastModified': result.lastModified,
            'validated': now.toIso8601String(),
            'failures': 0,
            'retry': null,
          });
          await store.saveArtworkVariant(request.identity, state, isCurrent: valid);
          check();
          staged = null; // Published only after successful cache IO and guards.
          if (nextKey != oldKey) artworkRevision++;
          safeNotifyListeners();
        }
      } on LocalLibraryPaused {
        rethrow;
      } catch (_) {
        check();
        final failures = ((state['failures'] as int? ?? 0) + 1).clamp(1, 5);
        final old = request.permanent
            ? store.posterFreshness(request.serverId, request.path)
            : store.artworkVariant(request.identity);
        old.addAll({
          'attempted': now.toIso8601String(),
          'failures': failures,
          'retry': now.add(Duration(minutes: 10 * (1 << (failures - 1)))).toIso8601String(),
        });
        await persist(old);
      } finally {
        if (staged != null) {
          // Failed/late new versions are not active. The prior key was never
          // overwritten, and normal CE GC continues to own published versions.
          try {
            await _artworkCache.removeFile(staged);
          } catch (_) {
            /* Best-effort cleanup of an unpublished CE candidate. */
          }
        }
      }
    }
  }

  LocalLibraryStore? _store;
  Timer? _timer;
  StreamSubscription<DeletionEvent>? _deletions;
  int _generation = 0;
  String? _lastDependencySignature;
  bool _running = false;
  bool _foreground = true;
  bool initialized = false;
  int revision = 0;
  int _readBoundaryRevision = 0;

  /// Changes that invalidate previously authorized reads, even with equal
  /// library keys. Ordinary sync/progress revisions leave this boundary alone.
  int get readBoundaryRevision => _readBoundaryRevision;
  String? _lastReadSignature;
  int _pendingReadInvalidations = 0;
  int done = 0;
  String currentTitle = '';
  int bytes = 0;
  LocalLibraryState state = LocalLibraryState.disabled;
  static const _maxCachedQueries = 8;
  final Map<({String library, LibraryQuery query}), List<MediaItem>> _queryCache = {};

  /// Cached query keys from least to most recently used; no result lists copied.
  @visibleForTesting
  Iterable<({String library, LibraryQuery query})> get cachedQueryKeys => List.unmodifiable(_queryCache.keys);

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
      !isDisposed &&
      _pendingReadInvalidations == 0 &&
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
      _lastReadSignature = _readSignature;
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
    _visibleArtwork.clear();
    artworkRegistrationEpoch++;
    _visibleDirty = false;
    artworkRevision++;
    _beginReadInvalidation();
    await _store?.clear();
    if (isDisposed) return;
    _pendingReadInvalidations--;
    artworkRegistrationEpoch++;
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
    _beginReadInvalidation();
    try {
      await store.removeConfirmed(event.serverId, event.itemId, isCurrent: () => !isDisposed);
      if (isDisposed) return;
      _pendingReadInvalidations--;
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

  // Fail closed during persistence: a restarted catalog cannot read the
  // just-cleared/deleted cache or fall back to an old in-flight response.
  void _beginReadInvalidation() {
    _pendingReadInvalidations++;
    _readBoundaryRevision++;
    revision++;
    _queryCache.clear();
    _refreshReadIndex();
    safeNotifyListeners();
  }

  String get _readSignature {
    // Ignore IO blocking here: only access policy belongs to this signature.
    final libraries = {
      for (final l in [...?_store?.libraries, ...librariesForSync()])
        if (l.serverId != null) l.globalKey: l,
    };
    final keys = libraries.keys.toList()..sort();
    return [
      for (final key in keys)
        '$key:${mayReadServer(libraries[key]!.serverId!)}:'
            '${_store?.serverAccess[libraries[key]!.serverId]}:'
            '${libraries[key]!.hidden}:${mayReadLibrary(libraries[key]!)}:'
            '${_store?.libraryAccess[libraries[key]!.serverId]?.contains(key)}',
    ].join('|');
  }

  String get _dependencySignature => [
    networkConnected(),
    wifiConnected(),
    wifiOnly,
    for (final l in librariesForSync())
      '${l.globalKey}:${l.updatedAt}:${_allowedLibrary(l)}:${l.serverId == null ? 0 : identityHashCode(clientFor(ServerId(l.serverId!)))}',
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
    final readSignature = _readSignature;
    final readChanged = readSignature != _lastReadSignature;
    _lastReadSignature = readSignature;
    final signature = _dependencySignature;
    if (!readChanged && signature == _lastDependencySignature) return;
    if (readChanged) _readBoundaryRevision++;
    _lastDependencySignature = signature;
    revision++;
    _generation++;
    if (readChanged || _visibleArtwork.values.any((r) => !identical(clientFor(ServerId(r.serverId)), r.client))) {
      _visibleArtwork.clear();
      artworkRegistrationEpoch++;
      _visibleDirty = false;
      artworkRevision++;
      unawaited(
        _store?.invalidateArtworkVariants().catchError((Object error, StackTrace stack) {
          appLogger.w('Artwork access invalidation could not be persisted', error: error, stackTrace: stack);
        }),
      );
    }
    _queryCache.clear();
    _refreshReadIndex();
    safeNotifyListeners(); // immediately hides revoked/hidden sources
    if (!_running) unawaited(synchronize());
  }

  Future<void> synchronize() async {
    final store = _store;
    if (_running || store == null || isDisposed) return;
    if (!enabled) {
      await revalidateVisibleArtwork();
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
          final priorKeys = store.libraryItems(library.globalKey).map((item) => item.globalKey).toSet();
          await LocalLibrarySync(
            store: store,
            mayContinue: space,
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
          // A completed scan may prove removals as well as append content.
          // Such membership loss is a hard boundary, never a retained row.
          if (!store.libraryItems(library.globalKey).map((item) => item.globalKey).toSet().containsAll(priorKeys)) {
            _readBoundaryRevision++;
          }
          _lastReadSignature = _readSignature;
          _queryCache.clear();
          safeNotifyListeners();
        } on LocalLibraryPaused {
          rethrow;
        } catch (error, stack) {
          failed = true;
          appLogger.w('Local library scan incomplete; retaining previous snapshot', error: error, stackTrace: stack);
        }
      }
      await _syncVisibleArtwork(valid);
      await LocalLibrarySync(
        store: store,
        mayContinue: space,
        clock: _artworkClock,
        posterRevalidator: _posterRevalidator,
      ).syncPosters(store.artworkItems.where(_allowedItem), (id) => clientFor(ServerId(id)), isCurrent: valid);
      if (valid()) safeNotifyListeners();
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
      if (_visibleDirty && !isDisposed) scheduleMicrotask(() => unawaited(revalidateVisibleArtwork()));
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
    if (isDisposed || serverId == null || path == null || !mayReadServer(serverId)) return null;
    // Image reads obey the same library boundary as metadata reads.
    if (!_posterReferences.contains('$serverId|${artworkStorageKey(path)}')) return null;
    _store?.prioritizePoster(serverId, path);
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
    // Dart maps preserve insertion order: removing a hit promotes it on reinsertion.
    var result = _queryCache.remove(key);
    if (result == null) {
      result = queryLocalLibrary(store.libraryItems(libraryKey), query);
      if (result == null) return null;
    }
    _queryCache[key] = result;
    if (_queryCache.length > _maxCachedQueries) {
      _queryCache.remove(_queryCache.keys.first);
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
    if (!canTrustStoredIdentity(cached, clientFor(ServerId(serverId)))) return null;
    if (hasAppliedExternalIds(cached)) return externalIdsCarriedBy(cached);
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
    _visibleArtwork.clear();
    artworkRegistrationEpoch++;
    _visibleDirty = false;
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

  @visibleForTesting
  static Future<LocalPosterResult> loadPoster(
    MediaServerClient client,
    MediaItem item,
    Map<String, dynamic> validators, {
    http.Client? transport,
  }) async {
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
    if (uri?.scheme == 'file') {
      return LocalPosterResult(bytes: await File.fromUri(uri!).readAsBytes(), variant: artworkStorageKey(url));
    }
    return revalidateLocalPoster(
      url,
      validators,
      transport: transport,
      headers: {'User-Agent': 'Pleya', if (client is PleyaServerClient) ...client.streamHeaders},
    );
  }
}

extension on int? {
  int? get mapBytes => this == null ? null : this! * 1024;
}
