/// All-source resolution for one identity (hoofdstuk 12.8 of
/// docs/tvos-unified-experience.md). The sources seen while paging a group
/// are not necessarily every source it has — on activation,
/// [SourceAllResolver.resolveAllSourcesForGroup] asks every relevant,
/// reachable server directly via [MediaServerClient.findAllByIdentity], the
/// hoofdstuk 4.3 "one identity pipeline" entry point for per-server lookup.
///
/// [fanOutFindAllByIdentity] is the shared low-level dispatch: bounded
/// batches, per-server error containment, and a caller-chosen stopping rule.
/// [SourceAllResolver] consumes it exhaustively (every eligible server gets
/// asked); `WatchlistAvailabilityResolver` consumes the same primitive but
/// stops at the first match, in deterministic server order — two different
/// consumption patterns over one shared dispatch loop, not two resolvers.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_identity.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';
import '../api_cache.dart';

/// The minimal per-server shape [fanOutFindAllByIdentity] needs: enough to
/// decide whether a server can be asked at all, nothing about why it can't.
/// Callers that need richer bookkeeping (offline vs auth-error, expected vs
/// checked) keep that on their own richer server record and map into this
/// shape only for the dispatch call.
typedef FanOutServer = ({ServerId serverId, MediaServerClient? client, bool online});

/// One server's answer to one `findAllByIdentity` call: every match it
/// returned, and whether the lookup itself succeeded. `ok: false` covers
/// "offline/no client" and "the call threw" alike — both mean this server
/// was not actually checked.
typedef SourceLookupOutcome = ({ServerId serverId, List<MediaItem> matches, bool ok});

/// Runs `findAllByIdentity(identity)` against [servers] in
/// [maxConcurrent]-sized batches, in list order — deterministic, so two
/// callers asking the same servers in the same order always try them in the
/// same order. After each batch resolves, [onBatch] sees that batch's
/// results and returns whether to stop (`true`) or continue to the next
/// batch (`false`). Returns once [onBatch] says stop, or once every server
/// has been asked.
Future<void> fanOutFindAllByIdentity({
  required List<FanOutServer> servers,
  required MediaIdentity identity,
  required int maxConcurrent,
  required bool Function(List<SourceLookupOutcome> batch) onBatch,
}) async {
  for (var i = 0; i < servers.length; i += maxConcurrent) {
    final batch = servers.skip(i).take(maxConcurrent);
    final results = await Future.wait(
      batch.map((server) async {
        final client = server.client;
        if (!server.online || client == null) {
          return (serverId: server.serverId, matches: const <MediaItem>[], ok: false);
        }
        try {
          return (serverId: server.serverId, matches: await client.findAllByIdentity(identity), ok: true);
        } catch (e, st) {
          appLogger.d('findAllByIdentity failed on ${server.serverId}', error: e, stackTrace: st);
          return (serverId: server.serverId, matches: const <MediaItem>[], ok: false);
        }
      }),
    );
    if (onBatch(results)) return;
  }
}

/// Drops the matches [serverId] returned that live in a library the active
/// profile has hidden (hoofdstuk 22/31.13: a hidden library may not leak into
/// any surface).
///
/// The server is the one that **answered**, not the one stamped on the item,
/// and that difference is the whole point. `DataAggregationService`'s
/// `filterHiddenLibraryItems` reads `item.serverId` because its items come off
/// paths that stamp one; the identity fan-out does not. Plex's
/// `findAllByIdentity` has two branches, and only the guid branch runs its
/// results through `_tagMetadata`. The title fallback maps candidates with
/// `PlexMappers.mediaItemFromJson(raw)` and passes no server id at all, so
/// those items carry a `libraryId` and a null `serverId` — an item-stamped
/// filter would fail open on exactly the branch a guid-less identity takes.
/// A client only ever answers with its own items, so the answering id is the
/// authoritative one and no branch can dodge the check.
///
/// Fail-open stays exactly where hoofdstuk 22 put it: an item with no
/// `libraryId` is in no library, so no hidden key can name it. That is the
/// only case that survives — a missing server id no longer is one.
List<MediaItem> visibleMatchesFromServer(List<MediaItem> matches, ServerId serverId, Set<String> hiddenLibraryKeys) {
  if (hiddenLibraryKeys.isEmpty) return matches;
  return matches.where((item) {
    final libraryId = item.libraryId;
    if (libraryId == null) return true;
    return !hiddenLibraryKeys.contains(buildGlobalKey(serverId, libraryId));
  }).toList();
}

