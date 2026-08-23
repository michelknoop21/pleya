import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/device_display_capabilities.dart' show DisplayResolutionCap;
import '../../models/transcode_quality_preset.dart';
import '../../mpv/player/platform/player_android.dart';
import '../../utils/quality_preset_labels.dart';
import '../../services/companion_remote/companion_remote_host_controller.dart';
import '../../services/device_capabilities_service.dart';
import '../../services/device_capability_overrides.dart';
import '../../services/discord_rpc_service.dart';
import '../../services/keyboard_shortcuts_service.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'external_player_screen.dart';
import 'playback/audio_section.dart';
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
        _displayMaxResolutionTile(),

        SettingsSectionHeader(t.settings.subtitlesAndConfig),
        SettingNavigationTile(
          icon: Symbols.subtitles_rounded,
          title: t.settings.subtitleStyling,
          subtitle: t.settings.subtitleStylingDescription,
          destinationBuilder: (_) => const SubtitleStylingScreen(),
        ),
        _mpvConfigTile(),

        ...playbackAudioSection(),

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
        SettingSwitchTile(
          pref: SettingsService.rememberTrackSelections,
          icon: Symbols.bookmark_rounded,
          title: t.settings.rememberTrackSelections,
          subtitle: t.settings.rememberTrackSelectionsDescription,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: SettingsService.instance.listenable(SettingsService.rememberTrackSelections),
          builder: (_, remembers, _) => SettingSwitchTile(
            pref: SettingsService.writeSeriesLanguageToServer,
            icon: Symbols.cloud_upload_rounded,
            title: t.settings.writeSeriesLanguageToServer,
            subtitle: t.settings.writeSeriesLanguageToServerDescription,
            enabled: remembers,
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
        const SizedBox(height: 24),
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
    // The bandwidth meaning of the preset is the connection layer of
    // DeviceCapabilities. Its second role, deciding whether a downloaded copy
    // beats the server stream, stays where it is in playback_source_resolver.
    onAfterWrite: (_) => DeviceCapabilitiesService.instance.applyOverrides(DeviceCapabilityOverrides.fromSettings()),
  );

  /// The override the model needs on the display layer, in the shape the audio
  /// output tile already uses: the chosen value next to what was actually
  /// detected, so an override reads as an override.
  Widget _displayMaxResolutionTile() => SettingSelectionTile<DisplayResolutionCap, DisplayResolutionCap>(
    pref: SettingsService.displayMaxResolution,
    icon: Symbols.aspect_ratio_rounded,
    title: t.settings.displayMaxResolutionTitle,
    subtitleBuilder: _displayMaxResolutionSubtitle,
    options: DisplayResolutionCap.values
        .map(
          (c) => DialogOption(
            value: c,
            title: _displayCapLabel(c),
            subtitle: switch (c) {
              DisplayResolutionCap.auto => t.settings.displayMaxResolutionOptionDescriptions.auto,
              DisplayResolutionCap.hd1080 => t.settings.displayMaxResolutionOptionDescriptions.hd1080,
              DisplayResolutionCap.uhd2160 => t.settings.displayMaxResolutionOptionDescriptions.uhd2160,
            },
          ),
        )
        .toList(),
    decode: (c) => c,
    encode: (c) => c,
    onAfterWrite: (_) => DeviceCapabilitiesService.instance.applyOverrides(DeviceCapabilityOverrides.fromSettings()),
  );

  /// "1080p (detected: 3840x2160)" where the display could be read, plain
  /// "1080p" where it could not. Same form as `"Auto (now: Dolby Atmos)"` in
  /// the player's settings sheet.
  String _displayMaxResolutionSubtitle(DisplayResolutionCap cap) {
    final detected = DeviceCapabilitiesService.instance.detected.display;
    final width = detected.maxWidth.value;
    final height = detected.maxHeight.value;
    if (width == null || height == null) return _displayCapLabel(cap);
    return '${_displayCapLabel(cap)} · ${t.settings.displayMaxResolutionNow(resolution: '${width}x$height')}';
  }

  String _displayCapLabel(DisplayResolutionCap cap) => switch (cap) {
    DisplayResolutionCap.auto => t.settings.displayMaxResolutionOptions.auto,
    DisplayResolutionCap.hd1080 => t.settings.displayMaxResolutionOptions.hd1080,
    DisplayResolutionCap.uhd2160 => t.settings.displayMaxResolutionOptions.uhd2160,
  };

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
