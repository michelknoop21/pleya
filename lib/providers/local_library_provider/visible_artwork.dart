part of '../local_library_provider.dart';

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

/// Visible-artwork leases and their revalidation.
extension LocalLibraryVisibleArtwork on LocalLibraryProvider {
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
      // A tap on "sync now" while this ran.
      if (_forcePending && !isDisposed) scheduleMicrotask(() => unawaited(synchronize(trigger: 'pending')));
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
}
