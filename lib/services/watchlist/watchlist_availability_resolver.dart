import 'dart:async';

import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_identity.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/watchlist_entry.dart';
import '../../utils/app_logger.dart';
import '../api_cache.dart';
import '../unified_catalog/source_resolver.dart' show fanOutFindAllByIdentity;

/// Where a title turned out to live, and how sure we are that the answer is
/// the whole story.
typedef WatchlistMatchResult = ({MediaItem? match, bool coverageComplete});

/// One server the resolver is allowed to ask.
///
/// [online] is separate from the client on purpose. A server that belongs to
/// the profile but is offline right now still counts in the denominator, which
/// is the whole reason `coverageComplete` can be false.
typedef EligibleServer = ({ServerId serverId, MediaBackend backend, MediaServerClient? client, bool online});

/// Looks up watchlist titles on the servers of the active profile.
///
/// **Coverage is derived from expectation, not from what happened to be
/// online.** Fanning out over the reachable clients only would make
/// `coverageComplete` meaningless: an offline server is not in that set, so
/// coverage would always be complete and a title sitting on the one server
/// that is down would read as "not in your libraries" and invite a request for
/// content the user already owns.
///
/// So the denominator is every server of this profile whose client can answer
/// a `findByIdentity` at all, and the numerator is those that actually did:
///
/// ```
/// eligible = servers of the active profile whose client can findByIdentity
/// checked  = eligible servers that answered without error
/// coverageComplete = checked == eligible
/// ```
///
/// Offline, timeout and transport error all count as not checked. A local
/// folder, a Pleya Share and a Pleya Server cannot match on catalogue identity
/// at all, so they are not eligible: they stay out of the denominator instead
/// of pretending to have looked.
class WatchlistAvailabilityResolver {
  WatchlistAvailabilityResolver({
    required this.profileId,
    required this.serversFor,
    required this.cache,
    this.maxConcurrent = 4,
    this.now,
  });

  /// The profile these answers belong to. Part of every cache key, because a
  /// match is only meaningful for the servers one profile can reach.
  final String profileId;

  /// Every server of the active profile, in a deterministic order.
  final List<EligibleServer> Function() serversFor;

  final ApiCache cache;

  /// Ceiling on parallel lookups. Plex Discover's rate limits are unknown, and
  /// a 300-title list would otherwise open 300 sockets at once.
  final int maxConcurrent;

  /// Injectable clock, so the TTL tests do not have to sleep.
  final DateTime Function()? now;

  /// A hit stays good for a week. It is still revalidated on read: the server
  /// it names has to still belong to this profile and be online.
  static const Duration positiveTtl = Duration(days: 7);

  /// A miss is only worth six hours, and only when coverage was complete.
  static const Duration negativeTtl = Duration(hours: 6);

  static final ServerId cacheServerId = ServerId('watchlist-availability');

  DateTime get _now => (now ?? DateTime.now)();

  /// Resolve one title.
  ///
  /// Returns the matching server item plus whether every eligible server was
  /// reached. A caller that gets `coverageComplete: false` with no match knows
  /// only that the servers it could reach do not have it.
  Future<WatchlistMatchResult> resolve(WatchlistEntry entry) async {
    final identity = identityOf(entry);
    if (!identity.isSearchable) return (match: null, coverageComplete: true);

    final servers = serversFor();
    final eligible = servers.where(_isEligible).toList();

    final cached = await _readCache(entry.key, eligible);
    if (cached != null) return cached;

    final reachable = eligible.where((s) => s.online && s.client != null).toList();
    MediaItem? match;
    var checked = 0;

    // Delegates the actual per-server dispatch to the same primitive the
    // all-source resolver uses (hoofdstuk 4.3: one identity pipeline, not a
    // second ad hoc resolver) — findAllByIdentity per server, in bounded,
    // deterministically-ordered batches. This resolver's own contract only
    // needs the first match, so it stops the shared fan-out as soon as one
    // turns up, in the same deterministic server order as before.
    await fanOutFindAllByIdentity(
      servers: [for (final s in reachable) (serverId: s.serverId, client: s.client, online: s.online)],
      identity: identity,
      maxConcurrent: maxConcurrent,
      onBatch: (batch) {
        for (final result in batch) {
          if (!result.ok) continue;
          checked++;
          // First match in the deterministic server order wins, so the same
          // watchlist resolves to the same server on every device.
          match ??= result.matches.firstOrNull;
        }
        return match != null;
      },
    );

    // Everything that was not reached is a hole in the coverage, whether it
    // was offline before the fan-out or errored during it.
    final complete = checked == eligible.length;
    await _writeCache(entry.key, match: match, complete: complete);
    return (match: match, coverageComplete: complete);
  }

