import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/device_display_capabilities.dart' show DisplayResolutionCap;
import '../../models/transcode_quality_preset.dart';
import '../../mpv/player/platform/player_android.dart';
import '../../services/audio_output_coordinator.dart';
import '../../services/audio_output_decision.dart';
import '../../services/companion_remote/companion_remote_host_controller.dart';
import '../../services/companion_remote/pleya_fly_receive.dart';
import '../../services/device_capabilities_service.dart';
import '../../services/device_capability_overrides.dart';
import '../../services/discord_rpc_service.dart';
import '../../services/keyboard_shortcuts_service.dart';
import '../../services/loudness/loudness_planner.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';
import '../../utils/quality_preset_labels.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'external_player_screen.dart';
import 'language_settings_screen.dart';
import 'mpv_config_screen.dart';
import 'settings_utils.dart';

part 'parts/playback_audio_rows.dart';
part 'parts/playback_rows.dart';

/// Rebuilds the capability source when Android switches player engines.
///
/// The decoder shape is derived from the engine baked into the platform probe,
/// so merely persisting `use_exoplayer` leaves Plex and Jellyfin planning
/// against the previous backend until restart. Configuration and detection are
/// one operation here so the settings callback cannot perform only half.
Future<void> refreshDeviceCapabilitiesForPlayerBackend(
  bool useExoPlayer, {
  DeviceCapabilitiesService Function(bool useExoPlayer)? configure,
  DeviceCapabilityOverrides? overrides,
}) async {
  final service = configure?.call(useExoPlayer) ?? DeviceCapabilitiesService.configure(useExoPlayer: useExoPlayer);
  await service.refresh(overrides: overrides ?? DeviceCapabilityOverrides.fromSettings());
  service.watchAudioRoute();
}

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  KeyboardShortcutsService? _keyboardService;

  @override
  void initState() {
    super.initState();
    if (KeyboardShortcutsService.isPlatformSupported()) {
      KeyboardShortcutsService.getInstance().then((s) {
        if (mounted) _keyboardService = s;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetector.isTV()) {
      return SettingsPage(title: Text(t.settings.videoPlayback), hideDescriptions: true, children: _phoneRows(context));
    }
    return SettingsPage(title: Text(t.settings.videoPlayback), children: _tvRows(context));
  }

  /// Afspelen off TV in the Studio series' order (`ios/04-afspelen-01..05`):
  /// Speler, Kwaliteit, Audio, Zoeken en timing, Gedrag, Automatisch
  /// overslaan. Every row the page had stays under the same condition; the
  /// MPV configuration moves to Kwaliteit, Maximaal volume to Audio and the
  /// chapter markers to Zoeken en timing, as the series places them.
  List<Widget> _phoneRows(BuildContext context) => [
    SettingsSectionHeader(t.settings.player),
    if (Platform.isAndroid) _playerBackendChoice(),
    if (PlatformDetector.supportsExternalPlayers()) _externalPlayerTile(),
    _hardwareDecodingTile(),
    if (PlatformDetector.supportsPictureInPicture()) _autoPipTile(),
    if (Platform.isAndroid) _matchContentFrameRateTile(),
    if (Platform.isWindows) _matchRefreshRateTile(),
    if (Platform.isWindows) _matchDynamicRangeTile(),
    _displaySwitchDelayTile(),
    _tunneledPlaybackTile(),

    SettingsSectionHeader(t.settingsStudio.quality),
    _defaultQualityTile(),
    _bufferSizeTile(),
    _displayMaxResolutionTile(),
    _dvConversionModeTile(),
    _mpvConfigTile(),

    SettingsSectionHeader(t.settings.audio),
    if (PlatformDetector.supportsAudioPassthrough()) _audioOutputModeTile(),
    if (PlatformDetector.supportsAudioPassthrough()) _audioPriorityChoice(),
    _audioLevelVolumeTile(),
    _audioReduceLoudSoundsTile(),
    _audioSyncOffsetTile(),
    _maxVolumeTile(),

    SettingsSectionHeader(t.settings.seekAndTiming),
    ..._seekTiles(),
    _chapterMarkersTile(),

    SettingsSectionHeader(t.settings.behavior),
    if (!PlatformDetector.isMobile(context)) _clickVideoTile(),
    ..._remoteAndPresenceTiles(context),
    _languageRow(),

    SettingsSectionHeader(t.settings.autoSkip),
    ..._autoSkipTiles(),
  ];

  /// Afspelen on TV in the series' groups (`tvos/03-afspelen-01..07`): Video,
  /// Audio, Besturing, Gedrag and Automatisch overslaan. Every row the TV page
  /// had stays under its own condition: the MPV configuration closes Video,
  /// Maximaal volume closes Audio, the chapter markers and the click on the
  /// video join the jumps under Besturing. Gedrag is not in the TV series; it
  /// keeps the remote, presence and language rows that exist on TV.
  List<Widget> _tvRows(BuildContext context) => [
    SettingsSectionHeader(t.settingsStudio.video),
    if (Platform.isAndroid) _playerBackendSelector(),
    if (PlatformDetector.supportsExternalPlayers()) _externalPlayerTile(),
    _hardwareDecodingTile(),
    if (PlatformDetector.supportsPictureInPicture()) _autoPipTile(),
    if (Platform.isAndroid) _matchContentFrameRateTile(),
    if (Platform.isWindows) _matchRefreshRateTile(),
    if (Platform.isWindows) _matchDynamicRangeTile(),
    _displaySwitchDelayTile(),
    _tunneledPlaybackTile(),
    _dvConversionModeTile(),
    _bufferSizeTile(),
    _defaultQualityTile(),
    _displayMaxResolutionTile(),
    _mpvConfigTile(),

    // These controls must retain the live loudness/passthrough behavior
    // from main; the re-baseline branch's extracted section predates it.
    SettingsSectionHeader(t.settings.audio),
    if (PlatformDetector.supportsAudioPassthrough()) _audioOutputModeTile(),
    if (PlatformDetector.supportsAudioPassthrough()) _audioPriorityTile(),
    _audioLevelVolumeTile(),
    _audioReduceLoudSoundsTile(),
    _audioSyncOffsetTile(),
    _maxVolumeTile(),

    SettingsSectionHeader(t.settingsStudio.controls),
    ..._seekTiles(),
    _chapterMarkersTile(),
    if (!PlatformDetector.isMobile(context)) _clickVideoTile(),

    SettingsSectionHeader(t.settings.behavior),
    ..._remoteAndPresenceTiles(context),
    // The two language switches moved to Instellingen ▸ Taal en ondertitels
    // with LANG1 (DEC-096 lid 9); this row is what is left of them here.
    _languageRow(),

    SettingsSectionHeader(t.settings.autoSkip),
    ..._autoSkipTiles(),
  ];
}
