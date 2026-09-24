import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../services/recommendations/recommendation_service.dart';
import '../../utils/global_key_utils.dart';

/// A seed and how it was earned. [completed] picks the title: a finished
/// title reads "Because you watched X", one still in progress "Because you're
/// watching X".
typedef _Seed = ({MediaItem item, bool completed});

/// Builds the "Because you watched X" rows for Home: picks the seeds, then
/// pairs each with its related hub on the owning server. Holds no state; the
/// caller owns generation checks and what ends up on screen.
class SeedRowsLoader {
  SeedRowsLoader({required this._recommendations, required this._clientFor});

  final RecommendationService? _recommendations;
  final MediaServerClient? Function(ServerId serverId) _clientFor;

  /// Up to three seed rows from [clients], which the caller has already
  /// narrowed to sources that answer related hubs. Seeds come from this
  /// profile's own interaction log; when that yields nothing, from what the
  /// servers report as recently watched, which is also the path when no log
  /// seed resolves. [candidates] is empty for now.
  Future<({List<MediaHub> rows, List<MediaItem> candidates})> load({
    required List<MediaServerClient> clients,
    required Set<String> alreadyShown,
  }) async {
    var seeds = await _seedsFromLog(clients);
    if (seeds.isEmpty) seeds = await _seedsFromServers(clients);
    final rows = seeds.isEmpty
        ? const <MediaHub?>[]
        : await Future.wait([
            for (final seed in seeds.take(3)) _relatedRowForSeed(seed, alreadyShown).catchError((Object _) => null),
          ]);
    return (rows: [for (final row in rows) ?row], candidates: const <MediaItem>[]);
  }

  /// Seeds from this profile's own interaction log, newest first, up to six:
  /// the first three build rows, the rest are for the candidate layer. A key
  /// that belongs to no eligible client is skipped without a fetch; the
  /// fetches run in parallel and keep the log's order.
  Future<List<_Seed>> _seedsFromLog(List<MediaServerClient> clients) async {
    final service = _recommendations;
    if (service == null) return const [];
    final byServer = {for (final c in clients) c.serverId: c};
    final seeds = await service.recentSeeds(limit: 6);
    final resolved = await Future.wait([for (final seed in seeds) _resolve(seed, byServer)]);
    // The same title on two servers is one seed, the newest; same identity
    // as the server path.
    final usedIdentities = <String>{};
    return [
      for (final seed in resolved)
        if (seed != null && usedIdentities.add(_identity(seed.item))) seed,
    ];
  }

  Future<_Seed?> _resolve(RecommendationSeed seed, Map<ServerId, MediaServerClient> byServer) async {
    final key = parseGlobalKey(seed.globalKey);
    final client = key == null ? null : byServer[key.serverId];
    if (key == null || client == null) return null;
    final item = await client.fetchItem(key.ratingKey).catchError((Object _) => null);
    if (item == null || item.title == null) return null;
    // A series is still being watched until every episode is seen, whatever
    // the newest row says: finishing episode four of ten is not finishing it.
    return (item: item, completed: item.kind == MediaKind.show ? item.isWatched : seed.completed);
  }

  static String _identity(MediaItem item) => (item.grandparentTitle ?? item.title ?? item.id).toLowerCase();

  /// The pre-log path: what each server itself says was watched last. Kept as
  /// the cold-start fallback so a fresh profile on an old server still gets
  /// its rows.
  Future<List<_Seed>> _seedsFromServers(List<MediaServerClient> clients) async {
    final recents = await Future.wait([
      for (final client in clients) client.fetchRecentlyWatched(limit: 5).catchError((Object _) => const <MediaItem>[]),
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