/// Which backends can answer a catalogue-identity lookup at all.
///
/// Same rule `WatchlistAvailabilityResolver` already established (hoofdstuk
/// 1.2): a local folder and a Pleya Share have no guid and no external ids;
/// neither does a Pleya Server (`external_ids` is PS-7). Counting one of
/// them as "expected" would make coverage never complete for a group that
/// includes one of their sources — they become eligible in the phase that
/// gives them identity, not before.
bool isIdentityEligibleBackend(MediaBackend backend) => switch (backend) {
  MediaBackend.plex || MediaBackend.jellyfin => true,
  MediaBackend.local || MediaBackend.pleyaServer => false,
};

/// One server [SourceAllResolver] is allowed to ask, plus enough state to
/// explain a coverage gap. [hasAuthError] is separate from [online]: an
/// auth-rejected server is not online, but hoofdstuk 27's "auth/offline
/// onderscheid" wants the coverage UI to say which.
typedef EligibleSourceServer = ({
  ServerId serverId,
  MediaBackend backend,
  MediaServerClient? client,
  bool online,
  bool hasAuthError,
});

/// Builds the [EligibleSourceServer] list a [SourceAllResolver] resolves over,
/// from the active profile's topology rather than from the clients that
/// happen to be instantiated (A19).
///
/// The denominator question is "which servers should have answered", and
/// `MultiServerManager.serverIds` cannot answer it: it is sourced from the
/// live client map, so a server the profile expects but never managed to
/// build a client for — never reached, rejected at connect, still racing its
/// connections — is simply absent. Absent from the list means absent from
/// [SourceCoverageState.expectedServerIds], which means coverage reports
/// *complete* while one of the profile's servers was never asked anything.
/// That is the one lie the type exists to prevent.
///
/// So [expectedServerIds] is the authority — `MultiServerProvider`'s own
/// profile-scoped expectation, the same set `authErrorServerIds` already
/// filters on, written by `ActiveProfileBinder`. A server in it with no
/// client is reported with `client: null, online: false`, and lands in
/// coverage as unchecked instead of vanishing.
///
/// [visibleServerIds] is unioned in rather than intersected: it is already
/// visibility-filtered, so it can only *add* a live server the expectation
/// has not caught up with (a connection added inline, mid-bind), never
/// re-admit one the profile hides. Server visibility itself closes upstream
/// — a server hidden from the active profile appears in neither set — which
/// is hoofdstuk 1.1 point 2's rule, applied where it already lives instead of
/// re-derived here.
///
/// A server with no client has no known backend either. It is reported as
/// [MediaBackend.plex] so it stays identity-eligible and therefore counted:
/// "we do not know, and it never answered" has to read as a gap, not as an
/// exemption.
List<EligibleSourceServer> eligibleSourceServers({
  required Iterable<String> expectedServerIds,
  required Iterable<String> visibleServerIds,
  required MediaServerClient? Function(ServerId serverId) clientFor,
  required bool Function(ServerId serverId) isOnline,
  required Set<String> authErrorServerIds,
}) {
  final ids = <String>{...expectedServerIds, ...visibleServerIds};
  return [
    for (final id in ids)
      (
        serverId: ServerId(id),
        backend: clientFor(ServerId(id))?.backend ?? MediaBackend.plex,
        client: clientFor(ServerId(id)),
        online: isOnline(ServerId(id)),
        hasAuthError: authErrorServerIds.contains(id),
      ),
  ];
}

/// Result of [SourceAllResolver.resolveAllSourcesForGroup]: every concrete
/// item found across every eligible server, plus how much of the expected
/// server set was actually reached.
typedef GroupSourceResolution = ({List<MediaItem> items, SourceCoverageState coverage});

