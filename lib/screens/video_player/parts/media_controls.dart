part of '../../video_player_screen.dart';

extension _VideoPlayerMediaControlsMethods on VideoPlayerScreenState {
  bool get _shouldSuspendMediaControlsForTvBackground =>
      Platform.isAndroid && PlatformDetector.isTV() && !_shouldSkipForPip;

  Future<void> _suspendMediaControlsForTvBackground(String reason) async {
    if (!_shouldSuspendMediaControlsForTvBackground) return;

    _mediaControlsManager?.suspendUpdates();
    if (!_mediaControlsSuspendedForTvBackground) {
      _mediaControlsSuspendedForTvBackground = true;
      _recordLifecycleState('media_controls', action: 'suspended:$reason');
    }

    await _mediaControlsManager?.clear();
  }

  void _resumeMediaControlsAfterTvBackground(String reason) {
    if (!_mediaControlsSuspendedForTvBackground) return;

    _mediaControlsSuspendedForTvBackground = false;
    _mediaControlsManager?.resumeUpdates();
    _recordLifecycleState('media_controls', action: 'resumed:$reason');
  }

  bool _consumePendingTvBackgroundMediaControlResume() {
    final shouldResume = _resumeFromSuspendedMediaControlOnForeground;
    _resumeFromSuspendedMediaControlOnForeground = false;
    _tvBackgroundMediaControlResumeTimer?.cancel();
    _tvBackgroundMediaControlResumeTimer = null;
    return shouldResume;
  }

