part of '../local_library_provider.dart';

extension _SyncRun on LocalLibraryProvider {
  Future<void> _runSync({required bool force, required String trigger}) async {
    final store = _store;
    if (force) _forcePending = true;
    if (_running || store == null || isDisposed) return;
    if (!enabled) {
      // Nothing to force while off; a kept flag would rerun this from
      // revalidateVisibleArtwork without end.
      _forcePending = false;
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
    ScanDiagnostics.scanning = true;
    final watch = Stopwatch()..start();
    final notifiesBefore = _notifies;
    // RSS as dart:io sees it sits below the tvOS phys_footprint, so it only
    // compares one sync with another, never with the system memory limit.
    final rssStart = ProcessInfo.currentRss;
    var scanned = 0;
    var skipped = 0;
    final forced = _forcePending;
    _forcePending = false;
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

    // Libraries this sync is for, against `libs=` stored ones: a stored library
    // that is no longer synced keeps its completion date (lastSync).
    var synced = 0;
    try {
      for (final library in librariesForSync().where(_allowedLibrary)) {
        synced++;
        if (!valid()) throw LocalLibraryPaused();
        if (!forced && _recentlyScanned(store, library)) {
          skipped++;
          continue;
        }
        final client = clientFor(ServerId(library.serverId!));
        if (client == null || client.isOfflineMode) {
          failed = true;
          continue;
        }
        scanned++;
        final stats = _scanStats = ScanStats();
        var result = 'error';
        try {
          final priorDone = done;
          final priorKeys = store.libraryItems(library.globalKey).map((item) => item.globalKey).toSet();
          LocalLibraryPartialScan? partial;
          try {
            await LocalLibrarySync(
              store: store,
              stats: stats,
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
          } on LocalLibraryPartialScan catch (error) {
            // Saved, so published below like a full scan, but not healthy.
            partial = error;
          }
          if (!valid()) throw LocalLibraryPaused();
          result = partial == null ? 'complete' : 'partial';
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
          if (partial != null) {
            failed = true;
            appLogger.w('Local library scan saved without some titles', error: partial);
          }
        } on LocalLibraryPaused {
          result = 'paused';
          rethrow;
        } catch (error, stack) {
          failed = true;
          appLogger.w('Local library scan incomplete; retaining previous snapshot', error: error, stackTrace: stack);
        } finally {
          _scanStats = null;
          appLogger.i(
            stats.line(
              library: library.title,
              backend: library.backend.name,
              result: result,
              items: store.libraryItems(library.globalKey).length,
            ),
          );
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
      ScanDiagnostics.scanning = false;
      appLogger.i(
        'syncstats trigger=$trigger ms=${watch.elapsedMilliseconds} scanned=$scanned skipped=$skipped '
        'notifies=${_notifies - notifiesBefore} libs=${store.libraries.length}/$synced '
        'rows=${store.artworkItems.length} '
        'rss=${rssStart >> 20}/${ProcessInfo.currentRss >> 20}/${ProcessInfo.maxRss >> 20}MB',
      );
      if (_visibleDirty && !isDisposed) scheduleMicrotask(() => unawaited(revalidateVisibleArtwork()));
      if (forced && (paused || generation != _generation)) _forcePending = true;
      if (!isDisposed) {
        if (generation != _generation) {
          state = enabled ? LocalLibraryState.paused : LocalLibraryState.disabled;
          if (enabled && _foreground && _allowedNetwork)
            scheduleMicrotask(() => unawaited(synchronize(trigger: 'retry')));
        } else if (!paused) {
          state = failed ? LocalLibraryState.error : LocalLibraryState.ready;
          // A tap on "sync now" while this sync ran.
          if (_forcePending) scheduleMicrotask(() => unawaited(synchronize(trigger: 'pending')));
        }
        safeNotifyListeners();
      }
    }
  }
}
