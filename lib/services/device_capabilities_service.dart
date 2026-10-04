import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../media/device_capabilities.dart';
import '../media/device_capability_baseline.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import 'apple_audio_session_service.dart';
import 'audio_output_decision.dart';
import 'device_capability_overrides.dart';

/// The platform facts detection branches on, gathered in one injectable place.
///
/// `DevicePerformance` and `TvDetectionService` both reach for a
/// `static const MethodChannel` and a bare `Platform.is…`, which is why neither
/// has a test on its detection. Everything this service needs about the host
/// arrives through this object instead, so a test can hand it an Apple TV or an
/// Android box without one being present.
@immutable
class DevicePlatformProbe {
  const DevicePlatformProbe({
    required this.engine,
    required this.isWindows,
    required this.hasAppleAudioRoute,
    required this.supportsAudioPassthrough,
  });

  /// Reads the real host. [useExoPlayer] comes from
  /// `SettingsService.useExoPlayer`, which is why it is a parameter: the
  /// player engine is an app setting, not a platform fact, and treating it as
  /// one is the mistake the old Jellyfin profile comment made.
  factory DevicePlatformProbe.host({required bool useExoPlayer}) {
    return DevicePlatformProbe(
      engine: Platform.isAndroid && useExoPlayer ? PlayerEngine.exoPlayer : PlayerEngine.mpv,
      isWindows: Platform.isWindows,
      hasAppleAudioRoute: AppleAudioSessionService.isAvailable,
      supportsAudioPassthrough: PlatformDetector.supportsAudioPassthrough(),
    );
  }

  final PlayerEngine engine;

  /// The only platform that enumerates real display modes today.
  final bool isWindows;

  /// iOS and tvOS, where `AppleAudioRoute` can answer the audio layer.
  final bool hasAppleAudioRoute;

  final bool supportsAudioPassthrough;
}

/// Holds the current `DeviceCapabilities` snapshot and refreshes it.
///
/// Deliberately not a `ChangeNotifier` and not in the MultiProvider: no screen
/// rebuilds on this. It is also deliberately not a bare mutable global. The
/// snapshot changes when the audio route changes, so a caller that grabbed a
/// `DeviceCapabilities` reference at startup would keep planning against a
/// route the user has since unplugged. Read [current] at the moment you need
/// it, and hand the result to a builder as a parameter.
class DeviceCapabilitiesService {
  DeviceCapabilitiesService({
    required this.probe,
    MethodChannel? displayChannel,
    Future<AppleAudioRoute> Function()? readAppleRoute,
  }) : _displayChannel = displayChannel ?? const MethodChannel(_displayChannelName),
       _readAppleRoute = readAppleRoute ?? _liveAppleRoute;

  /// Same channel the mpv player and `DisplayModeService` use.
  static const String _displayChannelName = 'com.pleya/mpv_player';

  static DeviceCapabilitiesService? _instance;

  /// The app-wide snapshot. [configure] fills it during boot; until then this
  /// reports every layer unknown, which every consumer reads as "keep doing
  /// what you did before".
  static DeviceCapabilitiesService get instance =>
      _instance ??= DeviceCapabilitiesService(probe: DevicePlatformProbe.host(useExoPlayer: true));

  /// Installs the app-wide instance with the real host probe. Called once from
  /// the boot sequence, before the first playback.
  static DeviceCapabilitiesService configure({required bool useExoPlayer}) {
    _instance?.dispose();
    return _instance = DeviceCapabilitiesService(probe: DevicePlatformProbe.host(useExoPlayer: useExoPlayer));
  }

  @visibleForTesting
  static void debugSetInstance(DeviceCapabilitiesService? service) {
    _instance?.dispose();
    _instance = service;
  }

  /// Convenience for call sites that only want the snapshot.
  static DeviceCapabilities get currentSnapshot => _instance?.current ?? DeviceCapabilities.unknown;

  /// The host this snapshot describes.
  final DevicePlatformProbe probe;
  final MethodChannel _displayChannel;
  final Future<AppleAudioRoute> Function() _readAppleRoute;

