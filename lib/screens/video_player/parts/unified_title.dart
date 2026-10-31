part of '../../video_player_screen.dart';

/// The player's side of one title across its sources. It only asks: which item
/// is next, and who hears about this one. The choice itself stays outside the
/// player (hoofdstuk 4.4).
extension _VideoPlayerUnifiedTitle on VideoPlayerScreenState {
  /// Keeps the other sources up to date with [metadata]. A card can show one
  /// source of three, so what the play came with is not all there is: the rest
  /// is looked up when it settles. Nothing waits for that, and no answer leaves
  /// it on the sources already known.
  PlaybackSettledCallback? _unifiedSettledCallback(MediaItem metadata, OfflineWatchSyncService? queue) {
    if (queue == null) return null;
    final title = widget.unifiedTitle;
    final known = title != null && title.holds(metadata) ? title : null;
    if (known != null) unawaited(known.prime());
    final discovery = UnifiedTitleDiscovery.of(context);
    if (known == null && discovery == null) return null;
    return UnifiedProgressMirror(
      known: known,
      find: discovery == null ? null : () => discovery.titleOf(metadata),
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
