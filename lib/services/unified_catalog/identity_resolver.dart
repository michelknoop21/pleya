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
/// evidence is fetched for its *show*, see [continueWatchingExternalIdTargetId]).
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

  /// Whether [item]'s own guid should contribute a strong token
  /// ([guidTokens]). Defaults to true. A caller that groups at a coarser
  /// granularity than [item]'s own kind — Continue Watching grouping an
  /// episode at its *show*'s scope — sets this false for episode/season
  /// items: [guidTokens] always scopes an episode's guid to `episode`
  /// (hoofdstuk 11.1 — an episode guid is never valid evidence for its show),
  /// so two different episodes correctly contributing to the same show group
  /// would otherwise disagree on that `episode:guid` namespace and trip
  /// `grouping_service.dart`'s hoofdstuk 11.5 conflict check, which is built
  /// to catch a namespace disagreeing about the *group's own* identity — not
  /// two sources legitimately reporting two different child rows.
  final bool includeGuidEvidence;

  const ResolvableItem({
    required this.item,
    this.identity,
    required this.scope,
    this.bucketKeyOverride,
    this.externalIdTarget,
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
              ...externalIdTokens(scope: entry.scope, ids: ids),
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

// -- Continue Watching compatibility mapping --------------------------------
//
// Extracted from data_aggregation_service.dart's pre-fase-1
// `_deduplicateContinueWatching` unchanged, so movie/show/season/episode rows
// keep bucketing and merging exactly as before (fase 1's DoD: byte-identical
// Continue Watching output). An episode or season's identity is its *show's*
// — a Continue Watching row tracks progress on a title, not one airing,
// matching hoofdstuk 1's "a series row is the server's next-episode
// substitution".
//
// This deliberately does not go through [CanonicalMediaIdentity]'s hoofdstuk
// 11.2 bucket (which also folds in release year and full punctuation-stripped
// title normalization) or `grouping_service.dart`'s weak title+year fallback
// (hoofdstuk 11.6): Continue Watching has never merged on title alone, only
// on shared external ids/guid, and changing that now would silently change
// what viewers see merged on their Home screen. Folding Continue Watching
// into the full shared pipeline belongs to the fase that builds its unified
// projection (hoofdstuk 27, fase 3+), not this extraction.

/// Continue Watching's token scope for [item], or null when its kind never
/// contributes to Continue Watching dedup.
String? continueWatchingScope(MediaItem item) => switch (item.kind) {
  MediaKind.episode || MediaKind.season || MediaKind.show => 'show',
  MediaKind.movie => 'movie',
  _ => null,
};

/// Continue Watching's cheap duplicate-bucket key: scope plus a
/// whitespace-collapsed, lower-cased title — no year, no punctuation
/// stripping. Distinct from [CanonicalMediaIdentity.bucketKey] on purpose;
/// see the section comment above.
String? continueWatchingBucketKey(MediaItem item) {
  final scope = continueWatchingScope(item);
  if (scope == null) return null;
  final title = switch (item.kind) {
    MediaKind.episode || MediaKind.season => item.grandparentTitle ?? item.parentTitle ?? item.title,
    _ => item.title,
  };
  final normalized = title?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) return null;
  return '$scope:$normalized';
}

/// Which id, on which server, Continue Watching fetches external ids for:
/// the show's id for an episode/season row, the item's own id for a show or
/// movie row.
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
