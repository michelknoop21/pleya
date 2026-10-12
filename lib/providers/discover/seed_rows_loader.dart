import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../services/recommendations/recommendation_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';

/// A seed and how it was earned. [completed] picks the title: a finished
/// title reads "Because you watched X", one still in progress "Because you're
/// watching X".
typedef _Seed = ({MediaItem item, bool completed});

/// Builds the "Because you watched X" rows for Home: picks the seeds, then
/// pairs each with its related hub on the owning server. The caller owns
/// generation checks and what ends up on screen; the only state is the short
/// memory of seeds whose item the server no longer has.
class SeedRowsLoader {
  SeedRowsLoader({
    required this._recommendations,
    required this._clientFor,
    @visibleForTesting DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final RecommendationService? _recommendations;
  final MediaServerClient? Function(ServerId serverId) _clientFor;
  final DateTime Function() _now;

  /// Seeds whose item the server answered "not there" for, and when. The log
  /// keeps a title after it is deleted from the library, so the same dead seed
  /// would otherwise cost one failed request and one of the six places on
  /// every Home refresh. Only a completed answer is remembered: a request that
  /// failed (offline, timeout) is tried again next time.
  final Map<String, DateTime> _goneSince = {};

  /// Long enough to span many refreshes, short enough that a title restored to
  /// the library is picked up again within the session.
  static const _goneMemory = Duration(minutes: 30);

  Set<String> _currentlyGone() {
    final cutoff = _now().subtract(_goneMemory);
    _goneSince.removeWhere((_, since) => since.isBefore(cutoff));
    return _goneSince.keys.toSet();
  }

  /// Up to three seed rows from [clients], which the caller has already
  /// narrowed to sources that answer related hubs. Seeds come from this
  /// profile's own interaction log first; when that yields fewer than three,
  /// what the servers report as recently watched tops them up to three, one
  /// seed per title. [candidates] are the unwatched related titles of seeds
  /// four to six: free input for the personalized rows, never a row of their
  /// own. Their related hubs load alongside the rows, at most three extra
  /// calls, and a failing one only costs its own seed.
  Future<({List<MediaHub> rows, List<MediaItem> candidates})> load({
    required List<MediaServerClient> clients,
    required Set<String> alreadyShown,
  }) async {
    final seeds = await _seedsFromLog(clients);
    if (seeds.length < 3) {
      final used = {for (final seed in seeds) _identity(seed.item)};
      for (final seed in await _seedsFromServers(clients)) {
        if (seeds.length >= 3) break;
        if (used.add(_identity(seed.item))) seeds.add(seed);
      }
    }
    final (rows, extraRelated) = await (
      Future.wait([
        for (final seed in seeds.take(3)) _relatedRowForSeed(seed, alreadyShown).catchError((Object _) => null),
      ]),
      Future.wait([
        for (final seed in seeds.skip(3).take(3)) _relatedHubs(seed).catchError((Object _) => const <MediaHub>[]),
      ]),
    ).wait;
    return (
      rows: [for (final row in rows) ?row],
      candidates: [
        for (final hubs in extraRelated)
          for (final hub in hubs)
            for (final item in hub.items)
              if (!item.isWatched) item,
      ],
    );
  }

  /// Seeds from this profile's own interaction log, newest first, up to six:
  /// the first three build rows, the rest are for the candidate layer. A key
  /// that belongs to no eligible client is skipped without a fetch; the
  /// fetches run in parallel and keep the log's order.
  Future<List<_Seed>> _seedsFromLog(List<MediaServerClient> clients) async {
    final service = _recommendations;
    if (service == null) return [];
    final byServer = {for (final c in clients) c.serverId: c};
    // Narrowed in the query, so a key on a source that cannot seed never
    // takes one of the six places.
    // The places a remembered dead seed would have taken go to the next ones.
    final gone = _currentlyGone();
    final seeds = (await service.recentSeeds(
      limit: 6 + gone.length,
      serverIds: {for (final id in byServer.keys) id.toString()},
    )).where((seed) => !gone.contains(seed.globalKey)).take(6).toList();
    // On a shared Jellyfin connection the server's watched state is the other
    // profile's too, so it may not rename a row; unknown counts as shared.
    Set<String>? shared;
    try {
      shared = await service.sharedHistoryServerIds();
    } catch (_) {}
    bool isShared(ServerId id) => shared?.contains(id.toString()) ?? true;
    final resolved = await Future.wait([for (final seed in seeds) _resolve(seed, byServer, isShared)]);
    // The same title on two servers is one seed, the newest; same identity
    // as the server path.
    final usedIdentities = <String>{};
    return [
      for (final seed in resolved)
        if (seed != null && usedIdentities.add(_identity(seed.item))) seed,
    ];
  }

  Future<_Seed?> _resolve(
    RecommendationSeed seed,
    Map<ServerId, MediaServerClient> byServer,
    bool Function(ServerId) isShared,
  ) async {
    final key = parseGlobalKey(seed.globalKey);
    final client = key == null ? null : byServer[key.serverId];
    if (key == null || client == null) return null;
    final MediaItem? item;
    try {
      item = await client.fetchItem(key.ratingKey);
    } catch (_) {
      return null;
    }
    if (item == null) {
      // A completed "no such item": the server dropped it. Not asked again
      // until the memory runs out.
      _goneSince[seed.globalKey] = _now();
      appLogger.d('SeedRowsLoader: seed ${seed.globalKey} is gone from its server, skipped for a while');
      return null;
    }
    if (item.title == null) return null;
    // A series is still being watched until every episode is seen, whatever
    // the newest row says: finishing episode four of ten is not finishing it.
    // A film finished elsewhere after a partial here is finished, unless
    // "elsewhere" may be another profile on a shared connection.
    final watchedElsewhere = item.isWatched && !isShared(key.serverId);
    return (item: item, completed: item.kind == MediaKind.show ? item.isWatched : seed.completed || watchedElsewhere);
  }

  /// One seed per title and kind: a film and a series that share a name are
  /// two seeds. An episode counts as its series; any other item keeps its
  /// own title.
  static String _identity(MediaItem item) {
    final (kind, title) = item.kind == MediaKind.episode
        ? (MediaKind.show, item.grandparentTitle ?? item.title)
        : (item.kind, item.title);
    return '${kind.name}:${(title ?? item.id).toLowerCase()}';
  }

  /// The pre-log path: what each server itself says was watched last. Tops
  /// up a thin log, so a fresh profile on an old server still gets its rows
  /// and plays in other apps still seed. A server whose history another
  /// profile shares is left out (DEC-062, DEC-132); when that cannot be told,
  /// the whole path is (fail closed).
  Future<List<_Seed>> _seedsFromServers(List<MediaServerClient> clients) async {
    final Set<String> shared;
    try {
      shared = await _recommendations?.sharedHistoryServerIds() ?? const {};
    } catch (e) {
      appLogger.w('SeedRowsLoader: sharing check failed, no server seeds', error: e);
      return const [];
    }
    final recents = await Future.wait([
      for (final client in clients)
        if (!shared.contains(client.serverId.toString()))
          client.fetchRecentlyWatched(limit: 5).catchError((Object _) => const <MediaItem>[]),
    ]);
    // Most-recent-first, then keep up to 3 distinct show/movie seeds so the
    // rows don't all come from the same binge.
    final merged = recents.expand((items) => items).toList()
      ..sort((a, b) => b.recencySortKey.compareTo(a.recencySortKey));
    final seeds = <_Seed>[];
    final usedIdentities = <String>{};
    for (final item in merged) {
      if (item.serverId == null || item.title == null) continue;
      if (!usedIdentities.add(_identity(item))) continue;
      seeds.add((item: item, completed: true));
      if (seeds.length >= 3) break;
    }
    return seeds;
  }

  Future<List<MediaHub>> _relatedHubs(_Seed seed) async {
    final serverId = seed.item.serverId;
    final client = serverId == null ? null : _clientFor(ServerId(serverId));
    return client?.fetchRelatedHubs(seed.item.id) ?? const <MediaHub>[];
  }

  /// Resolves a single seed row from the owning server's related hub, or null
  /// when nothing usable comes back. Finished titles are left out.
  Future<MediaHub?> _relatedRowForSeed(_Seed seed, Set<String> alreadyShown) async {
    final serverId = seed.item.serverId;
    final seedTitle = seed.item.title;
    if (serverId == null || seedTitle == null) return null;
    final client = _clientFor(ServerId(serverId));
    if (client == null) return null;
    final relatedHubs = await client.fetchRelatedHubs(seed.item.id);
    for (final hub in relatedHubs) {
      final items = hub.items
          .where(
            (item) =>
                item.globalKey != seed.item.globalKey && !item.isWatched && !alreadyShown.contains(item.globalKey),
          )
          .toList();
      if (items.isEmpty) continue;
      return hub.copyWith(
        identifier: 'home.becauseyouwatched',
        title: seed.completed
            ? t.discover.becauseYouWatched(title: seedTitle)
            : t.discover.becauseYouAreWatching(title: seedTitle),
        items: items,
      );
    }
    return null;
  }
}
