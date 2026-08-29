/// Pure connected-components grouping over already-collected identity
/// evidence (hoofdstuk 11.4/11.5/11.6/11.9 and hoofdstuk 4.7 of
/// docs/tvos-unified-experience.md). No I/O: every strong token and bucket
/// key a candidate carries must already be computed before it reaches this
/// file — `identity_resolver.dart` is the service that fetches external ids
/// and calls here with the result.
library;

import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/unified/identity_evidence.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_watch_state.dart';

/// One source plus the identity evidence already collected for it. Built by
/// `identity_resolver.dart`; consumed here.
class GroupingCandidate {
  final UnifiedMediaSource source;
  final IdentityEvidence evidence;

  const GroupingCandidate({required this.source, required this.evidence});
}

/// Backends DEC-063 forbids ever merging — not with Plex/Jellyfin, and not
/// with each other — because their identity data isn't proven equivalent yet
/// (Pleya Server's external-id support is PS-7, still unbuilt). A source on
/// one of these backends is always its own single-source group; hoofdstuk 4.2
/// still allows that group to *exist*, it just never grows a second source.
const _neverMergedBackends = {MediaBackend.local, MediaBackend.pleyaServer};

/// Groups [candidates] into [UnifiedMediaGroup]s. Every candidate ends up in
/// exactly one group — grouping never drops a source (hoofdstuk 4.2/11.5).
///
/// Two candidates merge when either:
/// - they share an identical strong [IdentityToken] (hoofdstuk 11.3/11.5), or
/// - hoofdstuk 11.6's strict weak fallback applies: same granularity, same
///   normalized title, both years known and equal, no conflicting strong
///   token between them, and neither one's server contributes a second
///   candidate to the same bucket (hoofdstuk 11.6, edge case C19).
///
/// A component formed via transitive strong-token chaining is rejected as
/// ambiguous (hoofdstuk 11.5) — and every one of its members falls back to
/// its own single-source group rather than a smaller guessed split — when it
/// contains two disagreeing values for the same scoped namespace (hoofdstuk
/// 11.4's "sterke IDs botsen", reachable through a bridging item even when no
/// single pair in the component looks conflicting on its own).
///
/// [allowWeakFallback] gates hoofdstuk 11.6's title+year fallback. It
/// defaults to on — the shape hoofdstuk 4.3 wants every caller to share.
/// `identity_resolver.dart`'s Continue Watching compatibility path is the one
/// caller that turns it off: Continue Watching has only ever merged on shared
/// external ids/guid, never on title alone, and that specific
/// compatibility shim needs to keep it that way (see the section comment
/// there for why).
///
/// Order is preserves: a group appears at the position of the first
/// candidate (in [candidates] order) that belongs to it.
List<UnifiedMediaGroup> groupUnifiedMediaSources(List<GroupingCandidate> candidates, {bool allowWeakFallback = true}) {
  if (candidates.isEmpty) return const [];

  final poolable = <int>[];
  final groups = <int, List<UnifiedMediaGroup>>{};

  for (var i = 0; i < candidates.length; i++) {
    if (_neverMergedBackends.contains(candidates[i].source.backend)) {
      groups[i] = [_buildSingleSourceGroup(candidates[i])];
    } else {
      poolable.add(i);
    }
  }

  if (poolable.isNotEmpty) {
    final components = _unionFind(candidates, poolable, allowWeakFallback: allowWeakFallback);
    for (final members in components) {
      final finalized = _finalizeComponent(members, candidates);
      groups[members.first] = finalized;
    }
  }

  final ordered = <UnifiedMediaGroup>[];
  for (var i = 0; i < candidates.length; i++) {
    final forThis = groups[i];
    if (forThis != null) ordered.addAll(forThis);
  }
  return ordered;
}

