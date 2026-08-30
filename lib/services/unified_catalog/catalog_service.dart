/// The unified catalog's k-way merge engine (hoofdstuk 12 and 27 fase 3 of
/// docs/tvos-unified-experience.md): pages every participating library in
/// parallel, merges their already-sorted streams into one globally-ordered
/// sequence, and runs that sequence through the same fase-1 identity
/// pipeline (`identity_resolver.dart` / `grouping_service.dart`) every other
/// unified-catalog surface uses (hoofdstuk 4.3), so a duplicate across
/// libraries or servers still counts once.
///
/// Deliberately headless: [UnifiedCatalogService] takes its libraries (via
/// [eligibleCatalogLibraries]) and a client resolver as plain constructor
/// arguments rather than reading `LibrariesProvider`/`MultiServerProvider`
/// itself, so this file's own tests exercise the merge algorithm without a
/// widget tree. Wiring it to the real app providers and layering transient
/// loading state around [loadMore] is `unified_catalog_provider.dart`'s job
/// (also fase 3 — see hoofdstuk 27's own Fase 3 file list; it lives under
/// `ProfileSessionScreen`, profile-scoped like `LibrariesProvider`).
library;

import 'dart:async';

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../utils/app_logger.dart';
import '../../utils/media_server_http_client.dart';
import '../../utils/media_server_timeouts.dart';
import 'grouping_service.dart';
import 'identity_resolver.dart';
import 'source_cursor.dart';
import 'unified_catalog_query.dart';
import 'unified_catalog_snapshot.dart';

class UnifiedCatalogService {
  UnifiedCatalogService({
    required UnifiedCatalogQuery query,
    required List<CatalogLibrary> libraries,
    required MediaServerClient? Function(ServerId serverId) clientFor,
    this.pageSize = 50,
    this.groupsPerPage = 20,
    this.maxConcurrentFetches = 4,
    this.maxRawItemsPerLoadMore = 500,
  }) : _clientFor = clientFor {
    _reset(query: query, libraries: libraries);
  }

  final MediaServerClient? Function(ServerId serverId) _clientFor;

  /// Per-library page size (hoofdstuk 12.1's per-cursor fetch).
  final int pageSize;

  /// hoofdstuk 12.3: the paging target is a *group* count, not a raw-item
  /// count — duplicates across libraries mean a full page of raw items can
  /// produce fewer cards than that.
  final int groupsPerPage;

  /// hoofdstuk 12.6: bounded concurrent library-page fetches.
  final int maxConcurrentFetches;

  /// Safety ceiling on how many raw items one [loadMore] call will pop
  /// before returning regardless of whether [groupsPerPage] new groups were
  /// reached — guards against a pathological all-duplicate stream
  /// (hoofdstuk 12.3's own example: twenty items collapsing into far fewer
  /// groups) turning one call into an unbounded loop.
  final int maxRawItemsPerLoadMore;

  UnifiedCatalogQuery _query = const UnifiedCatalogQuery(kind: MediaKind.movie);
  List<UnifiedSourceCursor> _cursors = [];

  /// Every raw item popped off the merge so far, in pop order — the ordered
  /// candidate history [groupUnifiedMediaSources] is a pure, order-preserving
  /// function of (hoofdstuk 11.9's "position of the first candidate"). Never
  /// truncated: re-running the full grouping pass over this list each round
  /// is what lets a late duplicate (hoofdstuk 12.5) merge into a group at its
  /// existing position instead of the caller having to hand-roll incremental
  /// union-find bookkeeping.
  final List<MediaItem> _poppedItems = [];

  List<UnifiedMediaGroup> _groups = [];
  int _generation = 0;
  bool _everSucceeded = false;

  UnifiedCatalogQuery get query => _query;

  /// True once no cursor will ever produce another group: every cursor has
  /// fetched everything its server has ([UnifiedSourceCursor.exhausted])
  /// *and* has no buffered item left to pop. A cursor can be exhausted
  /// server-side (its one and only page already arrived) while still holding
  /// several unpopped items — [isComplete] must stay false until those are
  /// actually consumed, or [loadMore]'s own `groupsPerPage` batching would
  /// falsely report completion the moment a large final page lands.
  bool get isComplete => _cursors.every((c) => c.exhausted && !c.hasBufferedItem);

  /// The library set this service currently merges over.
  List<CatalogLibrary> get libraries => [for (final c in _cursors) c.library];

  /// Settled-state snapshot — never mid-flight; the caller owns any
  /// transient `isInitialLoading`/`isLoadingMore` flags around calling
  /// [loadMore].
  UnifiedCatalogSnapshot get snapshot {
    final failedLibraryIds = {
      for (final c in _cursors)
        if (c.lastError != null) c.libraryGlobalKey,
    };
    final initialLoadFailed =
        !_everSucceeded && _groups.isEmpty && _cursors.isNotEmpty && _cursors.every((c) => c.lastError != null);
    return UnifiedCatalogSnapshot(
      groups: List.unmodifiable(_groups),
      initialLoadFailed: initialLoadFailed,
      failedLibraryIds: failedLibraryIds,
      isComplete: isComplete,
    );
  }

