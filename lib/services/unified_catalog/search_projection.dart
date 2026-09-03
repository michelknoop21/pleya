/// Search result projection (hoofdstuk 16.1/16.2 of
/// docs/tvos-unified-experience.md): "Dune (2021) — 3 bronnen", never
/// `Dune - NAS` / `Dune - Plex Familie` / `Dune - Jellyfin`.
///
/// Films, series and exactly identifiable episodes go through the same
/// central identity pipeline as every other unified surface (hoofdstuk 4.3),
/// so one logical result appears once with its concrete sources preserved
/// for activation. Collections and playlists stay source-concrete —
/// hoofdstuk 16.1 says so outright, and there is no identity rule for them
/// to merge on anyway.
///
/// The bias throughout is the one hoofdstuk 11.4/11.6 already encodes: a
/// false merge is worse than a false negative. Two rows a viewer can tell
/// apart cost a scroll; one row that quietly hides a different film costs
/// them the film.
library;

import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'grouping_service.dart';
import 'identity_resolver.dart';

/// Hoofdstuk 16.1's result sections, each kept separate: a viewer scanning
/// for a series should not have to read past episodes of it.
class UnifiedSearchProjection {
  /// Unified: one entry per logical title, sources preserved.
  final List<UnifiedMediaGroup> movies;
  final List<UnifiedMediaGroup> shows;
  final List<UnifiedMediaGroup> episodes;

  /// Source-concrete (hoofdstuk 16.1), server context shown where needed.
  final List<MediaItem> collections;
  final List<MediaItem> playlists;
  final List<MediaItem> people;

  /// Anything the backends returned that hoofdstuk 16.1 does not name —
  /// music, clips, folders. Kept rather than dropped: a result the servers
  /// found and Pleya silently discards is worse than a section the TV shell
  /// chooses not to render.
  final List<MediaItem> other;

  const UnifiedSearchProjection({
    this.movies = const [],
    this.shows = const [],
    this.episodes = const [],
    this.collections = const [],
    this.playlists = const [],
    this.people = const [],
    this.other = const [],
  });

  bool get isEmpty =>
      movies.isEmpty &&
      shows.isEmpty &&
      episodes.isEmpty &&
      collections.isEmpty &&
      playlists.isEmpty &&
      people.isEmpty &&
      other.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

/// Projects a flat, already-ranked cross-server result list (the shape
/// `data_aggregation_service.dart`'s `searchAcrossServers` returns) into
/// hoofdstuk 16.1's sections.
///
/// Relevance order survives: `groupUnifiedMediaSources` places a group at
/// the position of its first contributing candidate, so the ranking the
/// caller already applied still decides what a viewer sees first.
///
/// [fetchExternalIds] has the same shape [UnifiedIdentityResolver] takes
/// everywhere else, so this function does no network work of its own and a
/// test drives it with a fake. A callback that throws for one server
/// degrades that server's items to guid-only evidence rather than failing
/// the search.
///
/// [people] is passed in separately because the neutral model has no person
/// kind: nothing a backend client returns today lands in that section, and
/// inventing a `MediaKind.person` to route it is a model change this
/// projection has no business making.
Future<UnifiedSearchProjection> searchProjection(
  List<MediaItem> results, {
  required Future<ExternalIds> Function(String serverId, String targetId) fetchExternalIds,
  List<MediaItem> people = const [],
  int maxConcurrentFetches = 4,
}) async {
  if (results.isEmpty && people.isEmpty) return const UnifiedSearchProjection();

  final collections = <MediaItem>[];
  final playlists = <MediaItem>[];
  final other = <MediaItem>[];
  final unifiable = <MediaItem>[];

  for (final item in results) {
    switch (item.kind) {
      case MediaKind.movie:
      case MediaKind.show:
      case MediaKind.episode:
        unifiable.add(item);
      case MediaKind.collection:
        collections.add(item);
      case MediaKind.playlist:
        playlists.add(item);
      default:
        other.add(item);
    }
  }

  if (unifiable.isEmpty) {
    return UnifiedSearchProjection(collections: collections, playlists: playlists, people: people, other: other);
  }

  // One resolution pass over every unifiable result, not one per section:
  // duplicate-bucket detection and the per-(server, target) fetch cache both
  // live inside a single `resolveEvidence` call, and a bucket key already
  // carries its granularity, so a film and a series of the same name never
  // share one.
  final resolver = UnifiedIdentityResolver(
    fetchExternalIds: fetchExternalIds,
    maxConcurrentFetches: maxConcurrentFetches,
  );
  final evidence = await resolver.resolveEvidence([
    for (final item in unifiable)
      ResolvableItem(
        item: item,
        identity: canonicalIdentityOf(item),
        scope: (canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque()).granularity.name,
        externalIdTarget: _externalIdTargetFor(item),
      ),
  ]);

  final byKind = <MediaKind, List<GroupingCandidate>>{};
  for (var i = 0; i < unifiable.length; i++) {
    final item = unifiable[i];
    final serverId = item.serverId;
    // No server means no activation route (hoofdstuk 4.4) and no source key.
    // Drop it with a warning rather than throwing away the whole result set.
    if (serverId == null || serverId.isEmpty) {
      appLogger.w('Search projection: dropping result ${item.id} with no resolvable serverId');
      continue;
    }
    byKind
        .putIfAbsent(item.kind, () => <GroupingCandidate>[])
        .add(GroupingCandidate(source: UnifiedMediaSource.fromItem(item), evidence: evidence[i]));
  }

  return UnifiedSearchProjection(
    movies: groupUnifiedMediaSources(byKind[MediaKind.movie] ?? const []),
    shows: groupUnifiedMediaSources(byKind[MediaKind.show] ?? const []),
    // hoofdstuk 16.1 unifies only *exactly identifiable* episodes, so the
    // weak title+year fallback is off rather than merely inapplicable. It
    // would not fire anyway — an episode carries no year, and hoofdstuk
    // 11.6 requires both years known and equal — but saying so in the call
    // keeps the intent readable instead of leaving it to a coincidence two
    // files away.
    episodes: groupUnifiedMediaSources(byKind[MediaKind.episode] ?? const [], allowWeakFallback: false),
    collections: collections,
    playlists: playlists,
    people: people,
    other: other,
  );
}

/// Which id to enrich, and — for episodes — deliberately none.
///
/// Asked for an episode's external ids, a backend commonly answers with the
/// *show's* tmdb/tvdb id. Two different episodes of one series would then
/// both carry `episode:tmdb:<show id>` and merge into one result: a false
/// merge built on evidence that never identified an episode. An episode's
/// own stable guid is episode-scoped (see `guidTokens`) and remains its only
/// strong evidence, which is exactly hoofdstuk 16.1's "exact
/// identificeerbare afleveringen".
ExternalIdTarget? _externalIdTargetFor(MediaItem item) {
  final serverId = item.serverId;
  if (serverId == null || serverId.isEmpty) return null;
  if (item.kind == MediaKind.episode) return null;
  return (serverId: serverId, targetId: item.id);
}
