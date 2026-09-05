import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import '../../../mpv/mpv.dart';
import '../../../services/apple_audio_session_service.dart';
import '../../../services/audio_output_coordinator.dart';
import '../../../services/audio_output_decision.dart';
import '../../../services/settings_service.dart';
import '../../../utils/audio_output_labels.dart';
import '../../../utils/formatters.dart';
import '../../../utils/player_subtitle_labeling.dart';
import '../../../utils/track_label_builder.dart';
import '../helpers/track_filter_helper.dart';
import '../models/track_controls_state.dart';
import 'tv_panel_widgets.dart';

/// Volume boost steps: the ceiling and the level move together (AUD1).
const List<int> kTvPanelVolumeBoostSteps = [100, 150, 200, 300];

/// Subtitle text sizes a value row steps through; `sub-font-size` values.
const List<int> kTvPanelSubtitleSizes = [30, 38, 48, 60];

/// Background opacity the toggle writes when it turns the box on.
const int kTvPanelSubtitleBackgroundOpacity = 60;

/// "Sound" tab: tracks on the left, output on the right (volume boost, audio
/// sync, output mode, priority, level volume, reduce loud sounds).
class TvAudioTab extends StatelessWidget {
  final Player player;
  final TrackControlsState state;
  final FocusNode firstFocusNode;
  final VoidCallback onNavigateUp;
  final VoidCallback onOpenAudioSync;

  const TvAudioTab({
    super.key,
    required this.player,
    required this.state,
    required this.firstFocusNode,
    required this.onNavigateUp,
    required this.onOpenAudioSync,
  });

  /// Raises the ceiling first, then the level: mpv clamps `volume` to
  /// `volume-max`, so the other order would leave the boost at the old cap.
  /// Both are persisted the way playback start reads them back
  /// (`video_player_screen.dart`, `volume-max` then `volume`).
  static Future<void> applyVolumeBoost(Player player, int percent) async {
    await player.setProperty('volume-max', percent.toString());
    await player.setVolume(percent.toDouble());
    final settings = SettingsService.instance;
    await settings.write(SettingsService.maxVolume, percent);
    await settings.write(SettingsService.volume, percent.toDouble());
  }

  static String volumeBoostLabel(int percent) =>
      percent <= 100 ? t.common.off : t.videoControls.tvPanel.volumeBoostStep(percent: percent - 100);

  String _audioOutputModeLabel(AudioOutputMode mode) => switch (mode) {
    AudioOutputMode.auto => t.videoSettings.audioOutputModes.auto,
    AudioOutputMode.passthrough => t.videoSettings.audioOutputModes.passthrough,
    AudioOutputMode.pcm => t.videoSettings.audioOutputModes.pcm,
  };

  String _audioOutputModeDescription(AudioOutputMode mode) => switch (mode) {
    AudioOutputMode.auto => t.videoSettings.audioOutputModeDescriptions.auto,
    AudioOutputMode.passthrough => t.videoSettings.audioOutputModeDescriptions.passthrough,
    AudioOutputMode.pcm => t.videoSettings.audioOutputModeDescriptions.pcm,
  };

  String _audioPriorityLabel(AudioPriority priority) => switch (priority) {
    AudioPriority.evenVolume => t.videoSettings.audioPriorities.evenVolume,
    AudioPriority.originalDolby => t.videoSettings.audioPriorities.originalDolby,
  };

  Future<void> _setOutputMode(AudioOutputMode next) async {
    // Awaited: the coordinator reads the setting synchronously.
    await SettingsService.instance.write(SettingsService.audioOutputMode, next);
    await AudioOutputCoordinator.current?.onModeChanged();
  }

  Future<void> _setPriority(AudioPriority next) async {
    await SettingsService.instance.write(SettingsService.audioPriority, next);
    await AudioOutputCoordinator.current?.onModeChanged();
  }

  Future<void> _pushLoudness() async {
    final settings = SettingsService.instance;
    await player.setAudioNormalization(
      AudioLoudness(
        levelVolume: settings.read(SettingsService.audioLevelVolume),
        reduceLoudSounds: settings.read(SettingsService.audioReduceLoudSounds),
      ),
    );
  }