  StreamSubscription<AppleAudioRoute>? _routeSubscription;

  DeviceCapabilities _detected = DeviceCapabilities.unknown;
  DeviceCapabilityOverrides _overrides = DeviceCapabilityOverrides.defaults;
  DeviceCapabilities _current = DeviceCapabilities.unknown;

  /// Detection with the user's overrides applied. This is what a profile
  /// builder should be handed.
  DeviceCapabilities get current => _current;

  /// Detection on its own, before any override. Kept so the settings UI can
  /// show what the device said next to what the user asked for.
  DeviceCapabilities get detected => _detected;

  /// What this platform can bitstream at all. Forcing passthrough asserts this
  /// list and cannot conjure a codec the platform has no path for.
  Set<String> get platformBitstreamCodecs {
    if (probe.hasAppleAudioRoute) return appleBitstreamCodecs;
    return probe.supportsAudioPassthrough ? desktopBitstreamCodecs : const <String>{};
  }

  /// Re-runs every detection source and replaces [current].
  Future<DeviceCapabilities> refresh({DeviceCapabilityOverrides? overrides}) async {
    if (overrides != null) _overrides = overrides;
    final display = await _detectDisplay();
    final audio = await _detectAudio();
    _detected = _detected.copyWith(decoder: _detectDecoder(), display: display, audio: audio);
    return _republish();
  }

  /// Re-applies the overrides without touching the hardware. What a settings
  /// screen calls after a write.
  DeviceCapabilities applyOverrides(DeviceCapabilityOverrides overrides) {
    _overrides = overrides;
    return _republish();
  }

  DeviceCapabilities _republish() {
    _current = applyCapabilityOverrides(_detected, _overrides, platformBitstreamCodecs: platformBitstreamCodecs);
    return _current;
  }

  /// Follows the audio route for the lifetime of the app. Unplugging an AV
  /// receiver changes what this device can carry, and a snapshot taken at boot
  /// would not know.
  void watchAudioRoute() {
    if (!probe.hasAppleAudioRoute || _routeSubscription != null) return;
    _routeSubscription = AppleAudioSessionService.instance.routeChanges.listen((route) {
      _detected = _detected.copyWith(audio: _audioFromAppleRoute(route));
      _republish();
    });
  }

  Future<void> dispose() async {
    await _routeSubscription?.cancel();
    _routeSubscription = null;
  }

  // -- Decoder ---------------------------------------------------------------

  /// Inferred, never detected, and that is the honest answer.
  ///
  /// Nothing in this app asks mpv for `decoder-list`, `audio-device-list` or
  /// `hwdec-interop`; `hwdec-current` is read back, but only to fill the
  /// performance overlay. Publishing this as `detected` would let the PS-6
  /// planner treat a belief as a measurement. `inferred` says what it is and
  /// marks where the next win sits.
  ///
  /// ExoPlayer gets the same list as mpv in PS-5. Its real set is per-device
  /// and comes from `MediaCodecList`, which nobody queries yet; narrowing or
  /// widening it on a guess would change Android playback with no evidence
  /// behind it. What the layer does carry is [PlayerEngine], so the difference
  /// has a place to land the moment there is a source for it.
  DeviceDecoderCapabilities _detectDecoder() {
    return DeviceDecoderCapabilities(
      engine: probe.engine,
      videoCodecs: const Capability.inferred(kInferredVideoCodecs),
      audioCodecs: probe.engine == PlayerEngine.mpv
          ? const Capability.inferred(kInferredAudioCodecs)
          : const Capability.inferred(kInferredAudioCodecsExoPlayer),
      containers: const Capability.inferred(kInferredContainers),
    );
  }

  // -- Display ---------------------------------------------------------------