  Future<void> _requestForegroundResumeFromSuspendedMediaControl(String eventLabel) async {
    if (!_mediaControlsSuspendedForTvBackground) return;

    _resumeFromSuspendedMediaControlOnForeground = true;
    _tvBackgroundMediaControlResumeTimer?.cancel();
    _tvBackgroundMediaControlResumeTimer = Timer(const Duration(seconds: 8), () {
      _tvBackgroundMediaControlResumeTimer = null;
      if (!mounted || !_mediaControlsSuspendedForTvBackground) return;
      _resumeFromSuspendedMediaControlOnForeground = false;
      appLogger.d('Media control: deferred TV foreground resume expired before app resumed');
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: 'TV media control foreground resume expired',
            category: 'player.media_controls',
            data: {'event': eventLabel},
          ),
        ),
      );
    });

    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'TV media control requested foreground resume',
          category: 'player.media_controls',
          data: {'event': eventLabel},
        ),
      ),
    );

    final foregrounded = await AppForegroundService.requestForeground();
    appLogger.d('Media control: requested app foreground for $eventLabel (success=$foregrounded)');
    if (!foregrounded && mounted && _mediaControlsSuspendedForTvBackground) {
      _consumePendingTvBackgroundMediaControlResume();
    }
  }

  Future<void> _syncMediaControlsAvailability() async {
    if (_mediaControlsSuspendedForTvBackground) return;

    final manager = _mediaControlsManager;
    final currentPlayer = player;
    if (!mounted || manager == null || currentPlayer == null) return;

    final playbackState = context.read<PlaybackStateProvider>();
    final canNavigateEpisodes = _currentMetadata.isEpisode || playbackState.isPlaylistActive;
    final canSeek = _canSystemSeek;

    if (!mounted || currentPlayer != player || manager != _mediaControlsManager) return;

    await manager.setControlsEnabled(
      canGoNext: canNavigateEpisodes,
      canGoPrevious: canNavigateEpisodes,
      canSeek: canSeek,
    );
  }

  bool get _canSystemSeek => !widget.isLive && (player?.state.seekable == true || _usesPlexVodTranscodeSeekPolicy);

  Map<String, SubtitleTrack> _systemSubtitleTracks() => {
    for (final track in player?.state.tracks.subtitle ?? <SubtitleTrack>[])
      if (track.id != 'auto' && track.id != 'no') track.id: track,
  };

  void _onSystemSubtitleVisibilityChanged() => unawaited(_syncSystemSubtitles());

  Future<void> _syncSystemSubtitles() async {
    if (!mounted || !PlatformDetector.isAppleTV()) return;
    final tracks = _systemSubtitleTracks();
    final sourceTracks = _sourceSubtitleTracksForControls();
    final useSource = _isTranscoding && sourceTracks.isNotEmpty && _currentMetadata.backend == MediaBackend.plex;
    try {
      await _mediaControlsManager?.updateSubtitleOptions(
        [
          if (useSource)
            for (final track in sourceTracks)
              {
                'id': 'source:${track.id}',
                'language': track.languageCode ?? 'und',
                'title': track.displayTitle ?? track.title ?? track.languageCode ?? '${track.id}',
              },
          if (!useSource && _playbackSession?.result.streamEvidence.subtitle != PlaybackSubtitleDecision.burn)
            for (final track in tracks.values)
              {'id': track.id, 'language': track.language ?? 'und', 'title': track.title ?? track.language ?? track.id},
        ],
        !_systemSubtitleVisibility.value
            ? null
            : (useSource
                  ? 'source:${_selectedSourceSubtitleStreamIdForControls(sourceTracks)}'
                  : player?.state.track.subtitle?.id),
      );
    } catch (e) {
      appLogger.w('Failed to publish system subtitle options', error: e);
    }
  }

  Future<void> _selectSystemSubtitle(SubtitleOptionEvent event) async {
    final currentPlayer = player;
    if (!mounted || currentPlayer == null || !_canControlPlaybackFromRemote()) return;
    final session = _playbackSession;
    final generation = _playbackGeneration;
    bool sameItem() =>
        mounted &&
        player == currentPlayer &&
        _canControlPlaybackFromRemote() &&
        _playbackSession?.metadata.globalKey == session?.metadata.globalKey;
    bool isCurrent() => sameItem() && _playbackGeneration == generation;
    final sourceTracks = _sourceSubtitleTracksForControls();
    if (_isTranscoding && sourceTracks.isNotEmpty && _currentMetadata.backend == MediaBackend.plex) {
      final id = event.enabled ? int.tryParse(event.id?.replaceFirst('source:', '') ?? '') : 0;
      if (id == null || (id != 0 && !sourceTracks.any((track) => track.id == id))) return;
      if (event.enabled) {
        await currentPlayer.setProperty('sub-visibility', 'yes');
        if (!isCurrent()) return;
        _systemSubtitleVisibility.value = true;
      }
      await _switchPlaybackSource(newSubtitleStreamId: id, isCurrent: isCurrent, shouldContinue: sameItem);
      await _syncSystemSubtitles();
      return;
    }
    if (_playbackSession?.result.streamEvidence.subtitle == PlaybackSubtitleDecision.burn) return;
    final track = event.enabled ? _systemSubtitleTracks()[event.id] : SubtitleTrack.off;
    if (track == null) return;
    if (track.id != 'no') {
      await currentPlayer.setProperty('sub-visibility', 'yes');
      if (!isCurrent()) return;
      _systemSubtitleVisibility.value = true;
    }
    await currentPlayer.selectSubtitleTrack(track);
    if (!isCurrent()) return;
    await _onSubtitleTrackChanged(track, isCurrent: isCurrent);
    await _syncSystemSubtitles();
  }

  Future<void> _seekBackForRewind(Player p) async {
    if (_rewindOnResume <= 0) return;
    final target = p.state.position - Duration(seconds: _rewindOnResume);
    await _seekPlayback(clampSeekPosition(p, target));
  }

  Future<void> _restoreMediaControlsAfterResume() async {
    if (!_isPlayerInitialized || !mounted) return;

    final resumeRequestedByMediaControl = _consumePendingTvBackgroundMediaControlResume();

    unawaited(_setWakelock(player?.state.isActive ?? false));

    final manager = _mediaControlsManager;
    final currentPlayer = player;
    if (manager != null && currentPlayer != null) {
      final client = _isOfflinePlayback ? null : _getMediaServerClient(context);
      await manager.updateMetadata(
        metadata: _currentMetadata,
        client: client,
        duration: _currentMetadata.durationMs != null ? Duration(milliseconds: _currentMetadata.durationMs!) : null,
      );
      await _syncMediaControlsAvailability();
    }

    if (!mounted || currentPlayer != player || currentPlayer == null) return;

    final wasPlayingBeforeInactive = _wasPlayingBeforeInactive;
    if (wasPlayingBeforeInactive || resumeRequestedByMediaControl) {
      final resumeReason = resumeRequestedByMediaControl
          ? 'TV media control foreground request'
          : 'returning from inactive state';
      try {
        await _seekBackForRewind(currentPlayer);
        await _playWithPlaybackIntent(currentPlayer);
        appLogger.d('Video resumed after $resumeReason');
      } catch (e) {
        appLogger.w('Failed to resume playback after $resumeReason', error: e);
      } finally {
        _wasPlayingBeforeInactive = false;
        _backgroundPauseCaptured = false;
      }
    }

    _updateMediaControlsPlaybackState();
    appLogger.d('Media controls restored on app resume');
  }

  /// Wrapper method to update media controls playback state
  void _updateMediaControlsPlaybackState() {
    if (_mediaControlsSuspendedForTvBackground) return;
    if (player == null) return;

    _mediaControlsManager?.updatePlaybackState(
      isPlaying: player!.state.isActive,
      position: player!.state.position,
      speed: player!.state.rate,
      force: true, // Force update since this is an explicit state change
    );
  }
}
