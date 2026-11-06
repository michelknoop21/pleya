/// Bounded-concurrency identity-evidence resolution (hoofdstuk 11.2 fase B of
/// docs/tvos-unified-experience.md): the one place that turns "this item is
/// worth an external-id lookup" into an actual network call, with concurrency
/// capped and per-target results cached within one resolution pass so two
/// items pointing at the same (server, target) id never fetch twice.
///
/// Pure identity math (bucketing, tokens, grouping) lives in
/// `canonical_media_identity.dart`, `identity_evidence.dart` and
/// `grouping_service.dart`; this file is the only place in the unified
/// catalog that performs I/O.
library;

import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/carried_external_ids.dart';
import '../../media/unified/identity_evidence.dart';
import '../../media/unified/unified_media_group.dart';
import '../../utils/external_ids.dart';

/// Where to fetch external ids for one item: which server, and which id on
/// that server to ask about (not always the item's own id — an episode's
/// evidence is fetched for its *show*, see [continueWatchingExternalIdTarget]).
typedef ExternalIdTarget = ({String serverId, String targetId});

/// One item plus the pure facts already known about it before any network
/// call.
class ResolvableItem {
  final MediaItem item;

  /// The hoofdstuk 11.2 identity this item resolves to, when the caller wants
  /// [UnifiedIdentityResolver] to use [CanonicalMediaIdentity.bucketKey] for
  /// duplicate-bucket detection and to carry this identity into the returned
  /// [IdentityEvidence]. Null when the caller supplies its own bucketing via
  /// [bucketKeyOverride] instead (a caller reproducing pre-fase-1 behavior
  /// that isn't hoofdstuk-11.2-shaped) — the evidence then carries
  /// [CanonicalMediaIdentity.opaque] as a placeholder the caller isn't
  /// expected to read.
  final CanonicalMediaIdentity? identity;

  /// Token scope (`movie`, `show`, `episode`, ...) — see `identity_evidence.dart`.
  final String scope;

  /// Overrides [identity]'s bucket key for duplicate-bucket detection, for a
  /// caller whose bucketing rule isn't [CanonicalMediaIdentity]'s (hoofdstuk
  /// 11.2). Most callers leave this null and let [identity] decide.
  final String? bucketKeyOverride;

  final ExternalIdTarget? externalIdTarget;

  /// Narrows the *fetched* external ids down to what this item actually is,
  /// for a caller whose [externalIdTarget] is coarser than [scope] — Continue
  /// Watching fetching an episode's ids from its **series**. See
  /// [externalIdTokens]'s `discriminator`; null (the default) means the
  /// fetched ids describe the item itself and need no narrowing.
  final String? externalIdDiscriminator;

  /// Whether [item]'s own guid should contribute a strong token
  /// ([guidTokens]). Defaults to true. A caller that groups at a *coarser*
  /// granularity than [item]'s own kind sets this false: [guidTokens] always
  /// scopes an episode's guid to `episode` (hoofdstuk 11.1 — an episode guid
  /// is never valid evidence for its show), so two different episodes
  /// contributing to one show-scoped group would disagree on that
  /// `episode:guid` namespace and trip `grouping_service.dart`'s hoofdstuk
  /// 11.5 conflict check, which is built to catch a namespace disagreeing
  /// about the *group's own* identity — not two sources legitimately
  /// reporting two different child rows. Continue Watching is no longer such
  /// a caller (it groups episodes at episode granularity, hoofdstuk 11.8), so
  /// the episode guid is exactly the right evidence there and stays on.
  final bool includeGuidEvidence;

  const ResolvableItem({
    required this.item,
    this.identity,
    required this.scope,
    this.bucketKeyOverride,
    this.externalIdTarget,
    this.externalIdDiscriminator,
    this.includeGuidEvidence = true,
  });

  /// The numbers the item's own list answer carried, when they describe the
  /// item itself: the lookup target is the item and nothing narrows them.
  ExternalIds? _carriedIds({required bool allowLegacyPleya}) {
    if (externalIdDiscriminator != null) return null;
    final target = externalIdTarget;
    if (target == null || target.targetId != item.id) return null;
    return externalIdsCarriedBy(item, allowLegacyPleya: allowLegacyPleya);
  }

  String? get _effectiveBucketKey => bucketKeyOverride ?? identity?.resolutionKey;
}