  /// The identity to look up for [entry]: guid first, then external ids, with
  /// title and year as the last resort.
  static MediaIdentity identityOf(WatchlistEntry entry) => MediaIdentity(
    guid: entry.guid,
    externalIds: entry.externalIds,
    title: entry.item.title,
    year: entry.item.year,
    kind: entry.kind,
  );

  /// A server can be asked when its backend knows catalogue identity at all.
  ///
  /// A local folder and a Pleya Share have no guid, no external ids and no
  /// search that could answer the question, so they never count. Reading the
  /// backend off the record rather than off the client matters: an offline
  /// server has no client, and it still has to count in the denominator.
  static bool _isEligible(EligibleServer server) => switch (server.backend) {
    MediaBackend.plex || MediaBackend.jellyfin => true,
    // A local folder and a Pleya Share have no guid and no external ids.
    // Neither does a Pleya Server: `external_ids` is PS-7, so `findByIdentity`
    // can only ever answer null there. Counting it in the denominator would
    // make `coverageComplete` mean "asked a server that structurally cannot
    // answer", which is the exact confusion this predicate exists to prevent.
    // It becomes eligible in the phase that gives it identity, not before.
    MediaBackend.local || MediaBackend.pleyaServer => false,
  };

  /// Drop every cached answer, for every profile.
  ///
  /// Called when the server topology or reachability changes. Both invalidate
  /// a negative answer, and the cache table offers no cheaper prefix than the
  /// whole namespace. Wiping too much only costs a re-resolve; keeping a stale
  /// miss costs a wrong "not available" on a title the user owns.
  Future<void> invalidate() async {
    await cache.deleteForServer(cacheServerId);
  }

  String _endpointFor(String key) => 'match/$profileId/$key';

  /// A warm hit is validated, never trusted blindly.
  ///
  /// A cached match names a server. If that server has since left the profile
  /// or is offline, the answer is worthless and the resolve runs again.
  Future<WatchlistMatchResult?> _readCache(String key, List<EligibleServer> eligible) async {
    final Map<String, dynamic>? row;
    try {
      row = await cache.get(cacheServerId, _endpointFor(key));
    } catch (e) {
      appLogger.d('Watchlist availability cache read failed', error: e);
      return null;
    }
    if (row == null) return null;

    final checkedAtMs = row['checkedAtMs'];
    if (checkedAtMs is! int) return null;
    final age = _now.difference(DateTime.fromMillisecondsSinceEpoch(checkedAtMs));

    final serverId = row['serverId'];
    if (serverId is String && serverId.isNotEmpty) {
      if (age > positiveTtl) return null;
      final server = eligible.where((s) => s.serverId == serverId).firstOrNull;
      if (server == null || !server.online || server.client == null) return null;
      final itemJson = row['item'];
      if (itemJson is! Map<String, dynamic>) return null;
      try {
        return (match: MediaItem.fromJson(itemJson), coverageComplete: true);
      } catch (e) {
        appLogger.d('Watchlist availability cache row unreadable', error: e);
        return null;
      }
    }

    // Only a complete negative was written, so reaching here means the miss
    // was worth keeping. It still expires quickly: the missing title may have
    // been added to a library five minutes ago.
    if (age > negativeTtl) return null;
    return (match: null, coverageComplete: true);
  }

  Future<void> _writeCache(String key, {required MediaItem? match, required bool complete}) async {
    // An incomplete negative says nothing durable: the server that did not
    // answer may be exactly the one holding the title. Writing it would turn a
    // temporary outage into six hours of wrong answers.
    if (match == null && !complete) return;

    try {
      await cache.put(cacheServerId, _endpointFor(key), {
        'checkedAtMs': _now.millisecondsSinceEpoch,
        if (match?.serverId != null) ...{'serverId': match!.serverId, 'item': match.toJson()},
      });
    } catch (e) {
      appLogger.d('Watchlist availability cache write failed', error: e);
    }
  }
}
