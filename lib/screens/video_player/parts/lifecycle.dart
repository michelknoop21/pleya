part of '../../video_player_screen.dart';

extension _VideoPlayerLifecycleMethods on VideoPlayerScreenState {
  void _enqueueLifecycleTransition(String label, Future<void> Function() transition) {
    _lifecycleTransition = _lifecycleTransition
        .catchError((Object error, StackTrace stackTrace) {
          appLogger.w('Previous lifecycle transition failed', error: error, stackTrace: stackTrace);
        })
        .then((_) async {
          if (!mounted) return;
          try {
            await transition();
          } catch (e, stackTrace) {
            appLogger.w('Lifecycle transition failed during $label', error: e, stackTrace: stackTrace);
          }
        });
  }

  void _recordLifecycleState(String state, {String? action}) {
    final isTv = PlatformDetector.isTV();
    final pipActive = PipService().isPipActive.value;
    final breadcrumbData = <String, dynamic>{
      'state': state,
      'isTv': isTv,
      'autoPipEnabled': _autoPipEnabled,
      'pipActive': pipActive,
      'pipTransitionInFlight': _androidAutoPipTransitionInFlight,
      'hiddenForBackground': _hiddenForBackground,
      'mediaControlsSuspendedForTvBackground': _mediaControlsSuspendedForTvBackground,
      'pendingForegroundMediaResume': _resumeFromSuspendedMediaControlOnForeground,
      'backend': _playerBackendLabel,
    };
    if (action != null) {
      breadcrumbData['action'] = action;
    }

    Sentry.addBreadcrumb(
      Breadcrumb(message: 'Player lifecycle $state', category: 'player.lifecycle', data: breadcrumbData),
    );

    appLogger.d(
      'Player lifecycle: state=$state'
      '${action != null ? ' action=$action' : ''}'
      ' isTv=$isTv'
      ' autoPipEnabled=$_autoPipEnabled'
      ' pipActive=$pipActive'
      ' pipTransitionInFlight=$_androidAutoPipTransitionInFlight'
      ' hiddenForBackground=$_hiddenForBackground'
      ' mediaControlsSuspendedForTvBackground=$_mediaControlsSuspendedForTvBackground'
      ' pendingForegroundMediaResume=$_resumeFromSuspendedMediaControlOnForeground'
      ' backend=$_playerBackendLabel',
    );
  }

  void _setAndroidAutoPipTransitionInFlight(bool value, {required String reason}) {
    if (!Platform.isAndroid || _androidAutoPipTransitionInFlight == value) return;
    _androidAutoPipTransitionInFlight = value;
    _recordLifecycleState('pip_transition', action: '${value ? 'started' : 'cleared'}:$reason');
  }

  void _suspendLiveTimelineForBackground() {
    _live.resumeTimelineOnResume = _live.timelineTimer != null;
    _stopLiveTimelineUpdates();
  }

  void _resumeLiveTimelineAfterBackgroundIfNeeded() {
    final shouldResume = _live.resumeTimelineOnResume;
    _live.resumeTimelineOnResume = false;
    if (shouldResume && _live.session != null) {
      _startLiveTimelineUpdates();
    }
  }

  /// Re-read the backend position, then hand the write authority back.
  ///
  /// A revoked authority stays revoked when the refresh fails: without knowing
  /// the current state there is nothing this player can write safely.
  Future<void> _reconcileAndRetakeWriteAuthorityAfterResume() async {
    final authority = _playbackWriteAuthority;
    if (authority == null || authority.isHeld) return;

    try {
      await authority.retakeAfterRefresh(() async {
        final client = _playbackContext?.reportingClient;
        if (client == null) return;
        final fresh = await client.fetchItem(_currentMetadata.id);
        if (fresh != null && mounted) {
          _currentMetadata = _currentMetadata.copyWith(viewOffsetMs: fresh.viewOffsetMs);
        }
      }, reason: 'app resumed');
    } catch (e) {
      appLogger.w('Could not reconcile playback state on resume; keeping the write authority revoked', error: e);
    }
  }

