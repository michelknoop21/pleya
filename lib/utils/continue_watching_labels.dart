/// The one status line a Verder kijken card carries, on every platform.
///
/// Mockup 38 A / 22 (4 oktober 2026) fixed two card types and nothing else:
///
/// | begonnen              | volgende aflevering          |
/// |-----------------------|------------------------------|
/// | `S3 E4 · 18 min over` | `S3 E5 · Volgende aflevering` |
/// | voortgangsbalk        | geen balk                     |
///
/// A film says `42 min over`, or its runtime when nothing of it was watched.
/// Episode title and "2 dagen geleden" are deliberately not here: they belong
/// to the TV focus line and the full overview, not to a card at rest. The
/// remaining time is [formatRemainingTime], the same phrase the detail page's
/// resume button and the TV focus line use, so one fact has one wording.
library;

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import 'formatters.dart';

enum ContinueWatchingState { inProgress, nextEpisode, unstarted }

/// Derived from progress for now. Phase 2 (the sectioned overview) adds the
/// explicit resume/next-up origin from each backend; until then an episode in
/// the row without active progress is, by construction of every fetcher, the
/// next episode of its series.
ContinueWatchingState continueWatchingStateFor(MediaItem item) {
  if (item.hasActiveProgress) return ContinueWatchingState.inProgress;
  return item.isEpisode ? ContinueWatchingState.nextEpisode : ContinueWatchingState.unstarted;
}

/// The status line itself. [showEpisodeNumber] follows the
/// `showEpisodeNumberOnCards` setting: off, an episode keeps only its season.
String continueWatchingStatusLine(MediaItem item, {bool showEpisodeNumber = true}) {
  final parts = <String>[];
  if (item.isEpisode && item.parentIndex != null) {
    parts.add(
      showEpisodeNumber && item.index != null
          ? t.unifiedCatalog.discovery.episodeLabel(season: item.parentIndex!, episode: item.index!)
          : 'S${item.parentIndex}',
    );
  }
  switch (continueWatchingStateFor(item)) {
    case ContinueWatchingState.inProgress:
      final left = formatRemainingTime(item.durationMs, item.viewOffsetMs);
      if (left != null) parts.add(left);
    case ContinueWatchingState.nextEpisode:
      parts.add(t.discover.nextEpisodeStatus);
    case ContinueWatchingState.unstarted:
      final duration = item.durationMs;
      if (duration != null && duration > 0) parts.add(formatDurationTextual(duration));
  }
  return parts.join(' · ');
}
