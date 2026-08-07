import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// How the system is currently rendering audio, as reported by
/// `AVAudioSession.renderingMode` (iOS/tvOS 17.2+).
///
/// This is the system's own verdict, not a guess from codec or channel count —
/// [dolbyAtmos] means Atmos really is playing.
enum AppleRenderingMode {
  /// The route can't report a mode (or the OS predates 17.2).
  notApplicable,
  monoStereo,
  surround,
  spatialAudio,
  dolbyAudio,
  dolbyAtmos,
  unknown;

  static AppleRenderingMode parse(String? raw) {
    if (raw == null) return AppleRenderingMode.notApplicable;
    for (final mode in AppleRenderingMode.values) {
      if (mode.name == raw) return mode;
    }
    return AppleRenderingMode.unknown;
  }

  /// True once the system is doing something wider than plain stereo.
  bool get isImmersive => switch (this) {
    AppleRenderingMode.surround ||
    AppleRenderingMode.spatialAudio ||
    AppleRenderingMode.dolbyAudio ||
    AppleRenderingMode.dolbyAtmos => true,
    _ => false,
  };
}

/// A snapshot of the current Apple audio output route.
class AppleAudioRoute {
  /// Widest channel count the route will accept. Drives the choice between
  /// multichannel PCM and stereo: AirPods report 2 until the app opts into
  /// multichannel content, and some routes stay at 2 regardless.
  final int maximumOutputNumberOfChannels;

  /// Channels the session is actually running right now.
  final int outputNumberOfChannels;

  /// Whether the app's multichannel opt-in is currently in effect.
  final bool supportsMultichannelContent;

  /// Whether the route (AirPods, some AirPlay targets) can spatialize.
  final bool spatialAudioEnabled;

  /// `AVAudioSessionPort` raw value, e.g. `HDMI`, `BluetoothA2DP`, `AirPlay`.
  /// For display and logging only — classify with [isDigitalPassthroughPort],
  /// which the plugin derives from the real port constants.
  final String portType;
  final String portName;

  /// A wired digital output (HDMI, DisplayPort, line out, USB audio) that can
  /// carry a Dolby bitstream to something that decodes it.
  final bool isDigitalPassthroughPort;

  final AppleRenderingMode renderingMode;

  const AppleAudioRoute({
    this.maximumOutputNumberOfChannels = 2,
    this.outputNumberOfChannels = 2,
    this.supportsMultichannelContent = false,
    this.spatialAudioEnabled = false,
    this.portType = '',
    this.portName = '',
    this.isDigitalPassthroughPort = false,
    this.renderingMode = AppleRenderingMode.notApplicable,
  });

  /// Fallback used off Apple platforms and when the channel is unreachable:
  /// plain stereo, which is what every decision path degrades to safely.
  static const unknown = AppleAudioRoute();

  factory AppleAudioRoute.fromMap(Map<dynamic, dynamic> map) {
    return AppleAudioRoute(
      maximumOutputNumberOfChannels: (map['maximumOutputNumberOfChannels'] as num?)?.toInt() ?? 2,
      outputNumberOfChannels: (map['outputNumberOfChannels'] as num?)?.toInt() ?? 2,
      supportsMultichannelContent: map['supportsMultichannelContent'] as bool? ?? false,
      spatialAudioEnabled: map['spatialAudioEnabled'] as bool? ?? false,
      portType: map['portType'] as String? ?? '',
      portName: map['portName'] as String? ?? '',
      isDigitalPassthroughPort: map['isDigitalOutput'] as bool? ?? false,
      renderingMode: AppleRenderingMode.parse(map['renderingMode'] as String?),
    );
  }

  /// Whether the route will take more than stereo. False here is what forces
  /// the PCM path down to stereo instead of asking mpv for 5.1/7.1.
  bool get isMultichannelCapable => maximumOutputNumberOfChannels > 2;

  @override
  String toString() =>
      'AppleAudioRoute(port: $portType/$portName, max: $maximumOutputNumberOfChannels, '
      'out: $outputNumberOfChannels, multichannel: $supportsMultichannelContent, '
      'spatial: $spatialAudioEnabled, rendering: ${renderingMode.name})';
}

