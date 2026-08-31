/// The one place `MediaHub`/`MediaItem` becomes
/// [UnifiedMediaHub]/[UnifiedMediaGroup] (hoofdstuk 17 and 27 fase 6 of
/// docs/tvos-unified-experience.md, DEC-064).
///
/// Everything Home, the Films landing and the Series landing show comes out
/// of here. A widget never builds a discovery row from the complete
/// catalogus itself — that would be a second projection architecture beside
/// this one, and avoiding it is the reason fase 6 exists as its own phase.
///
/// Headless on purpose, like `catalog_service.dart`: this service takes a
/// [fetchExternalIds] callback rather than reaching for a client registry,
/// so its tests exercise the projection rules with a fake and no widget
/// tree. It also does no fetching of its own — it projects exactly the
/// bounded input it is handed, and never reaches into `UnifiedCatalogs` or
/// the fase-5 catalogue to fabricate a row out of the full library.
///
/// Visibility filtering is upstream (hoofdstuk 22: bronnen worden *vóór*
/// grouping gefilterd op actief profiel, zichtbare servers en zichtbare
/// libraries). This file never widens what it was given: no title can leave
/// a projection that did not enter it.
library;

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../media/unified/unified_media_source.dart';
import '../../providers/home_layout_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'grouping_service.dart';
import 'identity_resolver.dart';

class HomeProjectionService {
  HomeProjectionService({required this.fetchExternalIds, this.maxConcurrentFetches = 4});

  /// Same shape `data_aggregation_service.dart` hands
  /// [UnifiedIdentityResolver]. A server that is offline or failing does not
  /// need to be filtered out beforehand: a throwing callback degrades that
  /// one item to guid-only evidence (hoofdstuk 26 edge case C20), which is
  /// exactly what "one bad server never empties a row" means at this layer.
  final Future<ExternalIds> Function(String serverId, String targetId) fetchExternalIds;

  final int maxConcurrentFetches;

  /// Projects [hubs] into discovery rows, in stable input order: a row
  /// appears at the position of the first [MediaHub] that fed it.
  ///
  /// Rows that project to no groups at all are dropped — an empty carousel
  /// is not a row. That is not the partial-failure path: a hub whose healthy
  /// server still returned items keeps every one of those groups and is
  /// merely marked [UnifiedMediaHub.isPartial], per hoofdstuk 21.4.
  ///
  /// [failedServerIds] names the servers the caller knows did not answer.
  /// The projection cannot derive this — a server that failed contributed no
  /// hub, so it left no trace in [hubs] to notice.
  Future<List<UnifiedMediaHub>> projectHubs(List<MediaHub> hubs, {Set<String> failedServerIds = const {}}) async {
    if (hubs.isEmpty) return const [];

    final keys = _effectiveKeys(hubs);

    // Bucket by key, keeping first-appearance order so the output follows
    // the caller's input order rather than map iteration order.
    final bucketOrder = <String>[];
    final buckets = <String, List<int>>{};
    for (var i = 0; i < hubs.length; i++) {
      final value = keys[i].value;
      final bucket = buckets.putIfAbsent(value, () {
        bucketOrder.add(value);
        return <int>[];
      });
      bucket.add(i);
    }

    final projected = <UnifiedMediaHub>[];
    for (final value in bucketOrder) {
      final members = buckets[value]!;
      final key = keys[members.first];
      final contributors = [for (final i in members) hubs[i]]..sort(_compareHubRank);

      final groups = await _projectItems(_interleave(contributors), allowWeakFallback: true);
      if (groups.isEmpty) continue;

      final isServerScoped = key.serverScope != null;
      projected.add(
        UnifiedMediaHub.fromKey(
          key: key,
          title: contributors.first.title,
          kind: UnifiedHubKind.merged([for (final hub in contributors) UnifiedHubKind.fromHubType(hub.type)]),
          groups: groups,
          // A server-scoped row's own server plainly answered — it is the
          // reason the row exists. Only a global row can be missing a
          // contribution it should have had.
          isPartial: !isServerScoped && failedServerIds.isNotEmpty,
          contributingRowIds: [for (final hub in contributors) homeRowId(hub)],
          serverName: isServerScoped ? contributors.first.serverName : null,
        ),
      );
    }
    return projected;
  }

