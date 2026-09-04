import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../models/transcode_quality_preset.dart';
import '../../mpv/models.dart' show AudioLoudness;
import '../../mpv/player/platform/player_android.dart';
import '../../services/audio_output_coordinator.dart';
import '../../services/audio_output_decision.dart';
import '../../utils/quality_preset_labels.dart';
import '../../services/companion_remote/companion_remote_host_controller.dart';
import '../../services/discord_rpc_service.dart';
import '../../services/keyboard_shortcuts_service.dart';
import '../../media/pleya_profile_language_preferences.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/profile_language_switch_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'external_player_screen.dart';
import 'mpv_config_screen.dart';
import 'settings_utils.dart';
import 'subtitle_styling_screen.dart';

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
    final isMobile = PlatformDetector.isMobile(context);

    return SettingsPage(
      title: Text(t.settings.videoPlayback),
      children: [
        SettingsSectionHeader(t.settings.player),
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

        SettingsSectionHeader(t.settings.subtitlesAndConfig),
        SettingNavigationTile(
          icon: Symbols.subtitles_rounded,
          title: t.settings.subtitleStyling,
          subtitle: t.settings.subtitleStylingDescription,
          destinationBuilder: (_) => const SubtitleStylingScreen(),
        ),
        _mpvConfigTile(),

        // These three used to live only inside the player's settings sheet,
        // which meant they could not be set before playback started.
        SettingsSectionHeader(t.settings.audio),
        if (PlatformDetector.supportsAudioPassthrough()) _audioOutputModeTile(),
        if (PlatformDetector.supportsAudioPassthrough()) _audioPriorityTile(),
        _audioLevelVolumeTile(),
        _audioReduceLoudSoundsTile(),
        _audioSyncOffsetTile(),

        SettingsSectionHeader(t.settings.seekAndTiming),
        SettingNumberTile(
          pref: SettingsService.seekTimeSmall,
          icon: Symbols.replay_10_rounded,
          title: t.settings.smallSkipDuration,
          subtitleBuilder: (v) => t.settings.secondsUnit(seconds: v.toString()),
          labelText: t.settings.secondsLabel,
          suffixText: t.settings.secondsShort,
          min: 1,
          max: 120,
          onAfterWrite: (_) => _keyboardService?.refreshFromStorage(),
        ),
        SettingNumberTile(
          pref: SettingsService.seekTimeLarge,
          icon: Symbols.replay_30_rounded,
          title: t.settings.largeSkipDuration,
          subtitleBuilder: (v) => t.settings.secondsUnit(seconds: v.toString()),
          labelText: t.settings.secondsLabel,
          suffixText: t.settings.secondsShort,
          min: 1,
          max: 120,
          onAfterWrite: (_) => _keyboardService?.refreshFromStorage(),
        ),
        SettingNumberTile(
          pref: SettingsService.rewindOnResume,
          icon: Symbols.replay_rounded,
          title: t.settings.rewindOnResume,
          subtitleBuilder: (v) => t.settings.secondsUnit(seconds: v.toString()),
          labelText: t.settings.secondsLabel,
          suffixText: t.settings.secondsShort,
          min: 0,
          max: 10,
        ),
        SettingNumberTile(
          pref: SettingsService.sleepTimerDuration,
          icon: Symbols.bedtime_rounded,
          title: t.settings.defaultSleepTimer,
          subtitleBuilder: (v) => t.settings.minutesUnit(minutes: v.toString()),
          labelText: t.settings.minutesLabel,
          suffixText: t.settings.minutesShort,
          min: 5,
          max: 240,
        ),
        SettingNumberTile(
          pref: SettingsService.maxVolume,
          icon: Symbols.volume_up_rounded,
          title: t.settings.maxVolume,
          subtitleBuilder: (v) => t.settings.maxVolumePercent(percent: v.toString()),
          labelText: t.settings.maxVolumeDescription,
          suffixText: '%',
          min: 100,
          max: 300,
        ),

        SettingsSectionHeader(t.settings.behavior),
        if (DiscordRPCService.isAvailable)
          SettingSwitchTile(
            pref: SettingsService.enableDiscordRPC,
            icon: Symbols.chat_rounded,
            title: t.settings.discordRichPresence,
            subtitle: t.settings.discordRichPresenceDescription,
            onAfterWrite: (v) => DiscordRPCService.instance.setEnabled(v),
          ),
        if (PlatformDetector.shouldActAsRemoteHost(context))
          SettingSwitchTile(
            pref: SettingsService.enableCompanionRemoteServer,
            icon: Symbols.phone_android_rounded,
            title: t.settings.companionRemoteServer,
            subtitle: t.settings.companionRemoteServerDescription,
            onAfterWrite: (v) => applyCompanionRemoteServerSetting(context, v),
          ),
        // Backed by the Pleya profile, not by a device-wide pref: the owner
        // moved with DEC-096 lid 5. These two rows are due to move to
        // Instellingen ▸ Taal en ondertitels, which lid 9 makes the single
        // place this is managed; the storage change lands first so the move is
        // a pure relocation and never a second owner.
        ValueListenableBuilder<Map<String, PleyaProfileLanguagePreferences>>(
          valueListenable: SettingsService.instance.listenable(SettingsService.pleyaProfileLanguagePreferences),
          builder: (_, _, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileLanguageSwitchTile(
                icon: Symbols.bookmark_rounded,
                title: t.settings.rememberTrackSelections,
                subtitle: t.settings.rememberTrackSelectionsDescription,
                selector: (preferences) => preferences.rememberPerSeries,
                apply: (current, value) => current.copyWith(rememberPerSeries: value),
              ),
              ProfileLanguageSwitchTile(
                icon: Symbols.cloud_upload_rounded,
                title: t.settings.writeSeriesLanguageToServer,
                subtitle: t.settings.writeSeriesLanguageToServerDescription,
                selector: (preferences) => preferences.mirrorToPlex,
                apply: (current, value) => current.copyWith(mirrorToPlex: value),
              ),
            ],
          ),
        ),
        SettingSwitchTile(
          pref: SettingsService.showChapterMarkersOnTimeline,
          icon: Symbols.bookmarks_rounded,
          title: t.settings.showChapterMarkersOnTimeline,
          subtitle: t.settings.showChapterMarkersOnTimelineDescription,
        ),
        if (!isMobile)
          SettingSwitchTile(
            pref: SettingsService.clickVideoTogglesPlayback,
            icon: Symbols.play_pause_rounded,
            title: t.settings.clickVideoTogglesPlayback,
            subtitle: t.settings.clickVideoTogglesPlaybackDescription,
          ),

        SettingsSectionHeader(t.settings.autoSkip),
        SettingSwitchTile(
          pref: SettingsService.autoSkipIntro,
          icon: Symbols.fast_forward_rounded,
          title: t.settings.autoSkipIntro,
          subtitle: t.settings.autoSkipIntroDescription,
        ),
        SettingSwitchTile(
          pref: SettingsService.autoSkipCredits,
          icon: Symbols.skip_next_rounded,
          title: t.settings.autoSkipCredits,
          subtitle: t.settings.autoSkipCreditsDescription,
        ),
        SettingSwitchTile(
          pref: SettingsService.forceSkipMarkerFallback,
          icon: Symbols.tune_rounded,
          title: t.settings.forceSkipMarkerFallback,
          subtitle: t.settings.forceSkipMarkerFallbackDescription,
        ),
        SettingNumberTile(
          pref: SettingsService.autoSkipDelay,
          icon: Symbols.timer_rounded,
          title: t.settings.autoSkipDelay,
          subtitleBuilder: (v) => t.settings.autoSkipDelayDescription(seconds: v.toString()),
          labelText: t.settings.secondsLabel,
          suffixText: t.settings.secondsShort,
          min: 1,
          max: 30,
        ),
        SettingRegexTile(
          pref: SettingsService.introPattern,
          icon: Symbols.match_case_rounded,
          title: t.settings.introPattern,
          subtitle: t.settings.introPatternDescription,
          defaultValue: SettingsService.defaultIntroPattern,
        ),
        SettingRegexTile(
          pref: SettingsService.creditsPattern,
          icon: Symbols.match_case_rounded,
          title: t.settings.creditsPattern,
          subtitle: t.settings.creditsPatternDescription,
          defaultValue: SettingsService.defaultCreditsPattern,
        ),
      ],
    );
  }

  Widget _playerBackendSelector() => SettingSegmentedTile<bool, bool>(
    pref: SettingsService.useExoPlayer,
    icon: Symbols.play_circle_rounded,
    title: t.settings.playerBackend,
    segments: [
      ButtonSegment(value: true, label: Text(t.settings.exoPlayer)),
      ButtonSegment(value: false, label: Text(t.settings.mpv)),
    ],
    decode: (s) => s,
    encode: (s) => s,
  );

  Widget _externalPlayerTile() => SettingsBuilder(
    prefs: [SettingsService.useExternalPlayer, SettingsService.selectedExternalPlayer],
    builder: (context) {
      final svc = SettingsService.instance;
      final useExt = svc.read(SettingsService.useExternalPlayer);
      final player = svc.read(SettingsService.selectedExternalPlayer);
      return SettingNavigationTile(
        icon: Symbols.open_in_new_rounded,
        title: t.externalPlayer.title,
        subtitle: useExt
            ? (player.id == 'system_default' ? t.externalPlayer.systemDefault : player.name)
            : t.externalPlayer.off,
        destinationBuilder: (_) => const ExternalPlayerScreen(),
      );
    },
  );

  Widget _hardwareDecodingTile() => SettingSwitchTile(
    pref: SettingsService.enableHardwareDecoding,
    icon: Symbols.hardware_rounded,
    title: t.settings.hardwareDecoding,
    subtitle: t.settings.hardwareDecodingDescription,
  );

  Widget _autoPipTile() => SettingSwitchTile(
    pref: SettingsService.autoPip,
    icon: Symbols.picture_in_picture_alt_rounded,
    title: t.settings.autoPip,
    subtitle: t.settings.autoPipDescription,
  );

  Widget _matchContentFrameRateTile() => SettingSwitchTile(
    pref: SettingsService.matchContentFrameRate,
    icon: Symbols.display_settings_rounded,
    title: t.settings.matchContentFrameRate,
    subtitle: t.settings.matchContentFrameRateDescription,
  );

  Widget _matchRefreshRateTile() => SettingSwitchTile(
    pref: SettingsService.matchRefreshRate,
    icon: Symbols.display_settings_rounded,
    title: t.settings.matchRefreshRate,
    subtitle: t.settings.matchRefreshRateDescription,
  );

  Widget _matchDynamicRangeTile() => SettingSwitchTile(
    pref: SettingsService.matchDynamicRange,
    icon: Symbols.hdr_on_rounded,
    title: t.settings.matchDynamicRange,
    subtitle: t.settings.matchDynamicRangeDescription,
  );

  Widget _displaySwitchDelayTile() => SettingsBuilder(
    prefs: const [
      SettingsService.matchRefreshRate,
      SettingsService.matchDynamicRange,
      SettingsService.matchContentFrameRate,
    ],
    builder: (context) {
      final svc = SettingsService.instance;
      final shouldShow =
          PlatformDetector.isAppleTV() ||
          (Platform.isWindows &&
              (svc.read(SettingsService.matchRefreshRate) || svc.read(SettingsService.matchDynamicRange))) ||
          (Platform.isAndroid && svc.read(SettingsService.matchContentFrameRate));
      if (!shouldShow) return const SizedBox.shrink();
      return SettingNumberTile(
        pref: SettingsService.displaySwitchDelay,
        icon: Symbols.timer_rounded,
        title: t.settings.displaySwitchDelay,
        subtitleBuilder: (v) => t.settings.secondsUnit(seconds: v.toString()),
        labelText: t.settings.secondsLabel,
        suffixText: t.settings.secondsShort,
        min: 0,
        max: 10,
      );
    },
  );

  Widget _tunneledPlaybackTile() => SettingValueBuilder<bool>(
    pref: SettingsService.useExoPlayer,
    builder: (_, useExo, _) {
      if (!Platform.isAndroid || !useExo) return const SizedBox.shrink();
      return SettingSwitchTile(
        pref: SettingsService.tunneledPlayback,
        icon: Symbols.tv_options_input_settings_rounded,
        title: t.settings.tunneledPlayback,
        subtitle: t.settings.tunneledPlaybackDescription,
      );
    },
  );

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

  Widget _dvConversionModeTile() => SettingValueBuilder<bool>(
    pref: SettingsService.useExoPlayer,
    builder: (_, useExo, _) {
      if (!Platform.isAndroid || !useExo) return const SizedBox.shrink();
      return SettingSelectionTile<DvConversionModePreference, DvConversionModePreference>(
        pref: SettingsService.dvConversionMode,
        icon: Symbols.hdr_strong_rounded,
        title: t.settings.dvConversionMode,
        subtitleBuilder: (mode) => '${_dvConversionModeLabel(mode)} · ${t.settings.dvConversionModeDescription}',
        options: DvConversionModePreference.values
            .map((m) => DialogOption(value: m, title: _dvConversionModeLabel(m)))
            .toList(),
        decode: (m) => m,
        encode: (m) => m,
      );
    },
  );

  String _dvConversionModeLabel(DvConversionModePreference mode) => switch (mode) {
    DvConversionModePreference.auto => t.settings.dvConversionAuto,
    DvConversionModePreference.disabled => t.settings.dvConversionNative,
    DvConversionModePreference.dv81 => t.settings.dvConversionDv81,
    DvConversionModePreference.hevcStrip => t.settings.dvConversionHevcStrip,
  };

  Widget _bufferSizeTile() {
    final bufferOptions = const [0, 64, 128, 256, 512, 1024];
    return SettingSelectionTile<int, int>(
      pref: SettingsService.bufferSize,
      icon: Symbols.memory_rounded,
      title: t.settings.bufferSize,
      subtitleBuilder: (v) => v == 0 ? t.settings.bufferSizeAuto : t.settings.bufferSizeMB(size: v.toString()),
      options: bufferOptions
          .map((s) => DialogOption(value: s, title: s == 0 ? t.settings.bufferSizeAuto : '${s}MB'))
          .toList(),
      decode: (s) => s,
      encode: (s) => s,
      onAfterWrite: (value) async {
        if (Platform.isAndroid && value > 0) {
          final heapMB = await PlayerAndroid.getHeapSize();
          if (heapMB > 0 && value > heapMB ~/ 4 && mounted) {
            showAppSnackBar(context, t.settings.bufferSizeWarning(heap: heapMB.toString(), size: value.toString()));
          }
        }
      },
    );
  }

  Widget _defaultQualityTile() => SettingSelectionTile<TranscodeQualityPreset, TranscodeQualityPreset>(
    pref: SettingsService.defaultQualityPreset,
    icon: Symbols.high_quality_rounded,
    title: t.settings.defaultQualityTitle,
    subtitleBuilder: qualityPresetLabel,
    options: TranscodeQualityPreset.displayOrder
        .map((p) => DialogOption(value: p, title: qualityPresetLabel(p)))
        .toList(),
    decode: (p) => p,
    encode: (p) => p,
  );

  Widget _mpvConfigTile() => SettingValueBuilder<bool>(
    pref: SettingsService.useExoPlayer,
    builder: (_, useExo, _) {
      if (Platform.isAndroid && useExo) return const SizedBox.shrink();
      return SettingNavigationTile(
        icon: Symbols.tune_rounded,
        title: t.mpvConfig.title,
        subtitle: t.mpvConfig.description,
        destinationBuilder: (_) => const MpvConfigScreen(),
      );
    },
  );
}