  Future<DeviceDisplayCapabilities> _detectDisplay() async {
    if (!probe.isWindows) return DeviceDisplayCapabilities.unknown;
    try {
      final current = await _displayChannel.invokeMapMethod<String, dynamic>('getCurrentDisplayMode');
      final modes = await _displayChannel.invokeListMethod<Map<dynamic, dynamic>>('getDisplayModes');
      if (current == null || modes == null || modes.isEmpty) return DeviceDisplayCapabilities.unknown;

      final width = (current['width'] as num?)?.toInt();
      final height = (current['height'] as num?)?.toInt();
      var maxWidth = width ?? 0;
      var maxHeight = height ?? 0;
      final rates = <int>{};
      for (final mode in modes) {
        final modeWidth = (mode['width'] as num?)?.toInt() ?? 0;
        final modeHeight = (mode['height'] as num?)?.toInt() ?? 0;
        final rate = (mode['refreshRate'] as num?)?.toInt();
        if (modeWidth * modeHeight > maxWidth * maxHeight) {
          maxWidth = modeWidth;
          maxHeight = modeHeight;
        }
        if (rate != null && modeWidth == width && modeHeight == height) rates.add(rate);
      }

      return DeviceDisplayCapabilities(
        maxWidth: maxWidth > 0 ? Capability.detected(maxWidth) : const Capability<int>.unknown(),
        maxHeight: maxHeight > 0 ? Capability.detected(maxHeight) : const Capability<int>.unknown(),
        refreshRatesHz: rates.isEmpty ? const Capability<Set<int>>.unknown() : Capability.detected(rates),
        hdrTransfers: await _detectWindowsHdr(),
      );
    } on PlatformException catch (e) {
      appLogger.w('Display capability probe failed: ${e.code} ${e.message}');
      return DeviceDisplayCapabilities.unknown;
    } on MissingPluginException {
      return DeviceDisplayCapabilities.unknown;
    }
  }

  /// Windows is the only platform that can answer this. It asks the OS about
  /// the panel, which is a different question from "did we hand mpv
  /// `hdr-enabled`" — that one says what the player was told to do, and a
  /// backend acting on it would direct-play HDR to an SDR screen.
  Future<Capability<Set<String>>> _detectWindowsHdr() async {
    final supported = await _displayChannel.invokeMethod<bool>('isHDRSupported');
    if (supported == null) return const Capability<Set<String>>.unknown();
    return supported ? const Capability.detected({'sdr', 'hdr10'}) : const Capability.detected({'sdr'});
  }

  // -- Audio -----------------------------------------------------------------

  Future<DeviceAudioCapabilities> _detectAudio() async {
    if (probe.hasAppleAudioRoute) return _audioFromAppleRoute(await _readAppleRoute());
    return DeviceAudioCapabilities(
      maxChannels: const Capability<int>.unknown(),
      passthroughCodecs: probe.supportsAudioPassthrough
          ? const Capability.inferred(desktopBitstreamCodecs)
          : const Capability.inferred(<String>{}),
    );
  }

  /// Turns a route reading into the audio layer.
  ///
  /// The channel count is [CapabilityConfidence.unknown] rather than two on a
  /// wired digital port, because that is what the measurement says: an Apple TV
  /// 4K on an AV receiver reported `maximumOutputNumberOfChannels: 2` while the
  /// same session told mpv it had eight. `AppleAudioRoute.isMultichannelCapable`
  /// documents that. Publishing the two would tell a backend to downmix.
  static DeviceAudioCapabilities _audioFromAppleRoute(AppleAudioRoute route) {
    if (route.portType.isEmpty) return DeviceAudioCapabilities.unknown;

    final Capability<int> channels;
    if (route.maximumOutputNumberOfChannels > 2) {
      channels = Capability.detected(route.maximumOutputNumberOfChannels);
    } else if (route.isDigitalPassthroughPort) {
      channels = const Capability<int>.unknown();
    } else {
      channels = Capability.detected(route.maximumOutputNumberOfChannels);
    }

    return DeviceAudioCapabilities(
      maxChannels: channels,
      passthroughCodecs: route.isDigitalPassthroughPort
          ? const Capability.detected(appleBitstreamCodecs)
          : const Capability.detected(<String>{}),
    );
  }

  static Future<AppleAudioRoute> _liveAppleRoute() {
    final service = AppleAudioSessionService.instance;
    final known = service.lastKnown;
    if (known.portType.isNotEmpty) return Future<AppleAudioRoute>.value(known);
    return service.snapshot();
  }
}
