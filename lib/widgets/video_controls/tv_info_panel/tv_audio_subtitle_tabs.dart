import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../mpv/mpv.dart';
import '../../../services/apple_audio_session_service.dart';
import '../../../services/audio_output_coordinator.dart';
import '../../../services/audio_output_decision.dart';
import '../../../services/settings_service.dart';
import '../../../utils/audio_output_labels.dart';
import '../../../utils/player_subtitle_labeling.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/track_label_builder.dart';
import '../models/track_controls_state.dart';
import '../helpers/track_filter_helper.dart';
import 'tv_panel_widgets.dart';

/// "Audio" tab: audio track list + options (volume boost, delay, normalize).
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

  static const List<int> _maxVolumeSteps = [100, 150, 200, 300];

  Future<void> _cycleMaxVolume() async {
    final current = SettingsService.instance.read(SettingsService.maxVolume);
    var idx = _maxVolumeSteps.indexWhere((v) => v >= current);
    idx = idx < 0 ? 0 : (idx + 1) % _maxVolumeSteps.length;
    final next = _maxVolumeSteps[idx];
    await SettingsService.instance.write(SettingsService.maxVolume, next);
    await player.setProperty('volume-max', next.toString());
  }

  @override
  Widget build(BuildContext context) {
    final hasExternalSourceAudio = state.sourceAudioTracks.any((track) => track.isExternal);
    final useSourceAudio =
        (state.isTranscoding || hasExternalSourceAudio) &&
        state.sourceAudioTracks.length > 1 &&
        state.onSwitchAudioStreamId != null;

    return StreamBuilder<Tracks>(
      stream: player.streams.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) {
        return StreamBuilder<TrackSelection>(
          stream: player.streams.track,
          initialData: player.state.track,
          builder: (context, selSnapshot) {
            final rows = <Widget>[];
            var first = true;

            FocusNode? nodeFor() => first ? firstFocusNode : null;
            VoidCallback? upFor() => first ? onNavigateUp : null;

            rows.add(TvPanelSectionHeader(label: t.videoControls.tvPanel.tracks));

            if (useSourceAudio) {
              final selectedId = _selectedSourceAudioId();
              for (final track in state.sourceAudioTracks) {
                final isSelected = track.id == selectedId;
                rows.add(
                  TvPanelRow(
                    focusNode: nodeFor(),
                    onNavigateUp: upFor(),
                    title: track.label.primary,
                    selected: isSelected,
                    onSelect: () => state.onSwitchAudioStreamId!(track.id),
                  ),
                );
                first = false;
              }
            } else {
              final tracks = TrackFilterHelper.extractAndFilterTracks<AudioTrack>(
                tracksSnapshot.data,
                (t) => t?.audio ?? [],
              );
              final selectedId = selSnapshot.data?.audio?.id ?? '';
              for (var i = 0; i < tracks.length; i++) {
                final track = tracks[i];
                final label = TrackLabelBuilder.audioLabel(
                  title: track.title,
                  language: track.language,
                  codec: track.codec,
                  channels: track.channelsCount,
                  profile: track.profile,
                  index: i,
                );
                final isSelected = track.id == selectedId;
                final row = TvPanelRow(
                  focusNode: nodeFor(),
                  onNavigateUp: upFor(),
                  title: label.primary,
                  selected: isSelected,
                  onSelect: () {
                    player.selectAudioTrack(track);
                    state.onAudioTrackChanged?.call(track);
                  },
                );
                rows.add(
                  // Only the playing track can say what the system is doing
                  // with it — on Apple TV this is where Atmos becomes visible
                  // rather than assumed. It has to follow the route: switching
                  // the receiver to Atmos while the panel is open should not
                  // leave the old label on screen, and this panel otherwise
                  // only rebuilds when a track stream fires.
                  isSelected
                      ? StreamBuilder<AppleAudioRoute>(
                          stream: AppleAudioSessionService.instance.routeChanges,
                          initialData: AppleAudioSessionService.instance.lastKnown,
                          builder: (context, routeSnapshot) => TvPanelRow(
                            focusNode: row.focusNode,
                            onNavigateUp: row.onNavigateUp,
                            title: row.title,
                            value: audioRenderingLabel((routeSnapshot.data ?? AppleAudioRoute.unknown).renderingMode),
                            selected: true,
                            onSelect: row.onSelect,
                          ),
                        )
                      : row,
                );
                first = false;
              }
            }

            // Options
            rows.add(TvPanelSectionHeader(label: t.videoControls.tvPanel.options));

            rows.add(_MaxVolumeRow(focusNode: nodeFor(), onNavigateUp: upFor(), onSelect: _cycleMaxVolume));
            first = false;

            rows.add(
              TvPanelRow(
                icon: Symbols.sync_rounded,
                title: t.videoSettings.audioSync,
                value: state.audioSyncOffset != 0 ? '${(state.audioSyncOffset / 1000).toStringAsFixed(1)}s' : null,
                highlighted: state.audioSyncOffset != 0,
                showChevron: true,
                onSelect: onOpenAudioSync,
              ),
            );

            rows.add(
              ValueListenableBuilder<AudioOutputMode>(
                valueListenable: SettingsService.instance.listenable(SettingsService.audioOutputMode),
                builder: (context, mode, _) => TvPanelRow(
                  icon: Symbols.surround_sound_rounded,
                  title: t.videoSettings.audioOutputTitle,
                  value: _audioOutputModeLabel(mode),
                  highlighted: mode != AudioOutputMode.pcm,
                  // Tap cycles Auto → Passthrough → PCM, same as the mobile sheet.
                  onSelect: () async {
                    const order = AudioOutputMode.values;
                    final next = order[(mode.index + 1) % order.length];
                    await SettingsService.instance.write(SettingsService.audioOutputMode, next);
                    await AudioOutputCoordinator.current?.onModeChanged();
                  },
                ),
              ),
            );

            rows.add(
              ValueListenableBuilder<AudioNormalizationMode>(
                valueListenable: SettingsService.instance.listenable(SettingsService.audioNormalizationMode),
                builder: (context, mode, _) => TvPanelRow(
                  icon: Symbols.graphic_eq_rounded,
                  title: t.videoSettings.audioNormalizationTitle,
                  value: _audioNormalizationLabel(mode),
                  highlighted: mode.isEnabled,
                  // Tap cycles Off → Normalize → Night, same as the mobile sheet.
                  onSelect: () async {
                    const order = AudioNormalizationMode.values;
                    final next = order[(mode.index + 1) % order.length];
                    await SettingsService.instance.write(SettingsService.audioNormalizationMode, next);
                    await player.setAudioNormalization(next);
                    // A running bitstream outranks the loudness setting
                    // (DEC-013); say so once instead of changing nothing
                    // audible.
                    if (context.mounted && player.consumeNormalizationSuspendedNotice()) {
                      showAppSnackBar(context, t.videoSettings.audioNormalizationSuspended);
                    }
                  },
                ),
              ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
            );
          },
        );
      },
    );
  }

  String _audioOutputModeLabel(AudioOutputMode mode) => switch (mode) {
    AudioOutputMode.auto => t.videoSettings.audioOutputModes.auto,
    AudioOutputMode.passthrough => t.videoSettings.audioOutputModes.passthrough,
    AudioOutputMode.pcm => t.videoSettings.audioOutputModes.pcm,
  };

  String _audioNormalizationLabel(AudioNormalizationMode mode) => switch (mode) {
    AudioNormalizationMode.off => t.videoSettings.audioNormalizationModes.off,
    AudioNormalizationMode.normalize => t.videoSettings.audioNormalizationModes.normalize,
    AudioNormalizationMode.night => t.videoSettings.audioNormalizationModes.night,
  };

  int? _selectedSourceAudioId() {
    final explicit = state.selectedAudioStreamId;
    if (explicit != null && state.sourceAudioTracks.any((t) => t.id == explicit)) return explicit;
    for (final track in state.sourceAudioTracks) {
      if (track.selected) return track.id;
    }
    return null;
  }
}

