part of '../../video_player_screen.dart';

extension _VideoPlayerCompanionRemoteMethods on VideoPlayerScreenState {
  void _setupCompanionRemoteCallbacks() {
    final receiver = CompanionRemoteReceiver.instance;
    receiver.onStop = () {
      if (mounted) _handleBackButton();
    };
    receiver.onNextTrack = () {
      if (mounted && _nextEpisode != null) _playNext();
    };
    receiver.onPreviousTrack = () {
      if (mounted) unawaited(_restartOrPlayPrevious());
    };
    receiver.onSeekForward = () async {
      if (player == null) return;
      final settings = await SettingsService.getInstance();
      final seekSeconds = settings.read(SettingsService.seekTimeSmall);
      if (widget.isLive && _live.captureBuffer != null) {
        _liveSeek.seekBy(seekSeconds);
        return;
      }
      final target = clampSeekPosition(player!, player!.state.position + Duration(seconds: seekSeconds));
      await _seekPlayback(target);
    };
    receiver.onSeekBackward = () async {
      if (player == null) return;
      final settings = await SettingsService.getInstance();
      final seekSeconds = settings.read(SettingsService.seekTimeSmall);
      if (widget.isLive && _live.captureBuffer != null) {
        _liveSeek.seekBy(-seekSeconds);
        return;
      }
      final target = clampSeekPosition(player!, player!.state.position - Duration(seconds: seekSeconds));
      await _seekPlayback(target);
    };
    receiver.onVolumeUp = () async {
      if (player == null) return;
      final settings = await SettingsService.getInstance();
      final newVolume = (player!.state.volume + 10).clamp(0.0, kNormalVolumeMax.toDouble());
      unawaited(player!.setVolume(newVolume));
      unawaited(settings.write(SettingsService.volume, newVolume));
    };
    receiver.onVolumeDown = () async {
      if (player == null) return;
      final settings = await SettingsService.getInstance();
      final newVolume = (player!.state.volume - 10).clamp(0.0, kNormalVolumeMax.toDouble());
      unawaited(player!.setVolume(newVolume));
      unawaited(settings.write(SettingsService.volume, newVolume));
    };
    receiver.onVolumeMute = () async {
      if (player == null) return;
      final settings = await SettingsService.getInstance();
      final newVolume = player!.state.volume > 0 ? 0.0 : 100.0;
      unawaited(player!.setVolume(newVolume));
      unawaited(settings.write(SettingsService.volume, newVolume));
    };
    receiver.onSubtitles = _cycleSubtitleTrack;
    receiver.onAudioTracks = _cycleAudioTrack;
    receiver.onFullscreen = _toggleFullscreen;
    receiver.onFlyFollow = _answerFlyFollow;

    // Override home to exit the player first (main screen handler runs after pop)
    _savedOnHome = receiver.onHome;
    receiver.onHome = () {
      if (mounted) _handleBackButton();
    };

    // Store provider reference for use in dispose and notify remote
    try {
      _companionRemoteProvider = context.read<CompanionRemoteProvider>();
      _companionRemoteProvider!.sendCommand(RemoteCommandType.syncState, data: {'playerActive': true});
      // Phones in the Home see that a player is open and may ask what (A-23e).
      _companionRemoteProvider!.setNowPlayingBeacon(true);
    } catch (e) {
      appLogger.d('CompanionRemote provider unavailable', error: e);
    }
  }

  void _cleanupCompanionRemoteCallbacks() {
    final receiver = CompanionRemoteReceiver.instance;
    receiver.onStop = null;
    receiver.onNextTrack = null;
    receiver.onPreviousTrack = null;
    receiver.onSeekForward = null;
    receiver.onSeekBackward = null;
    receiver.onVolumeUp = null;
    receiver.onVolumeDown = null;
    receiver.onVolumeMute = null;
    receiver.onSubtitles = null;
    receiver.onAudioTracks = null;
    receiver.onFullscreen = null;
    receiver.onFlyFollow = null;
    receiver.onHome = _savedOnHome;
    _savedOnHome = null;

    // Notify remote that player is no longer active
    _companionRemoteProvider?.sendCommand(RemoteCommandType.syncState, data: {'playerActive': false});
    _companionRemoteProvider?.setNowPlayingBeacon(false);
    _companionRemoteProvider = null;
  }

  /// Tell the phone that handed this playback over that it now plays, once.
  void _acknowledgeHandoff() {
    final id = widget.handoffId;
    if (id == null || _handoffAcknowledged) return;
    _handoffAcknowledged = true;
    if (isPlaybackHandoffCancelled(id)) {
      // The phone gave up while this player opened: do not keep two devices playing.
      unawaited(_handleBackButton());
      return;
    }
    try {
      reportPlaybackHandoff(context.read<CompanionRemoteProvider>(), id, PlaybackHandoffOutcome.playing);
    } catch (e) {
      appLogger.d('Handoff acknowledgement not sent', error: e);
    }
  }

  /// mpv lists the sidecars and the one attached track on a server that selects
  /// subtitles, so the source list is what the viewer can cycle through. The
  /// switch stops a track that is still being prepared, as the track sheet does,
  /// and refuses while a reload runs, so that press has no track to announce.
  void _cycleSubtitleTrack() {
    if (_serverSupportsSubtitleSelection && !_isOfflinePlayback) {
      final tracks = _sourceSubtitleTracksForControls();
      final next = nextSourceSubtitleTrack(tracks, _selectedSourceSubtitleStreamIdForControls(tracks));
      if (next != null) {
        final accepted = _playbackTransition == _PlaybackTransition.idle;
        unawaited(_switchPlaybackSource(newSubtitleStreamId: next.id));
        if (accepted && mounted) {
          showAppSnackBar(
            context,
            'Subtitles: ${next.displayTitle ?? next.title ?? next.languageCode ?? next.id}',
            duration: const Duration(seconds: 1),
          );
        }
        return;
      }
    }
    _trackManager?.cycleSubtitleTrack();
  }

  void _cycleAudioTrack() => _trackManager?.cycleAudioTrack();

  Future<void> _toggleFullscreen() async {
    if (!PlatformDetector.isDesktopOS()) return;
    await FullscreenStateManager().toggleFullscreen();
  }
}