  /// Starts a fresh query/library set — a filter, sort or library-set change
  /// (hoofdstuk 12.7). Abandons every outstanding fetch via its
  /// [AbortController] and a bumped generation, so a response for the *old*
  /// query can never land in the new one's state.
  void updateQuery({required UnifiedCatalogQuery query, required List<CatalogLibrary> libraries}) =>
      _reset(query: query, libraries: libraries);

  /// Re-runs the same query from scratch — the sanctioned way to apply a
  /// reorder hoofdstuk 12.5 defers ("na scroll-idle of volgende refresh"): a
  /// full refresh re-derives every group's true sort key from a clean slate
  /// instead of this service trying to reorder already-yielded cards in
  /// place mid-session.
  void refresh({List<CatalogLibrary>? libraries}) => _reset(query: _query, libraries: libraries ?? this.libraries);

  void _reset({required UnifiedCatalogQuery query, required List<CatalogLibrary> libraries}) {
    _generation++;
    for (final cursor in _cursors) {
      cursor.inFlight?.abort();
    }
    _query = query;
    _cursors = [for (final library in libraries) UnifiedSourceCursor(library)];
    _poppedItems.clear();
    _groups = [];
    _everSucceeded = false;
  }

  /// Advances the merge until [groupsPerPage] new groups have been produced,
  /// every cursor is exhausted, or [maxRawItemsPerLoadMore] is hit. A no-op
  /// once [isComplete].
  ///
  /// A cursor that errors stays blocked for the rest of this call (tracked
  /// as it happens, in `_fillBuffers`'s `failedThisCall`) — without that cap,
  /// a cursor that errors early but still has buffer room left under
  /// [groupsPerPage] would get silently retried again later in the very same
  /// call once the outer loop asks for more, hiding a real failure that this
  /// round should have surfaced in [UnifiedCatalogSnapshot.failedLibraryIds].
  /// A genuine retry still happens — just on the *next* [loadMore] call,
  /// matching hoofdstuk 12.6. A cursor that *succeeds* is never blocked this
  /// way: draining a page into an already-empty buffer must not stop this
  /// same call from asking it for its next page too, or hoofdstuk 12.3's
  /// "keep going until groupsPerPage or exhausted" would give up early
  /// whenever a healthy library needs more than one page to help reach the
  /// target.
  Future<UnifiedCatalogSnapshot> loadMore() async {
    if (isComplete) return snapshot;

    final myGeneration = _generation;
    final groupCountAtStart = _groups.length;
    var poppedThisCall = 0;
    final failedThisCall = <UnifiedSourceCursor>{};

    while (_groups.length < groupCountAtStart + groupsPerPage && poppedThisCall < maxRawItemsPerLoadMore) {
      await _fillBuffers(myGeneration, failedThisCall);
      if (myGeneration != _generation) return snapshot; // superseded by updateQuery/refresh mid-flight

      var poppedThisBatch = 0;
      while (poppedThisBatch < groupsPerPage &&
          poppedThisCall < maxRawItemsPerLoadMore &&
          _cursors.any((c) => c.hasBufferedItem)) {
        _poppedItems.add(_popGlobalSmallestHead());
        poppedThisBatch++;
        poppedThisCall++;
      }

      if (poppedThisBatch == 0) break; // nothing buffered anywhere this round — stuck until a retry

      await _recomputeGroups();
      if (myGeneration != _generation) return snapshot;
    }

    return snapshot;
  }

  Future<void> _fillBuffers(int myGeneration, Set<UnifiedSourceCursor> failedThisCall) async {
    final toFetch = _cursors.where((c) => c.isFetchable && !c.hasBufferedItem && !failedThisCall.contains(c)).toList();
    for (var i = 0; i < toFetch.length; i += maxConcurrentFetches) {
      final batch = toFetch.skip(i).take(maxConcurrentFetches);
      await Future.wait(batch.map((cursor) => _fetchOnePage(cursor, myGeneration)));
      if (myGeneration != _generation) return;
      // A cursor that just failed must not be retried again within this same
      // call — that would silently mask the failure this round should
      // surface in UnifiedCatalogSnapshot.failedLibraryIds; it gets a real
      // retry on the *next* loadMore() call instead (hoofdstuk 12.6). A
      // cursor that succeeded is deliberately NOT blocked here: it may have
      // just drained a page-worth of items into an already-empty buffer, and
      // hoofdstuk 12.3 requires the merge to keep pulling further pages from
      // it within this same call until groupsPerPage is reached.
      for (final cursor in batch) {
        if (cursor.lastError != null) failedThisCall.add(cursor);
      }
    }
  }

