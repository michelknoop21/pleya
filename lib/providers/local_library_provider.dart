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
import '../services/local_library/scan_diagnostics.dart';
import '../utils/app_logger.dart';
import '../utils/deletion_notifier.dart';
import '../utils/external_ids.dart';
import '../utils/stored_identity_trust.dart';
import '../media/unified/carried_external_ids.dart';
import '../utils/media_image_helper.dart';

part 'local_library_provider/visible_artwork.dart';
part 'local_library_provider/reads.dart';
part 'local_library_provider/sync_run.dart';

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
    DateTime Function()? clock,
  }) : _changes = changes,
       _directory = directory,
       _availableBytes = availableBytes ?? _readAvailableBytes,
       _artworkCache = artworkCache ?? PlexImageCacheManager.instance,
       _artworkRevalidator = artworkRevalidator ?? revalidateLocalPoster,
       _artworkClock = artworkClock ?? DateTime.now,
       _clock = clock ?? DateTime.now,
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
  final DateTime Function() _clock;
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

  /// The scan in progress, for the read-index counters in its log line.
  ScanStats? _scanStats;
  int _notifies = 0;

  @override
  void notifyListeners() {
    _notifies++;
    super.notifyListeners();
  }

  void _refreshReadIndex() {
    final watch = Stopwatch()..start();
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
    _scanStats
      ?..readIndex += 1
      ..readIndexMs += watch.elapsedMilliseconds;
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
      final store = LocalLibraryStore(base, clock: _clock);
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
      _timer = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(synchronize(trigger: 'timer')));
      safeNotifyListeners();
      unawaited(synchronize(trigger: 'startup'));
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
    if (value) unawaited(synchronize(trigger: 'settings'));
  }

  Future<void> setWifiOnly(bool value) async {
    _generation++;
    await _store?.setOptions(wifiOnly: value);
    _lastDependencySignature = _dependencySignature;
    safeNotifyListeners();
    unawaited(synchronize(trigger: 'settings'));
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
    if (!_running) unawaited(synchronize(trigger: 'change'));
  }

  /// A library whose last full scan is younger than this, and whose server
  /// `updatedAt` has not moved since that scan, is skipped by the periodic,
  /// resume and dependency triggers. A full scan walks every show and season,
  /// so running it every ten minutes kept the UI isolate busy while the user
  /// navigated. The scan is also what refreshes watch state in the snapshot,
  /// so this bounds how stale a watched or in-progress mark from another
  /// device can be. [synchronize] with `force` (the manual button) ignores it.
  static const unchangedRescanAfter = Duration(hours: 1);

  /// A forced sync that could not run in full: requested while another sync
  /// ran, or cut off by a dependency change. The next sync takes it over.
  bool _forcePending = false;

  /// Also after a scan that left titles out: a detail call that fails every
  /// time would otherwise have the whole library walked on every trigger.
  bool _recentlyScanned(LocalLibraryStore store, MediaLibrary library) {
    final scan = store.lastScan(library.globalKey);
    if (scan == null || scan.updatedAt != library.updatedAt) return false;
    final age = _clock().difference(scan.at);
    // A clock set back must not stretch the window.
    return !age.isNegative && age < unchangedRescanAfter;
  }

  /// [trigger] only labels the `syncstats` log line.
  Future<void> synchronize({bool force = false, String trigger = 'other'}) => _runSync(force: force, trigger: trigger);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _generation++;
    if (_foreground) unawaited(synchronize(trigger: 'resume'));
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
