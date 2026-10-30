part of '../../media_detail_screen.dart';

/// The pill and the round actions under the synopsis.
extension _MediaDetailTvActionRow on _MediaDetailScreenState {
  /// A round action, addressable by [id] like every button on the row.
  Widget _tvDetailRoundAction(
    FocusableActionBuildState state,
    String id, {
    required Widget icon,
    required String? label,
    required VoidCallback? onPressed,
  }) {
    return AutomationNode(
      id: AutomationIds.mediaDetailAction,
      instance: id,
      role: 'button',
      label: label,
      focusNode: state.focusNode,
      state: () => {'enabled': onPressed != null},
      child: Pressable(
        onTap: onPressed,
        child: Semantics(
          button: true,
          label: label,
          child: TvDetailRoundButton(focused: state.showFocus, child: icon),
        ),
      ),
    );
  }

  /// The pill and the round actions of 06. Trailer and request sit in the ⋮
  /// menu here: the row has room for what the northstar draws, and the menu
  /// already offers both.
  Widget _buildTvDetailActionRow(MediaItem metadata) {
    final model = _detailActionModel(metadata);
    final pt = TvHig.of(context);
    final iconSize = TvHig.body * pt;
    final play = model.of(_DetailActionKind.play)!;
    // A series resumes into an episode, so that is what the ring reads.
    final target = _tvDetailResumeTarget(metadata);
    final resumable = (target?.viewOffsetMs ?? 0) > 0;
    final progress = resumable && (target?.durationMs ?? 0) > 0
        ? (target!.viewOffsetMs! / target.durationMs!).clamp(0.0, 1.0).toDouble()
        : null;
    final left = resumable && target?.durationMs != null
        ? formatDurationSpaced(target!.durationMs! - target.viewOffsetMs!)
        : null;
    final label = !resumable
        ? t.common.play
        : left == null
        ? t.common.resume
        : '${t.common.resume} • ${t.nowWatching.remaining(time: left)}';

    FocusableAction round(String id, VoidCallback? onPressed, Widget icon, {String? tooltip}) => FocusableAction(
      debugLabel: 'detail_$id',
      onPressed: onPressed,
      builder: (context, state) => _tvDetailRoundAction(state, id, icon: icon, label: tooltip, onPressed: onPressed),
    );

    final watchlist = model.of(_DetailActionKind.watchlist);
    final download = model.of(_DetailActionKind.download);
    final watched = model.of(_DetailActionKind.watched)!;
    final more = model.of(_DetailActionKind.more);
    final request = model.of(_DetailActionKind.request);
    void onRestart() => unawaited(_handlePlayFromStart(target ?? metadata));
    void onRate() => unawaited(_showRatingDialog(context, metadata));

    return FocusableActionBar(
      spacing: TvDetailLayout.actionGap * pt,
      onFocusChange: _setTvDetailActionRowFocus,
      onNavigateUp: _focusAboveActionRow,
      onNavigateDown: _focusBelowActionRow,
      actions: [
        FocusableAction(
          debugLabel: 'detail_play',
          focusNode: _playButtonFocusNode,
          onPressed: play.onPressed,
          builder: (context, state) => AutomationNode(
            id: AutomationIds.mediaDetailPlay,
            role: 'button',
            state: () => {'enabled': play.onPressed != null, 'resumable': resumable},
            focusNode: _playButtonFocusNode,
            child: Pressable(
              onTap: play.onPressed,
              child: metadata.isMovie
                  ? TvDetailPlayPill(
                      label: label,
                      icon: _getPlayButtonIcon(metadata),
                      progress: progress,
                      focused: state.showFocus,
                      enabled: play.onPressed != null,
                    )
                  : Semantics(
                      button: true,
                      label: label,
                      child: TvDetailRoundButton(
                        focused: state.showFocus,
                        child: progress == null
                            ? AppIcon(Symbols.play_arrow_rounded, fill: 1, size: iconSize)
                            : TvDetailProgressRing(value: progress),
                      ),
                    ),
            ),
          ),
        ),
        if (resumable && !widget.isOffline)
          round(
            'restart',
            onRestart,
            AppIcon(Symbols.replay_rounded, fill: 1, size: iconSize),
            tooltip: t.mediaMenu.playFromBeginning,
          ),
        if (watchlist != null)
          round(
            _DetailActionKind.watchlist.name,
            watchlist.onPressed,
            AppIcon(watchlist.icon!, fill: watchlist.iconFilled ? 1 : 0, size: iconSize),
            tooltip: watchlist.tooltip,
          ),
        if (!widget.isOffline)
          round(
            'rate',
            onRate,
            AppIcon(Symbols.star_rounded, fill: (metadata.userRating ?? 0) > 0 ? 1 : 0, size: iconSize),
            tooltip: t.mediaMenu.rate,
          ),
        round(
          _DetailActionKind.watched.name,
          watched.onPressed,
          AppIcon(metadata.isWatched ? Symbols.remove_done_rounded : Symbols.check_rounded, fill: 1, size: iconSize),
          tooltip: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
        ),
        if (download != null)
          round(
            _DetailActionKind.download.name,
            download.onPressed,
            AppIcon(Symbols.download_rounded, fill: 1, size: iconSize),
            tooltip: t.downloads.downloadNow,
          ),
        if (more != null)
          FocusableAction(
            debugLabel: 'detail_more',
            onPressed: more.onPressed,
            builder: (context, state) => AutomationNode(
              id: AutomationIds.mediaDetailAction,
              instance: _DetailActionKind.more.name,
              role: 'button',
              focusNode: state.focusNode,
              child: MediaContextMenu(
                key: _contextMenuKey,
                item: metadata,
                onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
                onPlayTrailer: model.onPlayTrailer,
                onRequest: request?.onPressed,
                child: TvDetailRoundButton(
                  focused: state.showFocus,
                  child: AppIcon(Symbols.more_vert_rounded, fill: 1, size: iconSize),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// What Play starts, for the ring and the restart button.
  MediaItem? _tvDetailResumeTarget(MediaItem metadata) {
    if (metadata.isMovie) return metadata;
    if (metadata.isShow) {
      final onDeck = _onDeckEpisode;
      return onDeck == null ? null : _fresh(onDeck);
    }
    final next = _seasonNextEpisode;
    return next == null ? null : _fresh(next);
  }

  Future<void> _handlePlayFromStart(MediaItem metadata) async {
    final pick = _detailTrackPickFor(metadata);
    await playFromBeginning(context, metadata, preferredAudioTrack: pick.audio, preferredSubtitleTrack: pick.subtitle);
    if (mounted) await refreshAfterPlayback(playedItemId: metadata.id);
  }
}