/// Union-find restricted to [indices] into [candidates] (already filtered to
/// poolable backends). Returns each resulting component as an index list, in
/// first-member-encountered order.
List<List<int>> _unionFind(List<GroupingCandidate> candidates, List<int> indices, {required bool allowWeakFallback}) {
  final parent = {for (final i in indices) i: i};
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]!]!;
      x = parent[x]!;
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  // Strong-token adjacency: any two candidates sharing an identical token key
  // are connected, regardless of bucket.
  final byToken = <String, List<int>>{};
  for (final i in indices) {
    for (final token in candidates[i].evidence.strongTokens) {
      byToken.putIfAbsent(token.key, () => []).add(i);
    }
  }
  for (final group in byToken.values) {
    for (var k = 1; k < group.length; k++) {
      union(group[0], group[k]);
    }
  }

  // Weak title+year fallback (hoofdstuk 11.6), only within a shared bucket
  // and only between candidates not already joined by strong evidence.
  if (allowWeakFallback) {
    final byBucket = <String, List<int>>{};
    for (final i in indices) {
      final key = candidates[i].evidence.identity.bucketKey;
      if (key != null) byBucket.putIfAbsent(key, () => []).add(i);
    }
    for (final bucketMembers in byBucket.values) {
      if (bucketMembers.length < 2) continue;
      final perServer = <String, int>{};
      for (final i in bucketMembers) {
        final serverId = candidates[i].source.serverId.value;
        perServer[serverId] = (perServer[serverId] ?? 0) + 1;
      }
      // C19: a server contributing more than one candidate to this bucket is
      // ambiguous — none of that server's candidates weak-fallback-merge here.
      final eligible = bucketMembers.where((i) => perServer[candidates[i].source.serverId.value] == 1).toList();
      for (var a = 0; a < eligible.length; a++) {
        for (var b = a + 1; b < eligible.length; b++) {
          final i = eligible[a], j = eligible[b];
          if (find(i) == find(j)) continue;
          if (_weakFallbackAllowed(candidates[i], candidates[j])) union(i, j);
        }
      }
    }
  }

  final byRoot = <int, List<int>>{};
  for (final i in indices) {
    byRoot.putIfAbsent(find(i), () => []).add(i);
  }
  return byRoot.values.toList();
}

bool _weakFallbackAllowed(GroupingCandidate a, GroupingCandidate b) {
  final ia = a.evidence.identity;
  final ib = b.evidence.identity;
  if (ia.granularity != ib.granularity) return false;
  if (ia.normalizedTitle == null || ia.normalizedTitle != ib.normalizedTitle) return false;
  if (!ia.yearAgreesWith(ib)) return false;
  if (_hasConflictingToken(a.evidence.strongTokens, b.evidence.strongTokens)) return false;
  return true;
}

bool _hasConflictingToken(Set<IdentityToken> a, Set<IdentityToken> b) {
  for (final ta in a) {
    for (final tb in b) {
      if (ta.scope == tb.scope && ta.namespace == tb.namespace && ta.value != tb.value) return true;
    }
  }
  return false;
}

List<UnifiedMediaGroup> _finalizeComponent(List<int> members, List<GroupingCandidate> candidates) {
  if (members.length == 1) {
    return [_buildSingleSourceGroup(candidates[members.single])];
  }
  if (_componentHasNamespaceConflict(members, candidates)) {
    return [for (final i in members) _buildSingleSourceGroup(candidates[i])];
  }
  return [_buildMergedGroup(members, candidates)];
}

/// Hoofdstuk 11.5: a component reached only through transitive strong-token
/// chaining (item A shares tmdb with B, B shares imdb with C) must still be
/// internally consistent — no scoped namespace may disagree across members,
/// even when no single pair in the chain looks conflicting on its own.
bool _componentHasNamespaceConflict(List<int> members, List<GroupingCandidate> candidates) {
  final valueByNamespace = <String, String>{};
  for (final i in members) {
    for (final token in candidates[i].evidence.strongTokens) {
      final namespaceKey = '${token.scope}:${token.namespace}';
      final existing = valueByNamespace[namespaceKey];
      if (existing != null && existing != token.value) return true;
      valueByNamespace[namespaceKey] = token.value;
    }
  }
  return false;
}

UnifiedMediaGroup _buildSingleSourceGroup(GroupingCandidate candidate) {
  final source = candidate.source;
  return UnifiedMediaGroup(
    groupId: _deterministicGroupId([candidate.evidence], fallbackKey: source.sourceKey),
    identity: candidate.evidence.identity,
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: selectRepresentativeWatchState({source.sourceKey: source.item}),
  );
}

UnifiedMediaGroup _buildMergedGroup(List<int> members, List<GroupingCandidate> candidates) {
  final ordered = [for (final i in members) candidates[i]];
  final sources = [for (final c in ordered) c.source];
  final representativeKey = selectRepresentativeSource(sources);
  final representativeIdentity = ordered.firstWhere((c) => c.source.sourceKey == representativeKey).evidence.identity;
  final fallbackKey = (sources.map((s) => s.sourceKey).toList()..sort()).join('|');
  return UnifiedMediaGroup(
    groupId: _deterministicGroupId([for (final c in ordered) c.evidence], fallbackKey: fallbackKey),
    identity: representativeIdentity,
    sources: sources,
    representativeSourceKey: representativeKey,
    watchState: selectRepresentativeWatchState({for (final s in sources) s.sourceKey: s.item}),
  );
}

