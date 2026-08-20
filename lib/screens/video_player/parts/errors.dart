part of '../../video_player_screen.dart';

extension _VideoPlayerErrorMethods on VideoPlayerScreenState {
  String _safePlaybackErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('No client registered')) {
      return t.notices.playbackConnectionLostBody;
    }
    // A recognised disc this build cannot play. Say that, instead of letting
    // mpv's "corrupt stream" reach the user for a perfectly fine DVD.
    if (error is UnsupportedDiscException) {
      return error.kind == DiscKind.dvd ? t.messages.dvdNotSupported : t.messages.discNotSupported;
    }
    final redacted = LogRedactionManager.redact(raw);
    logNoticeError('playback-init', redacted);
    return switch (classifyPlaybackFailure(redacted)) {
      PlaybackFailureKind.segmentUnavailable => t.notices.playbackSegmentUnavailableBody,
      PlaybackFailureKind.connectionLost => t.notices.playbackConnectionLostBody,
      PlaybackFailureKind.codecUnsupported => t.notices.playbackCodecUnsupportedBody,
      PlaybackFailureKind.serverError => t.notices.playbackServerErrorBody,
      PlaybackFailureKind.unknown => t.notices.playbackStoppedTitle,
    };
  }

  void _onPlayerError(PlayerError err) {
    appLogger.e('[Player ERROR] ${err.message}');
    if (!mounted || _isExiting.value) return;

    // Fatal, unrecoverable until server-side fix — show modal instead of a snackbar.
    if (err.cause == PlayerError.serverHttp500 || _sawServer500) {
      _showServerLimitDialog();
      return;
    }

    // Live TV: retry with progressively degraded stream settings
    // (mirrors Plex web client fallback chain).
    if (widget.isLive && _live.fallbackLevel < 2 && !_live.retrying) {
      _live.fallbackLevel++;
      _live.retrying = true;
      appLogger.w('Live stream failed, retrying with fallback level $_live.fallbackLevel');
      _retryLiveStream().whenComplete(() => _live.retrying = false);
      return;
    }

    noticeController.show(noticeForPlaybackFailure(_redactPlayerError(_lastLogError ?? err.message)));
    _handleBackButton();
  }

  void _onPlayerLog(PlayerLog log) {
    if (!_sawServer500 && VideoPlayerScreenState._server500Pattern.hasMatch(log.text)) {
      _sawServer500 = true;
    }
    if (log.level == PlayerLogLevel.error || log.level == PlayerLogLevel.fatal) {
      appLogger.e('[Player LOG ERROR] [${log.prefix}] ${log.text}');
      _lastLogError = _redactPlayerError(log.text.trim());
    }
  }

  String _redactPlayerError(String message) => LogRedactionManager.redact(message);

  Future<void> _showServerLimitDialog() async {
    if (!mounted) return;
    // Offer a one-step-lower restart when the server can transcode and we're
    // not already at the lowest preset — a common recovery for shared-server
    // bandwidth / transcode-limit rejections.
    final lowerPreset = _lowerQualityFallback();
    final tryLower = await showServerLimitDialog(context, canTryLowerQuality: lowerPreset != null);
    if (!mounted) return;
    if (tryLower && lowerPreset != null) {
      _retryWithLowerQuality(lowerPreset);
      return;
    }
    unawaited(_handleBackButton());
  }

  /// Handle notification when native player switched from ExoPlayer to MPV
  Future<void> _onBackendSwitched() async {
    _playerBackendLabel = 'mpv';
    _recordLifecycleState('backend_switched', action: 'mpv_fallback');

    _toastController.show(
      Symbols.swap_horiz_rounded,
      t.messages.switchingToCompatiblePlayer,
      duration: const Duration(seconds: 2),
    );

    await _trackManager?.onBackendSwitched();
  }
}
