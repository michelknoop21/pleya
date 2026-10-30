import 'dart:typed_data';
import 'package:flutter/foundation.dart' show VoidCallback;

import 'dart:async' show TimeoutException;

import '../../exceptions/identity_lookup_exceptions.dart';
import '../../exceptions/media_server_exceptions.dart';
import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../utils/external_ids.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/carried_external_ids.dart';
import '../jellyfin_client.dart';
import '../plex_client.dart';
import '../pleya_server_client.dart';
import '../local_folder_client.dart';
import 'local_library_store.dart';

class LocalLibraryPaused implements Exception {}

typedef LocalPosterLoader = Future<Uint8List> Function(MediaServerClient client, MediaItem item);

/// One bounded, resumable scan. It never treats failure as an empty library.
/// Partial checkpoints merge; only a fully enumerated hierarchy can replace.
class LocalLibrarySync {
  LocalLibrarySync({
    required this.store,
    this.pageSize = 100,
    this.mayContinue,
    this.posterLoader,
    this.onProgress,
    this.onCheckpoint,
  });
  final LocalLibraryStore store;
  final int pageSize;
  final Future<bool> Function()? mayContinue;
  final LocalPosterLoader? posterLoader;
  final void Function(int done, String title)? onProgress;
  final VoidCallback? onCheckpoint;

