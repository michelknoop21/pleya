import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../media/media_item.dart';
import '../../../media/media_version.dart';
import '../../../mpv/mpv.dart';
import '../../../media/media_source_info.dart';
import '../../../services/airplay_service.dart';
import '../../../services/sleep_timer_service.dart';
import '../../../utils/haptics.dart';
import '../../../utils/platform_detector.dart';
import '../../../i18n/strings.g.dart';
import '../../../widgets/overlay_sheet.dart';
import '../models/track_controls_state.dart';
import '../../../models/transcode_quality_preset.dart';
import '../sheets/chapter_sheet.dart';
import '../sheets/queue_sheet.dart';
import '../sheets/track_sheet.dart';
import '../sheets/video_settings_sheet.dart';
import '../tv_info_panel/tv_panel_types.dart';
import '../../../services/shader_service.dart';
import '../video_control_button.dart';

/// Row of track and chapter control buttons for the video player
class TrackChapterControls extends StatelessWidget {
  final Player player;
  final List<MediaChapter> chapters;
  final bool chaptersLoaded;
  final TrackControlsState trackControlsState;
  final Future<void> Function(Duration position)? onSeekRequested;
  final Function(Duration position)? onSeekCompleted;

  /// List of FocusNodes for the buttons (passed from parent for navigation)
  final List<FocusNode>? focusNodes;

  /// Called when focus changes on any button
  final ValueChanged<bool>? onFocusChange;

  /// Called to navigate left from the first button
  final VoidCallback? onNavigateLeft;

  /// Called to navigate up from any button (e.g., to focus timeline on TV)
  final VoidCallback? onNavigateUp;

  /// Called to navigate down from any button (e.g., to show content strip on TV)
  final VoidCallback? onNavigateDown;

  /// Whether to hide the chapters and queue buttons (mobile uses content strip instead)
  final bool hideChaptersAndQueue;

  /// On TV, the buttons open the player panel on a tab instead of a sheet
  /// (DEC-101). Null everywhere else, and the sheets behave as before.
  final ValueChanged<TvInfoPanelRequest>? onOpenTvPanel;

  const TrackChapterControls({
    super.key,
    required this.player,
    required this.chapters,
    required this.chaptersLoaded,
    required this.trackControlsState,
    this.onSeekRequested,
    this.onSeekCompleted,
    this.focusNodes,
    this.onFocusChange,
    this.onNavigateLeft,
    this.onNavigateUp,
    this.onNavigateDown,
    this.hideChaptersAndQueue = false,
    this.onOpenTvPanel,
  });

  List<MediaVersion> get availableVersions => trackControlsState.availableVersions;
  int get selectedMediaIndex => trackControlsState.selectedMediaIndex;
  TranscodeQualityPreset get selectedQualityPreset => trackControlsState.selectedQualityPreset;
  bool get serverSupportsTranscoding => trackControlsState.serverSupportsTranscoding;
  ValueChanged<TranscodeQualityPreset>? get onSwitchQualityPreset => trackControlsState.onSwitchQualityPreset;
  int get boxFitMode => trackControlsState.boxFitMode;
  double get videoZoomScale => trackControlsState.videoZoomScale;
  int get audioSyncOffset => trackControlsState.audioSyncOffset;
  int get subtitleSyncOffset => trackControlsState.subtitleSyncOffset;
  bool get isRotationLocked => trackControlsState.isRotationLocked;
  bool get isScreenLocked => trackControlsState.isScreenLocked;
  bool get isFullscreen => trackControlsState.isFullscreen;
  bool get isAlwaysOnTop => trackControlsState.isAlwaysOnTop;
  VoidCallback? get onTogglePIPMode => trackControlsState.onTogglePIPMode;
  VoidCallback? get onCycleBoxFitMode => trackControlsState.onCycleBoxFitMode;
  ValueChanged<double>? get onVideoZoomChanged => trackControlsState.onVideoZoomChanged;
  VoidCallback? get onResetVideoZoom => trackControlsState.onResetVideoZoom;
  VoidCallback? get onToggleRotationLock => trackControlsState.onToggleRotationLock;
  VoidCallback? get onToggleScreenLock => trackControlsState.onToggleScreenLock;
  VoidCallback? get onToggleFullscreen => trackControlsState.onToggleFullscreen;
  VoidCallback? get onToggleAlwaysOnTop => trackControlsState.onToggleAlwaysOnTop;
  Function(int)? get onSwitchVersion => trackControlsState.onSwitchVersion;
  VoidCallback? get onLoadSeekTimes => trackControlsState.onLoadSeekTimes;
  VoidCallback? get onCancelAutoHide => trackControlsState.onCancelAutoHide;
  VoidCallback? get onStartAutoHide => trackControlsState.onStartAutoHide;
  void Function(String propertyName, int offset)? get onSyncOffsetChanged => trackControlsState.onSyncOffsetChanged;
  String? get serverId => trackControlsState.serverId;
  ShaderService? get shaderService => trackControlsState.shaderService;
  VoidCallback? get onShaderChanged => trackControlsState.onShaderChanged;
  bool get isAmbientLightingEnabled => trackControlsState.isAmbientLightingEnabled;
  VoidCallback? get onToggleAmbientLighting => trackControlsState.onToggleAmbientLighting;
  bool get canControl => trackControlsState.canControl;
  bool get isLive => trackControlsState.isLive;
  bool get subtitlesVisible => trackControlsState.subtitlesVisible;
  bool get showQueueButton => trackControlsState.showQueueButton;
  Function(MediaItem)? get onQueueItemSelected => trackControlsState.onQueueItemSelected;

