part of '../local_library_provider.dart';

/// Offline reads, each behind the same library boundary as the catalog.
extension LocalLibraryReads on LocalLibraryProvider {
  String? posterPath(String? serverId, String? path) {
    ScanDiagnostics.posterPathCalls++;
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
    if (_queryCache.length > LocalLibraryProvider._maxCachedQueries) {
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
}