  int? _selectedSourceAudioId() {
    final explicit = state.selectedAudioStreamId;
    if (explicit != null && state.sourceAudioTracks.any((t) => t.id == explicit)) return explicit;
    for (final track in state.sourceAudioTracks) {
      if (track.selected) return track.id;
    }
    return null;
  }

  List<Widget> _trackRows(Tracks? tracks, TrackSelection? selection, FocusNode? Function() nodeFor) {
    final hasExternalSourceAudio = state.sourceAudioTracks.any((track) => track.isExternal);
    final useSourceAudio =
        (state.isTranscoding || hasExternalSourceAudio) &&
        state.sourceAudioTracks.length > 1 &&
        state.onSwitchAudioStreamId != null;
    final rows = <Widget>[];
    if (useSourceAudio) {
      final selectedId = _selectedSourceAudioId();
      for (var i = 0; i < state.sourceAudioTracks.length; i++) {
        final track = state.sourceAudioTracks[i];
        final label = track.label;
        final node = nodeFor();
        rows.add(
          TvPanelRow.choice(
            focusNode: node,
            onNavigateUp: node == null ? null : onNavigateUp,
            title: label.primary,
            subtitle: label.secondary,
            selected: track.id == selectedId,
            onSelect: () => state.onSwitchAudioStreamId!(track.id),
            automationId: AutomationIds.playerPanelRow,
            automationInstance: 'audio.track.$i',
          ),
        );
      }
      return rows;
    }
    final mpvTracks = TrackFilterHelper.extractAndFilterTracks<AudioTrack>(tracks, (t) => t?.audio ?? []);
    final selectedId = selection?.audio?.id ?? '';
    for (var i = 0; i < mpvTracks.length; i++) {
      final track = mpvTracks[i];
      final label = TrackLabelBuilder.audioLabel(
        title: track.title,
        language: track.language,
        codec: track.codec,
        channels: track.channelsCount,
        profile: track.profile,
        index: i,
      );
      final isSelected = track.id == selectedId;
      final node = nodeFor();
      void select() {
        player.selectAudioTrack(track);
        state.onAudioTrackChanged?.call(track);
      }

      if (!isSelected) {
        rows.add(
          TvPanelRow.choice(
            focusNode: node,
            onNavigateUp: node == null ? null : onNavigateUp,
            title: label.primary,
            subtitle: label.secondary,
            selected: false,
            onSelect: select,
            automationId: AutomationIds.playerPanelRow,
            automationInstance: 'audio.track.$i',
          ),
        );
        continue;
      }
      // Only the playing track can say what the system is doing with it — on
      // Apple TV this is where Atmos becomes visible rather than assumed. It
      // follows the route, so a receiver switching to Atmos while the panel is
      // open updates the label.
      rows.add(
        StreamBuilder<AppleAudioRoute>(
          stream: AppleAudioSessionService.instance.routeChanges,
          initialData: AppleAudioSessionService.instance.lastKnown,
          builder: (context, routeSnapshot) {
            final rendering = audioRenderingLabel((routeSnapshot.data ?? AppleAudioRoute.unknown).renderingMode);
            return TvPanelRow.choice(
              focusNode: node,
              onNavigateUp: node == null ? null : onNavigateUp,
              title: label.primary,
              subtitle: label.secondary,
              value: rendering == null ? null : t.videoSettings.audioOutputNow(mode: rendering),
              selected: true,
              onSelect: select,
              automationId: AutomationIds.playerPanelRow,
              automationInstance: 'audio.track.$i',
            );
          },
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return StreamBuilder<Tracks>(
      stream: player.streams.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) {
        return StreamBuilder<TrackSelection>(
          stream: player.streams.track,
          initialData: player.state.track,
          builder: (context, selSnapshot) {
            var first = true;
            FocusNode? nodeFor() {
              if (!first) return null;
              first = false;
              return firstFocusNode;
            }

            final trackRows = _trackRows(tracksSnapshot.data, selSnapshot.data, nodeFor);
            final boostNode = nodeFor();

            return ValueListenableBuilder<bool>(
              valueListenable: AudioOutputCoordinator.bitstreamActive,
              builder: (context, bitstreaming, _) {
                final output = <Widget>[
                  ValueListenableBuilder<int>(
                    valueListenable: settings.listenable(SettingsService.maxVolume),
                    builder: (context, maxVol, _) => bitstreaming
                        ? TvPanelRow(
                            focusNode: boostNode,
                            onNavigateUp: boostNode == null ? null : onNavigateUp,
                            icon: Symbols.volume_up_rounded,
                            title: t.videoControls.tvPanel.volumeBoost,
                            subtitle: t.videoControls.tvPanel.passthroughSetsLevel,
                            value: t.videoControls.tvPanel.paused,
                            dimmed: true,
                            automationId: AutomationIds.playerPanelRow,
                            automationInstance: 'volume_boost',
                          )
                        : TvPanelRow.value(
                            focusNode: boostNode,
                            onNavigateUp: boostNode == null ? null : onNavigateUp,
                            icon: Symbols.volume_up_rounded,
                            title: t.videoControls.tvPanel.volumeBoost,
                            subtitle: t.videoControls.tvPanel.volumeBoostHint,
                            value: volumeBoostLabel(maxVol),
                            highlighted: maxVol > 100,
                            onSelect: () => applyVolumeBoost(player, stepValue(kTvPanelVolumeBoostSteps, maxVol, 1)),
                            onStepLeft: () => applyVolumeBoost(player, stepValue(kTvPanelVolumeBoostSteps, maxVol, -1)),
                            onStepRight: () => applyVolumeBoost(player, stepValue(kTvPanelVolumeBoostSteps, maxVol, 1)),
                            automationId: AutomationIds.playerPanelRow,
                            automationInstance: 'volume_boost',
                            automationState: () => {'percent': maxVol},
                          ),
                  ),
                  TvPanelRow(
                    icon: Symbols.sync_rounded,
                    title: t.videoSettings.audioSync,
                    value: formatSyncOffset(state.audioSyncOffset.toDouble()),
                    highlighted: state.audioSyncOffset != 0,
                    showChevron: true,
                    onSelect: onOpenAudioSync,
                    automationId: AutomationIds.playerPanelRow,
                    automationInstance: 'audio_sync',
                  ),
                  ValueListenableBuilder<AudioOutputMode>(
                    valueListenable: settings.listenable(SettingsService.audioOutputMode),
                    builder: (context, mode, _) => TvPanelRow.value(
                      icon: Symbols.surround_sound_rounded,
                      title: t.videoSettings.audioOutputTitle,
                      subtitle: _audioOutputModeDescription(mode),
                      value: _audioOutputModeLabel(mode),
                      highlighted: mode != AudioOutputMode.pcm,
                      onSelect: () => _setOutputMode(stepValue(AudioOutputMode.values, mode, 1)),
                      onStepLeft: () => _setOutputMode(stepValue(AudioOutputMode.values, mode, -1)),
                      onStepRight: () => _setOutputMode(stepValue(AudioOutputMode.values, mode, 1)),
                      automationId: AutomationIds.playerPanelRow,
                      automationInstance: 'audio_output_mode',
                      automationState: () => {'mode': mode.name},
                    ),
                  ),
                  // Priority only means something under Auto; the explicit modes
                  // already say which property they protect. Dimmed and skipped
                  // by traversal rather than removed, so the column keeps its
                  // shape and the focus never falls out of the panel.
                  ValueListenableBuilder<AudioOutputMode>(
                    valueListenable: settings.listenable(SettingsService.audioOutputMode),
                    builder: (context, mode, _) => ValueListenableBuilder<AudioPriority>(
                      valueListenable: settings.listenable(SettingsService.audioPriority),
                      builder: (context, priority, _) {
                        final active = mode == AudioOutputMode.auto;
                        return TvPanelRow.value(
                          icon: Symbols.tune_rounded,
                          title: t.videoSettings.audioPriorityTitle,
                          value: _audioPriorityLabel(priority),
                          highlighted: active && priority == AudioPriority.originalDolby,
                          dimmed: !active,
                          canRequestFocus: active,
                          onSelect: active ? () => _setPriority(stepValue(AudioPriority.values, priority, 1)) : null,
                          onStepLeft: active ? () => _setPriority(stepValue(AudioPriority.values, priority, -1)) : null,
                          onStepRight: active ? () => _setPriority(stepValue(AudioPriority.values, priority, 1)) : null,
                          automationId: AutomationIds.playerPanelRow,
                          automationInstance: 'audio_priority',
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: settings.listenable(SettingsService.audioLevelVolume),
                    builder: (context, levelling, _) => _loudnessRow(
                      icon: Symbols.graphic_eq_rounded,
                      title: t.videoSettings.audioLevelVolume,
                      subtitle: t.videoSettings.audioLevelVolumeDescription,
                      enabled: levelling,
                      active: true,
                      bitstreaming: bitstreaming,
                      instance: 'audio_level_volume',
                      onToggle: () async {
                        await settings.write(SettingsService.audioLevelVolume, !levelling);
                        await _pushLoudness();
                      },
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: settings.listenable(SettingsService.audioLevelVolume),
                    builder: (context, levelling, _) => ValueListenableBuilder<bool>(
                      valueListenable: settings.listenable(SettingsService.audioReduceLoudSounds),
                      // Without a level to hold, the compressor measurably
                      // clipped instead of helping: dimmed while levelling is off.
                      builder: (context, reduce, _) => _loudnessRow(
                        icon: Symbols.compress_rounded,
                        title: t.videoSettings.audioReduceLoudSounds,
                        subtitle: t.videoSettings.audioReduceLoudSoundsDescription,
                        enabled: reduce,
                        active: levelling,
                        bitstreaming: bitstreaming,
                        instance: 'audio_reduce_loud_sounds',
                        onToggle: () async {
                          await settings.write(SettingsService.audioReduceLoudSounds, !reduce);
                          await _pushLoudness();
                        },
                      ),
                    ),
                  ),
                ];

                return TvPanelColumns(
                  left: [
                    TvPanelSectionHeader(label: t.videoControls.tvPanel.tracks),
                    if (trackRows.isNotEmpty) TvPanelGroup(children: trackRows),
                  ],
                  right: [TvPanelSectionHeader(label: t.videoControls.tvPanel.output), TvPanelGroup(children: output)],
                );
              },
            );
          },
        );
      },
    );
  }

  /// One of the two loudness switches. During a bitstream it says why it is
  /// inert instead of flipping a value nobody can hear (DEC-013).
  Widget _loudnessRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required bool active,
    required bool bitstreaming,
    required String instance,
    required Future<void> Function() onToggle,
  }) {
    if (bitstreaming) {
      return TvPanelRow(
        icon: icon,
        title: title,
        subtitle: t.videoControls.tvPanel.passthroughSetsLevel,
        value: t.videoControls.tvPanel.paused,
        dimmed: true,
        automationId: AutomationIds.playerPanelRow,
        automationInstance: instance,
      );
    }
    return TvPanelRow.toggle(
      icon: icon,
      title: title,
      subtitle: subtitle,
      toggled: enabled,
      dimmed: !active,
      canRequestFocus: active,
      onSelect: active ? onToggle : null,
      automationId: AutomationIds.playerPanelRow,
      automationInstance: instance,
      automationState: () => {'on': enabled},
    );
  }
}

/// "Subtitles" tab: tracks (Off, tracks, online search) on the left, style and
/// timing on the right (delay, text size, background, and where the rest
/// lives). Style rows write the global preferences and apply them live; they
/// never touch language (DEC-096).
class TvSubtitlesTab extends StatelessWidget {
  final Player player;
  final TrackControlsState state;
  final FocusNode firstFocusNode;
  final VoidCallback onNavigateUp;
  final VoidCallback onOpenSubtitleSync;
  final VoidCallback? onOpenSubtitleSearch;

  const TvSubtitlesTab({
    super.key,
    required this.player,
    required this.state,
    required this.firstFocusNode,
    required this.onNavigateUp,
    required this.onOpenSubtitleSync,
    this.onOpenSubtitleSearch,
  });

  static String textSizeLabel(int size) {
    final index = kTvPanelSubtitleSizes.indexOf(size);
    return switch (index) {
      0 => t.videoControls.tvPanel.textSizeSmall,
      2 => t.videoControls.tvPanel.textSizeLarge,
      3 => t.videoControls.tvPanel.textSizeExtraLarge,
      _ => t.videoControls.tvPanel.textSizeNormal,
    };
  }

  /// Snaps a stored size onto the nearest step, so a value set on the global
  /// page still lands on a step here.
  static int nearestTextSize(int size) {
    var best = kTvPanelSubtitleSizes.first;
    for (final step in kTvPanelSubtitleSizes) {
      if ((step - size).abs() < (best - size).abs()) best = step;
    }
    return best;
  }

  static Future<void> applyTextSize(Player player, int size) async {
    await SettingsService.instance.write(SettingsService.subtitleFontSize, size);
    await player.setProperty('sub-font-size', size.toString());
  }

  /// The same two writes playback start does for the background box.
  static Future<void> applyBackground(Player player, bool on) async {
    final settings = SettingsService.instance;
    final opacity = on ? kTvPanelSubtitleBackgroundOpacity : 0;
    await settings.write(SettingsService.subtitleBackgroundOpacity, opacity);
    final alpha = (opacity * 255 / 100).toInt();
    final color = settings.read(SettingsService.subtitleBackgroundColor).replaceFirst('#', '');
    await player.setProperty('sub-back-color', '#${alpha.toRadixString(16).padLeft(2, '0').toUpperCase()}$color');
    await player.setProperty('sub-border-style', on ? 'background-box' : 'outline-and-shadow');
  }

  int _selectedSourceSubId() {
    final explicit = state.selectedSubtitleStreamId;
    if (explicit != null && (explicit == 0 || state.sourceSubtitleTracks.any((t) => t.id == explicit))) {
      return explicit;
    }
    for (final track in state.sourceSubtitleTracks) {
      if (track.selected) return track.id;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return StreamBuilder<Tracks>(
      stream: player.streams.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) {
        return StreamBuilder<TrackSelection>(
          stream: player.streams.track,
          initialData: player.state.track,
          builder: (context, selSnapshot) {
            final rows = <Widget>[];
            final useSourceSubs = state.canUseSourceSubtitles;
            final playerSubtitleTracks = TrackFilterHelper.extractAndFilterTracks<SubtitleTrack>(
              tracksSnapshot.data,
              (t) => t?.subtitle ?? [],
            );
            logSubtitleLabelingDiagnostics(
              surface: 'tv',
              playerTracks: playerSubtitleTracks,
              serverTracks: state.sourceSubtitleMetadata,
              canUseSourceSubtitles: useSourceSubs,
            );
            if (useSourceSubs) {
              final selectedId = _selectedSourceSubId();
              rows.add(
                TvPanelRow.choice(
                  focusNode: firstFocusNode,
                  onNavigateUp: onNavigateUp,
                  title: t.common.off,
                  selected: selectedId == 0,
                  onSelect: () => state.onSwitchSubtitleStreamId!(0),
                  automationId: AutomationIds.playerPanelRow,
                  automationInstance: 'subtitle.off',
                ),
              );
              for (var i = 0; i < state.sourceSubtitleTracks.length; i++) {
                final track = state.sourceSubtitleTracks[i];
                final label = track.labelForIndex(i);
                rows.add(
                  TvPanelRow.choice(
                    title: label.primary,
                    subtitle: label.secondary,
                    selected: track.id == selectedId,
                    onSelect: () => state.onSwitchSubtitleStreamId!(track.id),
                    automationId: AutomationIds.playerPanelRow,
                    automationInstance: 'subtitle.track.$i',
                  ),
                );
              }
            } else {
              final selectedSub = selSnapshot.data?.subtitle;
              final isOff = selectedSub == null || selectedSub.id == 'no';
              rows.add(
                TvPanelRow.choice(
                  focusNode: firstFocusNode,
                  onNavigateUp: onNavigateUp,
                  title: t.common.off,
                  selected: isOff,
                  onSelect: () {
                    player.selectSubtitleTrack(SubtitleTrack.off);
                    state.onSubtitleTrackChanged?.call(SubtitleTrack.off);
                  },
                  automationId: AutomationIds.playerPanelRow,
                  automationInstance: 'subtitle.off',
                ),
              );
              for (var i = 0; i < playerSubtitleTracks.length; i++) {
                final track = playerSubtitleTracks[i];
                final label = labelForPlayerSubtitle(
                  track: track,
                  visibleIndex: i,
                  playerTracks: playerSubtitleTracks,
                  serverTracks: state.sourceSubtitleMetadata,
                );
                rows.add(
                  TvPanelRow.choice(
                    title: label.primary,
                    subtitle: label.secondary,
                    selected: !isOff && track.id == selectedSub.id,
                    onSelect: () {
                      player.selectSubtitleTrack(track);
                      state.onSubtitleTrackChanged?.call(track);
                    },
                    automationId: AutomationIds.playerPanelRow,
                    automationInstance: 'subtitle.track.$i',
                  ),
                );
              }
            }
            if (state.canSearchSubtitles && onOpenSubtitleSearch != null) {
              rows.add(
                TvPanelRow(
                  icon: Symbols.search_rounded,
                  title: t.videoControls.searchSubtitles,
                  showChevron: true,
                  onSelect: onOpenSubtitleSearch,
                  automationId: AutomationIds.playerPanelRow,
                  automationInstance: 'subtitle.search',
                ),
              );
            }

            final style = <Widget>[
              TvPanelRow(
                icon: Symbols.sync_rounded,
                title: t.videoSettings.subtitleSync,
                value: formatSyncOffset(state.subtitleSyncOffset.toDouble()),
                highlighted: state.subtitleSyncOffset != 0,
                showChevron: true,
                onSelect: onOpenSubtitleSync,
                automationId: AutomationIds.playerPanelRow,
                automationInstance: 'subtitle_sync',
              ),
              ValueListenableBuilder<int>(
                valueListenable: settings.listenable(SettingsService.subtitleFontSize),
                builder: (context, stored, _) {
                  final size = nearestTextSize(stored);
                  return TvPanelRow.value(
                    icon: Symbols.format_size_rounded,
                    title: t.videoControls.tvPanel.textSize,
                    subtitle: t.videoControls.tvPanel.textSizeHint,
                    value: textSizeLabel(size),
                    onSelect: () => applyTextSize(player, stepValue(kTvPanelSubtitleSizes, size, 1)),
                    onStepLeft: () => applyTextSize(player, stepValue(kTvPanelSubtitleSizes, size, -1)),
                    onStepRight: () => applyTextSize(player, stepValue(kTvPanelSubtitleSizes, size, 1)),
                    automationId: AutomationIds.playerPanelRow,
                    automationInstance: 'subtitle_text_size',
                    automationState: () => {'size': size},
                  );
                },
              ),
              ValueListenableBuilder<int>(
                valueListenable: settings.listenable(SettingsService.subtitleBackgroundOpacity),
                builder: (context, opacity, _) => TvPanelRow.toggle(
                  icon: Symbols.subtitles_rounded,
                  title: t.videoControls.tvPanel.background,
                  subtitle: t.videoControls.tvPanel.backgroundHint,
                  toggled: opacity > 0,
                  onSelect: () => applyBackground(player, opacity == 0),
                  automationId: AutomationIds.playerPanelRow,
                  automationInstance: 'subtitle_background',
                ),
              ),
            ];

            return TvPanelColumns(
              left: [TvPanelSectionHeader(label: t.videoControls.tvPanel.tracks), TvPanelGroup(children: rows)],
              right: [
                TvPanelSectionHeader(label: t.videoControls.tvPanel.styleAndTiming),
                TvPanelGroup(children: style),
                TvPanelStaticRow(
                  title: t.videoControls.tvPanel.allStyleSettings,
                  subtitle: t.videoControls.tvPanel.allStyleSettingsPath,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