/// Reads and configures the Apple audio session so playback can negotiate more
/// than stereo.
///
/// The multichannel opt-in has to be in effect *before* mpv initialises its
/// audio output — `ao_audiounit` samples the route once at init and hard
/// downmixes when it sees two channels. [configure] is therefore called ahead
/// of `loadfile`, not after.
///
/// iOS and tvOS only (Flutter reports Apple TV as iOS). Everywhere else the
/// methods no-op and return [AppleAudioRoute.unknown].
class AppleAudioSessionService {
  AppleAudioSessionService._();

  static final AppleAudioSessionService instance = AppleAudioSessionService._();

  static const MethodChannel _channel = MethodChannel('com.pleya/audio_session');
  static const EventChannel _events = EventChannel('com.pleya/audio_session/events');

  /// The native plugin ships on iOS and tvOS only.
  static bool get isAvailable => Platform.isIOS;

  AppleAudioRoute _lastKnown = AppleAudioRoute.unknown;

  /// Most recent snapshot, without a round trip. Starts at
  /// [AppleAudioRoute.unknown] until the first [configure] or [snapshot].
  AppleAudioRoute get lastKnown => _lastKnown;

  Stream<AppleAudioRoute>? _routeChanges;

  /// Route changes, spatial-capability changes and rendering-mode changes,
  /// each delivered as a full snapshot. Broadcast, so several widgets can
  /// listen without racing over a single subscription.
  Stream<AppleAudioRoute> get routeChanges {
    if (!isAvailable) return const Stream<AppleAudioRoute>.empty();
    return _routeChanges ??= _events.receiveBroadcastStream().map((event) {
      final route = AppleAudioRoute.fromMap(event as Map<dynamic, dynamic>);
      _lastKnown = route;
      return route;
    }).asBroadcastStream();
  }

  /// Applies the playback session (`.playback` + `.moviePlayback`) and the
  /// multichannel opt-in, then returns the resulting route.
  Future<AppleAudioRoute> configure({bool multichannel = true}) async {
    return _invoke('configure', {'multichannel': multichannel});
  }

  /// Reads the route without changing the session.
  Future<AppleAudioRoute> snapshot() => _invoke('snapshot', null);

  bool _measured = false;

  /// Logs the route with the multichannel opt-in off and then on, once per app
  /// run, and leaves it on.
  ///
  /// This is the measurement the multichannel-PCM path stands or falls on:
  /// Apple documents that the opt-in *allows* a wider route, not that any given
  /// route takes it, and Bluetooth outputs have been reported to stay at two
  /// channels either way. Reading it from the device beats guessing, and the
  /// answer belongs in bug reports about "why is this only stereo".
  ///
  /// Runs before playback starts. Flipping the flag mid-stream would reload the
  /// audio output, so this must not be called again later.
  Future<void> logChannelNegotiation() async {
    if (!isAvailable || _measured) return;
    _measured = true;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('measure');
      if (result == null) return;
      final before = AppleAudioRoute.fromMap(result['before'] as Map<dynamic, dynamic>? ?? const {});
      final after = AppleAudioRoute.fromMap(result['after'] as Map<dynamic, dynamic>? ?? const {});
      _lastKnown = after;
      appLogger.i('Channel negotiation, multichannel off: $before');
      appLogger.i('Channel negotiation, multichannel on : $after');
      appLogger.i(
        'Multichannel PCM is ${after.isMultichannelCapable ? "available" : "unavailable"} '
        'on this route (max ${before.maximumOutputNumberOfChannels} → ${after.maximumOutputNumberOfChannels})',
      );
    } on PlatformException catch (e) {
      appLogger.w('Channel negotiation probe failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      // Older host build without the plugin.
    }
  }

  Future<AppleAudioRoute> _invoke(String method, Map<String, dynamic>? args) async {
    if (!isAvailable) return AppleAudioRoute.unknown;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(method, args);
      if (result == null) return _lastKnown;
      _lastKnown = AppleAudioRoute.fromMap(result);
      return _lastKnown;
    } on PlatformException catch (e) {
      appLogger.w('Audio session $method failed: ${e.code} ${e.message}');
      return _lastKnown;
    } on MissingPluginException {
      // Older host build without the plugin — stay on the stereo-safe default.
      return AppleAudioRoute.unknown;
    }
  }
}
