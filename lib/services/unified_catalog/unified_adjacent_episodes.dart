/// What the player shows as next and previous when its title has more sources
/// (besluit 2 of DEC-XXX "Eén titel over servers heen", hoofdstuk 15 of
/// docs/tvos-unified-experience.md).
library;

import '../../media/media_item.dart';
import '../../providers/playback_state_provider.dart';
import '../../utils/app_logger.dart';
import '../episode_navigation_service.dart';
import 'unified_title_playback.dart';

/// The queue's neighbours of [current], with an episode the chosen server lacks
/// filled in from a source that has it, and the play back on the chosen server
/// as soon as it can be.
///
/// A shuffle or a playlist keeps its own order, and a Watch Together party
/// stays on the server it agreed on. [queue] is the provider [queued] came
/// from: a series queue names the series on the server that built it, which
/// after a borrowed episode is not the server that plays.
Future<AdjacentEpisodes> adjacentAcrossSources({
  required UnifiedTitlePlayback? title,
  required MediaItem current,
  required AdjacentEpisodes queued,
  required PlaybackStateProvider queue,
  required bool inWatchTogether,
}) async {
  if (title == null || inWatchTogether || !title.holds(current)) return queued;
  final context = queue.shuffleContextKey;
  if (queue.isShuffleActive || (context != null && !title.isSeriesKey(context))) return queued;
  try {
    return AdjacentEpisodes(
      next: await title.neighbourOf(current, forward: true, queued: queued.next),
      previous: await title.neighbourOf(current, forward: false, queued: queued.previous),
    );
  } catch (e) {
    appLogger.d('Could not read the episodes across sources', error: e);
    return queued;
  }
}
