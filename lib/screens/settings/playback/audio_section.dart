import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../mpv/models.dart' show AudioLoudness;
import '../../../services/audio_output_coordinator.dart';
import '../../../services/audio_output_decision.dart';
import '../../../services/device_capabilities_service.dart';
import '../../../services/device_capability_overrides.dart';
import '../../../services/settings_service.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/setting_tile.dart';
import '../../../widgets/settings_builder.dart';
import '../../../widgets/settings_section.dart';
import '../settings_utils.dart';

/// The audio block of the playback settings page.
///
/// Lifted out of `playback_settings_screen.dart` unchanged: that file was over
/// five hundred lines before this phase added anything to it. Nothing here
/// behaves differently from where it sat before.
///
/// These three used to live only inside the player's settings sheet, which
/// meant they could not be set before playback started.
List<Widget> playbackAudioSection() => [
  SettingsSectionHeader(t.settings.audio),
  if (PlatformDetector.supportsAudioPassthrough()) _audioOutputModeTile(),
  if (PlatformDetector.supportsAudioPassthrough()) _audioPriorityTile(),
  _audioLevelVolumeTile(),
  _audioReduceLoudSoundsTile(),
  _audioSyncOffsetTile(),
];

/// Both the running player and the capability snapshot follow the setting: the
/// coordinator so the current title switches output path, the snapshot so the
/// next backend profile describes the route the user just chose.
Future<void> _onAudioOutputChanged() async {
  DeviceCapabilitiesService.instance.applyOverrides(DeviceCapabilityOverrides.fromSettings());
  await AudioOutputCoordinator.current?.onModeChanged();
}

Widget _audioOutputModeTile() => SettingSelectionTile<AudioOutputMode, AudioOutputMode>(
  pref: SettingsService.audioOutputMode,
  icon: Symbols.surround_sound_rounded,
  title: t.videoSettings.audioOutputTitle,
  subtitleBuilder: (mode) => '${_audioOutputModeLabel(mode)} · ${_audioOutputModeDescription(mode)}',
  options: AudioOutputMode.values
      .map((m) => DialogOption(value: m, title: _audioOutputModeLabel(m), subtitle: _audioOutputModeDescription(m)))
      .toList(),
  decode: (m) => m,
  encode: (m) => m,
  // Takes effect on the running player too, not just the next title.
  onAfterWrite: (_) => _onAudioOutputChanged(),
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
          onAfterWrite: (_) => _onAudioOutputChanged(),
        ),
);

Widget _audioLevelVolumeTile() => SettingSwitchTile(
  pref: SettingsService.audioLevelVolume,
  icon: Symbols.graphic_eq_rounded,
  title: t.videoSettings.audioLevelVolume,
  subtitle: t.videoSettings.audioLevelVolumeDescription,
  onAfterWrite: (_) => _pushLoudness(),
);

/// Gated on levelling, and that is a measurement rather than a shortcut: a
/// compressor with makeup gain and no loudness target ran a test excerpt up
/// to +5,4 dBFS while leaving the loudness range where it was.
Widget _audioReduceLoudSoundsTile() => SettingValueBuilder<bool>(
  pref: SettingsService.audioLevelVolume,
  builder: (context, levelling, _) => SettingSwitchTile(
    pref: SettingsService.audioReduceLoudSounds,
    icon: Symbols.compress_rounded,
    title: t.videoSettings.audioReduceLoudSounds,
    subtitle: t.videoSettings.audioReduceLoudSoundsDescription,
    enabled: levelling,
    onAfterWrite: (_) => _pushLoudness(),
  ),
);

/// Takes effect on the running player too, not just the next title. The
/// coordinator is the handle on the playback session currently on screen.
Future<void> _pushLoudness() async {
  final settings = SettingsService.instance;
  await AudioOutputCoordinator.current?.player.setAudioNormalization(
    AudioLoudness(
      levelVolume: settings.read(SettingsService.audioLevelVolume),
      reduceLoudSounds: settings.read(SettingsService.audioReduceLoudSounds),
    ),
  );
}

Widget _audioSyncOffsetTile() => SettingNumberTile(
  pref: SettingsService.audioSyncOffset,
  icon: Symbols.sync_rounded,
  title: t.videoSettings.audioSync,
  subtitleBuilder: (v) => '${(v / 1000).toStringAsFixed(1)}s · ${t.settings.audioSyncOffsetDescription}',
  labelText: t.videoSettings.audioSync,
  suffixText: 'ms',
  min: -5000,
  max: 5000,
);