  /// Projects the Continue Watching row (hoofdstuk 13.3), keeping every
  /// contributing source instead of collapsing each title to one
  /// representative [MediaItem].
  ///
  /// The identity contract is exactly
  /// `data_aggregation_service.dart`'s `_deduplicateContinueWatching`, down
  /// to `allowWeakFallback: false`: Continue Watching has only ever merged on
  /// shared external ids/guid, never on title+year, and this projection is
  /// not the place to change what viewers see merged on their Home screen.
  /// What differs is only the output — a [UnifiedMediaGroup] per card, so the
  /// source picker and the hoofdstuk 13.4 group contract have the concrete
  /// sources to work with.
  ///
  /// [title] is passed in already resolved; this layer has no locale.
  Future<UnifiedMediaHub> projectContinueWatching(
    List<MediaItem> onDeck, {
    required String title,
    Set<String> failedServerIds = const {},
    String slug = 'continueWatching',
  }) async {
    final groups = await _projectContinueWatchingGroups(onDeck);
    return UnifiedMediaHub.synthesized(
      slug: slug,
      title: title,
      kind: UnifiedHubKind.merged([for (final group in groups) _hubKindOfItem(group.representativeSource.item)]),
      groups: groups,
      isPartial: failedServerIds.isNotEmpty,
    );
  }

  // -- Hub keys ------------------------------------------------------------

  /// The key each hub actually merges on.
  ///
  /// A key that one single server contributes twice is ambiguous: the
  /// backend is telling us these are two rows and distinguishing them by a
  /// reason [UnifiedHubKey] cannot read (several "Because you watched" rows
  /// share one identifier — see `homeRowId` in `home_layout_provider.dart`).
  /// Every hub under such a key is narrowed to its own backend row instead,
  /// so the ambiguity yields two honest rows rather than one fused one. Same
  /// rule `grouping_service.dart` applies to items: ambiguity never merges.
  List<UnifiedHubKey> _effectiveKeys(List<MediaHub> hubs) {
    final keys = [for (final hub in hubs) UnifiedHubKey.forHub(hub)];

    final perKeyPerServer = <String, Map<String, int>>{};
    for (var i = 0; i < hubs.length; i++) {
      final byServer = perKeyPerServer.putIfAbsent(keys[i].value, () => <String, int>{});
      final serverId = hubs[i].serverId ?? '';
      byServer[serverId] = (byServer[serverId] ?? 0) + 1;
    }
    final ambiguous = {
      for (final entry in perKeyPerServer.entries)
        if (entry.value.values.any((count) => count > 1)) entry.key,
    };
    if (ambiguous.isEmpty) return keys;

    return [
      for (var i = 0; i < hubs.length; i++)
        ambiguous.contains(keys[i].value)
            ? keys[i].narrowedTo(serverId: hubs[i].serverId, backendRowKey: hubs[i].id)
            : keys[i],
    ];
  }

  /// Deterministic contributor order (hoofdstuk 4.7's tie-break tail, and
  /// hoofdstuk 17.3's "sourcevolgorde is deterministic"). Explicitly not the
  /// order the servers answered in: whichever server replied first must
  /// never decide which title leads a row.
  static int _compareHubRank(MediaHub a, MediaHub b) {
    final nameCmp = (a.serverName ?? '').compareTo(b.serverName ?? '');
    if (nameCmp != 0) return nameCmp;
    final idCmp = (a.serverId ?? '').compareTo(b.serverId ?? '');
    if (idCmp != 0) return idCmp;
    return a.id.compareTo(b.id);
  }

