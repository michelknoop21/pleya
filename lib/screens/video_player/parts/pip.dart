part of '../../video_player_screen.dart';

extension _VideoPlayerPipMethods on VideoPlayerScreenState {
  void _attachPipStateListener() {
    final pipState = PipService().isPipActive;
    pipState.removeListener(_onPipStateChanged);
    pipState.addListener(_onPipStateChanged);
  }

  void _detachPipStateListener() {
    PipService().isPipActive.removeListener(_onPipStateChanged);
  }

  void _clearAutoPipEnteringCallback() {
    final callback = _autoPipEnteringCallback;
    if (callback != null && identical(PipService.onAutoPipEntering, callback)) {
      PipService.onAutoPipEntering = null;
    }
    _autoPipEnteringCallback = null;
  }

  /// Initialize VideoFilterManager and VideoPIPManager if not already set up.
  /// Called from both live TV and VOD playback paths.
  Future<void> _initVideoFilterAndPip() async {
    final currentPlayer = player;
    if (!mounted || currentPlayer == null) return;
    // The store keeps the outgoing item's key until the replacement file has
    // opened. Reload failures must not redirect user changes to another title.
    if (!widget.isLive &&
        (_videoDisplayPreferenceStore == null || !_videoDisplayPreferenceStore!.matches(_currentMetadata))) {
      final metadata = _currentMetadata;
      final store = await VideoDisplayPreferenceStore.forItem(metadata);
      if (!mounted || player != currentPlayer || _currentMetadata != metadata) return;
      final saved = store.read();
      if (_videoFilterManager != null && _videoFilterManager!.player == currentPlayer) {
        final settings = await SettingsService.getInstance();
        if (!mounted || player != currentPlayer || _currentMetadata != metadata) return;
        await _videoFilterManager!.restoreDisplaySettings(
          boxFitMode: saved?.boxFitMode ?? settings.read(SettingsService.defaultBoxFitMode),
          zoomScale: saved?.zoomScale ?? 1.0,
        );
        if (!mounted || player != currentPlayer || _currentMetadata != metadata) return;
      }
      _videoDisplayPreferenceStore = store;
    }
    if (_videoFilterManager != null && _videoFilterManager!.player != currentPlayer) {
      // A retry after an init error disposes the old player and creates a new
      // one in place without disposing this screen, so the manager's cached
      // `_appliedProps`/`_appliedVideoZoom` still say "already applied" for a
      // player that's gone. Left alone, every future write (including zoom)
      // silently no-ops against the disposed player. Rebuild against the new one.
      _videoFilterManager!.dispose();
      _videoFilterManager = null;
      _videoPIPManager = null;
    }
    if (_videoFilterManager != null && _videoPIPManager != null) {
      _attachPipStateListener();
      return;
    }

    final needsVideoFilter = _videoFilterManager == null;
    final settings = needsVideoFilter ? await SettingsService.getInstance() : null;
    if (!mounted || player != currentPlayer) return;
    final initialPlayerSize = _lastVideoLayoutPlayer == currentPlayer ? _lastVideoLayoutSize : null;

    if (needsVideoFilter && _videoFilterManager == null && settings != null) {
      final saved = _videoDisplayPreferenceStore?.read();
      _videoFilterManager = VideoFilterManager(
        player: currentPlayer,
        initialBoxFitMode: saved?.boxFitMode ?? settings.read(SettingsService.defaultBoxFitMode),
        initialZoomScale: saved?.zoomScale ?? 1.0,
        initialPlayerSize: initialPlayerSize,
        onBoxFitModeChanged: widget.isLive ? (mode) => settings.write(SettingsService.defaultBoxFitMode, mode) : null,
        onDisplaySettingsChanged: (mode, zoom) {
          unawaited(_videoDisplayPreferenceStore?.save(boxFitMode: mode, zoomScale: zoom));
        },
        subtitleBasePosition: () => settings.read(SettingsService.subtitlePosition),
      );
      unawaited(_videoFilterManager!.updateVideoFilter());
      _syncTvSubtitleLift();
    }

    _videoPIPManager ??= VideoPIPManager(player: currentPlayer, initialPlayerSize: initialPlayerSize);
    _videoPIPManager!.onBeforeEnterPip = _preparePipFiltersForEntry;
    _attachPipStateListener();
  }

  /// TV only: while the player chrome is up, lift subtitles above the bottom
  /// control block; when it hides, drop the lift so the manager writes the
  /// crop/zoom-compensated base position again (PLR-SUBS1). The manager ignores
  /// an unchanged lift, so chrome notifications without a visibility or height
  /// change write nothing.
  void _syncTvSubtitleLift() {
    if (!PlatformDetector.isTV()) return;
    _videoFilterManager?.setSubtitleLift(_chromeController.subtitleLift);
  }

  Future<void> _togglePIPMode() async {
    final result = await _videoPIPManager?.togglePIP();
    if (result != null && !result.$1 && mounted) {
      _restorePipFiltersAfterExit();
      showErrorSnackBar(context, result.$2 ?? t.videoControls.pipFailed);
    }
  }

  void _preparePipFiltersForEntry() {
    if (!mounted) return;
    if (_pipFiltersPrepared) return;
    _pipFiltersPrepared = true;
    _videoFilterManager?.enterPipMode();
  }

  void _restorePipFiltersAfterExit() {
    if (!mounted) {
      _pipFiltersPrepared = false;
      return;
    }

    final filterManager = _videoFilterManager;
    if (filterManager == null) {
      _pipFiltersPrepared = false;
      return;
    }

    final restoreAmbient = filterManager.hadAmbientLightingBeforePip;
    filterManager.exitPipMode();
    if (restoreAmbient) {
      filterManager.clearPipAmbientLightingFlag();
      unawaited(_restoreAmbientLighting());
    }
    _pipFiltersPrepared = false;
  }

  /// Handle PiP state changes to restore video scaling when exiting PiP
  void _onPipStateChanged() {
    if (!mounted || player == null) {
      _detachPipStateListener();
      return;
    }

    final isInPip = _videoPIPManager?.isPipActive.value ?? PipService().isPipActive.value;
    _setAndroidAutoPipTransitionInFlight(false, reason: 'pip_state_changed');
    _recordLifecycleState('pip_state_changed', action: isInPip ? 'entered' : 'exited');

    if (_videoPIPManager == null || _videoFilterManager == null) return;

    if (isInPip) {
      _preparePipFiltersForEntry();
    } else {
      _restorePipFiltersAfterExit();
    }
  }
}
