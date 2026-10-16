/// The one status line a Verder kijken card carries, on every platform.
///
/// Mockup 38 A / 22 (4 oktober 2026) fixed two card types and nothing else:
///
/// | begonnen              | volgende aflevering          |
/// |-----------------------|------------------------------|
/// | `S3 E4 · 18 min over` | `S3 E5 · Volgende aflevering` |
/// | voortgangsbalk        | geen balk                     |
///
/// A next episode that is provably new says `Nieuwe aflevering`, or
/// `Nieuw seizoen` for the first episode of a later season
/// ([continueWatchingFreshness]); when that is not certain it stays "Volgende
/// aflevering".
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
import 'continue_watching_order.dart';
import 'formatters.dart';

enum ContinueWatchingState { inProgress, nextEpisode, unstarted }

/// The backend's own word where it gave one ([MediaItem.continueWatchingKind]);
/// otherwise progress decides, and an episode in the row without progress is,
/// by construction of every fetcher, the next episode of its series.
ContinueWatchingState continueWatchingStateFor(MediaItem item) {
  switch (item.continueWatchingKind) {
    case ContinueWatchingKind.nextUp:
      return ContinueWatchingState.nextEpisode;
    case ContinueWatchingKind.resume:
      return ContinueWatchingState.inProgress;
    case null:
      if (item.hasActiveProgress) return ContinueWatchingState.inProgress;
      return item.isEpisode ? ContinueWatchingState.nextEpisode : ContinueWatchingState.unstarted;
  }
}

/// The status line itself. [showEpisodeNumber] follows the
/// `showEpisodeNumberOnCards` setting: off, an episode keeps only its season.
/// [includePlace] false drops `S3 E4` altogether, for a row that already
/// states the place on its own line (the iPhone overview).
String continueWatchingStatusLine(
  MediaItem item, {
  bool showEpisodeNumber = true,
  bool includePlace = true,
  DateTime? now,
}) {
  final parts = <String>[];
  if (includePlace && item.isEpisode && item.parentIndex != null) {
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
      parts.add(continueWatchingNextEpisodeWording(item, now: now));
    case ContinueWatchingState.unstarted:
      final duration = item.durationMs;
      if (duration != null && duration > 0) parts.add(formatDurationTextual(duration));
  }
  return parts.join(' · ');
}

/// What a next-episode card says about itself: new episode, new season, or the
/// plain "next episode". The one wording the status line and the TV focus line
/// share.
String continueWatchingNextEpisodeWording(MediaItem item, {DateTime? now}) =>
    switch (continueWatchingFreshness(item, now: now ?? DateTime.now())) {
      ContinueWatchingFreshness.newSeason => t.discover.newSeasonStatus,
      ContinueWatchingFreshness.newEpisode => t.discover.newEpisodeStatus,
      ContinueWatchingFreshness.none => t.discover.nextEpisodeStatus,
    };