  /// Fair interleave over already-ranked [contributors] (hoofdstuk 17.3).
  ///
  /// Round-robin, one item per contributor per pass. Concatenating and
  /// re-sorting on a backend score is the failure mode this replaces: Plex,
  /// Jellyfin and the local recommendation engine do not produce comparable
  /// numbers, so a server with a generous rating scale would take the whole
  /// row.
  static List<MediaItem> _interleave(List<MediaHub> contributors) {
    if (contributors.length == 1) return contributors.single.items;
    var longest = 0;
    for (final hub in contributors) {
      if (hub.items.length > longest) longest = hub.items.length;
    }
    final interleaved = <MediaItem>[];
    for (var slot = 0; slot < longest; slot++) {
      for (final hub in contributors) {
        if (slot < hub.items.length) interleaved.add(hub.items[slot]);
      }
    }
    return interleaved;
  }

  // -- Shared identity pipeline -------------------------------------------

  /// Runs [items] through the central identity pipeline (hoofdstuk 4.3):
  /// [UnifiedIdentityResolver] for evidence, [groupUnifiedMediaSources] for
  /// the grouping itself. No second dedup implementation lives here.
  ///
  /// Dedup is scoped to this one call, and every caller passes exactly one
  /// row's items — hoofdstuk 17.4: the same title legitimately appears in
  /// Verder kijken *and* in Topkeuzes, and filtering it out of the second
  /// one makes relevant recommendations vanish for no reason a viewer can
  /// see.
  Future<List<UnifiedMediaGroup>> _projectItems(List<MediaItem> items, {required bool allowWeakFallback}) async {
    if (items.isEmpty) return const [];

    final resolver = UnifiedIdentityResolver(
      fetchExternalIds: fetchExternalIds,
      maxConcurrentFetches: maxConcurrentFetches,
    );
    final evidence = await resolver.resolveEvidence([for (final item in items) _resolvableFor(item)]);

    final candidates = <GroupingCandidate>[];
    for (var i = 0; i < items.length; i++) {
      final serverId = items[i].serverId;
      // A source with no server has no playback or detail route (hoofdstuk
      // 4.4), so it cannot become a UnifiedMediaSource and cannot be
      // rendered as a card either. Never expected from a real mapper; drop
      // it with a warning rather than throwing away the rest of the row.
      if (serverId == null || serverId.isEmpty) {
        appLogger.w('Home projection: dropping item ${items[i].id} with no resolvable serverId');
        continue;
      }
      candidates.add(GroupingCandidate(source: UnifiedMediaSource.fromItem(items[i]), evidence: evidence[i]));
    }
    return groupUnifiedMediaSources(candidates, allowWeakFallback: allowWeakFallback);
  }

  ResolvableItem _resolvableFor(MediaItem item) {
    final identity = canonicalIdentityOf(item);
    if (identity == null) {
      // Collections, playlists, folders, music: hoofdstuk 11.1 has no
      // identity rule for them, so they stay concrete. `includeGuidEvidence`
      // is off because a guid token at the opaque scope would merge two
      // servers' rows on evidence nobody has checked describes the same
      // thing — hoofdstuk 16.1's "collecties en playlists blijven concrete
      // serveritems", applied wherever such a row shows up.
      return ResolvableItem(item: item, scope: CanonicalIdentityGranularity.other.name, includeGuidEvidence: false);
    }
    return ResolvableItem(
      item: item,
      identity: identity,
      scope: identity.granularity.name,
      externalIdTarget: _externalIdTargetFor(item),
    );
  }

  /// Which id an item's external ids are fetched for — and, for episodes and
  /// seasons, deliberately none at all.
  ///
  /// A backend asked for an episode's external ids commonly answers with the
  /// *show's* tmdb/tvdb id. Two different episodes of one series would then
  /// each carry `episode:tmdb:<show id>` and merge into a single card, which
  /// is a false merge on evidence that never identified an episode. An
  /// episode's own stable guid is episode-scoped (see `guidTokens`) and
  /// stays the only strong evidence it gets — hoofdstuk 11.8's "exact
  /// identificeerbare afleveringen", and a false negative where the evidence
  /// runs out.
  ExternalIdTarget? _externalIdTargetFor(MediaItem item) {
    final serverId = item.serverId;
    if (serverId == null || serverId.isEmpty) return null;
    if (item.kind == MediaKind.episode || item.kind == MediaKind.season) return null;
    return (serverId: serverId, targetId: item.id);
  }