/// Resolves [IdentityEvidence] for a batch of [ResolvableItem]s, in input
/// order. Only items whose bucket key is shared by more than one item in the
/// batch ever cost a network call (hoofdstuk 11.2: "Items die niet in een
/// mogelijke duplicate bucket vallen krijgen geen extra externe-ID-call") —
/// every other item's evidence is built from its own guid alone, which is
/// already in memory and needs no fetch.
///
/// A fetch failure degrades that one item to guid-only evidence rather than
/// failing the batch (hoofdstuk 26 edge case C20): losing one server's
/// external ids should never take down the rest of the resolution.
class UnifiedIdentityResolver {
  final Future<ExternalIds> Function(String serverId, String targetId) fetchExternalIds;
  final int maxConcurrentFetches;

  UnifiedIdentityResolver({
    required this.fetchExternalIds,
    this.maxConcurrentFetches = 4,
    this.trustStoredIdentity = storedIdentityIsSafe,
  });

  final bool Function(MediaItem) trustStoredIdentity;

  /// [known] and [onResolved] let a caller that resolves a growing list every
  /// round keep its own evidence: an item whose evidence came from fetched ids
  /// never loses it (bucket counts only grow and ids do not change), so it is
  /// neither re-derived nor awaited again. Guid-only evidence is never reported
  /// through [onResolved]: that item may still gain a duplicate-bucket mate, and
  /// a failed fetch has to be retried.
  Future<List<IdentityEvidence>> resolveEvidence(
    List<ResolvableItem> items, {
    IdentityEvidence? Function(int index)? known,
    void Function(int index, IdentityEvidence evidence)? onResolved,
  }) async {
    if (items.isEmpty) return const [];

    final bucketCounts = <String, int>{};
    for (final entry in items) {
      final key = entry._effectiveBucketKey;
      if (key == null) continue;
      bucketCounts[key] = (bucketCounts[key] ?? 0) + 1;
    }
    final duplicateBuckets = {
      for (final count in bucketCounts.entries)
        if (count.value > 1) count.key,
    };

    final evidence = List<IdentityEvidence?>.filled(items.length, null);
    final trustedAtStart = [for (final entry in items) trustStoredIdentity(entry.item)];
    final newlyResolved = <int>{};
    final pending = <int>[];
    for (var i = 0; i < items.length; i++) {
      final entry = items[i];
      // Numbers the list answer already carried decide identity on their own:
      // no request, and no title or year in the way. A title bucket only
      // gathers candidates for items that came without them.
      final trusted = trustedAtStart[i];
      final carried = entry._carriedIds(allowLegacyPleya: trusted);
      if (carried != null) {
        evidence[i] = IdentityEvidence(
          identity: entry.identity ?? CanonicalMediaIdentity.opaque(),
          strongTokens: {
            ..._guidTokensFor(entry),
            ...externalIdTokens(scope: entry.scope, ids: carried),
          },
        );
        continue;
      }
      final key = entry._effectiveBucketKey;
      final inDuplicateBucket = key != null && duplicateBuckets.contains(key);
      final remembered = inDuplicateBucket && trusted ? known?.call(i) : null;
      if (remembered != null) {
        evidence[i] = remembered;
      } else if (!inDuplicateBucket || entry.externalIdTarget == null) {
        evidence[i] = _guidOnlyEvidence(entry);
      } else {
        pending.add(i);
      }
    }

    if (pending.isNotEmpty) {
      final cache = <String, Future<ExternalIds>>{};
      await _runBounded(pending, maxConcurrentFetches, (i) async {
        final entry = items[i];
        final target = entry.externalIdTarget!;
        try {
          final cacheKey = '${target.serverId}:${target.targetId}';
          final ids = await cache.putIfAbsent(cacheKey, () => fetchExternalIds(target.serverId, target.targetId));
          final resolved = IdentityEvidence(
            identity: entry.identity ?? CanonicalMediaIdentity.opaque(),
            strongTokens: {
              ..._guidTokensFor(entry),
              ...externalIdTokens(scope: entry.scope, ids: ids, discriminator: entry.externalIdDiscriminator),
            },
          );
          evidence[i] = resolved;
          newlyResolved.add(i);
        } catch (_) {
          evidence[i] = _guidOnlyEvidence(entry);
        }
      });
    }

    // A completed legacy answer can wait behind another source. Qualify the
    // whole pass before publishing any answer into the caller's known cache.
    for (var i = 0; i < items.length; i++) {
      if (trustedAtStart[i] && !trustStoredIdentity(items[i].item)) {
        evidence[i] = _guidOnlyEvidence(items[i]);
      } else if (newlyResolved.contains(i)) {
        onResolved?.call(i, evidence[i]!);
      }
    }
    return [for (final e in evidence) e!];
  }

