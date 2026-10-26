/// The audio rows of Afspelen: output, priority, levelling, sync and the
/// volume ceiling. A `part` of `playback_settings_screen.dart`, split from
/// `playback_rows.dart` to keep both readable (A-24b).
part of '../playback_settings_screen.dart';

extension _PlaybackAudioRows on _PlaybackSettingsScreenState {
  Widget _maxVolumeTile() => SettingNumberTile(
    pref: SettingsService.volumeBoost,
    icon: Symbols.volume_up_rounded,
    title: t.settings.maxVolume,
    subtitleBuilder: (v) => t.settings.maxVolumePercent(percent: v.toString()),
    labelText: t.settings.maxVolumeDescription,
    suffixText: '%',
    min: 100,
    max: 300,
    // The boost is part of the filter chain now, so a running player has to
    // be told; it used to be an mpv property the next title read back.
    onAfterWrite: (_) => _pushLoudness(),
  );

  /// Prioriteit audiospoor off TV: a value row with a picker; only under
  /// Automatic, like the TV row.
  Widget _audioPriorityChoice() => SettingValueBuilder<AudioOutputMode>(
    pref: SettingsService.audioOutputMode,
    builder: (context, mode, _) => mode != AudioOutputMode.auto
        ? const SizedBox.shrink()
        : SettingSelectionTile<AudioPriority, AudioPriority>(
            pref: SettingsService.audioPriority,
            icon: Symbols.tune_rounded,
            title: t.videoSettings.audioPriorityTitle,
            subtitleBuilder: _audioPriorityLabel,
            options: [for (final p in AudioPriority.values) DialogOption(value: p, title: _audioPriorityLabel(p))],
            decode: (v) => v,
            encode: (v) => v,
            onAfterWrite: (_) => AudioOutputCoordinator.current?.onModeChanged(),
          ),
  );

  String _audioPriorityLabel(AudioPriority priority) => switch (priority) {
    AudioPriority.evenVolume => t.videoSettings.audioPriorities.evenVolume,
    AudioPriority.originalDolby => t.videoSettings.audioPriorities.originalDolby,
  };

  Widget _audioOutputModeTile() => SettingSelectionTile<AudioOutputMode, AudioOutputMode>(
    pref: SettingsService.audioOutputMode,
    icon: Symbols.surround_sound_rounded,
    title: t.videoSettings.audioOutputTitle,
    subtitleBuilder: (mode) => '${_audioOutputModeLabel(mode)} · ${_audioOutputModeDescription(mode)}',
    valueBuilder: _audioOutputModeLabel,
    descriptionBuilder: _audioOutputModeDescription,
    options: AudioOutputMode.values
        .map((m) => DialogOption(value: m, title: _audioOutputModeLabel(m), subtitle: _audioOutputModeDescription(m)))
        .toList(),
    decode: (m) => m,
    encode: (m) => m,
    // Takes effect on the running player too, not just the next title.
    onAfterWrite: (_) => AudioOutputCoordinator.current?.onModeChanged(),
  );

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

  /// Only shown for Automatic: the explicit Passthrough and PCM modes already
  /// say which property they protect, so a priority under them would be a
  /// second answer to a question the user already answered.
  Widget _audioPriorityTile() => SettingValueBuilder<AudioOutputMode>(
    pref: SettingsService.audioOutputMode,
    builder: (context, mode, _) => mode != AudioOutputMode.auto
        ? const SizedBox.shrink()
        : SettingSegmentedTile<AudioPriority, AudioPriority>(
            pref: SettingsService.audioPriority,
            icon: Symbols.tune_rounded,
            title: t.videoSettings.audioPriorityTitle,
            segments: [
              ButtonSegment(value: AudioPriority.evenVolume, label: Text(t.videoSettings.audioPriorities.evenVolume)),
              ButtonSegment(
                value: AudioPriority.originalDolby,
                label: Text(t.videoSettings.audioPriorities.originalDolby),
              ),
            ],
            decode: (v) => v,
            encode: (v) => v,
            onAfterWrite: (_) => AudioOutputCoordinator.current?.onModeChanged(),
          ),
  );

  Widget _audioLevelVolumeTile() => SettingSwitchTile(
    pref: SettingsService.audioLevelVolume,
    icon: Symbols.graphic_eq_rounded,
    title: t.videoSettings.audioLevelVolume,
    subtitle: t.videoSettings.audioLevelVolumeDescription,
    onAfterWrite: (_) => _pushLoudness(),
  );

  /// Independent of levelling. Reduce-only used to be refused because a
  /// compressor with makeup gain and no ceiling ran a test excerpt to
  /// +5,4 dBFS; with neutral makeup and the true-peak limiter behind it that
  /// cannot happen, so the switch means what it says on its own.
  Widget _audioReduceLoudSoundsTile() => SettingSwitchTile(
    pref: SettingsService.audioReduceLoudSounds,
    icon: Symbols.compress_rounded,
    title: t.videoSettings.audioReduceLoudSounds,
    subtitle: t.videoSettings.audioReduceLoudSoundsDescription,
    onAfterWrite: (_) => _pushLoudness(),
  );

  /// Takes effect on the running player too, not just the next title. The
  /// coordinator is the handle on the playback session currently on screen.
  Future<void> _pushLoudness() async {
    await AudioOutputCoordinator.current?.player.setAudioNormalization(audioLoudnessPrefs());
  }

  Widget _audioSyncOffsetTile() => SettingNumberTile(
    pref: SettingsService.audioSyncOffset,
    icon: Symbols.sync_rounded,
    title: t.videoSettings.audioSync,
    subtitleBuilder: (v) => '${(v / 1000).toStringAsFixed(1)}s · ${t.settings.audioSyncOffsetDescription}',
    valueBuilder: (v) => '${(v / 1000).toStringAsFixed(1)}s',
    descriptionBuilder: (_) => t.settings.audioSyncOffsetDescription,
    labelText: t.videoSettings.audioSync,
    suffixText: 'ms',
    min: -5000,
    max: 5000,
  );
}
