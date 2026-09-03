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
import '../../media/unified/identity_evidence.dart';
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

  String? get _effectiveBucketKey => bucketKeyOverride ?? identity?.bucketKey;
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

  UnifiedIdentityResolver({required this.fetchExternalIds, this.maxConcurrentFetches = 4});

  Future<List<IdentityEvidence>> resolveEvidence(List<ResolvableItem> items) async {
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
    final pending = <int>[];
    for (var i = 0; i < items.length; i++) {
      final entry = items[i];
      final key = entry._effectiveBucketKey;
      final inDuplicateBucket = key != null && duplicateBuckets.contains(key);
      if (!inDuplicateBucket || entry.externalIdTarget == null) {
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
          evidence[i] = IdentityEvidence(
            identity: entry.identity ?? CanonicalMediaIdentity.opaque(),
            strongTokens: {
              ..._guidTokensFor(entry),
              ...externalIdTokens(scope: entry.scope, ids: ids, discriminator: entry.externalIdDiscriminator),
            },
          );
        } catch (_) {
          evidence[i] = _guidOnlyEvidence(entry);
        }
      });
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
// Hoofdstuk 11.8 is binding: Verder kijken groups on the **exact episode** —
// `show identity + season + episode` — and never folds every episode of one
// series into a single Continue Watching entry. Two servers holding the
// viewer at S02E04 are one card with two sources; S02E04 and S02E05 are two
// cards, even when both resolve the same series-wide tmdb/tvdb/Plex show
// identity.
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

/// Continue Watching's cheap duplicate-bucket key: scope, a
/// whitespace-collapsed lower-cased title, and — for an episode or season —
/// its [continueWatchingOrdinal]. No year, no punctuation stripping; distinct
/// from [CanonicalMediaIdentity.bucketKey] on purpose (see the section
/// comment above).
///
/// Returns null for an episode or season whose ordinal is unknown: without it
/// there is no exact-episode bucket, and bucketing such a row on its series
/// alone is precisely the fold hoofdstuk 11.8 forbids.
String? continueWatchingBucketKey(MediaItem item) {
  final scope = continueWatchingScope(item);
  if (scope == null) return null;
  final title = switch (item.kind) {
    MediaKind.episode || MediaKind.season => item.grandparentTitle ?? item.parentTitle ?? item.title,
    _ => item.title,
  };
  final normalized = title?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) return null;
  if (item.kind != MediaKind.episode && item.kind != MediaKind.season) return '$scope:$normalized';
  final ordinal = continueWatchingOrdinal(item);
  if (ordinal == null) return null;
  return '$scope:$normalized:$ordinal';
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