/// Asks every relevant, reachable server for every unambiguous match of one
/// identity (hoofdstuk 12.8).
///
/// **Coverage is derived from expectation, not from what happened to be
/// online** — the same rule `WatchlistAvailabilityResolver` already proved
/// out (hoofdstuk 1.2 calls its coverage semantics already finished, meant to
/// be reused rather than reinvented): the denominator is every eligible
/// server of the active profile, online or not, and the numerator is those
/// that actually answered.
///
/// Positive and negative results are cached. A negative is only cached when
/// coverage was complete — an incomplete miss might just be the one server
/// that did not answer, and caching that as "not available" would be wrong
/// for up to [negativeTtl].
class SourceAllResolver {
  SourceAllResolver({
    required this.profileId,
    required this.serversFor,
    required this.cache,
    this.hiddenLibraryKeysFor,
    this.maxConcurrent = 4,
    this.now,
  });

  /// The profile these answers belong to. Part of every cache key: a result
  /// is only meaningful for the servers one profile can reach.
  final String profileId;

  /// Every server of the active profile eligible to answer, in a
  /// deterministic order. Already **server**-visibility-filtered by the
  /// caller — a server hidden from the active profile must never appear here
  /// (hoofdstuk 1.1 point 2: visibility closes before the unified fan-out).
  /// Library visibility is a separate matter and closes here, via
  /// [hiddenLibraryKeysFor].
  final List<EligibleSourceServer> Function() serversFor;

  /// Every library the active profile has hidden, as `serverId:libraryId`
  /// global keys. Read per resolve like [serversFor], not captured once — a
  /// resolver is built once per profile and outlives any number of visibility
  /// changes.
  ///
  /// Server visibility is closed by the caller before [serversFor] ever
  /// returns a server; **library** visibility cannot be, because a hidden
  /// library sits inside a visible server that must still be asked for its
  /// other libraries. So it closes here instead, and the two halves of
  /// hoofdstuk 1.1 point 2 meet: no hidden server is asked, and nothing a
  /// visible server returns out of a hidden library survives.
  ///
  /// Omitting it keeps the pre-fase-9 behaviour of no library filtering, which
  /// is correct only for a caller that genuinely has no visibility context.
  final Set<String> Function()? hiddenLibraryKeysFor;

  final ApiCache cache;

  /// Ceiling on parallel lookups, matching `WatchlistAvailabilityResolver`'s
  /// default.
  final int maxConcurrent;

  /// Injectable clock, so TTL tests do not have to sleep.
  final DateTime Function()? now;

  static const Duration positiveTtl = Duration(days: 7);
  static const Duration negativeTtl = Duration(hours: 6);

  static final ServerId cacheServerId = ServerId('source-all-resolver');

  DateTime get _now => (now ?? DateTime.now)();

  /// Resolve every source for [identity].
  ///
  /// [isCancelled] is polled between batches. Hoofdstuk 14.5 opens the source
  /// picker on the sources already known and enriches coverage behind it, and
  /// requires that "kiezen annuleert resterende niet-essentiële lookups" — so
  /// a user who picks a server while three others are still being asked stops
  /// paying for the rest. Omitting it keeps the exhaustive behaviour every
  /// existing caller has: every eligible server gets asked.
  ///
  /// A cancelled resolution reports the coverage it actually achieved, with
  /// the servers it never reached marked [UncheckedSourceReason.lookupFailed]
  /// — they were not checked, and saying coverage is complete because we
  /// stopped asking would be the one lie [SourceCoverageState] exists to
  /// prevent. Nothing partial is cached, for the same reason.
  Future<GroupSourceResolution> resolveAllSourcesForGroup(
    MediaIdentity identity, {
    bool Function()? isCancelled,
  }) async {
    if (!identity.isSearchable) {
      return (items: const <MediaItem>[], coverage: SourceCoverageState.none);
    }

    final servers = serversFor();
    final eligible = servers.where((s) => isIdentityEligibleBackend(s.backend)).toList();
    final expectedIds = {for (final s in eligible) s.serverId.toString()};

    // Read once and thread it through the whole resolve. Reading it again at
    // write time would let a hide that lands mid-flight store filtered items
    // under the fingerprint of the set that was *not* used to filter them.
    final hiddenLibraryKeys = hiddenLibraryKeysFor?.call() ?? const <String>{};
    final visibility = _visibilityFingerprint(hiddenLibraryKeys);

    final cacheKey = _identityCacheKey(identity);
    final cached = await _readCache(cacheKey, visibility, eligible, expectedIds);
    if (cached != null) return cached;

    final items = <MediaItem>[];
    final checked = <String>{};
    final uncheckedReasons = <String, UncheckedSourceReason>{
      for (final s in eligible.where((s) => !s.online))
        s.serverId.toString(): s.hasAuthError ? UncheckedSourceReason.authError : UncheckedSourceReason.offline,
    };

    final reachable = eligible.where((s) => s.online && s.client != null).toList();
    var cancelled = false;
    await fanOutFindAllByIdentity(
      servers: [for (final s in reachable) (serverId: s.serverId, client: s.client, online: s.online)],
      identity: identity,
      maxConcurrent: maxConcurrent,
      onBatch: (batch) {
        for (final result in batch) {
          final id = result.serverId.toString();
          if (result.ok) {
            checked.add(id);
            // Before the result is kept, and therefore before it can be
            // cached: a filter behind the cache would be undone by the next
            // warm hit for up to [positiveTtl].
            items.addAll(visibleMatchesFromServer(result.matches, result.serverId, hiddenLibraryKeys));
          } else {
            uncheckedReasons[id] = UncheckedSourceReason.lookupFailed;
          }
        }
        // Without a caller-supplied rule this never stops early: every
        // eligible server gets asked, exactly as before.
        cancelled = isCancelled?.call() ?? false;
        return cancelled;
      },
    );

    for (final server in reachable) {
      final id = server.serverId.toString();
      if (!checked.contains(id) && !uncheckedReasons.containsKey(id)) {
        uncheckedReasons[id] = UncheckedSourceReason.lookupFailed;
      }
    }

    final coverage = SourceCoverageState(
      expectedServerIds: expectedIds,
      checkedServerIds: checked,
      uncheckedReasons: uncheckedReasons,
    );

    // A cancelled run asked fewer servers than it was going to; caching that
    // would freeze a deliberately partial answer for the full positive TTL.
    if (!cancelled) await _writeCache(cacheKey, visibility, items: items, coverage: coverage);
    return (items: items, coverage: coverage);
  }

