/// Merge a backend's two continue-watching sources, resume and Next Up, into
/// one recency-ordered shelf. Lifted out of the Jellyfin client so Pleya
/// Server (DEC-144 fase 2) merges its `continue_watching` and `next_up` hubs
/// by exactly the same rule.
///
/// Resume items are deduped first so an in-progress episode wins over the
/// same series' Next Up entry, then the combined list is ordered by
/// [MediaItem.recencySortKey] (matching `DataAggregationService`) before the
/// limit is applied, so a recent Next Up episode is never starved by a long
/// run of older resume items. Each item is stamped with its origin.
library;

import '../media/media_item.dart';
import '../media/media_kind.dart';

List<MediaItem> mergeContinueWatchingAndNextUp({
  required List<MediaItem> resume,
  required List<MediaItem> nextUp,
  required int? limit,
}) {
  if (limit != null && limit <= 0) return const [];

  final merged = <MediaItem>[];
  final seenIds = <String>{};
  final seenSeriesIds = <String>{};

  // Resume first: first-wins dedup makes an in-progress episode beat the same
  // series' Next Up entry.
  for (final item in [
    for (final r in resume) r.copyWith(continueWatchingKind: ContinueWatchingKind.resume),
    for (final n in nextUp) n.copyWith(continueWatchingKind: ContinueWatchingKind.nextUp),
  ]) {
    if (!seenIds.add(item.id)) continue;
    final seriesId = item.kind == MediaKind.episode ? item.grandparentId : null;
    if (seriesId != null && !seenSeriesIds.add(seriesId)) continue;
    merged.add(item);
  }

  // Stable sort by recency: Dart's List.sort isn't stable, so break ties on the
  // insertion index to keep ordering deterministic across refreshes.
  final ordered = [for (var i = 0; i < merged.length; i++) (item: merged[i], index: i)];
  ordered.sort((a, b) {
    final byRecency = b.item.recencySortKey.compareTo(a.item.recencySortKey);
    return byRecency != 0 ? byRecency : a.index.compareTo(b.index);
  });
  final result = [for (final entry in ordered) entry.item];

  if (limit != null && result.length > limit) return result.sublist(0, limit);
  return result;
}