  Future<void> _handleAppHidden() async {
    if (_shouldSkipForPip) {
      _recordLifecycleState('hidden', action: 'skipped_for_pip');
      return;
    }

    // Suppress Watch Together heartbeats while backgrounded so App Nap
    // doesn't cause stale position broadcasts that make guests loop.
    _watchTogetherProvider?.setBackgrounded(true);

    final currentPlayer = player;
    if (currentPlayer == null || !_isPlayerInitialized) {
      _recordLifecycleState('hidden', action: 'skipped_no_player');
      return;
    }

    final isTv = PlatformDetector.isTV();
    // iOS handhelds keep playing when backgrounded/locked: the native core
    // switches to audio-only (MpvPlayerCore.enterBackground sets vid=no), so
    // audio continues under lock and video restores on foreground. Pausing
    // here would defeat that — and the pause/native-restore race left the
    // player unresumable after unlock.
    final iosBackgroundAudio = Platform.isIOS && !isTv;
    final shouldPauseForBackground = !iosBackgroundAudio && (PlatformDetector.isHandheld(context) || isTv);

    // Pause first so Android MPV does not keep decoding against a transient
    // background surface while the app is locking or hiding.
    if (shouldPauseForBackground) {
      // Capture once per background cycle — see _backgroundPauseCaptured.
      if (!_backgroundPauseCaptured) {
        _backgroundPauseCaptured = true;
        _wasPlayingBeforeInactive = currentPlayer.state.isActive;
      }
      if (_wasPlayingBeforeInactive) {
        try {
          await _pauseWithPlaybackIntent(currentPlayer);
          appLogger.d('Video paused due to app being hidden (${isTv ? 'tv' : 'handheld'})');
        } catch (e) {
          appLogger.w('Failed to pause video before background transition', error: e);
        }
      }
    }

    if (!mounted || currentPlayer != player) return;

    if (shouldPauseForBackground) {
      await _flushFinalPlaybackReportForLifecycle('hidden', wasPlaying: _wasPlayingBeforeInactive);
      if (!mounted || currentPlayer != player) return;
    }

    _suspendLiveTimelineForBackground();

    if (isTv) {
      await _suspendMediaControlsForTvBackground('hidden');
      _recordLifecycleState('hidden', action: 'tv_background_pause_only');
      return;
    }

    _hiddenForBackground = true;
    await currentPlayer.setVisible(false, restoreOnWindowVisible: Platform.isMacOS);
    _recordLifecycleState('hidden', action: 'render_hidden');
  }

  /// Flush at most one final report for a lifecycle transition.
  ///
  /// Everything about *whether* to write lives in
  /// [PlaybackLifecycleReportDecision]; this only supplies the three facts it
  /// asks for and performs the write. The tracker's own `sendStoppedProgressOnce`
  /// keeps the "exactly once" guarantee across the background, detach and
  /// dispose paths, which can all fire for the same exit.
  Future<void> _flushFinalPlaybackReportForLifecycle(String label, {required bool wasPlaying}) async {
    if (!_shouldFlushFinalPlaybackReport(label, wasPlaying: wasPlaying)) return;
    await _sendStoppedProgressOnce();
  }

  /// The synchronous half, for `dispose`, which cannot await.
  bool _shouldFlushFinalPlaybackReport(String label, {required bool wasPlaying}) {
    final tracker = _progressTracker;
    if (tracker == null) return false;

    final decision = PlaybackLifecycleReportDecision.resolve(
      authorityHeld: _playbackWriteAuthority?.isHeld ?? true,
      wasPlaying: wasPlaying,
      positionChanged: tracker.hasReportablePositionChange,
    );
    if (decision == PlaybackLifecycleReport.none) {
      appLogger.d('Lifecycle $label: no final playback report needed');
      return false;
    }

    appLogger.d('Lifecycle $label: flushing one final playback report');
    return true;
  }

  Future<void> _handleAppResumed() async {
    _recordLifecycleState('resumed', action: 'begin');
    _watchTogetherProvider?.setBackgrounded(false);

    if (Platform.isAndroid && _androidAutoPipTransitionInFlight && !PipService().isPipActive.value) {
      _setAndroidAutoPipTransitionInFlight(false, reason: 'resume_without_pip');
    }

    final currentPlayer = player;

    // Restore render layer if it was hidden for background, then force a
    // video-output refresh before any auto-resume logic runs.
    if (_hiddenForBackground && currentPlayer != null && _isPlayerInitialized) {
      await currentPlayer.setVisible(true);
      if (!Platform.isMacOS) {
        await currentPlayer.updateFrame();
      }

      if (!mounted || currentPlayer != player) return;

      _hiddenForBackground = false;
      _recordLifecycleState('resumed', action: 'render_restored');
    }

    // Restore media controls and wakelock when app is resumed.
    if (_isPlayerInitialized && mounted) {
      _resumeMediaControlsAfterTvBackground('app_resumed');
      await _restoreMediaControlsAfterResume();
    }
    // Re-arm the background-pause capture for the next background cycle —
    // also when the restore above didn't run (not playing before background).
    _backgroundPauseCaptured = false;

    _resumeLiveTimelineAfterBackgroundIfNeeded();

    // Resuming reads the backend's current state first and only then takes the
    // write authority back. Taking it first would let this player report a
    // position it has not reconciled, which is the overwrite the authority
    // exists to prevent.
    await _reconcileAndRetakeWriteAuthorityAfterResume();

    _recordLifecycleState('resumed', action: 'complete');
  }
}