/// Hoofdstuk 11.9: content-derived and improvable, not assigned by a
/// long-lived store — fase 1 has no provider/session yet (that arrives in
/// fase 3's `UnifiedCatalogProvider`), so this is the deterministic default a
/// later fase's persistence layer builds on rather than replaces.
///
/// Prefers the lexicographically-smallest strong token key across every
/// member (independent of which source ends up representative, so the id
/// doesn't change just because a new source shifted the tie-break); falls
/// back to the smallest bucket key; falls back to [fallbackKey] when a group
/// has neither (hoofdstuk 11.1's weakest case, e.g. C24).
String _deterministicGroupId(Iterable<IdentityEvidence> evidences, {required String fallbackKey}) {
  final tokenKeys = <String>{for (final e in evidences) ...e.strongTokens.map((t) => t.key)};
  if (tokenKeys.isNotEmpty) {
    final sorted = tokenKeys.toList()..sort();
    return 'group:${sorted.first}';
  }
  final bucketKeys = <String>{
    for (final e in evidences)
      if (e.identity.bucketKey != null) e.identity.bucketKey!,
  };
  if (bucketKeys.isNotEmpty) {
    final sorted = bucketKeys.toList()..sort();
    return 'group:${sorted.first}';
  }
  return 'group:source:$fallbackKey';
}

/// Deterministic representative-source tie-break (hoofdstuk 4.7), restricted
/// to what a source knows about itself. The full contract also ranks by
/// preferred source and live online state — inputs fase 1 does not have (no
/// per-profile preference store yet, no server health signal reaches this
/// pure file); [preferredSourceKey] and [onlineSourceKeys] are accepted so
/// fase 2/4 can layer those tiers on top without this function changing
/// shape, and default to "no preference" / "every source counts as equally
/// online" so fase 1's own callers get pure, deterministic behavior today.
String selectRepresentativeSource(
  List<UnifiedMediaSource> sources, {
  String? preferredSourceKey,
  Set<String>? onlineSourceKeys,
}) {
  assert(sources.isNotEmpty, 'selectRepresentativeSource requires at least one source');
  final ranked = [...sources]
    ..sort(
      (a, b) => _compareSourceRank(a, b, preferredSourceKey: preferredSourceKey, onlineSourceKeys: onlineSourceKeys),
    );
  return ranked.first.sourceKey;
}

int _compareSourceRank(
  UnifiedMediaSource a,
  UnifiedMediaSource b, {
  required String? preferredSourceKey,
  required Set<String>? onlineSourceKeys,
}) {
  if (preferredSourceKey != null) {
    final ap = a.sourceKey == preferredSourceKey;
    final bp = b.sourceKey == preferredSourceKey;
    if (ap != bp) return ap ? -1 : 1;
  }
  if (onlineSourceKeys != null) {
    final ao = onlineSourceKeys.contains(a.sourceKey);
    final bo = onlineSourceKeys.contains(b.sourceKey);
    if (ao != bo) return ao ? -1 : 1;
  }
  final metaCmp = _metadataCompleteness(b.item).compareTo(_metadataCompleteness(a.item));
  if (metaCmp != 0) return metaCmp;
  final artCmp = _artworkCompleteness(b.item).compareTo(_artworkCompleteness(a.item));
  if (artCmp != 0) return artCmp;
  final qualityCmp = _qualityScore(b.item).compareTo(_qualityScore(a.item));
  if (qualityCmp != 0) return qualityCmp;
  final nameCmp = a.serverName.compareTo(b.serverName);
  if (nameCmp != 0) return nameCmp;
  final idCmp = a.serverId.value.compareTo(b.serverId.value);
  if (idCmp != 0) return idCmp;
  return a.item.id.compareTo(b.item.id);
}

int _metadataCompleteness(MediaItem item) {
  var score = 0;
  if ((item.summary ?? '').isNotEmpty) score++;
  if ((item.genres ?? const []).isNotEmpty) score++;
  if (item.rating != null) score++;
  if ((item.originallyAvailableAt ?? '').isNotEmpty) score++;
  return score;
}

int _artworkCompleteness(MediaItem item) {
  var score = 0;
  if ((item.artPath ?? '').isNotEmpty) score++;
  if ((item.thumbPath ?? '').isNotEmpty) score++;
  if ((item.backgroundSquarePath ?? '').isNotEmpty) score++;
  if ((item.clearLogoPath ?? '').isNotEmpty) score++;
  return score;
}

int _qualityScore(MediaItem item) {
  var best = 0;
  for (final version in item.mediaVersions ?? const []) {
    final height = version.height ?? 0;
    if (height > best) best = height;
  }
  return best;
}
