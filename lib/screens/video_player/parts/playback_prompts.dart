part of '../../video_player_screen.dart';

extension _VideoPlayerPlaybackPromptMethods on VideoPlayerScreenState {
  void _onVideoCompleted(bool completed, {bool skipAutoPlayCountdown = false}) async {
    // Live TV streams are continuous — ignore spurious EOF events caused by
    // inter-segment gaps in the chunked MKV transcode stream.
    if (widget.isLive) return;
    if (!completed) return;
    // Ignore spurious EOF from the old file during an in-place media-source
    // transition (episode swap, transcode restart, channel switch). Remember
    // it: mpv flips `eof-reached` once per file, so a real completion that
    // lands here must be replayed when the transition settles instead of
    // disappearing. The replay re-checks that playback is still parked at the
    // end, which rules out the spurious case.
    if (_playbackTransition != _PlaybackTransition.idle) {
      appLogger.i('Autoplay: completion deferred, transition ${_playbackTransition.name} in flight');
      _pendingCompletion = true;
      return;
    }

    // mpv does not flip the `pause` property on EOF, so _onPlayingStateChanged
    // never fires false.  Normalize all playback-dependent state.
    unawaited(_setWakelock(false));
    final duration = player?.state.duration;
    unawaited(
      duration != null && duration.inMilliseconds > 0
          ? _sendStoppedProgressOnce(positionOverride: duration)
          : _sendStoppedProgressOnce(),
    );
    _updateMediaControlsPlaybackState();
    unawaited(DiscordRPCService.instance.pausePlayback());
    unawaited(TraktScrobbleService.instance.pausePlayback());
    if (_autoPipEnabled) {
      unawaited(_videoPIPManager?.updateAutoPipState(isPlaying: false));
    }

    // End-of-video sleep timer takes precedence over autoplay / next-episode
    // dialogs: the user explicitly asked to stop after this item.
    final sleepTimerService = SleepTimerService();
    if (sleepTimerService.isEndOfVideoMode && !_completionLatch.triggered) {
      _completionLatch.latch();
      sleepTimerService.notifyVideoCompleted();
      return;
    }

    if (_nextEpisode != null && !_showPlayNextDialog && !_showStillWatchingPrompt && !_completionLatch.triggered) {
      // PiP: skip dialog (user can't interact), auto-play immediately
      if (PipService().isPipActive.value) {
        _completionLatch.latch();
        unawaited(_playNext());
        return;
      }

      // Capture keyboard mode before async gap
      final isKeyboardMode = PlatformDetector.isTV() && InputModeTracker.isKeyboardMode(context);

      // Claim the prompt slot before the async gap. The skip/next button hides
      // on `hasPlayNextPrompt`, so waiting for the settings round-trip leaves
      // both next-episode affordances on screen during the credits. The
      // countdown stays idle until the setting is known, so the card cannot
      // flash a number while auto-play is off.
      _autoPlayCountdown.cancel();
      _setPlayerState(() {
        _showPlayNextDialog = true;
      });

      // Already-loaded settings keep this whole branch synchronous; the await
      // is only for the very first read of the session.
      final settings = SettingsService.instanceOrNull ?? await SettingsService.getInstance();
      if (!mounted) return;
      // Latch only now that the prompt is really going up: an unmount during
      // the settings round-trip must not burn the one EOF signal mpv sends.
      _completionLatch.latch();
      final autoPlayEnabled = settings.read(SettingsService.autoPlayNextEpisode);
      appLogger.i('Autoplay: play-next prompt shown, autoPlay=$autoPlayEnabled');

      if (skipAutoPlayCountdown && autoPlayEnabled) {
        unawaited(_playNext());
        return;
      }

      // Auto-focus Play Next button on TV when dialog appears (only in keyboard/TV mode)
      if (isKeyboardMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _playNextConfirmFocusNode.requestFocus();
          }
        });
      }

      if (autoPlayEnabled) {
        _startAutoPlayTimer();
      }
    } else if (_nextEpisode == null && !_completionLatch.triggered) {
      // The adjacent-episode fetch is fire-and-forget, so a short episode can
      // reach EOF before the next episode is known. Give it a moment before
      // falling back to closing the player.
      final pendingLoad = _adjacentEpisodesLoad;
      if (pendingLoad != null) {
        await pendingLoad.timeout(const Duration(seconds: 3), onTimeout: () {});
        if (!mounted) return;
        if (_nextEpisode != null) {
          appLogger.i('Autoplay: next episode resolved after waiting for the adjacent load');
          _onVideoCompleted(true, skipAutoPlayCountdown: skipAutoPlayCountdown);
          return;
        }
      }
      appLogger.i('Autoplay: no next episode, leaving the player');
      _completionLatch.latch();
      unawaited(_handleBackButton());
    } else {
      // Still-watching owns the screen: replay the completion once the user
      // confirms they are watching, otherwise this EOF is gone for good.
      if (_showStillWatchingPrompt) _pendingCompletion = true;
      appLogger.i(
        'Autoplay: completion ignored '
        '(next=${_nextEpisode != null}, prompt=$_showPlayNextDialog, '
        'stillWatching=$_showStillWatchingPrompt, latched=${_completionLatch.triggered})',
      );
    }
  }

  /// Replay a completion that arrived while something else owned the screen.
  /// Only valid while playback is still parked at the end of the same file —
  /// anything else (new item opened, user seeked back) drops it.
  void _retryPendingCompletion(String trigger) {
    if (!_pendingCompletion) return;
    _pendingCompletion = false;
    if (!mounted) return;
    final currentPlayer = player;
    if (currentPlayer == null) return;
    final durationMs = currentPlayer.state.duration.inMilliseconds;
    final positionMs = currentPlayer.state.position.inMilliseconds;
    if (durationMs <= 0 || positionMs < durationMs - _completionLatch.rearmWindowMs) return;
    appLogger.i('Autoplay: replaying deferred completion after $trigger');
    _onVideoCompleted(true);
  }

  void _startAutoPlayTimer() {
    appLogger.i('Autoplay: countdown started');
    _autoPlayCountdown.start(
      onTick: () => _setPlayerState(() {}),
      onElapsed: () {
        if (mounted) _playNext();
      },
    );
  }

  void _cancelAutoPlay() {
    _autoPlayCountdown.cancel();
    _unfocusPlayNextPrompt();
    _progressTracker?.resumeAfterStoppedReport();
    // Keep the latch set while playback is still parked at EOF, so duplicate
    // completed signals cannot re-open this prompt. It is re-armed once playback
    // seeks back clear of the end region (see the position listener) or new media loads.
    _setPlayerState(() {
      _showPlayNextDialog = false;
    });
  }

  void _dismissPlaybackPromptForBack() {
    if (_showPlayNextDialog) {
      _cancelAutoPlay();
      return;
    }
    if (_showStillWatchingPrompt) {
      _dismissStillWatching();
    }
  }

  /// Re-arm the end-of-video latch so Play Next can fire again. Callers
  /// decide *when* it is safe to re-arm (media reloaded, or playback moved
  /// back out of the end region); the latch itself refuses while a prompt
  /// or countdown is active.
  void _rearmCompletionLatch() {
    _completionLatch.rearmIfClear(promptVisible: _showPlayNextDialog, countdownActive: _autoPlayCountdown.isActive);
  }

  void _showStillWatchingDialog() {
    // Don't show if auto-play dialog is already visible
    if (_showPlayNextDialog) return;

    final isKeyboardMode = PlatformDetector.isTV() && InputModeTracker.isKeyboardMode(context);

    _setPlayerState(() {
      _showStillWatchingPrompt = true;
      _stillWatchingCountdown = 30;
    });

    if (isKeyboardMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _stillWatchingContinueFocusNode.requestFocus();
      });
    }

    _stillWatchingTimer?.cancel();
    _stillWatchingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _setPlayerState(() {
        _stillWatchingCountdown--;
      });
      if (_stillWatchingCountdown <= 0) {
        timer.cancel();
        _onStillWatchingTimeout();
      }
    });
  }

  void _onStillWatchingTimeout() {
    _unfocusStillWatchingPrompt();
    final currentPlayer = player;
    if (currentPlayer != null) unawaited(_pauseWithPlaybackIntent(currentPlayer));
    // Nobody is watching, so a completion that arrived behind this prompt must
    // not auto-advance once it closes.
    _pendingCompletion = false;
    _setPlayerState(() {
      _showStillWatchingPrompt = false;
    });
  }

  void _onStillWatchingContinue() {
    _stillWatchingTimer?.cancel();
    _unfocusStillWatchingPrompt();
    SleepTimerService().restartTimer();
    _setPlayerState(() {
      _showStillWatchingPrompt = false;
    });
    _retryPendingCompletion('still-watching confirmed');
  }

  void _onStillWatchingPause() {
    _stillWatchingTimer?.cancel();
    _unfocusStillWatchingPrompt();
    final currentPlayer = player;
    if (currentPlayer != null) unawaited(_pauseWithPlaybackIntent(currentPlayer));
    _pendingCompletion = false;
    _setPlayerState(() {
      _showStillWatchingPrompt = false;
    });
  }

  void _dismissStillWatching() {
    _stillWatchingTimer?.cancel();
    if (_showStillWatchingPrompt) {
      // Dismissed by another action (back, play next); it owns what happens
      // next, so a deferred completion must not fire on top of it.
      _pendingCompletion = false;
      _unfocusStillWatchingPrompt();
      _setPlayerState(() {
        _showStillWatchingPrompt = false;
      });
    }
  }

  void _unfocusPlayNextPrompt() {
    _playNextCancelFocusNode.unfocus();
    _playNextConfirmFocusNode.unfocus();
  }

  void _unfocusStillWatchingPrompt() {
    _stillWatchingPauseFocusNode.unfocus();
    _stillWatchingContinueFocusNode.unfocus();
  }
}