  /// Handle key event for button navigation
  KeyEventResult _handleButtonKeyEvent(FocusNode _, KeyEvent event, int index) {
    if (!event.isActionable) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // LEFT arrow - move to previous button or exit to volume
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0 && focusNodes != null && focusNodes!.length > index - 1) {
        focusNodes![index - 1].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 0) {
        onNavigateLeft?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // RIGHT arrow - move to next button. The focus-node list is fixed-size and
    // shared, so we can't trust its length; instead check whether the next node
    // is actually mounted to a rendered button (context != null). This is
    // immune to conditional buttons (AirPlay, screen-lock) being added later.
    if (key == LogicalKeyboardKey.arrowRight) {
      final next = index + 1;
      if (focusNodes != null && next < focusNodes!.length && focusNodes![next].context != null) {
        focusNodes![next].requestFocus();
      }
      // At end (or no next button), consume to prevent bubbling.
      return KeyEventResult.handled;
    }

    // UP arrow - navigate up (e.g., to timeline)
    if (key == LogicalKeyboardKey.arrowUp) {
      onNavigateUp?.call();
      return KeyEventResult.handled;
    }

    // DOWN arrow - navigate down (e.g., to content strip)
    if (key == LogicalKeyboardKey.arrowDown) {
      onNavigateDown?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Build a track control button with consistent focus handling
  Widget _buildTrackButton({
    required int buttonIndex,
    required IconData icon,
    required String semanticLabel,
    required VoidCallback? onPressed,
    required bool isMobile,
    required bool isDesktop,
    String? tooltip,
    bool isActive = false,
    String? automationId,
  }) {
    return VideoControlButton(
      icon: icon,
      tooltip: tooltip,
      semanticLabel: semanticLabel,
      isActive: isActive,
      automationId: automationId,
      focusNode: focusNodes != null && focusNodes!.length > buttonIndex ? focusNodes![buttonIndex] : null,
      onKeyEvent: focusNodes != null ? (node, event) => _handleButtonKeyEvent(node, event, buttonIndex) : null,
      onFocusChange: onFocusChange,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.streams.tracks,
      initialData: player.state.tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data;
        final isMobile = PlatformDetector.isMobile(context);
        final isDesktop = PlatformDetector.isDesktopOS();

        // Build list of buttons dynamically to track indices
        final buttons = <Widget>[];
        int buttonIndex = 0;

        // Settings button (always shown)
        buttons.add(
          ListenableBuilder(
            listenable: SleepTimerService(),
            builder: (context, _) {
              final sleepTimer = SleepTimerService();
              final isShaderActive =
                  shaderService != null && shaderService!.isSupported && shaderService!.currentPreset.isEnabled;
              final isZoomActive = (videoZoomScale - 1.0).abs() > 0.0001;
              final isActive =
                  sleepTimer.isActive ||
                  audioSyncOffset != 0 ||
                  subtitleSyncOffset != 0 ||
                  isShaderActive ||
                  isZoomActive;
              return _buildTrackButton(
                buttonIndex: 0,
                icon: Symbols.tune_rounded,
                isActive: isActive,
                automationId: AutomationIds.playerSettingsButton,
                tooltip: t.videoControls.settingsButton,
                semanticLabel: t.videoControls.settingsButton,
                isMobile: isMobile,
                isDesktop: isDesktop,
                onPressed: () {
                  final openPanel = onOpenTvPanel;
                  if (openPanel != null) {
                    openPanel(TvInfoPanelRequest.video);
                    return;
                  }
                  onCancelAutoHide?.call();
                  OverlaySheetController.of(context)
                      .show(
                        builder: (_) => VideoSettingsSheet(
                          player: player,
                          audioSyncOffset: audioSyncOffset,
                          subtitleSyncOffset: subtitleSyncOffset,
                          videoZoomScale: videoZoomScale,
                          onVideoZoomChanged: onVideoZoomChanged,
                          onResetVideoZoom: onResetVideoZoom,
                          canControl: canControl,
                          isLive: isLive,
                          availableVersions: availableVersions,
                          selectedMediaIndex: selectedMediaIndex,
                          selectedQualityPreset: selectedQualityPreset,
                          serverSupportsTranscoding: serverSupportsTranscoding,
                          sourceDurationMs: trackControlsState.sourceDurationMs,
                          onVersionSelected: onSwitchVersion == null ? null : (i) => onSwitchVersion!(i),
                          onQualitySelected: onSwitchQualityPreset,
                          shaderService: shaderService,
                          onShaderChanged: onShaderChanged,
                          isAmbientLightingEnabled: isAmbientLightingEnabled,
                          onToggleAmbientLighting: onToggleAmbientLighting,
                          onCancelAutoHide: onCancelAutoHide,
                          onStartAutoHide: onStartAutoHide,
                          onSyncOffsetChanged: onSyncOffsetChanged,
                        ),
                      )
                      .whenComplete(() {
                        onStartAutoHide?.call();
                        onLoadSeekTimes?.call();
                      });
                },
              );
            },
          ),
        );
        buttonIndex++;

        // Combined audio & subtitles button
        {
          final currentIndex = buttonIndex;
          final hasSubtitleControls = trackControlsState.hasSubtitleControls(tracks);
          final selectedSub = player.state.track.subtitle;
          final hasActiveSubtitle = selectedSub != null && selectedSub.id != 'no';
          final isHidden = hasSubtitleControls && hasActiveSubtitle && !subtitlesVisible;
          final icon = hasSubtitleControls
              ? (isHidden ? Symbols.subtitles_off_rounded : Symbols.subtitles_rounded)
              : Symbols.audiotrack_rounded;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: icon,
              tooltip: t.videoControls.tracksButton,
              semanticLabel: t.videoControls.tracksButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: () {
                final openPanel = onOpenTvPanel;
                if (openPanel != null) {
                  openPanel(hasSubtitleControls ? TvInfoPanelRequest.subtitles : TvInfoPanelRequest.audio);
                  return;
                }
                onCancelAutoHide?.call();
                OverlaySheetController.of(context)
                    .show(
                      builder: (_) => TrackSheet(player: player, trackControlsState: trackControlsState),
                    )
                    .whenComplete(() => onStartAutoHide?.call());
              },
            ),
          );
          buttonIndex++;
        }

        // Chapters button (hidden on mobile when content strip is available)
        if (chapters.isNotEmpty && !hideChaptersAndQueue) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: Symbols.bookmarks_rounded,
              tooltip: t.videoControls.chaptersButton,
              semanticLabel: t.videoControls.chaptersButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: () {
                final openPanel = onOpenTvPanel;
                if (openPanel != null) {
                  openPanel(TvInfoPanelRequest.chapters);
                  return;
                }
                onCancelAutoHide?.call();
                OverlaySheetController.of(context)
                    .show(
                      builder: (_) => ChapterSheet(
                        player: player,
                        chapters: chapters,
                        chaptersLoaded: chaptersLoaded,
                        serverId: serverId,
                        onSeekRequested: onSeekRequested,
                        onSeekCompleted: onSeekCompleted,
                      ),
                    )
                    .whenComplete(() => onStartAutoHide?.call());
              },
            ),
          );
          buttonIndex++;
        }

        // Queue button (hidden on mobile when content strip is available)
        if (showQueueButton && onQueueItemSelected != null && !hideChaptersAndQueue) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: Symbols.queue_rounded,
              tooltip: t.videoControls.queue,
              semanticLabel: t.videoControls.queue,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: () {
                onCancelAutoHide?.call();
                OverlaySheetController.of(context)
                    .show(builder: (_) => QueueSheet(onItemSelected: onQueueItemSelected!))
                    .whenComplete(() => onStartAutoHide?.call());
              },
            ),
          );
          buttonIndex++;
        }

        // Picture-in-Picture mode
        if (onTogglePIPMode != null) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: Symbols.picture_in_picture_alt,
              tooltip: t.videoControls.pipButton,
              semanticLabel: t.videoControls.pipButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: onTogglePIPMode,
            ),
          );
          buttonIndex++;
        }

        // AirPlay route picker (iOS only — native AVRoutePickerView).
        if (AirPlayService.isAvailable) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: Symbols.airplay,
              tooltip: t.videoControls.airplayButton,
              semanticLabel: t.videoControls.airplayButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: () {
                Haptics.light();
                unawaited(AirPlayService.showRoutePicker());
              },
            ),
          );
          buttonIndex++;
        }

        // BoxFit mode button
        if (onCycleBoxFitMode != null) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: _getBoxFitIcon(boxFitMode),
              tooltip: _getBoxFitTooltip(boxFitMode),
              semanticLabel: t.videoControls.aspectRatioButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: onCycleBoxFitMode,
            ),
          );
          buttonIndex++;
        }

        // Rotation lock button (mobile only, not on TV since screens don't rotate)
        if (isMobile && !PlatformDetector.isTV()) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: isRotationLocked ? Symbols.screen_lock_rotation_rounded : Symbols.screen_rotation_rounded,
              tooltip: isRotationLocked ? t.videoControls.unlockRotation : t.videoControls.lockRotation,
              semanticLabel: t.videoControls.rotationLockButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: onToggleRotationLock,
            ),
          );
          buttonIndex++;
        }

        // Screen lock button (mobile only, not on TV)
        if (isMobile && !PlatformDetector.isTV()) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: Symbols.lock_rounded,
              tooltip: t.videoControls.lockScreen,
              semanticLabel: t.videoControls.screenLockButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: onToggleScreenLock,
            ),
          );
          buttonIndex++;
        }

        // Always on top button (desktop only, not TV)
        if (isDesktop && onToggleAlwaysOnTop != null) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: Symbols.layers_rounded,
              tooltip: t.videoControls.alwaysOnTopButton,
              semanticLabel: t.videoControls.alwaysOnTopButton,
              isActive: isAlwaysOnTop,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: onToggleAlwaysOnTop,
            ),
          );
          buttonIndex++;
        }

        // Fullscreen button (desktop only)
        if (isDesktop) {
          final currentIndex = buttonIndex;
          buttons.add(
            _buildTrackButton(
              buttonIndex: currentIndex,
              icon: isFullscreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
              tooltip: isFullscreen ? t.videoControls.exitFullscreenButton : t.videoControls.fullscreenButton,
              semanticLabel: isFullscreen ? t.videoControls.exitFullscreenButton : t.videoControls.fullscreenButton,
              isMobile: isMobile,
              isDesktop: isDesktop,
              onPressed: onToggleFullscreen,
            ),
          );
        }

        return IntrinsicHeight(
          child: Row(mainAxisSize: .min, crossAxisAlignment: .stretch, children: buttons),
        );
      },
    );
  }

  IconData _getBoxFitIcon(int mode) {
    switch (mode) {
      case 0:
        return Symbols.fit_screen_rounded; // contain (letterbox)
      case 1:
        return Symbols.aspect_ratio_rounded; // cover (fill screen)
      case 2:
        return Symbols.settings_overscan_rounded; // fill (stretch)
      default:
        return Symbols.fit_screen_rounded;
    }
  }

  String _getBoxFitTooltip(int mode) {
    switch (mode) {
      case 0:
        return t.videoControls.letterbox;
      case 1:
        return t.videoControls.fillScreen;
      case 2:
        return t.videoControls.stretch;
      default:
        return t.videoControls.letterbox;
    }
  }
}