  /// Drop every cached answer, for every profile. Called when server
  /// topology, reachability or a title's metadata changes — the cache table
  /// offers no cheaper prefix than the whole namespace, and wiping too much
  /// only costs a re-resolve, while keeping a stale miss costs a wrong
  /// "no sources" on a title one of them now has.
  Future<void> invalidate() async => cache.deleteForServer(cacheServerId);

  /// Cache rows are addressed by profile **and** by which libraries that
  /// profile has hidden. Both are context the answer depends on: a resolve run
  /// with a library hidden holds fewer sources than the same resolve run
  /// without it, so serving one where the other was asked for is exactly the
  /// leak this key exists to prevent — in both directions. Hiding a library
  /// therefore makes the old row unreachable rather than stale, and unhiding
  /// it lands back on the row the earlier visible resolve already wrote.
  ///
  /// Rows under a fingerprint nobody asks for any more age out on the normal
  /// TTLs; [invalidate] still drops the whole namespace at once.
  String _endpointFor(String key, String visibility) => 'match/$profileId/$visibility/$key';

  Future<GroupSourceResolution?> _readCache(
    String key,
    String visibility,
    List<EligibleSourceServer> eligible,
    Set<String> expectedIds,
  ) async {
    final Map<String, dynamic>? row;
    try {
      row = await cache.get(cacheServerId, _endpointFor(key, visibility));
    } catch (e) {
      appLogger.d('Source-all-resolver cache read failed', error: e);
      return null;
    }
    if (row == null) return null;

    final checkedAtMs = row['checkedAtMs'];
    if (checkedAtMs is! int) return null;
    final age = _now.difference(DateTime.fromMillisecondsSinceEpoch(checkedAtMs));

    final rawItems = row['items'];
    final checkedIds = (row['checkedServerIds'] as List?)?.cast<String>().toSet() ?? const <String>{};

    if (rawItems is List && rawItems.isNotEmpty) {
      if (age > positiveTtl) return null;
      // Every source named by a warm hit must still be reachable under the
      // *current* eligibility, or the answer no longer means anything: a
      // server that left the profile or went offline cannot serve what it
      // was cached as having.
      final currentlyReachable = {
        for (final s in eligible)
          if (s.online && s.client != null) s.serverId.toString(),
      };
      if (!checkedIds.every(currentlyReachable.contains)) return null;

      final List<MediaItem> items;
      try {
        items = [for (final raw in rawItems) MediaItem.fromJson(raw as Map<String, dynamic>)];
      } catch (e) {
        appLogger.d('Source-all-resolver cache row unreadable', error: e);
        return null;
      }
      final rawReasons = row['uncheckedReasons'];
      final uncheckedReasons = <String, UncheckedSourceReason>{
        for (final id in expectedIds.difference(checkedIds))
          id: _reasonFromName(rawReasons is Map ? rawReasons[id] as String? : null),
      };
      return (
        items: items,
        coverage: SourceCoverageState(
          expectedServerIds: expectedIds,
          checkedServerIds: checkedIds,
          uncheckedReasons: uncheckedReasons,
        ),
      );
    }

    // Only a complete negative was ever written, so reaching here means the
    // miss was worth keeping.
    if (age > negativeTtl) return null;
    // ...but only over the servers it actually asked. A server the profile
    // gained since — a re-add under a new id (A18), or any plain addition —
    // was never in that run, and replaying the miss as complete would assert
    // it holds nothing without ever having asked it. That is the one lie
    // [SourceCoverageState] exists to prevent, so a widened expectation
    // discards the row and re-resolves. A row written before negatives
    // carried their server set has no ids at all and falls out here too.
    if (!expectedIds.every(checkedIds.contains)) return null;
    return (items: const <MediaItem>[], coverage: SourceCoverageState.complete(expectedIds));
  }

