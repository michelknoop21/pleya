import 'dart:async';
import '../media/ids.dart';

import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../media/unified/unified_media_source.dart';
import '../services/unified_catalog/grouping_service.dart';
import '../services/unified_catalog/identity_resolver.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_timeouts.dart';
import '../utils/global_key_utils.dart';
import '../utils/search_relevance.dart';
import 'multi_server_manager.dart';

typedef OnDeckAggregationResult = ({List<MediaItem> items, Set<String> succeededServerIds});
typedef HubAggregationResult = ({List<MediaHub> hubs, Set<String> succeededServerIds});
typedef SearchAggregationResult = ({List<MediaItem> items, Set<String> succeededServerIds});

/// Drops items that live in a library the active profile has hidden.
///
/// Hoofdstuk 22/31.13 of docs/tvos-unified-experience.md: a hidden library may
/// not leak into any surface, and the filter belongs **before** grouping,
/// ranking or capping — not after. Filtering afterwards would let hidden items
/// consume the result budget, and on the unified path it would have to prune
/// [UnifiedMediaGroup.sources], which asserts it is never a subset.
///
/// Fail-open on an unknown library is deliberate and matches every caller: an
/// item the backend returns without a `libraryId` (a Plex Discover hit from
/// `includeExternalMedia`, say) is not in any library, so no hidden key can
/// name it.
List<MediaItem> filterHiddenLibraryItems(List<MediaItem> items, Set<String>? hiddenLibraryKeys) {
  if (hiddenLibraryKeys == null || hiddenLibraryKeys.isEmpty) return items;
  return items.where((item) {
    if (item.libraryId == null || item.serverId == null) return true;
    final globalKey = buildGlobalKey(ServerId(item.serverId!), item.libraryId!);
    return !hiddenLibraryKeys.contains(globalKey);
  }).toList();
}

/// Cross-server aggregation: fans calls out to every online client and
/// merges the results. Single-server operations now go through the
/// [MediaServerClient] interface directly (resolved via
/// [ProviderExtensions.tryGetMediaClientForServer] etc.), so this service
/// only owns the genuinely multi-server flows: home/discover hubs, on-deck,
/// search, and the global library list.
class DataAggregationService {
  final MultiServerManager _serverManager;

  DataAggregationService(this._serverManager, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The clock the release window is measured against. A seam for tests;
  /// production is `DateTime.now`.
  final DateTime Function() _now;

  /// How old a release may be and still count as "recent uitgebracht" for
  /// the Home hero and the row of the same name (DEC-097, 5 September 2026:
  /// 90 days). One constant, one owner; `FeaturedSelector` deliberately does
  /// not repeat it.
  static const Duration heroReleaseWindow = Duration(days: 90);

  /// Online clients, optionally restricted to [serverIds] — delta refreshes
  /// fan out to newly-online servers only. Always visibility-filtered: a
  /// server the active profile has hidden never contributes here, regardless
  /// of [serverIds]. [MultiServerManager.onlineClients] itself is NOT
  /// visibility-filtered (profile visibility lives on the manager but isn't
  /// applied there), so every aggregation entry point must go through this
  /// method rather than reading `onlineClients` directly.
  Map<String, MediaServerClient> _clientsFor(Set<String>? serverIds) {
    final clients = _serverManager.onlineClients;
    return {
      for (final entry in clients.entries)
        if (_serverManager.isServerVisible(ServerId(entry.key)) && (serverIds == null || serverIds.contains(entry.key)))
          entry.key: entry.value,
    };
  }

  /// Fetch libraries from all online clients regardless of backend, returning
  /// the merged neutral [MediaLibrary]s alongside the ids of the servers whose
  /// fetch actually succeeded. [serverIds] restricts the fan-out to those
  /// servers.
  ///
  /// A per-server `fetchLibraries()` failure is swallowed (that server simply
  /// contributes no libraries) so one unreachable server doesn't sink the whole
  /// list. [succeededServerIds] lets callers tell a *failed* fetch apart from a
  /// server that genuinely has no libraries — both contribute nothing, so
  /// conflating them would let a transient failure be cached as "loaded" and
  /// never retried.
  Future<({List<MediaLibrary> libraries, Set<String> succeededServerIds})> getMediaLibrariesFromAllServers({
    Set<String>? serverIds,
  }) async {
    final clients = _clientsFor(serverIds);
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching libraries (neutral)');
      return (libraries: const <MediaLibrary>[], succeededServerIds: const <String>{});
    }
    final succeededServerIds = <String>{};
    final futures = clients.entries.map((entry) async {
      try {
        final libraries = await entry.value.fetchLibraries();
        succeededServerIds.add(entry.key);
        return libraries;
      } catch (e, stackTrace) {
        appLogger.e('Failed neutral library fetch from ${entry.key}', error: e, stackTrace: stackTrace);
        return <MediaLibrary>[];
      }
    });
    final results = await Future.wait(futures);
    return (libraries: [for (final list in results) ...list], succeededServerIds: succeededServerIds);
  }

