part of '../../video_player_screen.dart';

/// The player's side of one title across its sources. It only asks: which item
/// is next, and who hears about this one. The choice itself stays outside the
/// player (hoofdstuk 4.4).
extension _VideoPlayerUnifiedTitle on VideoPlayerScreenState {
  PlaybackSettledCallback? _unifiedSettledCallback(MediaItem metadata, OfflineWatchSyncService? queue) =>
      unifiedSettledCallback(
        metadata: metadata,
        queue: queue,
        title: widget.unifiedTitle,
        discovery: UnifiedTitleDiscovery.of(context),
      );

  Future<AdjacentEpisodes> _adjacentAcrossSources(MediaItem current, AdjacentEpisodes queued) => adjacentAcrossSources(
    title: widget.unifiedTitle,
    current: current,
    queued: queued,
    queue: context.read<PlaybackStateProvider>(),
    inWatchTogether: _activeWatchTogetherSession() != null,
  );
}