class _MaxVolumeRow extends StatelessWidget {
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback onSelect;
  const _MaxVolumeRow({this.focusNode, this.onNavigateUp, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SettingsService.instance.listenable(SettingsService.maxVolume),
      builder: (context, maxVol, _) => TvPanelRow(
        focusNode: focusNode,
        onNavigateUp: onNavigateUp,
        icon: Symbols.volume_up_rounded,
        title: t.settings.maxVolume,
        value: '$maxVol%',
        highlighted: maxVol > 100,
        onSelect: onSelect,
      ),
    );
  }
}

/// "Subtitles" tab: subtitle track list (Off + tracks), "More…" search and delay.
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.streams.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) {
        return StreamBuilder<TrackSelection>(
          stream: player.streams.track,
          initialData: player.state.track,
          builder: (context, selSnapshot) {
            final rows = <Widget>[];
            var first = true;
            FocusNode? nodeFor() => first ? firstFocusNode : null;
            VoidCallback? upFor() => first ? onNavigateUp : null;

            rows.add(TvPanelSectionHeader(label: t.videoControls.tvPanel.tracks));

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
              // Off
              rows.add(
                TvPanelRow(
                  focusNode: nodeFor(),
                  onNavigateUp: upFor(),
                  title: t.common.off,
                  selected: selectedId == 0,
                  onSelect: () => state.onSwitchSubtitleStreamId!(0),
                ),
              );
              first = false;
              for (var i = 0; i < state.sourceSubtitleTracks.length; i++) {
                final track = state.sourceSubtitleTracks[i];
                rows.add(
                  TvPanelRow(
                    title: track.labelForIndex(i).primary,
                    selected: track.id == selectedId,
                    onSelect: () => state.onSwitchSubtitleStreamId!(track.id),
                  ),
                );
              }
            } else {
              final tracks = playerSubtitleTracks;
              final selectedSub = selSnapshot.data?.subtitle;
              final isOff = selectedSub == null || selectedSub.id == 'no';
              rows.add(
                TvPanelRow(
                  focusNode: nodeFor(),
                  onNavigateUp: upFor(),
                  title: t.common.off,
                  selected: isOff,
                  onSelect: () {
                    player.selectSubtitleTrack(SubtitleTrack.off);
                    state.onSubtitleTrackChanged?.call(SubtitleTrack.off);
                  },
                ),
              );
              first = false;
              for (var i = 0; i < tracks.length; i++) {
                final track = tracks[i];
                final label = labelForPlayerSubtitle(
                  track: track,
                  visibleIndex: i,
                  playerTracks: tracks,
                  serverTracks: state.sourceSubtitleMetadata,
                );
                rows.add(
                  TvPanelRow(
                    title: label.primary,
                    selected: !isOff && track.id == selectedSub.id,
                    onSelect: () {
                      player.selectSubtitleTrack(track);
                      state.onSubtitleTrackChanged?.call(track);
                    },
                  ),
                );
              }
            }

            // Options
            rows.add(TvPanelSectionHeader(label: t.videoControls.tvPanel.options));

            if (state.canSearchSubtitles && onOpenSubtitleSearch != null) {
              rows.add(
                TvPanelRow(
                  icon: Symbols.search_rounded,
                  title: t.videoControls.tvPanel.more,
                  showChevron: true,
                  onSelect: onOpenSubtitleSearch,
                ),
              );
            }

            rows.add(
              TvPanelRow(
                icon: Symbols.sync_rounded,
                title: t.videoSettings.subtitleSync,
                value: state.subtitleSyncOffset != 0
                    ? '${(state.subtitleSyncOffset / 1000).toStringAsFixed(1)}s'
                    : null,
                highlighted: state.subtitleSyncOffset != 0,
                showChevron: true,
                onSelect: onOpenSubtitleSync,
              ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
            );
          },
        );
      },
    );
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
}