  /// Fetch "On Deck" (Continue Watching) from all servers and merge by recency.
  /// Items are tagged with server info by the underlying client. Returns
  /// neutral [MediaItem]s plus the ids of servers whose fetch succeeded.
  /// [serverIds] restricts the fan-out to those servers.
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async {
    final clients = _clientsFor(serverIds);
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching on deck');
      return (items: const <MediaItem>[], succeededServerIds: const <String>{});
    }

    final futures = clients.entries.map((entry) async {
      final client = entry.value;
      try {
        final items = await client.fetchContinueWatching(count: limit);
        return (serverId: entry.key, items: items);
      } catch (e, st) {
        appLogger.e('Failed on-deck fetch from ${entry.key}', error: e, stackTrace: st);
        return (serverId: null, items: <MediaItem>[]);
      }
    });
    final results = await Future.wait(futures);
    final succeededServerIds = {
      for (final result in results)
        if (result.serverId != null) result.serverId!,
    };
    final allOnDeck = results.expand((result) => result.items).toList();

    // Filter out items from hidden libraries
    List<MediaItem> filteredOnDeck = filterHiddenLibraryItems(allOnDeck, hiddenLibraryKeys);

    // Watched movies without active progress don't belong in Continue
    // Watching — some servers keep them in the hub while scrobble processing
    // settles, and out-of-band watches (another client) land here too.
    // Movies only: a series row is the server's next-episode substitution.
    filteredOnDeck = filteredOnDeck
        .where((item) => item.kind != MediaKind.movie || item.isUnwatchedOrInProgress)
        .toList();

    // Sort by most recently viewed, falling back to addedAt for unwatched items.
    // Same key as JellyfinClient's continue-watching merge (MediaItem.recencySortKey)
    // so per-server and cross-server ordering can't drift apart.
    filteredOnDeck.sort((a, b) => b.recencySortKey.compareTo(a.recencySortKey));

    filteredOnDeck = await _deduplicateContinueWatching(filteredOnDeck);

    // Apply limit if specified
    final items = limit != null && limit < filteredOnDeck.length ? filteredOnDeck.sublist(0, limit) : filteredOnDeck;

    appLogger.i('Fetched ${items.length} on deck items from all servers');

