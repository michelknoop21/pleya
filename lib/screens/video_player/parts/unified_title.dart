part of '../../video_player_screen.dart';

/// The player's side of one title across its sources. It only asks: which item
/// is next, and who hears about this one. The choice itself stays outside the
/// player (hoofdstuk 4.4).
extension _VideoPlayerUnifiedTitle on VideoPlayerScreenState {
  /// Keeps the other sources up to date with [metadata]. A play that came
  /// without them, a card that showed one source, looks them up when it settles:
  /// nothing waits for that, and no answer leaves it on this source.
  PlaybackSettledCallback? _unifiedSettledCallback(MediaItem metadata, OfflineWatchSyncService? queue) {
    if (queue == null) return null;
    final title = widget.unifiedTitle;
    if (title != null && title.holds(metadata)) {
      unawaited(title.prime());
      return UnifiedProgressMirror(title: title, playing: metadata, queue: queue).report;
    }
    final discovery = UnifiedTitleDiscovery.of(context);
    if (discovery == null) return null;
    return UnifiedProgressMirror.discovering(
      find: () => discovery.titleOf(metadata),
      playing: metadata,
      queue: queue,
    ).report;
  }

  Future<AdjacentEpisodes> _adjacentAcrossSources(MediaItem current, AdjacentEpisodes queued) => adjacentAcrossSources(
    title: widget.unifiedTitle,
    current: current,
    queued: queued,
    queue: context.read<PlaybackStateProvider>(),
    inWatchTogether: _activeWatchTogetherSession() != null,
  );
}
