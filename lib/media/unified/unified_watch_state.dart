/// Representative watch-state selection for a group of sources describing the
/// same logical title (hoofdstuk 13.2 of docs/tvos-unified-experience.md).
/// Pure: given each source's already-fetched [MediaItem], picks which one's
/// progress the group displays. Never writes anything back — hoofdstuk 4.6
/// keeps every write brongebonden.
library;

import '../media_item.dart';
import '../watch_progress.dart';

/// The source [UnifiedWatchState] chose to represent a group, and the facts
/// read off it. Carries no per-source detail beyond that — a caller who wants
/// every source's own progress reads it straight off `UnifiedMediaSource`.
class UnifiedWatchState {
  final String representativeSourceKey;
  final int? lastViewedAt;
  final bool hasActiveProgress;
  final bool isWatched;

  /// Whether this group's sources disagree on runtime badly enough that
  /// hoofdstuk 13.2's "bij editions met een groot runtimeverschil blijft
  /// progress brongebonden" applies.
  ///
  /// True means the facts above describe exactly one concrete cut and say
  /// nothing about the others — no progress tier was allowed to run, so the
  /// pick rests on recency and the remembered choice alone. The card already
  /// reads its bar off the representative source's own offset/duration pair,
  /// so nothing is blended either way; this is the flag a surface needs if it
  /// ever wants to say so out loud rather than imply a shared position.
  final bool runtimesDiffer;

  const UnifiedWatchState({
    required this.representativeSourceKey,
    this.lastViewedAt,
    this.hasActiveProgress = false,
    this.isWatched = false,
    this.runtimesDiffer = false,
  });

  @override
  String toString() =>
      'UnifiedWatchState($representativeSourceKey, lastViewedAt: $lastViewedAt, active: $hasActiveProgress, watched: $isWatched, runtimesDiffer: $runtimesDiffer)';
}

/// How far two sources' runtimes may differ and still describe the same cut,
/// as a fraction of the longer one.
///
/// Not a taste threshold. Real copies of one cut differ by a few percent for
/// reasons that have nothing to do with content: a PAL transfer runs exactly
/// 4% short of its 24fps source, and trimmed leaders, distributor logos and
/// differently-encoded credits account for the rest. Every difference this
/// rule is meant to catch — an extended edition, a director's cut, a
/// double-length episode file, an episode mistakenly matched to its whole
/// season — is far outside it, so 5% separates the two populations with room
/// on both sides rather than splitting either.
const double runtimeCompatibilityTolerance = 0.05;

/// Whether [a] and [b] can be reconciled on *progress* at all (G7,
/// hoofdstuk 13.2).
///
/// Unknown runtimes are not "clearly incompatible": an item with no
/// [MediaItem.durationMs] can never report [MediaItem.hasActiveProgress]
/// either, so nothing is projected by leaving it comparable, and treating
/// missing metadata as a conflict would silently disable the tier for every
/// backend that ships a slim field set.
///
/// Two *known* runtimes outside [runtimeCompatibilityTolerance] are a real
/// conflict: "A is at 1:20:00 and B at 0:40:00, so A is further" is not a
/// fact about the title when A is a three-hour extended cut and B a
/// ninety-minute theatrical one. It is the same sentence about two different
/// films.
bool runtimesAreComparable(MediaItem a, MediaItem b) {
  final da = a.durationMs;
  final db = b.durationMs;
  if (da == null || db == null || da <= 0 || db <= 0) return true;
  final longest = da > db ? da : db;
  return (da - db).abs() <= longest * runtimeCompatibilityTolerance;
}

