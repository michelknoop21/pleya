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

import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_identity.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../utils/app_logger.dart';
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
typedef EligibleSourceServer =
    ({ServerId serverId, MediaBackend backend, MediaServerClient? client, bool online, bool hasAuthError});

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
  SourceAllResolver({required this.profileId, required this.serversFor, required this.cache, this.maxConcurrent = 4, this.now});

  /// The profile these answers belong to. Part of every cache key: a result
  /// is only meaningful for the servers one profile can reach.
  final String profileId;

  /// Every server of the active profile eligible to answer, in a
  /// deterministic order. Already visibility-filtered by the caller — a
  /// server hidden from the active profile must never appear here (hoofdstuk
  /// 1.1 point 2: visibility closes before the unified fan-out).
  final List<EligibleSourceServer> Function() serversFor;

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
  Future<GroupSourceResolution> resolveAllSourcesForGroup(MediaIdentity identity) async {
    if (!identity.isSearchable) {
      return (items: const <MediaItem>[], coverage: SourceCoverageState.none);
    }

    final servers = serversFor();
    final eligible = servers.where((s) => isIdentityEligibleBackend(s.backend)).toList();
    final expectedIds = {for (final s in eligible) s.serverId.toString()};

    final cacheKey = _identityCacheKey(identity);
    final cached = await _readCache(cacheKey, eligible, expectedIds);
    if (cached != null) return cached;

    final items = <MediaItem>[];
    final checked = <String>{};
    final uncheckedReasons = <String, UncheckedSourceReason>{
      for (final s in eligible.where((s) => !s.online))
        s.serverId.toString(): s.hasAuthError ? UncheckedSourceReason.authError : UncheckedSourceReason.offline,
    };

    final reachable = eligible.where((s) => s.online && s.client != null).toList();
    await fanOutFindAllByIdentity(
      servers: [for (final s in reachable) (serverId: s.serverId, client: s.client, online: s.online)],
      identity: identity,
      maxConcurrent: maxConcurrent,
      onBatch: (batch) {
        for (final result in batch) {
          final id = result.serverId.toString();
          if (result.ok) {
            checked.add(id);
            items.addAll(result.matches);
          } else {
            uncheckedReasons[id] = UncheckedSourceReason.lookupFailed;
          }
        }
        return false; // never stop early — every eligible server gets asked
      },
    );

    final coverage = SourceCoverageState(
      expectedServerIds: expectedIds,
      checkedServerIds: checked,
      uncheckedReasons: uncheckedReasons,
    );

    await _writeCache(cacheKey, items: items, coverage: coverage);
    return (items: items, coverage: coverage);
  }

  /// Drop every cached answer, for every profile. Called when server
  /// topology, reachability or a title's metadata changes — the cache table
  /// offers no cheaper prefix than the whole namespace, and wiping too much
  /// only costs a re-resolve, while keeping a stale miss costs a wrong
  /// "no sources" on a title one of them now has.
  Future<void> invalidate() async => cache.deleteForServer(cacheServerId);

  String _endpointFor(String key) => 'match/$profileId/$key';

  Future<GroupSourceResolution?> _readCache(
    String key,
    List<EligibleSourceServer> eligible,
    Set<String> expectedIds,
  ) async {
    final Map<String, dynamic>? row;
    try {
      row = await cache.get(cacheServerId, _endpointFor(key));
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
        coverage: SourceCoverageState(expectedServerIds: expectedIds, checkedServerIds: checkedIds, uncheckedReasons: uncheckedReasons),
      );
    }

    // Only a complete negative was ever written, so reaching here means the
    // miss was worth keeping.
    if (age > negativeTtl) return null;
    return (items: const <MediaItem>[], coverage: SourceCoverageState.complete(expectedIds));
  }

  Future<void> _writeCache(String key, {required List<MediaItem> items, required SourceCoverageState coverage}) async {
    // An incomplete negative says nothing durable: the server that did not
    // answer may be exactly the one holding the title.
    if (items.isEmpty && !coverage.isComplete) return;

    try {
      await cache.put(cacheServerId, _endpointFor(key), {
        'checkedAtMs': _now.millisecondsSinceEpoch,
        if (items.isNotEmpty) ...{
          'items': [for (final item in items) item.toJson()],
          'checkedServerIds': coverage.checkedServerIds.toList(),
          'uncheckedReasons': {for (final e in coverage.uncheckedReasons.entries) e.key: e.value.name},
        },
      });
    } catch (e) {
      appLogger.d('Source-all-resolver cache write failed', error: e);
    }
  }
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