  IdentityEvidence _guidOnlyEvidence(ResolvableItem entry) => IdentityEvidence(
    identity: entry.identity ?? CanonicalMediaIdentity.opaque(),
    strongTokens: _guidTokensFor(entry),
  );

  Set<IdentityToken> _guidTokensFor(ResolvableItem entry) {
    if (!entry.includeGuidEvidence) return const {};
    return guidTokens(scope: entry.scope, guid: entry.item.guid, kind: entry.item.kind);
  }
}

Future<void> _runBounded(List<int> indices, int maxConcurrent, Future<void> Function(int index) run) async {
  var cursor = 0;
  Future<void> worker() async {
    while (true) {
      if (cursor >= indices.length) return;
      final index = indices[cursor];
      cursor++;
      await run(index);
    }
  }

  final workerCount = maxConcurrent < indices.length ? maxConcurrent : indices.length;
  await Future.wait(List.generate(workerCount, (_) => worker()));
}

// -- Continue Watching identity --------------------------------------------
//
// Hoofdstuk 11.8: Verder kijken groups on the **exact episode**:
// `show identity + season + episode`. Two servers holding the viewer at
// S02E04 are one card with two sources. S02E04 on one server and S02E05 on
// another are never one group; since DEC-XXX the row shows only the most
// recently watched of them ([oneContinueWatchingCardPerSeries]), and only
// when a shared series number proves they are the same series.
//
// That is why an episode's series-wide external ids are never used raw here:
// a backend asked for an episode's ids answers with the *series'* id, which
// identifies the series and nothing finer. It is narrowed by
// [continueWatchingOrdinal] into `episode:tmdb:95396/s2e4` (edge case D4),
// and the episode's own stable guid — the strongest exact-episode evidence
// there is — contributes alongside it (edge case D3).
//
// The invariant a missing ordinal falls back on is the general one: a false
// merge is worse than a false negative. An episode with no usable season or
// episode index has no exact-episode bucket at all, so it never buys a
// series-wide id it could be folded on; its guid stays its only evidence,
// which is hoofdstuk 11.8's "ontbrekende indexen vereisen een sterk
// episode-ID" (edge cases D6/D7).
//
// This deliberately still does not go through [CanonicalMediaIdentity]'s
// hoofdstuk 11.2 bucket (which also folds in release year and full
// punctuation-stripped title normalization) or `grouping_service.dart`'s weak
// title+year fallback (hoofdstuk 11.6): Continue Watching merges on shared
// external ids/guid only, never on title alone.

/// Continue Watching's token scope for [item], or null when its kind never
/// contributes to Continue Watching dedup.
///
/// Each kind is scoped at its own granularity — an episode at `episode`, not
/// at its show — so a token collected for one episode can never serve as
/// evidence about a sibling episode (hoofdstuk 11.8).
String? continueWatchingScope(MediaItem item) => switch (item.kind) {
  MediaKind.episode => 'episode',
  MediaKind.season => 'season',
  MediaKind.show => 'show',
  MediaKind.movie => 'movie',
  _ => null,
};

/// The ordinal that narrows a *series-wide* external id down to the exact
/// child row [item] is — `s2e4` for an episode, `s2` for a season — or null
/// when [item] is not a child row or its indexes are missing.
///
/// Passed to [externalIdTokens] as its `discriminator`, and appended to
/// [continueWatchingBucketKey], so both the cheap bucket and the strong token
/// carry the same season/episode specificity.
String? continueWatchingOrdinal(MediaItem item) {
  switch (item.kind) {
    case MediaKind.episode:
      final season = item.parentIndex;
      final episode = item.index;
      if (season == null || episode == null) return null;
      return 's${season}e$episode';
    case MediaKind.season:
      final season = item.index;
      if (season == null) return null;
      return 's$season';
    default:
      return null;
  }
}

