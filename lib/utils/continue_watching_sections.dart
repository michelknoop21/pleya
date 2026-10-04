/// The four sections of the full Verder kijken overview (mockups 38 D, 23, 40,
/// DEC-144 fase 2). Every item lands in exactly one; empty sections disappear.
///
/// * Series hervatten: episodes with progress.
/// * Films hervatten: films with progress.
/// * Volgende afleveringen: the next episode of a series, nothing started yet.
/// * Eerder begonnen: begun more than [staleAfter] ago, less prominent, never
///   removed. Only something *begun* can be old: a next episode that just
///   became available is not, whatever the series' last-watched date says, and
///   an item without a date is never old either.
library;

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import 'continue_watching_labels.dart';

enum ContinueWatchingSection { resumeShows, resumeMovies, nextEpisodes, stale }

/// Michel, 4 oktober 2026: a fixed product rule, not a user setting.
const Duration continueWatchingStaleAfter = Duration(days: 90);

ContinueWatchingSection continueWatchingSectionFor(MediaItem item, {required DateTime now}) {
  final state = continueWatchingStateFor(item);
  if (state == ContinueWatchingState.nextEpisode) return ContinueWatchingSection.nextEpisodes;
  final last = item.lastViewedAt;
  if (last != null && now.difference(DateTime.fromMillisecondsSinceEpoch(last * 1000)) > continueWatchingStaleAfter) {
    return ContinueWatchingSection.stale;
  }
  return item.isEpisode ? ContinueWatchingSection.resumeShows : ContinueWatchingSection.resumeMovies;
}

/// Sections in display order, each keeping the input order of its items;
/// empty ones are left out. [itemOf] reads the `MediaItem` out of whatever the
/// caller sections (a unified group, a plain item).
List<(ContinueWatchingSection, List<T>)> continueWatchingSections<T>(
  Iterable<T> items, {
  required MediaItem Function(T) itemOf,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final buckets = {for (final s in ContinueWatchingSection.values) s: <T>[]};
  for (final item in items) {
    buckets[continueWatchingSectionFor(itemOf(item), now: at)]!.add(item);
  }
  return [
    for (final s in ContinueWatchingSection.values)
      if (buckets[s]!.isNotEmpty) (s, buckets[s]!),
  ];
}

String continueWatchingSectionTitle(ContinueWatchingSection section) => switch (section) {
  ContinueWatchingSection.resumeShows => t.discover.cwSectionResumeShows,
  ContinueWatchingSection.resumeMovies => t.discover.cwSectionResumeMovies,
  ContinueWatchingSection.nextEpisodes => t.discover.cwSectionNextEpisodes,
  ContinueWatchingSection.stale => t.discover.cwSectionStale,
};
