/// The order of the Verder kijken list, in one place.
///
/// 1. What the user watched last comes first.
/// 2. Straight after it come at most [continueWatchingFreshLimit] series that
///    got a new episode or a new season, newest first, also when the series was
///    last watched months ago.
/// 3. The other active titles, on their last activity.
/// 4. Eerder begonnen: titles left alone for longer than
///    [continueWatchingStaleAfter], newest first.
///
/// A new episode only jumps the queue for [continueWatchingFreshWindow]; after
/// that it is an ordinary next episode. It is only called new when the data
/// proves it: a next-up item whose episode was added after the series was last
/// watched. Without both dates there is no label and no priority.
library;

import '../media/media_item.dart';
import '../media/media_item_types.dart';

/// Michel, 4 oktober 2026: a fixed product rule, not a user setting.
const Duration continueWatchingStaleAfter = Duration(days: 90);

/// How long a new episode keeps its priority. The same 14 days as the corner
/// badge on cards (`new_content_badge.dart`).
const Duration continueWatchingFreshWindow = Duration(days: 14);

/// At most this many new-episode cards go straight after the last watched one.
const int continueWatchingFreshLimit = 2;

/// An episode added on the day of the last watch is not new: the margin covers
/// a library scan that ran while the user was watching.
const Duration _addedAfterWatchMargin = Duration(days: 1);

enum ContinueWatchingFreshness { none, newEpisode, newSeason }

/// Whether [item] is a new episode or the first episode of a new season of a
/// series the user followed.
///
/// Needs a next-up item with `addedAt` and a `lastViewedAt` that is the last
/// time the *series* was watched (the backend or the client puts it there for a
/// next-up item). Anything less is [ContinueWatchingFreshness.none], so an
/// unsure case shows the plain "Volgende aflevering".
ContinueWatchingFreshness continueWatchingFreshness(MediaItem item, {required DateTime now}) {
  if (item.continueWatchingKind != ContinueWatchingKind.nextUp || !item.isEpisode) {
    return ContinueWatchingFreshness.none;
  }
  final added = item.addedAt;
  final watched = item.lastViewedAt;
  if (added == null || watched == null) return ContinueWatchingFreshness.none;

  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  if (added > nowSeconds + _addedAfterWatchMargin.inSeconds) return ContinueWatchingFreshness.none; // clock skew
  if (nowSeconds - added > continueWatchingFreshWindow.inSeconds) return ContinueWatchingFreshness.none;
  if (added <= watched + _addedAfterWatchMargin.inSeconds) return ContinueWatchingFreshness.none;

  final season = item.parentIndex;
  final isFirstOfNewSeason = item.index == 1 && season != null && season > 1;
  return isFirstOfNewSeason ? ContinueWatchingFreshness.newSeason : ContinueWatchingFreshness.newEpisode;
}

/// Begun and then left alone for longer than [continueWatchingStaleAfter].
/// Something without a date is never old, and neither is a new episode.
bool isContinueWatchingStale(MediaItem item, {required DateTime now}) {
  if (continueWatchingFreshness(item, now: now) != ContinueWatchingFreshness.none) return false;
  final last = item.lastViewedAt;
  if (last == null) return false;
  return now.difference(DateTime.fromMillisecondsSinceEpoch(last * 1000)) > continueWatchingStaleAfter;
}

/// [items] in the order described above. [itemOf] reads the `MediaItem` out of
/// whatever the caller orders (a plain item, a unified group). The sort is
/// stable: equal items keep their incoming order.
List<T> orderContinueWatching<T>(Iterable<T> items, {required MediaItem Function(T) itemOf, DateTime? now}) {
  final at = now ?? DateTime.now();
  final entries = [
    for (final (index, value) in items.indexed)
      (index: index, value: value, item: itemOf(value), fresh: continueWatchingFreshness(itemOf(value), now: at)),
  ];
  if (entries.length < 2) return [for (final e in entries) e.value];

  // 1. Last watched: the highest lastViewedAt; the first one wins a tie.
  var head = entries.first;
  for (final e in entries) {
    if ((e.item.lastViewedAt ?? -1) > (head.item.lastViewedAt ?? -1)) head = e;
  }

  // 2. New episodes and seasons, newest first, capped.
  final fresh = entries.where((e) => !identical(e, head) && e.fresh != ContinueWatchingFreshness.none).toList()
    ..sort((a, b) => _byDescending(a.item.addedAt ?? 0, b.item.addedAt ?? 0, a.index, b.index));
  final promoted = fresh.take(continueWatchingFreshLimit).toList();

  // 3 and 4. The rest on recency, with the stale ones behind the active ones.
  final rest = entries.where((e) => !identical(e, head) && !promoted.any((p) => identical(p, e))).toList();
  int byRecency(a, b) => _byDescending(a.item.recencySortKey, b.item.recencySortKey, a.index, b.index);
  final active = rest.where((e) => !isContinueWatchingStale(e.item, now: at)).toList()..sort(byRecency);
  final stale = rest.where((e) => isContinueWatchingStale(e.item, now: at)).toList()..sort(byRecency);

  return [
    for (final e in [head, ...promoted, ...active, ...stale]) e.value,
  ];
}

int _byDescending(int a, int b, int aIndex, int bIndex) {
  final byValue = b.compareTo(a);
  return byValue != 0 ? byValue : aIndex.compareTo(bIndex);
}
