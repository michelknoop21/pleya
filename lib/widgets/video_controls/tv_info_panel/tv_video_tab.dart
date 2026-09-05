import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_source_info.dart';
import '../../../media/media_version.dart';
import '../../../models/shader_preset.dart';
import '../../../models/transcode_quality_preset.dart';
import '../../../mpv/mpv.dart';
import '../../../services/settings_service.dart';
import '../../../services/shader_service.dart';
import '../../../services/sleep_timer_service.dart';
import '../../../services/video_filter_manager.dart';
import '../../../utils/formatters.dart';
import '../../../utils/quality_preset_labels.dart';
import '../../../automation/automation_ids.dart';
import 'tv_panel_types.dart';
import 'tv_panel_widgets.dart';

/// Ambient lighting intensity steps. `off` disables the effect; the others map
/// to shader brightness in AmbientLightingService.
const List<String> kAmbientIntensityModes = ['off', 'subtle', 'balanced', 'bright'];

/// Playback speeds a value row steps through; the same list the sheet offers.
const List<double> kTvPanelSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0];

/// Zoom presets, the same list the sheet offers.
const List<double> kTvPanelZoomPresets = [0.5, 0.75, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0];

/// "Video" tab: Display (aspect ratio, zoom, HDR, shaders, ambient lighting)
/// on the left, Playback (speed, chapters, version and quality, sleep timer,
/// auto-play next, playback statistics) on the right. Every value row steps
/// with LEFT/RIGHT and cycles forward on Select; the list rows open a sub-view.
class TvVideoTab extends StatelessWidget {
  final Player player;
  final int boxFitMode;
  final VoidCallback? onCycleBoxFit;
  final ValueChanged<int>? onSetBoxFitMode;
  final double videoZoomScale;
  final ValueChanged<double>? onVideoZoomChanged;
  final List<MediaChapter> chapters;
  final bool canControl;
  final bool isLive;
  final bool ambientSupported;
  final bool ambientEnabled;
  final String ambientIntensity;
  final ValueChanged<String> onSetAmbientIntensity;
  final ShaderService? shaderService;
  final bool hasVersionQuality;
  final List<MediaVersion> availableVersions;
  final int selectedMediaIndex;
  final TranscodeQualityPreset selectedQualityPreset;
  final bool serverSupportsTranscoding;
  final FocusNode firstFocusNode;
  final VoidCallback onNavigateUp;
  final ValueChanged<TvInfoPanelSubView> onOpenSubView;

  const TvVideoTab({
    super.key,
    required this.player,
    required this.boxFitMode,
    required this.onCycleBoxFit,
    this.onSetBoxFitMode,
    this.videoZoomScale = 1.0,
    this.onVideoZoomChanged,
    required this.chapters,
    required this.canControl,
    required this.isLive,
    required this.ambientSupported,
    required this.ambientEnabled,
    required this.ambientIntensity,
    required this.onSetAmbientIntensity,
    this.shaderService,
    this.hasVersionQuality = false,
    this.availableVersions = const [],
    this.selectedMediaIndex = 0,
    this.selectedQualityPreset = TranscodeQualityPreset.original,
    this.serverSupportsTranscoding = false,
    required this.firstFocusNode,
    required this.onNavigateUp,
    required this.onOpenSubView,
  });

  static bool get _hdrSupported => Platform.isIOS || Platform.isMacOS || Platform.isWindows;

  String _boxFitLabel(int mode) => switch (mode) {
    1 => t.videoControls.fillScreen,
    2 => t.videoControls.stretch,
    _ => t.videoControls.letterbox,
  };

  void _stepBoxFit(int delta) {
    final set = onSetBoxFitMode;
    if (set != null) {
      set(stepValue(const [0, 1, 2], boxFitMode, delta));
    } else {
      onCycleBoxFit?.call();
    }
  }

  String _ambientLabel() {
    if (!ambientEnabled) return t.common.off;
    return switch (ambientIntensity) {
      'subtle' => t.videoControls.ambientIntensitySubtle,
      'bright' => t.videoControls.ambientIntensityBright,
      _ => t.videoControls.ambientIntensityBalanced,
    };
  }

  void _stepAmbient(int delta) {
    final current = ambientEnabled ? ambientIntensity : 'off';
    onSetAmbientIntensity(stepValue(kAmbientIntensityModes, current, delta));
  }

  Future<void> _stepSpeed(int delta) async {
    final next = stepValue(kTvPanelSpeeds, player.state.rate, delta, equals: (a, b) => (a - b).abs() < 0.01);
    await player.setRate(next);
    await SettingsService.instance.write(SettingsService.defaultPlaybackSpeed, next);
  }