  Future<void> syncLibrary(MediaLibrary library, MediaServerClient client, {bool Function()? isCurrent}) async {
    bool valid() => (isCurrent?.call() ?? true) && !client.isOfflineMode;
    Future<void> check() async {
      if (!valid() || !(await mayContinue?.call() ?? true) || !valid()) throw LocalLibraryPaused();
    }

    final previous = {for (final i in store.libraryItems(library.globalKey)) i.globalKey: i};
    final next = <String, MediaItem>{};
    var done = 0;
    var checkpointDone = 0;
    if (client is LocalFolderClient) client.invalidateScanCache();

    Future<LibraryPage<MediaItem>> rootPage(MediaKind kind, int offset, int limit) {
      final query = LibraryQuery(
        kind: kind,
        offset: offset,
        limit: limit,
        sort: const LibrarySort(field: 'title', direction: LibrarySortDirection.ascending),
      );
      return switch (client) {
        PlexClient() => client.fetchLibraryContent(library.id, query, requireTotalCount: true),
        JellyfinClient() => client.fetchLibraryPagedContent(
          library.id,
          query: query,
          libraryKind: kind,
          requireTotalCount: true,
        ),
        PleyaServerClient() => client.fetchLibraryPagedContent(
          library.id,
          query: query,
          libraryKind: kind,
          strictSnapshot: true,
        ),
        _ => client.fetchLibraryPagedContent(library.id, query: query, libraryKind: kind),
      };
    }

    Future<void> keep(MediaItem candidate) async {
      await check();
      final old = previous[candidate.globalKey];
      MediaItem? detail;
      if (old != null &&
          candidate.updatedAt != null &&
          candidate.updatedAt == old.updatedAt &&
          candidate.thumbPath == old.thumbPath &&
          candidate.title == old.title &&
          candidate.year == old.year) {
        // Retain full descriptive fields, but use fresh per-user watch state.
        detail = old.copyWith(
          viewCount: candidate.viewCount,
          viewOffsetMs: candidate.viewOffsetMs,
          viewedLeafCount: candidate.viewedLeafCount,
          lastViewedAt: candidate.lastViewedAt,
        );
      } else {
        detail = await client.fetchItem(candidate.id).timeout(const Duration(seconds: 20));
      }
      await check();
      if (detail == null) throw StateError('Item disappeared during library scan');
      final item = detail.copyWith(
        serverId: library.serverId,
        serverName: library.serverName,
        libraryId: library.id,
        libraryTitle: library.title,
        parentId: detail.parentId ?? candidate.parentId,
        grandparentId: detail.grandparentId ?? candidate.grandparentId,
      );
      // Preserve strong cross-server identity for offline grouping. The list
      // answer usually carried the numbers already (Plex `includeGuids`,
      // Jellyfin `ProviderIds`, Pleya `external_ids`); only without them is
      // the server asked per title.
      ExternalIds? ids;
      // Whether the stored answer may be trusted as final. Only a Pleya Server
      // that knows the field says so; the others keep the behaviour they had.
      var authoritative = false;
      // A Pleya row whose stored answer was not final (written by an older build,
      // or by a server that predates the field) is asked again, also when the
      // rest of the row was retained unchanged.
      final storedFinal = client is! PleyaServerClient || item.raw?['pleyaLocalExternalIdsFinal'] == true;
      if ((item.kind == MediaKind.movie || item.kind == MediaKind.show) &&
          (item.raw?['pleyaLocalExternalIds'] == null || !storedFinal)) {
        final listed = externalIdsCarriedBy(candidate) ?? externalIdsCarriedBy(item);
        if (listed != null) {
          ids = listed;
          authoritative = true;
        } else {
          try {
            if (client is PleyaServerClient) {
              final answer = await client.fetchExternalIdsDetailed(item.id).timeout(const Duration(seconds: 20));
              ids = answer.ids;
              authoritative = answer.authoritative;
            } else {
              ids = await client.fetchExternalIds(item.id).timeout(const Duration(seconds: 20));
            }
          } on MediaServerHttpException {
            // Plex used to answer a failed lookup with no ids. Keep that here: one
            // flaky includeGuids call must not fail the whole library scan.
            ids = null;
          } on IdentityLookupException {
            // The server did not answer (offline, 429, 503, a broken body). The row
            // is kept with no stored answer, which readers treat as unknown rather
            // than as "no numbers", so the next scan or lookup asks again.
            ids = null;
          } on TimeoutException {
            ids = null;
          }
          await check();
        }
      }
      next[item.globalKey] = ids == null
          ? item
          : item.copyWith(
              raw: {
                ...?item.raw,
                'pleyaLocalExternalIds': ids.toJson(),
                if (client is PleyaServerClient) 'pleyaLocalExternalIdsFinal': authoritative,
              },
            );
      final loader = posterLoader;
      final path = item.thumbPath;
      if (loader != null &&
          path != null &&
          path.isNotEmpty &&
          item.serverId != null &&
          (store.posterPath(item.serverId!, path) == null ||
              old?.thumbPath != path ||
              (item.updatedAt != null && item.updatedAt != old?.updatedAt))) {
        final bytes = await loader(client, item).timeout(const Duration(seconds: 30));
        await check();
        await store.savePoster(item.serverId!, path, bytes, isCurrent: valid);
      }
      onProgress?.call(++done, item.displayTitle);
    }

    late Future<void> Function(MediaItem) scanChildren;
    Future<void> scan(Future<LibraryPage<MediaItem>> Function(int, int) fetch, {MediaKind? kind}) async {
      var offset = 0;
      int? total;
      final seen = <String>{};
      String? first;
      while (true) {
        await check();
        final page = await fetch(offset, pageSize).timeout(const Duration(seconds: 20));
        await check();
        total ??= page.totalCount;
        if (page.totalCount != total || page.totalCount < 0 || page.items.length > pageSize) {
          throw StateError('Library changed or returned an unverified page; keep previous snapshot');
        }
        for (final item in page.items) {
          if (!seen.add(item.globalKey)) throw StateError('Library pagination did not advance');
          if (kind != null && item.kind != kind) throw StateError('Library returned a different media kind');
          first ??= item.globalKey;
          final bound = item.copyWith(
            serverId: library.serverId,
            serverName: library.serverName,
            libraryId: library.id,
            libraryTitle: library.title,
          );
          await keep(bound);
          if (item.kind == MediaKind.show || item.kind == MediaKind.season) {
            await scanChildren(item);
          }
        }
        if (done - checkpointDone >= pageSize) {
          await store.saveLibrary(library, next.values.toList(), complete: false, isCurrent: valid);
          checkpointDone = done;
          if (valid()) onCheckpoint?.call();
        }
        offset += page.items.length;
        if (page.items.length < pageSize || offset >= total) break;
      }
      if (seen.length != total) throw StateError('Incomplete library scan');
      // Recheck the head/count after enumeration. A drifting scan never prunes.
      final head = await fetch(0, 1).timeout(const Duration(seconds: 20));
      await check();
      if (head.totalCount != total || head.items.firstOrNull?.globalKey != first) {
        throw StateError('Library changed during scan');
      }
    }

    // Local mutually-recursive functions use this closure so every parent is
    // paged and verified independently, including empty seasons.
    final ancestors = <String>{};
    scanChildren = (MediaItem parent) async {
      if (!ancestors.add(parent.globalKey)) throw StateError('Cyclic library hierarchy');
      try {
        await scan((offset, size) async {
          final page = await switch (client) {
            PleyaServerClient() => client.fetchChildrenPage(parent.id, start: offset, size: size, strictSnapshot: true),
            PlexClient() => client.fetchChildrenPage(parent.id, start: offset, size: size, requireTotalCount: true),
            JellyfinClient() => client.fetchChildrenPage(parent.id, start: offset, size: size, requireTotalCount: true),
            _ => client.fetchChildrenPage(parent.id, start: offset, size: size),
          };
          return page.copyWith(
            items: [
              for (final child in page.items)
                child.copyWith(
                  parentId: child.parentId ?? parent.id,
                  grandparentId: child.grandparentId ?? (parent.kind == MediaKind.season ? parent.parentId : null),
                  parentIndex: child.parentIndex ?? (parent.kind == MediaKind.season ? parent.index : null),
                ),
            ],
          );
        });
      } finally {
        ancestors.remove(parent.globalKey);
      }
    };
    {
      final kinds = switch (library.kind) {
        MediaKind.movie => [MediaKind.movie],
        MediaKind.show => [MediaKind.show],
        _ => [MediaKind.movie, MediaKind.show],
      };
      for (final kind in kinds) {
        await scan((offset, size) => rootPage(kind, offset, size), kind: kind);
      }
      await check();
      if (client is LocalFolderClient && client.hasIncompleteScan) throw StateError('Folder scan is incomplete');
      await store.saveLibrary(library, next.values.toList(), complete: true, isCurrent: valid);
    }
  }
}
