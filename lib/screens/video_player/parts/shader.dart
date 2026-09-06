part of '../../video_player_screen.dart';

extension _VideoPlayerShaderMethods on VideoPlayerScreenState {
  /// Apply the saved shader preset on playback start.
  /// Reads directly from SettingsService (synchronous SharedPreferences) to
  /// avoid a race with ShaderProvider's async initialization.
  Future<void> _applySavedShaderPreset() async {
    if (_shaderService == null || !_shaderService!.isSupported) return;

    try {
      final shaderProvider = context.read<ShaderProvider>();
      final settings = await SettingsService.getInstance();
      final presetId = settings.read(SettingsService.globalShaderPreset);
      final preset =
          (shaderProvider.initialized ? shaderProvider.findPresetById(presetId) : ShaderPreset.fromId(presetId)) ??
          ShaderPreset.none;
      await _shaderService!.applyPreset(preset);
      if (!mounted) return;
      shaderProvider.setCurrentPreset(preset);
    } catch (e) {
      appLogger.d('Could not apply shader preset', error: e);
    }
  }

  /// Restore ambient lighting from persisted setting
  Future<void> _restoreAmbientLighting() async {
    if (!mounted) return;

    final shaderProvider = context.read<ShaderProvider>();
    final settings = await SettingsService.getInstance();
    if (!mounted) return;
    if (!settings.read(SettingsService.ambientLighting)) return;

    final ambientLighting = _ambientLightingService;
    if (ambientLighting == null || !ambientLighting.isSupported) return;

    // Same enable logic as _toggleAmbientLighting
    final dwidth = await player?.getProperty('dwidth');
    final dheight = await player?.getProperty('dheight');
    if (dwidth == null || dheight == null) return;
    final w = double.tryParse(dwidth);
    final h = double.tryParse(dheight);
    if (w == null || h == null || h == 0) return;
    final videoAspect = w / h;

    final playerSize = _videoFilterManager?.playerSize;
    if (playerSize == null || playerSize.height == 0) return;
    final outputAspect = playerSize.width / playerSize.height;

    // Clear shaders — ambient lighting and shaders are mutually exclusive
    if (shaderProvider.isShaderEnabled) {
      await _shaderService!.applyPreset(ShaderPreset.none);
      shaderProvider.setCurrentPreset(ShaderPreset.none);
    }

    _videoFilterManager?.resetToContain();
    await ambientLighting.enable(videoAspect, outputAspect);
    if (mounted) _setPlayerState(() {});
  }

  /// Cycle through BoxFit modes: contain → cover → fill → contain (for button)
  void _cycleBoxFitMode() {
    // Disable ambient lighting when switching boxfit modes
    // (cover/fill change the video rect, making the baked-in shader incorrect)
    _ambientLightingService?.disable();
    _setPlayerState(() {
      _videoFilterManager?.cycleBoxFitMode();
    });
  }

  /// Set a BoxFit mode directly (0 contain, 1 cover, 2 fill): the TV panel
  /// steps it backwards as well as forwards. Same ambient rule as the cycle.
  void _setBoxFitMode(int mode) {
    _ambientLightingService?.disable();
    _setPlayerState(() {
      _videoFilterManager?.setBoxFitMode(mode);
    });
  }

  void _showZoomToast(double zoomScale) {
    _toastController.show(Symbols.zoom_in_rounded, t.videoControls.zoomPercent(percent: (zoomScale * 100).round()));
  }

  double _setVideoZoom(double zoomScale, {bool showToast = true}) {
    final filterManager = _videoFilterManager;
    if (filterManager == null) return 1.0;

    _ambientLightingService?.disable();
    final next = filterManager.setZoomScale(zoomScale);
    if (showToast) _showZoomToast(next);
    if (mounted) _setPlayerState(() {});
    return next;
  }

  void _zoomVideoIn() {
    final current = _videoFilterManager?.zoomScale ?? 1.0;
    _setVideoZoom(current + VideoFilterManager.zoomStep);
  }

  void _zoomVideoOut() {
    final current = _videoFilterManager?.zoomScale ?? 1.0;
    _setVideoZoom(current - VideoFilterManager.zoomStep);
  }

  void _resetVideoZoom() {
    _setVideoZoom(1.0);
  }

  /// Update video-aspect-override when player size changes.
  /// The shader adapts automatically via built-in target_size uniform.
  void _updateAmbientLightingOnResize(Size newSize) {
    final ambientLighting = _ambientLightingService;
    if (ambientLighting == null || !ambientLighting.isEnabled) return;
    if (newSize.height == 0) return;

    ambientLighting.updateOutputAspect(newSize.width / newSize.height);
  }

  /// Toggle ambient lighting effect on/off
  Future<void> _toggleAmbientLighting() async {
    final ambientLighting = _ambientLightingService;
    if (ambientLighting == null || !ambientLighting.isSupported) return;
    final shaderProvider = context.read<ShaderProvider>();

    if (ambientLighting.isEnabled) {
      await ambientLighting.disable();
      unawaited(_videoFilterManager?.updateVideoFilter());
    } else {
      // Get video display aspect ratio
      final dwidth = await player?.getProperty('dwidth');
      final dheight = await player?.getProperty('dheight');
      if (dwidth == null || dheight == null) return;
      final w = double.tryParse(dwidth);
      final h = double.tryParse(dheight);
      if (w == null || h == null || h == 0) return;
      final videoAspect = w / h;

      // Get player widget aspect ratio
      final playerSize = _videoFilterManager?.playerSize;
      if (playerSize == null || playerSize.height == 0) return;
      final outputAspect = playerSize.width / playerSize.height;

      // Clear shaders — ambient lighting and shaders are mutually exclusive
      if (shaderProvider.isShaderEnabled) {
        await _shaderService!.applyPreset(ShaderPreset.none);
        shaderProvider.setCurrentPreset(ShaderPreset.none);
      }

      // Force contain mode when enabling ambient lighting
      _videoFilterManager?.resetToContain();

      await ambientLighting.enable(videoAspect, outputAspect);
    }

    // Persist ambient lighting state
    final settings = await SettingsService.getInstance();
    unawaited(settings.write(SettingsService.ambientLighting, ambientLighting.isEnabled));

    if (mounted) _setPlayerState(() {});
  }

  /// Set ambient lighting intensity from the TV info panel.
  /// [mode] is 'off' | 'subtle' | 'balanced' | 'bright'. 'off' disables the
  /// effect; the others persist the intensity and enable (or live-refresh) it.
  Future<void> _setAmbientIntensity(String mode) async {
    final ambientLighting = _ambientLightingService;
    if (ambientLighting == null || !ambientLighting.isSupported) return;

    if (mode == 'off') {
      if (ambientLighting.isEnabled) await _toggleAmbientLighting();
      return;
    }

    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.ambientLightingIntensity, mode);

    if (ambientLighting.isEnabled) {
      await ambientLighting.refreshIntensity();
      if (mounted) _setPlayerState(() {});
    } else {
      // Enables with the new intensity baked into the freshly generated shader.
      await _toggleAmbientLighting();
    }
  }
}