  void _stepZoom(int delta) {
    final current = VideoFilterManager.normalizeZoomScale(videoZoomScale);
    onVideoZoomChanged?.call(stepValue(kTvPanelZoomPresets, current, delta, equals: (a, b) => (a - b).abs() < 0.005));
  }

  String _versionQualityValue() {
    final values = <String>[];
    if (availableVersions.length > 1 && selectedMediaIndex >= 0 && selectedMediaIndex < availableVersions.length) {
      values.add(availableVersions[selectedMediaIndex].displayLabel);
    }
    if (serverSupportsTranscoding) values.add(qualityPresetLabel(selectedQualityPreset));
    return values.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    // The first row of the left column takes the tab's landing node, so the
    // pill's DOWN lands there and its UP goes back to the pill.
    var first = true;
    FocusNode? nodeFor() {
      if (!first) return null;
      first = false;
      return firstFocusNode;
    }

    VoidCallback? upFor(FocusNode? node) => node == null ? null : onNavigateUp;

    final display = <Widget>[];
    if (onCycleBoxFit != null || onSetBoxFitMode != null) {
      final node = nodeFor();
      display.add(
        TvPanelRow.value(
          focusNode: node,
          onNavigateUp: upFor(node),
          icon: Symbols.aspect_ratio_rounded,
          title: t.videoControls.aspectRatioButton,
          value: _boxFitLabel(boxFitMode),
          highlighted: boxFitMode != 0,
          onSelect: () => _stepBoxFit(1),
          onStepLeft: () => _stepBoxFit(-1),
          onStepRight: () => _stepBoxFit(1),
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'aspect_ratio',
        ),
      );
    }
    if (onVideoZoomChanged != null) {
      final node = nodeFor();
      final zoom = VideoFilterManager.normalizeZoomScale(videoZoomScale);
      display.add(
        TvPanelRow.value(
          focusNode: node,
          onNavigateUp: upFor(node),
          icon: Symbols.zoom_in_rounded,
          title: t.videoSettings.zoom,
          value: '${(zoom * 100).round()}%',
          highlighted: (zoom - 1.0).abs() > 0.0001,
          onSelect: () => _stepZoom(1),
          onStepLeft: () => _stepZoom(-1),
          onStepRight: () => _stepZoom(1),
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'zoom',
        ),
      );
    }
    if (_hdrSupported) {
      final node = nodeFor();
      display.add(
        ValueListenableBuilder<bool>(
          valueListenable: settings.listenable(SettingsService.enableHDR),
          builder: (context, hdr, _) => TvPanelRow.toggle(
            focusNode: node,
            onNavigateUp: upFor(node),
            icon: Symbols.hdr_strong_rounded,
            title: t.videoSettings.hdr,
            toggled: hdr,
            onSelect: () async {
              await settings.write(SettingsService.enableHDR, !hdr);
              await player.setProperty('hdr-enabled', !hdr ? 'yes' : 'no');
            },
            automationId: AutomationIds.playerPanelRow,
            automationInstance: 'hdr',
          ),
        ),
      );
    }
    final shaders = shaderService;
    if (shaders != null && shaders.isSupported) {
      final node = nodeFor();
      final preset = shaders.currentPreset;
      display.add(
        TvPanelRow(
          focusNode: node,
          onNavigateUp: upFor(node),
          icon: Symbols.auto_fix_high_rounded,
          title: t.shaders.title,
          value: preset.id == ShaderPreset.none.id ? t.common.off : preset.name,
          highlighted: preset.isEnabled,
          showChevron: true,
          onSelect: () => onOpenSubView(TvInfoPanelSubView.shaders),
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'shaders',
        ),
      );
    }
    if (ambientSupported) {
      final node = nodeFor();
      display.add(
        TvPanelRow.value(
          focusNode: node,
          onNavigateUp: upFor(node),
          icon: Symbols.blur_on,
          title: t.videoControls.ambientLighting,
          value: _ambientLabel(),
          highlighted: ambientEnabled,
          onSelect: () => _stepAmbient(1),
          onStepLeft: () => _stepAmbient(-1),
          onStepRight: () => _stepAmbient(1),
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'ambient',
        ),
      );
    }

    final playback = <Widget>[];
    if (canControl && !isLive) {
      final node = nodeFor();
      playback.add(
        StreamBuilder<double>(
          stream: player.streams.rate,
          initialData: player.state.rate,
          builder: (context, snapshot) {
            final rate = snapshot.data ?? 1.0;
            return TvPanelRow.value(
              focusNode: node,
              onNavigateUp: upFor(node),
              icon: Symbols.speed_rounded,
              title: t.videoSettings.playbackSpeed,
              value: formatPlaybackRate(rate, normalAtOne: true),
              highlighted: (rate - 1.0).abs() > 0.01,
              onSelect: () => _stepSpeed(1),
              onStepLeft: () => _stepSpeed(-1),
              onStepRight: () => _stepSpeed(1),
              automationId: AutomationIds.playerPanelRow,
              automationInstance: 'speed',
              automationState: () => {'rate': rate},
            );
          },
        ),
      );
    }
    if (chapters.isNotEmpty) {
      final node = nodeFor();
      playback.add(
        StreamBuilder<Duration>(
          stream: player.streams.position,
          initialData: player.state.position,
          builder: (context, snapshot) {
            final index = MediaChapter.indexAtPosition(snapshot.data ?? Duration.zero, chapters);
            return TvPanelRow(
              focusNode: node,
              onNavigateUp: upFor(node),
              icon: Symbols.bookmark_rounded,
              title: t.videoControls.chapters,
              subtitle: index == null ? null : chapters[index].label,
              value: index == null
                  ? '${chapters.length}'
                  : t.videoControls.tvPanel.chaptersOf(current: index + 1, total: chapters.length),
              showChevron: true,
              onSelect: () => onOpenSubView(TvInfoPanelSubView.chapters),
              automationId: AutomationIds.playerPanelRow,
              automationInstance: 'chapters',
            );
          },
        ),
      );
    }
    if (hasVersionQuality) {
      final node = nodeFor();
      playback.add(
        TvPanelRow(
          focusNode: node,
          onNavigateUp: upFor(node),
          icon: Symbols.art_track,
          title: t.videoControls.versionQualityButton,
          value: _versionQualityValue(),
          showChevron: true,
          onSelect: () => onOpenSubView(TvInfoPanelSubView.versionQuality),
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'version_quality',
        ),
      );
    }
    final sleepNode = nodeFor();
    playback.add(
      ListenableBuilder(
        listenable: SleepTimerService(),
        builder: (context, _) {
          final sleepTimer = SleepTimerService();
          final remaining = sleepTimer.remainingTime;
          final value = !sleepTimer.isActive
              ? t.common.off
              : (sleepTimer.isEndOfVideoMode || remaining == null
                    ? t.videoControls.sleepTimerEndOfVideo
                    : formatDurationWithSeconds(remaining));
          return TvPanelRow(
            focusNode: sleepNode,
            onNavigateUp: upFor(sleepNode),
            icon: Symbols.bedtime_rounded,
            title: t.videoSettings.sleepTimer,
            value: value,
            highlighted: sleepTimer.isActive,
            showChevron: true,
            onSelect: () => onOpenSubView(TvInfoPanelSubView.sleepTimer),
            automationId: AutomationIds.playerPanelRow,
            automationInstance: 'sleep_timer',
          );
        },
      ),
    );
    playback.add(
      ValueListenableBuilder<bool>(
        valueListenable: settings.listenable(SettingsService.autoPlayNextEpisode),
        builder: (context, autoPlay, _) => TvPanelRow.toggle(
          icon: Symbols.skip_next_rounded,
          title: t.videoControls.autoPlayNext,
          toggled: autoPlay,
          onSelect: () => settings.write(SettingsService.autoPlayNextEpisode, !autoPlay),
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'auto_play_next',
        ),
      ),
    );
    playback.add(
      ValueListenableBuilder<bool>(
        valueListenable: settings.listenable(SettingsService.showPerformanceOverlay),
        builder: (context, showPerf, _) => TvPanelRow.toggle(
          icon: Symbols.analytics_rounded,
          title: t.videoSettings.performanceOverlay,
          toggled: showPerf,
          onSelect: () => settings.write(SettingsService.showPerformanceOverlay, !showPerf),
          automationId: AutomationIds.playerPanelRow,
          automationInstance: 'performance_overlay',
        ),
      ),
    );

    return TvPanelColumns(
      left: [
        if (display.isNotEmpty) ...[
          TvPanelSectionHeader(label: t.videoControls.tvPanel.display),
          TvPanelGroup(children: display),
        ],
      ],
      right: [TvPanelSectionHeader(label: t.videoControls.tvPanel.playback), TvPanelGroup(children: playback)],
    );
  }
}