  // -- Continue Watching ---------------------------------------------------

  Future<List<UnifiedMediaGroup>> _projectContinueWatchingGroups(List<MediaItem> onDeck) async {
    if (onDeck.isEmpty) return const [];

    final resolver = UnifiedIdentityResolver(
      fetchExternalIds: fetchExternalIds,
      maxConcurrentFetches: maxConcurrentFetches,
    );
    final evidence = await resolver.resolveEvidence([
      for (final item in onDeck)
        ResolvableItem(
          item: item,
          scope: continueWatchingScope(item) ?? '',
          bucketKeyOverride: continueWatchingBucketKey(item),
          externalIdTarget: continueWatchingExternalIdTarget(item),
          // An episode/season row's external ids are fetched from its
          // *series*, so they are narrowed to the exact row before they
          // become a token (hoofdstuk 11.8) — otherwise every episode of one
          // series would share `episode:tmdb:<series id>` and fold into one
          // card. Its own guid needs no such narrowing: it already names the
          // concrete episode, which is the granularity this groups at.
          externalIdDiscriminator: continueWatchingOrdinal(item),
        ),
    ]);

    final candidates = <GroupingCandidate>[];
    for (var i = 0; i < onDeck.length; i++) {
      final serverId = onDeck[i].serverId;
      // Same guard `_deduplicateContinueWatching` applies: a row with no
      // serverId can never be a UnifiedMediaSource (its source key is
      // `serverId:id`) and can never legitimately merge with anything. It is
      // set aside so one malformed row cannot throw and take the whole row
      // down with it. Unlike that method, this projection cannot splice it
      // back afterwards — its output is groups, and a group needs a source —
      // so it is dropped with a warning.
      if (serverId == null || serverId.isEmpty) {
        appLogger.w('Continue Watching projection: dropping item ${onDeck[i].id} with no resolvable serverId');
        continue;
      }
      candidates.add(GroupingCandidate(source: UnifiedMediaSource.fromItem(onDeck[i]), evidence: evidence[i]));
    }

    return _byNewestSourceRecency(groupUnifiedMediaSources(candidates, allowWeakFallback: false));
  }

  /// Hoofdstuk 13.3: a card sorts on the newest recency among its own valid
  /// sources. Groups with no timestamp at all sink below every dated group
  /// and keep their incoming order among themselves — `List.sort` is not
  /// stable, so the incoming index is carried along as the final tie-break
  /// rather than left to chance.
  static List<UnifiedMediaGroup> _byNewestSourceRecency(List<UnifiedMediaGroup> groups) {
    final ranked =
        [for (var i = 0; i < groups.length; i++) (index: i, group: groups[i], recency: _newestRecency(groups[i]))]
          ..sort((a, b) {
            final ar = a.recency;
            final br = b.recency;
            if (ar != br) {
              if (ar == null) return 1;
              if (br == null) return -1;
              return br.compareTo(ar);
            }
            return a.index.compareTo(b.index);
          });
    return [for (final entry in ranked) entry.group];
  }

  static int? _newestRecency(UnifiedMediaGroup group) {
    int? newest;
    for (final source in group.sources) {
      final viewed = source.item.lastViewedAt;
      if (viewed == null) continue;
      if (newest == null || viewed > newest) newest = viewed;
    }
    return newest;
  }

  static UnifiedHubKind _hubKindOfItem(MediaItem item) => switch (item.kind) {
    MediaKind.movie => UnifiedHubKind.movie,
    MediaKind.show || MediaKind.season => UnifiedHubKind.show,
    MediaKind.episode => UnifiedHubKind.episode,
    _ => UnifiedHubKind.other,
  };
}