/// Picks the representative source for a group's watch-state display
/// (hoofdstuk 13.2). [sources] maps a stable source key to the concrete item
/// carrying that source's watch-state; must be non-empty.
///
/// The tiers are **in order**, and each one only eliminates candidates it can
/// actually separate. That matters more than it looks: a pairwise "newest
/// wins" comparator is not transitive once a reliability margin is involved
/// (A and B are indistinguishable, B and C are indistinguishable, A and C are
/// not), so folding over pairs would make the answer depend on iteration
/// order. Each tier therefore filters the whole remaining set at once.
///
/// **Tier 1 — ownership.** Unchanged and upstream: `WatchStateStore` has
/// already applied this session's own writes to the items handed in here, and
/// its own `serverWinsMargin` rule decides when a server snapshot outranks a
/// local patch. Nothing in this file may second-guess that; it only chooses
/// between sources whose state is already settled.
///
/// **Tier 2 — reliable recency.** The newest [MediaItem.lastViewedAt] wins,
/// but only over sources it beats by more than [watchStateReliabilityMargin].
/// Inside the margin two timestamps do not order anything — they both mean
/// "around now" — so every candidate within it survives to the next tier
/// instead of a few seconds of clock skew deciding. A source with no
/// timestamp at all loses to one that has any: that is not a skew question
/// but an information one, and it is how G6 stays deterministic.
///
/// **Tier 3 — active progress over watched.** Only reached when recency
/// produced no reliable winner, which is exactly what keeps a demonstrably
/// newer watched event from being undone: a watched state beyond the margin
/// has already eliminated the older in-progress source in tier 2. Within the
/// margin, a source with real resumable progress speaks for the group over
/// one that merely says "finished", so a stale watched bit cannot bury a
/// position the viewer is actually sitting at.
///
/// **G7 gate.** Tier 3 and its raw-offset follow-up are progress
/// reconciliation, so they only run when the surviving candidates are
/// mutually runtime-comparable ([runtimesAreComparable]). When they are not,
/// hoofdstuk 13.2's "blijft progress brongebonden" applies: no progress fact
/// from one cut is allowed to outrank another, and the answer falls to tier 4.
/// The offset compared is raw milliseconds rather than a percentage for the
/// same reason — 13.2 forbids comparing percentages across runtimes — and the
/// gate now makes that promise hold instead of merely stating it.
///
/// **Tier 4 — remembered choice.** [preferredSourceKey] (hoofdstuk 14.8) is
/// the last deterministic tie-break, not a trump: it only picks among
/// candidates every earlier tier judged equal. A preferred source that is
/// stale, unwatched or behind never wins here, because it never gets this far
/// alone. With no preference and a real tie, the first source in [sources]'
/// iteration order keeps the win, so a caller that always iterates in the same
/// order gets a stable, deterministic pick.
UnifiedWatchState selectRepresentativeWatchState(Map<String, MediaItem> sources, {String? preferredSourceKey}) {
  assert(sources.isNotEmpty, 'selectRepresentativeWatchState requires at least one source');

  var candidates = sources.entries.toList();
  // Reported as a fact about the *group*: these memberships are not all the
  // same cut, whatever the tiers below decide.
  final runtimesDiffer = !_allRuntimesComparable(candidates);

  if (candidates.length > 1) {
    candidates = _tierReliableRecency(candidates);
  }
  // The G7 gate is re-read on the survivors, not on the group, because that is
  // what it is about: whether progress may be reconciled between the
  // candidates still in the running. Reading the group's value here let an
  // already-eliminated cut keep the progress tiers switched off — a year-old
  // extended edition, gone in tier 2, still deciding that a theatrical
  // half-watched and a theatrical watched could not be compared, so the winner
  // fell to map iteration order and the card drew a watched tick over thirty
  // minutes of real progress. Removing that third membership flipped the
  // answer, which is how it was found.
  if (candidates.length > 1 && _allRuntimesComparable(candidates)) {
    candidates = _tierActiveProgress(candidates);
    if (candidates.length > 1) candidates = _tierHighestRawOffset(candidates);
  }

  final winner = candidates.length > 1
      ? candidates.firstWhere((c) => c.key == preferredSourceKey, orElse: () => candidates.first)
      : candidates.first;

  final item = winner.value;
  return UnifiedWatchState(
    representativeSourceKey: winner.key,
    lastViewedAt: item.lastViewedAt,
    hasActiveProgress: item.hasActiveProgress,
    isWatched: item.isWatched,
    runtimesDiffer: runtimesDiffer,
  );
}

/// Whether every pair among [candidates] is runtime-comparable. Evaluated
/// over the whole set rather than pairwise during selection: comparability is
/// not transitive, and a group that is coherent for one pair and not for
/// another has no single answer to "may progress be reconciled here". The
/// honest reading of that is the conservative one — it may not.
bool _allRuntimesComparable(List<MapEntry<String, MediaItem>> candidates) {
  for (var i = 0; i < candidates.length; i++) {
    for (var j = i + 1; j < candidates.length; j++) {
      if (!runtimesAreComparable(candidates[i].value, candidates[j].value)) return false;
    }
  }
  return true;
}

/// Drops every candidate a newer timestamp beats by more than
/// [watchStateReliabilityMargin]. Returns [candidates] untouched when nobody
/// carries a timestamp (G6).
List<MapEntry<String, MediaItem>> _tierReliableRecency(List<MapEntry<String, MediaItem>> candidates) {
  final timed = candidates.where((c) => c.value.lastViewedAt != null).toList();
  if (timed.isEmpty) return candidates;

  var newest = timed.first.value.lastViewedAt!;
  for (final candidate in timed.skip(1)) {
    final at = candidate.value.lastViewedAt!;
    if (at > newest) newest = at;
  }
  // lastViewedAt is epoch *seconds* on every backend that reports it.
  final marginSeconds = watchStateReliabilityMargin.inSeconds;
  return timed.where((c) => newest - c.value.lastViewedAt! <= marginSeconds).toList();
}

/// Keeps the candidates with resumable progress when any has it, so a stale
/// watched bit cannot outrank a position the viewer is sitting at.
List<MapEntry<String, MediaItem>> _tierActiveProgress(List<MapEntry<String, MediaItem>> candidates) {
  final active = candidates.where((c) => c.value.hasActiveProgress).toList();
  return active.isEmpty ? candidates : active;
}

/// Hoofdstuk 13.2's last progress fallback: the highest raw offset. Raw
/// milliseconds, never a percentage — and only reachable behind the G7 gate,
/// so the runtimes it compares across are already known to be comparable.
List<MapEntry<String, MediaItem>> _tierHighestRawOffset(List<MapEntry<String, MediaItem>> candidates) {
  var highest = candidates.first.value.viewOffsetMs ?? 0;
  for (final candidate in candidates.skip(1)) {
    final offset = candidate.value.viewOffsetMs ?? 0;
    if (offset > highest) highest = offset;
  }
  return candidates.where((c) => (c.value.viewOffsetMs ?? 0) == highest).toList();
}
