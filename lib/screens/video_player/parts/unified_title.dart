part of '../../video_player_screen.dart';

/// The player's side of one title across its sources. It only asks: which item
/// is next, and who hears about this one. The choice itself stays outside the
/// player (hoofdstuk 4.4).
extension _VideoPlayerUnifiedTitle on VideoPlayerScreenState {
  /// Keeps the other sources up to date with [metadata]. Null without a title.
  PlaybackSettledCallback? _unifiedSettledCallback(MediaItem metadata, OfflineWatchSyncService? queue) {
    final title = widget.unifiedTitle;
    if (title == null || queue == null || !title.holds(metadata)) return null;
    unawaited(title.prime());
    return UnifiedProgressMirror(title: title, playing: metadata, queue: queue).report;
  }

  /// The queue's neighbours of [current], with an episode the chosen server
  /// lacks filled in from a source that has it, and the play back on the chosen
  /// server as soon as it can be. A shuffle or a playlist keeps its own order,
  /// and a Watch Together party stays on the server it agreed on.
  Future<AdjacentEpisodes> _adjacentAcrossSources(MediaItem current, AdjacentEpisodes queued) async {
    final title = widget.unifiedTitle;
    if (title == null || _activeWatchTogetherSession() != null || !title.holds(current)) return queued;
    final queue = context.read<PlaybackStateProvider>();
    final showKey = queue.shuffleContextKey;
    if (queue.isShuffleActive || (showKey != null && showKey != current.grandparentId)) return queued;
    try {
      final next = await title.neighbourOf(current, forward: true, queued: queued.next);
      final previous = await title.neighbourOf(current, forward: false, queued: queued.previous);
      return AdjacentEpisodes(next: next, previous: previous);
    } catch (e) {
      appLogger.d('Could not read the episodes across sources', error: e);
      return queued;
    }
  }
}
