import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_source_info.dart';
import '../../../mpv/mpv.dart';
import '../../../services/settings_service.dart';
import '../../../utils/formatters.dart';
import 'tv_panel_widgets.dart';

/// Ambient lighting intensity steps cycled by the Video tab. `off` disables
/// the effect; the others map to shader brightness in AmbientLightingService.
const List<String> kAmbientIntensityModes = ['off', 'subtle', 'balanced', 'bright'];

/// "Video" tab: Infuse-style action rows (zoom mode, chapters, playback speed,
/// ambient lighting intensity, playback statistics). Every action reuses the
/// same callbacks the VideoSettingsSheet already receives.
class TvVideoTab extends StatelessWidget {
  final Player player;
  final int boxFitMode;
  final VoidCallback? onCycleBoxFit;
  final List<MediaChapter> chapters;
  final Future<void> Function(Duration)? onSeekToChapter;
  final bool canControl;
  final bool isLive;
  final bool ambientSupported;
  final bool ambientEnabled;
  final String ambientIntensity;
  final ValueChanged<String> onSetAmbientIntensity;
  final FocusNode firstFocusNode;
  final VoidCallback onNavigateUp;

  const TvVideoTab({
    super.key,
    required this.player,
    required this.boxFitMode,
    required this.onCycleBoxFit,
    required this.chapters,
    required this.onSeekToChapter,
    required this.canControl,
    required this.isLive,
    required this.ambientSupported,
    required this.ambientEnabled,
    required this.ambientIntensity,
    required this.onSetAmbientIntensity,
    required this.firstFocusNode,
    required this.onNavigateUp,
  });

  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  String _boxFitLabel() => switch (boxFitMode) {
    1 => t.videoControls.fillScreen,
    2 => t.videoControls.stretch,
    _ => t.videoControls.letterbox,
  };

  String _ambientLabel() {
    if (!ambientEnabled) return t.common.off;
    return switch (ambientIntensity) {
      'subtle' => t.videoControls.ambientIntensitySubtle,
      'bright' => t.videoControls.ambientIntensityBright,
      _ => t.videoControls.ambientIntensityBalanced,
    };
  }

  void _cycleAmbient() {
    final current = ambientEnabled ? ambientIntensity : 'off';
    final idx = kAmbientIntensityModes.indexOf(current);
    final next = kAmbientIntensityModes[(idx + 1) % kAmbientIntensityModes.length];
    onSetAmbientIntensity(next);
  }

  Future<void> _cycleSpeed() async {
    final current = player.state.rate;
    var idx = _speeds.indexWhere((s) => (s - current).abs() < 0.01);
    idx = idx < 0 ? _speeds.indexOf(1.0) : (idx + 1) % _speeds.length;
    final next = _speeds[idx];
    await player.setRate(next);
    await SettingsService.instance.write(SettingsService.defaultPlaybackSpeed, next);
  }

  Future<void> _jumpToNextChapter() async {
    if (chapters.isEmpty) return;
    final posMs = player.state.position.inMilliseconds;
    for (final chapter in chapters) {
      if ((chapter.startTimeOffset ?? 0) > posMs) {
        await (onSeekToChapter ?? player.seek)(chapter.startTime);
        return;
      }
    }
    // Past the last chapter — wrap to the first.
    await (onSeekToChapter ?? player.seek)(chapters.first.startTime);
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    // The top-row focus node/nav callback are consumed by the first row added,
    // so its UP returns to the pill tab bar. Nullable-reassignment keeps the
    // analyzer from folding this into dead code.
    FocusNode? topNode = firstFocusNode;
    VoidCallback? topUp = onNavigateUp;

    // Zoom mode
    if (onCycleBoxFit != null) {
      rows.add(
        TvPanelRow(
          focusNode: topNode,
          onNavigateUp: topUp,
          icon: Symbols.aspect_ratio_rounded,
          title: t.videoControls.aspectRatioButton,
          value: _boxFitLabel(),
          highlighted: boxFitMode != 0,
          onSelect: onCycleBoxFit,
        ),
      );
      topNode = null;
      topUp = null;
    }

    // Chapters
    if (chapters.isNotEmpty) {
      rows.add(
        TvPanelRow(
          focusNode: topNode,
          onNavigateUp: topUp,
          icon: Symbols.bookmark_rounded,
          title: t.videoControls.chapters,
          trailing: StreamBuilderChapterLabel(player: player, chapters: chapters),
          onSelect: () => _jumpToNextChapter(),
        ),
      );
      topNode = null;
      topUp = null;
    }

    // Playback speed (hidden for live / no control)
    if (canControl && !isLive) {
      rows.add(_SpeedRow(player: player, focusNode: topNode, onNavigateUp: topUp, onSelect: _cycleSpeed));
      topNode = null;
      topUp = null;
    }

    // Ambient lighting intensity
    if (ambientSupported) {
      rows.add(
        TvPanelRow(
          focusNode: topNode,
          onNavigateUp: topUp,
          icon: Symbols.blur_on,
          title: t.videoControls.ambientLighting,
          value: _ambientLabel(),
          highlighted: ambientEnabled,
          onSelect: _cycleAmbient,
        ),
      );
      topNode = null;
      topUp = null;
    }

    // Playback statistics (performance overlay toggle)
    final perfNode = topNode;
    final perfUp = topUp;
    rows.add(
      ValueListenableBuilder<bool>(
        valueListenable: SettingsService.instance.listenable(SettingsService.showPerformanceOverlay),
        builder: (context, showPerf, _) {
          return TvPanelRow(
            focusNode: perfNode,
            onNavigateUp: perfUp,
            icon: Symbols.analytics_rounded,
            title: t.videoSettings.performanceOverlay,
            value: showPerf ? t.common.ok : t.common.off,
            highlighted: showPerf,
            onSelect: () => SettingsService.instance.write(SettingsService.showPerformanceOverlay, !showPerf),
          );
        },
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

/// Trailing value for the chapters row: the current chapter's label.
class StreamBuilderChapterLabel extends StatelessWidget {
  final Player player;
  final List<MediaChapter> chapters;
  const StreamBuilderChapterLabel({super.key, required this.player, required this.chapters});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.streams.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final idx = MediaChapter.indexAtPosition(pos, chapters);
        final label = idx != null ? chapters[idx].label : '';
        return Text(
          label,
          style: const TextStyle(color: TvPanelTheme.textMuted, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

class _SpeedRow extends StatelessWidget {
  final Player player;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback onSelect;

  const _SpeedRow({required this.player, this.focusNode, this.onNavigateUp, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.streams.rate,
      initialData: player.state.rate,
      builder: (context, snapshot) {
        final rate = snapshot.data ?? 1.0;
        return TvPanelRow(
          focusNode: focusNode,
          onNavigateUp: onNavigateUp,
          icon: Symbols.speed_rounded,
          title: t.videoSettings.playbackSpeed,
          value: formatPlaybackRate(rate, normalAtOne: true),
          highlighted: (rate - 1.0).abs() > 0.01,
          onSelect: onSelect,
        );
      },
    );
  }
}
