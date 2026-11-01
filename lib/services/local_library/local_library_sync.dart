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
import '../download_artwork_helpers.dart';

class LocalLibraryPaused implements Exception {}

class LocalPosterResult {
  const LocalPosterResult({this.bytes, this.etag, this.lastModified, required this.variant});
  final Uint8List? bytes; // null means a successful conditional 304.
  final String? etag;
  final String? lastModified;
  final String variant;
}

typedef LocalPosterRevalidator =
    Future<LocalPosterResult> Function(MediaServerClient client, MediaItem item, Map<String, dynamic> validators);

typedef LocalPosterLoader = Future<Uint8List> Function(MediaServerClient client, MediaItem item);

/// One bounded, resumable scan. It never treats failure as an empty library.
/// Partial checkpoints merge; only a fully enumerated hierarchy can replace.
class LocalLibrarySync {
  LocalLibrarySync({
    required this.store,
    this.pageSize = 100,
    this.checkpointEvery = const Duration(seconds: 30),
    this.mayContinue,
    this.posterLoader,
    this.posterRevalidator,
    DateTime Function()? clock,
    this.onProgress,
    this.onCheckpoint,
  }) : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final LocalPosterRevalidator? posterRevalidator;
  final LocalLibraryStore store;
  final int pageSize;

  /// A checkpoint rewrites the whole library file, so a count of rows alone
  /// would make a scan quadratic: an unchanged library walks hundreds of rows
  /// a second, and on a 34 MB library the scan spent 57% of its time rewriting.
  /// A scan that stops loses at most this much progress.
  final Duration checkpointEvery;
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
    final sinceCheckpoint = Stopwatch()..start();
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
      // Numbers the fresh list answer carries always win: a retained row keeps
      // its old stored answer, which predates a match the server made since.
      final fresh = externalIdsCarriedBy(candidate);
      if (fresh != null) {
        ids = fresh;
        authoritative = true;
      } else if ((item.kind == MediaKind.movie || item.kind == MediaKind.show) &&
          (item.raw?['pleyaLocalExternalIds'] == null || !storedFinal)) {
        final listed = externalIdsCarriedBy(item);
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
      done++;
      onProgress?.call(done, item.displayTitle);
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
        if (done - checkpointDone >= pageSize && sinceCheckpoint.elapsed >= checkpointEvery) {
          await store.saveLibrary(library, next.values.toList(), complete: false, isCurrent: valid);
          checkpointDone = done;
          sinceCheckpoint.reset();
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
      if (posterLoader != null || posterRevalidator != null) {
        await syncPosters(next.values, (_) => client, isCurrent: valid);
      }
    }
  }

  /// Pilot ceiling, not an optimal device/network budget. Sequential IO keeps
  /// at most one response body in memory (below the proposed concurrency 3).
  /// Select bounded references only; never gather the poster catalog or bytes.
  Future<void> syncPosters(
    Iterable<MediaItem> items,
    MediaServerClient? Function(String) clientFor, {
    required bool Function() isCurrent,
  }) async {
    final now = clock().toUtc();
    bool valid() => isCurrent();
    Future<void> check() async {
      if (!valid() || !(await mayContinue?.call() ?? true) || !valid()) throw LocalLibraryPaused();
    }

    await check();
    const interval = Duration(minutes: 10);
    final budget = store.posterBudget(now);
    if (budget.total >= 60) return;
    final priority = <MediaItem>[];
    final oldest = <MediaItem>[];
    String key(MediaItem i) => '${i.serverId}|${artworkStorageKey(i.thumbPath!)}';
    DateTime attempted(MediaItem i) =>
        DateTime.tryParse(store.posterFreshness(i.serverId!, i.thumbPath!)['attempted'] as String? ?? '') ??
        DateTime.utc(1970);
    void insert(List<MediaItem> list, MediaItem item, int cap) {
      if (list.any((i) => key(i) == key(item))) return;
      list.add(item);
      list.sort((a, b) {
        final order = attempted(a).compareTo(attempted(b));
        return order == 0 ? key(a).compareTo(key(b)) : order;
      });
      if (list.length > cap) list.removeLast();
    }

    for (final item in items) {
      if (item.serverId == null || item.thumbPath == null || item.thumbPath!.isEmpty) continue;
      final state = store.posterFreshness(item.serverId!, item.thumbPath!);
      final last = attempted(item);
      final retry = DateTime.tryParse(state['retry'] as String? ?? '');
      if (now.difference(last) < interval || (retry != null && now.isBefore(retry))) continue;
      insert(oldest, item, 60);
      if (store.posterIsPriority(item.serverId!, item.thumbPath!)) insert(priority, item, 20);
    }
    final selected = <MediaItem>[...priority.take(20 - budget.priority)];
    final priorityKeys = selected.map(key).toSet();
    selected.addAll(oldest.where((i) => !priorityKeys.contains(key(i))).take(40 - (budget.total - budget.priority)));
    for (final item in selected.take(60 - budget.total)) {
      await check();
      final client = clientFor(item.serverId!);
      if (client == null || client.isOfflineMode) continue;
      final path = item.thumbPath!;
      final state = store.posterFreshness(item.serverId!, path);
      state['attempted'] = clock().toUtc().toIso8601String();
      store.reservePosterAttempt(clock().toUtc(), priority: priorityKeys.contains(key(item)));
      // Reserve before IO so restart/interruption cannot replay a whole round.
      await store.savePosterFreshness(item.serverId!, path, state, isCurrent: valid);
      await check();
      try {
        final hasFile = store.posterPath(item.serverId!, path) != null;
        final result = posterRevalidator != null
            ? await posterRevalidator!(client, item, hasFile ? state : {})
            : LocalPosterResult(
                bytes: await posterLoader!(client, item).timeout(const Duration(seconds: 30)),
                variant: path,
              );
        await check();
        if (client.isOfflineMode) throw LocalLibraryPaused();
        if (result.bytes == null && store.posterPath(item.serverId!, path) == null)
          throw StateError('304 without local bytes');
        if (result.bytes != null) await store.savePoster(item.serverId!, path, result.bytes!, isCurrent: valid);
        await check();
        state.addAll({
          'variant': result.variant,
          'etag': result.etag,
          'lastModified': result.lastModified,
          'validated': now.toIso8601String(),
          'failures': 0,
          'retry': null,
        });
        await store.savePosterFreshness(item.serverId!, path, state, isCurrent: valid);
      } on LocalLibraryPaused {
        rethrow;
      } catch (_) {
        await check();
        final failures = ((state['failures'] as int? ?? 0) + 1).clamp(1, 5);
        state['failures'] = failures;
        state['retry'] = now.add(Duration(minutes: 10 * (1 << (failures - 1)))).toIso8601String();
        await store.savePosterFreshness(item.serverId!, path, state, isCurrent: valid);
        // A failed poster never replaces valid bytes or fails metadata sync.
      }
    }
  }
}
