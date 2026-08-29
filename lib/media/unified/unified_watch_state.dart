/// Representative watch-state selection for a group of sources describing the
/// same logical title (hoofdstuk 13.2 of docs/tvos-unified-experience.md).
/// Pure: given each source's already-fetched [MediaItem], picks which one's
/// progress the group displays. Never writes anything back — hoofdstuk 4.6
/// keeps every write brongebonden.
library;

import '../media_item.dart';

/// The source [UnifiedWatchState] chose to represent a group, and the facts
/// read off it. Carries no per-source detail beyond that — a caller who wants
/// every source's own progress reads it straight off `UnifiedMediaSource`.
class UnifiedWatchState {
  final String representativeSourceKey;
  final int? lastViewedAt;
  final bool hasActiveProgress;
  final bool isWatched;

  const UnifiedWatchState({
    required this.representativeSourceKey,
    this.lastViewedAt,
    this.hasActiveProgress = false,
    this.isWatched = false,
  });

  @override
  String toString() =>
      'UnifiedWatchState($representativeSourceKey, lastViewedAt: $lastViewedAt, active: $hasActiveProgress, watched: $isWatched)';
}

/// Picks the representative source for a group's watch-state display
/// (hoofdstuk 13.2). [sources] maps a stable source key to the concrete item
/// carrying that source's watch-state; must be non-empty.
///
/// Tie-break order, applied pairwise: newest [MediaItem.lastViewedAt] wins
/// (a missing timestamp always loses to a present one); a tie there prefers
/// active progress ([MediaItem.hasActiveProgress]) over a merely-finished
/// watch; a further tie falls back to the highest raw
/// [MediaItem.viewOffsetMs] — deliberately the raw offset, not a percentage,
/// since hoofdstuk 13.2 forbids comparing progress *percentage* across
/// sources with materially different runtimes (an edition's cut length isn't
/// comparable to another's). Only once every automatic tier is exhausted does
/// [preferredSourceKey] (the profile's remembered choice, hoofdstuk 14.8)
/// decide; with no preference and a true tie, the first source in [sources]'
/// iteration order keeps the win, so a caller that always iterates in the
/// same order gets a stable, deterministic pick.
UnifiedWatchState selectRepresentativeWatchState(Map<String, MediaItem> sources, {String? preferredSourceKey}) {
  assert(sources.isNotEmpty, 'selectRepresentativeWatchState requires at least one source');

  var winner = sources.entries.first;
  for (final candidate in sources.entries.skip(1)) {
    final cmp = _compareWatchCandidates(candidate.value, winner.value);
    final candidateWins = cmp > 0 || (cmp == 0 && preferredSourceKey != null && candidate.key == preferredSourceKey);
    if (candidateWins) winner = candidate;
  }

  final item = winner.value;
  return UnifiedWatchState(
    representativeSourceKey: winner.key,
    lastViewedAt: item.lastViewedAt,
    hasActiveProgress: item.hasActiveProgress,
    isWatched: item.isWatched,
  );
}

/// Positive when [a] should be preferred over [b]; 0 on a true tie.
int _compareWatchCandidates(MediaItem a, MediaItem b) {
  final at = a.lastViewedAt;
  final bt = b.lastViewedAt;
  if (at != bt) {
    if (at == null) return -1;
    if (bt == null) return 1;
    return at.compareTo(bt);
  }
  if (a.hasActiveProgress != b.hasActiveProgress) {
    return a.hasActiveProgress ? 1 : -1;
  }
  final ao = a.viewOffsetMs ?? 0;
  final bo = b.viewOffsetMs ?? 0;
  return ao.compareTo(bo);
}