  Future<void> _fetchOnePage(UnifiedSourceCursor cursor, int myGeneration) async {
    cursor.fetchInFlight = true;
    final abort = AbortController();
    cursor.inFlight = abort;
    try {
      final client = _clientFor(cursor.library.serverId);
      if (client == null) {
        cursor.lastError = StateError('No client for ${cursor.library.serverId}');
        return;
      }
      final libraryQuery = _query.toLibraryQuery(offset: cursor.offset, limit: pageSize);
      final page = await client
          .fetchLibraryPagedContent(
            cursor.library.libraryId,
            query: libraryQuery,
            libraryKind: _query.kind,
            abort: abort,
          )
          .timeout(
            MediaServerTimeouts.unifiedCatalogLibraryPage,
            onTimeout: () {
              abort.abort();
              throw TimeoutException(
                'Unified catalog page fetch timed out',
                MediaServerTimeouts.unifiedCatalogLibraryPage,
              );
            },
          );
      if (myGeneration != _generation) return; // superseded while in flight — discard

      cursor.buffer.addAll(page.items);
      cursor.offset += page.items.length;
      cursor.sourceTotal = page.totalCount;
      cursor.lastError = null;
      _everSucceeded = true;
      if (page.items.isEmpty || cursor.offset >= page.totalCount) cursor.exhausted = true;
    } catch (e, st) {
      if (myGeneration != _generation) return;
      appLogger.d('Unified catalog page fetch failed for ${cursor.libraryGlobalKey}', error: e, stackTrace: st);
      cursor.lastError = e;
    } finally {
      if (myGeneration == _generation) {
        cursor.fetchInFlight = false;
        cursor.inFlight = null;
      }
    }
  }

  /// hoofdstuk 12.2's k-way merge step: pop the buffered head that compares
  /// smallest under the query's sort, across every cursor. Ties (same sort
  /// key value on two different libraries) break deterministically on server
  /// id then library id, so two callers merging the same servers always pop
  /// in the same order.
  MediaItem _popGlobalSmallestHead() {
    final compare = unifiedCatalogItemComparator(_query);
    UnifiedSourceCursor? winner;
    for (final cursor in _cursors) {
      if (!cursor.hasBufferedItem) continue;
      if (winner == null) {
        winner = cursor;
        continue;
      }
      final cmp = compare(cursor.head, winner.head);
      if (cmp < 0 || (cmp == 0 && _tieBreak(cursor, winner) < 0)) winner = cursor;
    }
    return winner!.popHead();
  }

  int _tieBreak(UnifiedSourceCursor a, UnifiedSourceCursor b) {
    final serverCmp = a.library.serverId.value.compareTo(b.library.serverId.value);
    if (serverCmp != 0) return serverCmp;
    return a.library.libraryId.compareTo(b.library.libraryId);
  }

  /// Resolves identity evidence for the *entire* popped history and re-runs
  /// [groupUnifiedMediaSources] over it (hoofdstuk 4.3: one identity
  /// pipeline, not a second ad hoc merge; `allowWeakFallback` stays at its
  /// default `true` here — unlike Continue Watching's deliberate opt-out,
  /// the main catalog is exactly the caller hoofdstuk 11.6's title+year
  /// fallback was built for). Re-resolving already-seen items on every round
  /// re-fetches external ids for any item still sitting in a duplicate
  /// bucket — real but bounded waste (only bucket-colliding items cost a
  /// fetch at all, per `identity_resolver.dart`'s own two-phase rule)
  /// accepted for fase 3 rather than adding a second, invalidation-prone
  /// cache on top of it.
  Future<void> _recomputeGroups() async {
    final resolver = UnifiedIdentityResolver(
      fetchExternalIds: (serverId, targetId) async {
        final client = _clientFor(ServerId(serverId));
        if (client == null) throw StateError('No client for server $serverId');
        return client.fetchExternalIds(targetId);
      },
    );
    final resolvables = [
      for (final item in _poppedItems)
        ResolvableItem(
          item: item,
          identity: canonicalIdentityOf(item),
          scope: _scopeOf(item),
          externalIdTarget: _externalIdTargetFor(item),
        ),
    ];
    final evidence = await resolver.resolveEvidence(resolvables);

    final candidates = <GroupingCandidate>[];
    for (var i = 0; i < _poppedItems.length; i++) {
      final item = _poppedItems[i];
      final serverId = item.serverId;
      // UnifiedMediaSource.fromItem requires a resolvable server id — never
      // expected from a real library-page mapper, but a group is
      // unrenderable without one (no playable route, no globalKey), so this
      // can only be dropped with a warning rather than passed through as its
      // own card (unlike _deduplicateContinueWatching's equivalent guard,
      // whose output is a bare MediaItem list that *can* represent one).
      if (serverId == null || serverId.isEmpty) {
        appLogger.w('Unified catalog: dropping item ${item.id} with no resolvable serverId');
        continue;
      }
      candidates.add(GroupingCandidate(source: UnifiedMediaSource.fromItem(item), evidence: evidence[i]));
    }
    _groups = groupUnifiedMediaSources(candidates);
  }

  String _scopeOf(MediaItem item) => (canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque()).granularity.name;

  ExternalIdTarget? _externalIdTargetFor(MediaItem item) {
    final serverId = item.serverId;
    if (serverId == null || serverId.isEmpty) return null;
    return (serverId: serverId, targetId: item.id);
  }
}