  Future<void> _writeCache(
    String key,
    String visibility, {
    required List<MediaItem> items,
    required SourceCoverageState coverage,
  }) async {
    // An incomplete negative says nothing durable: the server that did not
    // answer may be exactly the one holding the title.
    if (items.isEmpty && !coverage.isComplete) return;

    try {
      await cache.put(cacheServerId, _endpointFor(key, visibility), {
        'checkedAtMs': _now.millisecondsSinceEpoch,
        // Written for a negative too: the read side needs to know which
        // servers the miss actually covers, so a later-added server cannot
        // inherit an answer nobody asked it for.
        'checkedServerIds': coverage.checkedServerIds.toList(),
        if (items.isNotEmpty) ...{
          'items': [for (final item in items) item.toJson()],
          'uncheckedReasons': {for (final e in coverage.uncheckedReasons.entries) e.key: e.value.name},
        },
      });
    } catch (e) {
      appLogger.d('Source-all-resolver cache write failed', error: e);
    }
  }
}

/// Deterministic, order-free digest of the hidden-library set, short enough to
/// sit in a cache key.
///
/// A digest rather than the set itself: `hiddenLibraryKeys` is unordered and
/// unbounded, so joining it raw would give two orderings of the same set two
/// different rows, and a profile that hides forty libraries a key longer than
/// the identity it is keying. Sorting first makes the digest depend on the set
/// and not on iteration order; `sha1` matches the key-derivation the codebase
/// already uses for artwork storage keys.
String _visibilityFingerprint(Set<String> hiddenLibraryKeys) {
  if (hiddenLibraryKeys.isEmpty) return 'v0';
  final sorted = hiddenLibraryKeys.toList()..sort();
  // The separator is a character no `serverId:libraryId` key can contain, so
  // {"a:b", "c"} and {"a", "b:c"} cannot digest to the same string.
  return 'v${sha1.convert(utf8.encode(sorted.join('\u0000')))}'.substring(0, 17);
}

UncheckedSourceReason _reasonFromName(String? name) =>
    UncheckedSourceReason.values.firstWhere((r) => r.name == name, orElse: () => UncheckedSourceReason.offline);

/// Deterministic cache key for a [MediaIdentity]: guid first, then external
/// ids, then title/year/kind as the last resort — same priority order as
/// [MediaIdentity.pickMatch]/[MediaIdentity.pickAllMatches], so two callers
/// asking "the same identity" always land on the same cache row.
String _identityCacheKey(MediaIdentity identity) {
  final guid = identity.guid;
  if (guid != null && guid.isNotEmpty) return 'guid:$guid';
  final ids = identity.externalIds;
  if (ids.imdb != null && ids.imdb!.isNotEmpty) return 'imdb:${ids.imdb}';
  if (ids.tmdb != null) return 'tmdb:${ids.tmdb}';
  if (ids.tvdb != null) return 'tvdb:${ids.tvdb}';
  final title = identity.title?.trim().toLowerCase() ?? '';
  return 'title:$title:${identity.year ?? ''}:${identity.kind.name}';
}