    return (items: items, succeededServerIds: succeededServerIds);
  }

  /// Newest *released* movies across all servers, for the home hero.
  ///
  /// [fetchRecentlyAdded] only supplies the candidate pool; selection and
  /// ordering are release-date based, never added-date based. The server
  /// endpoint sorts by *added*, so we over-fetch (pool cap 100 per server) and
  /// re-sort hard on release date — otherwise a small pool would silently make
  /// this "recently added" instead of "newest released". Movies only, no series
  /// fallback: no films → empty list (the hero hides).
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async {
    final clients = _clientsFor(serverIds);
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching latest movies');
      return (items: const <MediaItem>[], succeededServerIds: const <String>{});
    }

    final futures = clients.entries.map((entry) async {
      try {
        // ponytail: 100 = candidate pool, not the output cap.
        final items = await entry.value.fetchRecentlyAdded(limit: 100);
        return (serverId: entry.key, items: items);
      } catch (e, st) {
        appLogger.e('Failed latest-movies fetch from ${entry.key}', error: e, stackTrace: st);
        return (serverId: null, items: <MediaItem>[]);
      }
    });
    final results = await Future.wait(futures);
    final succeededServerIds = {
      for (final result in results)
        if (result.serverId != null) result.serverId!,
    };

    var candidates = results.expand((result) => result.items).toList();

    // Filter out items from hidden libraries.
    candidates = filterHiddenLibraryItems(candidates, hiddenLibraryKeys);

    // Hard films-only: no series, no series fallback.
    candidates = candidates.where((item) => item.kind == MediaKind.movie).toList();

    // "Recent uitgebracht" is a window on the release date, not an ordering
    // (DEC-097). Before this there was no lower bound at all: the 100 most
    // recently *added* items were sorted by release date and the top 12 kept,
    // so a library back-filled with old films put a 1998 title in the hero
    // under a heading that promised the opposite. A film without a release
    // date cannot be recently released by any reading, so it is out as well:
    // Pleya Server, Pleya Share and the local folder carry no date over the
    // line today, and that is a protocol gap to close where the contract may
    // change, not a reason to show "recently added" under this name.
    final cutoff = _now().subtract(heroReleaseWindow);
    final dated = <({MediaItem item, DateTime released})>[
      for (final item in candidates)
        if (_releaseDate(item) case final released? when !released.isBefore(cutoff)) (item: item, released: released),
    ];
    dated.sort((a, b) => b.released.compareTo(a.released));
    candidates = [for (final entry in dated) entry.item];

    // Lightweight cross-server dedup on shared identity (guid) then globalKey.
    final seen = <String>{};
    final deduped = <MediaItem>[];
    for (final item in candidates) {
      final key = item.guid ?? item.globalKey;
      if (!seen.add(key)) continue;
      deduped.add(item);
    }

    final cap = limit ?? 12;
    final items = cap < deduped.length ? deduped.sublist(0, cap) : deduped;

    appLogger.i('Fetched ${items.length} latest movies from all servers');
    return (items: items, succeededServerIds: succeededServerIds);
  }

  /// Newest *added* shows across all servers, one tile per series.
  ///
  /// Mirrors [getLatestMoviesFromAllServers] except for the sort: for series
  /// the release date is the show's first-aired year, which says nothing about
  /// when it landed on the server, so `addedAt` is the primary key here.
  Future<OnDeckAggregationResult> getLatestShowsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async {
    final clients = _clientsFor(serverIds);
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching latest shows');
      return (items: const <MediaItem>[], succeededServerIds: const <String>{});
    }

    final results = await Future.wait(
      clients.entries.map((entry) async {
        try {
          final items = await entry.value.fetchRecentlyAddedShows(limit: 50);
          return (serverId: entry.key, items: items);
        } catch (e, st) {
          appLogger.e('Failed latest-shows fetch from ${entry.key}', error: e, stackTrace: st);
          return (serverId: null, items: <MediaItem>[]);
        }
      }),
    );
    final succeededServerIds = {
      for (final result in results)
        if (result.serverId != null) result.serverId!,
    };

    var candidates = results.expand((result) => result.items).toList();

    candidates = filterHiddenLibraryItems(candidates, hiddenLibraryKeys);

    // Defensive: a backend that ignores the series-level filter must not leak
    // episodes into a shows row.
    candidates = candidates.where((item) => item.kind == MediaKind.show).toList();

    candidates.sort((a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));

    final seen = <String>{};
    final deduped = <MediaItem>[];
    for (final item in candidates) {
      if (!seen.add(item.guid ?? item.globalKey)) continue;
      deduped.add(item);
    }

    final cap = limit ?? 12;
    final items = cap < deduped.length ? deduped.sublist(0, cap) : deduped;

    appLogger.i('Fetched ${items.length} latest shows from all servers');
    return (items: items, succeededServerIds: succeededServerIds);
  }

  /// Parsed release date, or null when the item has no usable
  /// `originallyAvailableAt` (those items are outside the release window).
  DateTime? _releaseDate(MediaItem item) {
    final raw = item.originallyAvailableAt;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Merge an [existing] Continue Watching list with [fresh] rows from
  /// newly-online servers: same recency ordering and cross-server identity
  /// dedup as [getOnDeckFromAllServers], applied to the union.
  Future<List<MediaItem>> mergeContinueWatching(List<MediaItem> existing, List<MediaItem> fresh, {int? limit}) async {
    final combined = [...existing, ...fresh]..sort((a, b) => b.recencySortKey.compareTo(a.recencySortKey));
    final deduped = await _deduplicateContinueWatching(combined);
    return limit != null && limit < deduped.length ? deduped.sublist(0, limit) : deduped;
  }

  /// Same dedup this method has always done — bucket by scope+title, then
  /// only for a shared bucket check whether two items' external ids/guid
  /// actually agree — now built on the shared unified identity/grouping layer
  /// (`unified_catalog/identity_resolver.dart`, `unified_catalog/grouping_service.dart`)
  /// instead of ad hoc private helpers, per
  /// [DEC-063](../../docs/DECISIONS.md#dec-063) fase 1. `allowWeakFallback:
  /// false` keeps the merge rule itself exactly what it always was: Continue
  /// Watching has only ever merged on shared external ids/guid, never on
  /// title+year alone (see `continueWatchingBucketKey`'s doc comment) — that
  /// bucket key only ever decides which items are worth an external-id fetch,
  /// same as before.
  Future<List<MediaItem>> _deduplicateContinueWatching(List<MediaItem> items) async {
    if (items.length < 2) return items;

    final duplicateBuckets = <String>{};
    final bucketCounts = <String, int>{};
    for (final item in items) {
      final bucket = continueWatchingBucketKey(item);
      if (bucket == null) continue;
      final count = (bucketCounts[bucket] ?? 0) + 1;
      bucketCounts[bucket] = count;
      if (count > 1) duplicateBuckets.add(bucket);
    }
    if (duplicateBuckets.isEmpty) return items;

    final resolver = UnifiedIdentityResolver(
      fetchExternalIds: (serverId, targetId) async {
        try {
          final client = _serverManager.getClient(ServerId(serverId));
          if (client == null) throw StateError('No online client for server $serverId');
          return await client.fetchExternalIds(targetId);
        } catch (e, stackTrace) {
          appLogger.d(
            'Failed to resolve Continue Watching identity for $serverId:$targetId',
            error: e,
            stackTrace: stackTrace,
          );
          rethrow;
        }
      },
    );
    final resolvables = [
      for (final item in items)
        ResolvableItem(
          item: item,
          scope: continueWatchingScope(item) ?? '',
          bucketKeyOverride: continueWatchingBucketKey(item),
          externalIdTarget: _hasOnlineClient(item) ? continueWatchingExternalIdTarget(item) : null,
          // An episode/season row's external ids are fetched from its
          // *series*, so they are narrowed to the exact row before they
          // become a token (hoofdstuk 11.8) — otherwise every episode of one
          // series would share `episode:tmdb:<series id>` and fold into one
          // entry. Its own guid needs no such narrowing: it already names the
          // concrete episode, which is the granularity this groups at.
          externalIdDiscriminator: continueWatchingOrdinal(item),
        ),
    ];
    final evidence = await resolver.resolveEvidence(resolvables);

    // A row with no serverId can never become a UnifiedMediaSource — its
    // sourceKey is `serverId:id` — and can never legitimately merge with
    // anything either way. Such a row is set aside before grouping and
    // spliced back in at its own original position afterward, rather than
    // letting one malformed item throw and crash dedup for the whole batch
    // (every other per-item path in this file contains a bad row the same
    // way instead of losing the good ones next to it).
    final malformedIndexes = <int>{
      for (var i = 0; i < items.length; i++)
        if (items[i].serverId == null || items[i].serverId!.isEmpty) i,
    };

    final originalIndexOf = <String, int>{};
    final candidates = <GroupingCandidate>[];
    for (var i = 0; i < items.length; i++) {
      if (malformedIndexes.contains(i)) continue;
      final source = UnifiedMediaSource.fromItem(items[i]);
      originalIndexOf[source.sourceKey] = i;
      candidates.add(GroupingCandidate(source: source, evidence: evidence[i]));
    }
    final groups = groupUnifiedMediaSources(candidates, allowWeakFallback: false);

    // `sources` preserves candidates' original (recency-sorted) order, so the
    // first source in each group is the one with the highest recency —
    // exactly the representative this method has always projected. Grouped
    // representatives and the set-aside malformed rows are merged back by
    // original index, so nothing silently changes position.
    final resultByIndex = <int, MediaItem>{
      for (final group in groups) originalIndexOf[group.sources.first.sourceKey]!: group.sources.first.item,
      for (final i in malformedIndexes) i: items[i],
    };
    return [for (final i in resultByIndex.keys.toList()..sort()) resultByIndex[i]!];
  }

  bool _hasOnlineClient(MediaItem item) {
    final serverId = item.serverId;
    return serverId != null && _serverManager.getClient(ServerId(serverId)) != null;
  }

  /// Fetch recommendation hubs from all servers as neutral [MediaHub]s.
  /// When useGlobalHubs is true (default), rich-hub backends use their true
  /// home page hubs (Plex's promoted/global hub endpoint).
  /// Backends without rich home hubs fall back to per-library hubs so one
  /// capped "Latest" response cannot hide whole library types.
  /// [serverIds] restricts the fan-out (including the library prefetch) to
  /// those servers. Returns the ids of servers whose hub fetch succeeded so
  /// callers do not cache transient per-server failures as loaded.
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async {
    final clients = _clientsFor(serverIds);
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching hubs');
      return (hubs: const <MediaHub>[], succeededServerIds: const <String>{});
    }

    // Only fallback clients need a library prefetch when home layout is on;
    // rich-hub backends return the intended home rows directly.
    final needsLibraryPrefetch = useGlobalHubs && clients.values.any((client) => !client.capabilities.richHubs);
    final libraries = needsLibraryPrefetch
        ? _groupLibrariesByServer((await getMediaLibrariesFromAllServers(serverIds: serverIds)).libraries)
        : null;

    final futures = clients.entries.map((entry) async {
      final serverId = entry.key;
      final client = entry.value;
      try {
        final serverLibraries = libraries?[serverId];
        final shouldUseGlobalHubs = useGlobalHubs && client.capabilities.richHubs;
        final hubItemLimit = limit ?? defaultHubPreviewLimit;
        final hubs = shouldUseGlobalHubs
            ? await client.fetchGlobalHubs(limit: hubItemLimit, includePlaybackHubs: includePlaybackHubs)
            : await _fetchLibraryHubsForClient(
                client,
                limit: hubItemLimit,
                hiddenLibraryKeys: hiddenLibraryKeys,
                includePlaybackHubs: includePlaybackHubs,
                libraries: useGlobalHubs ? serverLibraries : null,
              );
        return (
          serverId: serverId,
          hubs: _postProcessHubs(hubs, serverId: ServerId(serverId), hiddenLibraryKeys: hiddenLibraryKeys),
        );
      } catch (e, stackTrace) {
        appLogger.e('Failed to fetch hubs from server $serverId', error: e, stackTrace: stackTrace);
        return (serverId: null, hubs: <MediaHub>[]);
      }
    });

    final results = await Future.wait(futures);
    final succeededServerIds = {
      for (final result in results)
        if (result.serverId != null) result.serverId!,
    };
    final all = <MediaHub>[];
    for (final result in results) {
      all.addAll(result.hubs);
    }
    final hubs = limit != null && limit < all.length ? all.sublist(0, limit) : all;
    return (hubs: hubs, succeededServerIds: succeededServerIds);
  }

  /// Per-library hub fetch for a single client. Filters to visible
  /// movie/show libraries (Plex hides music libraries from this surface) and
  /// concatenates the results.
  Future<List<MediaHub>> _fetchLibraryHubsForClient(
    MediaServerClient client, {
    required int limit,
    Set<String>? hiddenLibraryKeys,
    required bool includePlaybackHubs,
    List<MediaLibrary>? libraries,
  }) async {
    final libs = libraries ?? await client.fetchLibraries();
    final visible = libs.where((l) {
      if (l.kind != MediaKind.movie && l.kind != MediaKind.show) return false;
      if (l.hidden) return false;
      if (hiddenLibraryKeys != null && hiddenLibraryKeys.contains(l.globalKey)) return false;
      return true;
    }).toList();

    const concurrency = 3;
    final all = <MediaHub>[];
    for (var start = 0; start < visible.length; start += concurrency) {
      final batch = visible.skip(start).take(concurrency);
      final results = await Future.wait(
        batch.map((l) async {
          try {
            return await client.fetchLibraryHubs(
              l.id,
              libraryName: l.title,
              limit: limit,
              includePlaybackHubs: includePlaybackHubs,
              libraryKind: l.kind,
            );
          } catch (e, st) {
            appLogger.e('Failed to fetch library hubs for ${l.globalKey}', error: e, stackTrace: st);
            return <MediaHub>[];
          }
        }),
      );
      for (final list in results) {
        all.addAll(list);
      }
    }
    return all;
  }

  /// Filter hidden-library items and drop empty hubs.
  List<MediaHub> _postProcessHubs(List<MediaHub> hubs, {required ServerId serverId, Set<String>? hiddenLibraryKeys}) {
    var filtered = hubs;
    if (hiddenLibraryKeys != null && hiddenLibraryKeys.isNotEmpty) {
      filtered = filtered
          .map((hub) {
            final filteredItems = hub.items.where((item) {
              final libraryId = item.libraryId;
              if (libraryId == null) return true;
              final globalKey = buildGlobalKey(ServerId(serverId), libraryId);
              return !hiddenLibraryKeys.contains(globalKey);
            }).toList();
            if (filteredItems.isEmpty) return null;
            return hub.copyWith(items: filteredItems, size: filteredItems.length);
          })
          .whereType<MediaHub>()
          .toList();
    }
    return filtered;
  }

  /// Search across all online servers (Plex + Jellyfin). Returns neutral
  /// [MediaItem]s plus the ids of the servers that actually answered.
  ///
  /// Per-server failures are contained (that server just contributes nothing),
  /// but the caller needs to tell "every server failed" apart from "nobody has
  /// a match" — otherwise a dead connection renders as a plain "no results".
  ///
  /// [hiddenLibraryKeys] are `serverId:libraryId` keys the active profile has
  /// hidden; matching results are dropped before ranking.
  Future<SearchAggregationResult> searchAcrossServers(
    String query, {
    int? limit,
    Set<String>? hiddenLibraryKeys,
  }) async {
    if (query.trim().isEmpty) {
      return (items: const <MediaItem>[], succeededServerIds: const <String>{});
    }

    final clients = _clientsFor(null);
    if (clients.isEmpty) return (items: const <MediaItem>[], succeededServerIds: const <String>{});

    final resultLimit = limit ?? defaultMediaSearchLimit;
    final fetchLimit = resultLimit < defaultMediaSearchLimit ? defaultMediaSearchLimit : resultLimit;

    final futures = clients.entries.map((entry) async {
      final client = entry.value;
      try {
        // Per-server budget. Errors were already contained, but a server that
        // is marked online and simply never answers used to hold up the whole
        // fan-out for the full receive timeout (×2 with endpoint failover) —
        // minutes of skeletons while the healthy servers were long done. A
        // timeout counts as a failure, not as "this server has no matches".
        final items = await client.searchItems(query, limit: fetchLimit).timeout(MediaServerTimeouts.searchPerServer);
        return (serverId: entry.key, items: items);
      } catch (e, st) {
        appLogger.e('Search failed on ${entry.key}', error: e, stackTrace: st);
        return (serverId: null, items: <MediaItem>[]);
      }
    });

    final perServer = await Future.wait(futures);
    final succeededServerIds = {
      for (final entry in perServer)
        if (entry.serverId != null) entry.serverId!,
    };
    // Visibility before ranking (hoofdstuk 22/31.13). Search was the only
    // aggregation entry point without this filter: servers were excluded by
    // _clientsFor, libraries by nobody. Filtering here rather than in a caller
    // keeps hidden items from consuming the result budget, and keeps the TV
    // path honest — searchProjection groups what it is handed, and
    // UnifiedMediaGroup.sources asserts it is never a subset.
    final allResults = filterHiddenLibraryItems(perServer.expand((entry) => entry.items).toList(), hiddenLibraryKeys);
    final result = rankMediaSearchResults(allResults, query, limit: resultLimit);

    appLogger.i('Found ${result.length} search results across ${succeededServerIds.length} servers');

    return (items: result, succeededServerIds: succeededServerIds);
  }

  /// Group libraries by server (internal aggregation helper).
  Map<String, List<MediaLibrary>> _groupLibrariesByServer(List<MediaLibrary> libraries) {
    final grouped = <String, List<MediaLibrary>>{};

    for (final library in libraries) {
      final serverId = library.serverId;
      if (serverId != null) {
        grouped.putIfAbsent(serverId, () => []).add(library);
      }
    }

    return grouped;
  }
}