/// Continue Watching's cheap duplicate-bucket key: scope plus a
/// whitespace-collapsed lower-cased title (the series title for an episode or
/// season). No year, no punctuation stripping; distinct from
/// [CanonicalMediaIdentity.bucketKey] on purpose (see the section comment
/// above).
///
/// An episode buckets on its series, not on its ordinal, so two different
/// episodes of one series on two servers still buy the series numbers that
/// [oneContinueWatchingCardPerSeries] needs (DEC-XXX). The bucket only decides
/// who is worth a lookup; the tokens stay narrowed to the exact episode.
///
/// Returns null for an episode or season whose ordinal is unknown: it has no
/// exact-episode token, so a series-wide id would be its only evidence and it
/// must never buy one (edge cases D6/D7).
String? continueWatchingBucketKey(MediaItem item) {
  final scope = continueWatchingScope(item);
  if (scope == null) return null;
  final title = switch (item.kind) {
    MediaKind.episode || MediaKind.season => item.grandparentTitle ?? item.parentTitle ?? item.title,
    _ => item.title,
  };
  final normalized = title?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) return null;
  if ((item.kind == MediaKind.episode || item.kind == MediaKind.season) && continueWatchingOrdinal(item) == null) {
    return null;
  }
  return '$scope:$normalized';
}

/// Which id, on which server, Continue Watching fetches external ids for:
/// the show's id for an episode/season row, the item's own id for a show or
/// movie row.
///
/// Coarser than the row itself for episodes and seasons on purpose — that is
/// the only id a backend answers for them — which is exactly why the result
/// is narrowed by [continueWatchingOrdinal] before it becomes a token.
ExternalIdTarget? continueWatchingExternalIdTarget(MediaItem item) {
  final serverId = item.serverId;
  if (serverId == null || serverId.isEmpty) return null;
  final targetId = switch (item.kind) {
    MediaKind.episode => item.grandparentId,
    MediaKind.season => item.grandparentId ?? item.parentId,
    MediaKind.show || MediaKind.movie => item.id,
    _ => null,
  };
  if (targetId == null || targetId.isEmpty) return null;
  return (serverId: serverId, targetId: targetId);
}

/// One Verder kijken card per series (DEC-XXX): of the episode groups whose
/// series is proven the same, only the most recently watched one stays. Each
/// backend already keeps one episode per series in its own row; this applies
/// that rule across servers.
///
/// The series is read from the episode tokens' series number
/// (`episode:tmdb:95396/s2e4` belongs to `tmdb:95396`), never from the title.
/// Two groups are the same series when they share a number and disagree on
/// none. Groups without such a number (no lookup, guid-only, movies) pass
/// through untouched. Input order is kept.
List<UnifiedMediaGroup> oneContinueWatchingCardPerSeries(
  List<UnifiedMediaGroup> groups,
  Map<String, IdentityEvidence> evidenceBySourceKey,
) {
  Map<String, String> seriesNumbersOf(UnifiedMediaGroup group) => {
    for (final source in group.sources)
      for (final token in evidenceBySourceKey[source.sourceKey]?.strongTokens ?? const <IdentityToken>{})
        if (token.namespace != identityTokenNamespaceGuid && token.value.contains('/'))
          token.namespace: token.value.substring(0, token.value.lastIndexOf('/')),
  };
  bool sameSeries(Map<String, String> a, Map<String, String> b) {
    var shared = false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) continue;
      if (other != entry.value) return false;
      shared = true;
    }
    return shared;
  }

  int newestOf(UnifiedMediaGroup group) =>
      group.sources.map((s) => s.item.recencySortKey).reduce((a, b) => a > b ? a : b);

  final byRecency = [for (var i = 0; i < groups.length; i++) i]
    ..sort((a, b) {
      final cmp = newestOf(groups[b]).compareTo(newestOf(groups[a]));
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  final kept = <Map<String, String>>[];
  final dropped = <int>{};
  for (final i in byRecency) {
    final numbers = seriesNumbersOf(groups[i]);
    if (numbers.isEmpty) continue;
    if (kept.any((k) => sameSeries(k, numbers))) {
      dropped.add(i);
    } else {
      kept.add(numbers);
    }
  }
  if (dropped.isEmpty) return groups;
  return [
    for (var i = 0; i < groups.length; i++)
      if (!dropped.contains(i)) groups[i],
  ];
}
