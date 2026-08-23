import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/device_capabilities.dart';
import 'package:pleya/media/device_capability_baseline.dart';
import 'package:pleya/services/apple_audio_session_service.dart';
import 'package:pleya/services/audio_output_decision.dart';
import 'package:pleya/services/device_capabilities_service.dart';

/// Detection with the platform handed in instead of read from `Platform.is…`.
///
/// `DevicePerformance` and `TvDetectionService` reach for a
/// `static const MethodChannel`, which is exactly why neither has a test on its
/// own detection. This service takes the channel and the probe as arguments, so
/// an Apple TV and a Windows box can both be pretended into existence here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const displayChannel = MethodChannel('test_device_display');

  void setHandler(Future<Object?> Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(displayChannel, handler);
  }

  DeviceCapabilitiesService serviceFor({
    PlayerEngine engine = PlayerEngine.mpv,
    bool isWindows = false,
    bool hasAppleAudioRoute = false,
    bool supportsAudioPassthrough = false,
    AppleAudioRoute route = AppleAudioRoute.unknown,
  }) {
    return DeviceCapabilitiesService(
      probe: DevicePlatformProbe(
        engine: engine,
        isWindows: isWindows,
        hasAppleAudioRoute: hasAppleAudioRoute,
        supportsAudioPassthrough: supportsAudioPassthrough,
      ),
      displayChannel: displayChannel,
      readAppleRoute: () async => route,
    );
  }

  tearDown(() => setHandler(null));

  group('decoder', () {
    test('is inferred and never detected, because nothing asks mpv', () async {
      final caps = await serviceFor().refresh();

      expect(caps.decoder.videoCodecs.confidence, CapabilityConfidence.inferred);
      expect(caps.decoder.videoCodecs.value, kInferredVideoCodecs);
      expect(caps.decoder.containers.value, kInferredContainers);
      expect(caps.decoder.hasCodecShapeLimits, isFalse);
    });

    test('reads the player engine, not the platform', () async {
      final exo = await serviceFor(engine: PlayerEngine.exoPlayer).refresh();
      final mpv = await serviceFor().refresh();

      expect(exo.decoder.engine, PlayerEngine.exoPlayer);
      expect(mpv.decoder.engine, PlayerEngine.mpv);
    });
  });

  group('display', () {
    test('Windows reports real modes as detected', () async {
      setHandler((call) async {
        return switch (call.method) {
          'getCurrentDisplayMode' => {'width': 1920, 'height': 1080, 'refreshRate': 60},
          'getDisplayModes' => [
            {'width': 1920, 'height': 1080, 'refreshRate': 60},
            {'width': 1920, 'height': 1080, 'refreshRate': 120},
            {'width': 3840, 'height': 2160, 'refreshRate': 60},
          ],
          'isHDRSupported' => true,
          _ => null,
        };
      });

      final caps = await serviceFor(isWindows: true).refresh();

      expect(caps.display.maxWidth.value, 3840);
      expect(caps.display.maxHeight.value, 2160);
      expect(caps.display.maxWidth.confidence, CapabilityConfidence.detected);
      expect(caps.display.refreshRatesHz.value, {60, 120});
      expect(caps.display.hdrTransfers.value, {'sdr', 'hdr10'});
      expect(caps.display.hasResolutionCeiling, isTrue);
    });

    test('Windows without HDR support says so, and that is still a measurement', () async {
      setHandler((call) async {
        return switch (call.method) {
          'getCurrentDisplayMode' => {'width': 1920, 'height': 1080, 'refreshRate': 60},
          'getDisplayModes' => [
            {'width': 1920, 'height': 1080, 'refreshRate': 60},
          ],
          'isHDRSupported' => false,
          _ => null,
        };
      });

      final caps = await serviceFor(isWindows: true).refresh();

      expect(caps.display.hdrTransfers.value, {'sdr'});
      expect(caps.display.hdrTransfers.confidence, CapabilityConfidence.detected);
    });

    // Enabling mpv's `hdr-enabled` says what the player was told to do. It is
    // not a reading of the panel, and a backend acting on it would direct-play
    // HDR to an SDR screen.
    test('every other platform leaves the display unknown', () async {
      final caps = await serviceFor().refresh();

      expect(caps.display.maxWidth.isKnown, isFalse);
      expect(caps.display.hdrTransfers.isKnown, isFalse);
      expect(caps.display.hdrTransfers.confidence, CapabilityConfidence.unknown);
    });

    test('a channel that is not there leaves the display unknown', () async {
      setHandler(null);

      final caps = await serviceFor(isWindows: true).refresh();

      expect(caps.display.maxWidth.isKnown, isFalse);
    });
  });

  group('audio on Apple', () {
    test('a digital port keeps the channel count unknown instead of two', () async {
      const appleTvOnReceiver = AppleAudioRoute(
        portType: 'HDMI',
        portName: 'Receiver',
        maximumOutputNumberOfChannels: 2,
        isDigitalPassthroughPort: true,
        supportsMultichannelContent: true,
      );

      final caps = await serviceFor(hasAppleAudioRoute: true, route: appleTvOnReceiver).refresh();

      expect(caps.audio.maxChannels.isKnown, isFalse);
      expect(caps.audio.passthroughCodecs.value, appleBitstreamCodecs);
      expect(caps.audio.passthroughCodecs.confidence, CapabilityConfidence.detected);
    });

    test('a wide route reports its real count', () async {
      const wide = AppleAudioRoute(
        portType: 'HDMI',
        portName: 'Receiver',
        maximumOutputNumberOfChannels: 8,
        isDigitalPassthroughPort: true,
      );

      final caps = await serviceFor(hasAppleAudioRoute: true, route: wide).refresh();

      expect(caps.audio.maxChannels.value, 8);
      expect(caps.audio.isMultichannel, isTrue);
    });

    test('AirPods take no bitstream and say so', () async {
      const airPods = AppleAudioRoute(
        portType: 'BluetoothA2DP',
        portName: 'AirPods Pro',
        maximumOutputNumberOfChannels: 2,
        spatialAudioEnabled: true,
      );

      final caps = await serviceFor(hasAppleAudioRoute: true, route: airPods).refresh();

      expect(caps.audio.maxChannels.value, 2);
      expect(caps.audio.passthroughCodecs.value, isEmpty);
      expect(caps.audio.carriesBitstream('eac3'), isFalse);
    });

    test('a route that has not reported yet stays unknown', () async {
      final caps = await serviceFor(hasAppleAudioRoute: true).refresh();

      expect(caps.audio.maxChannels.isKnown, isFalse);
      expect(caps.audio.passthroughCodecs.isKnown, isFalse);
    });
  });

  group('audio elsewhere', () {
    test('desktop infers the full device-passthrough list', () async {
      final caps = await serviceFor(supportsAudioPassthrough: true).refresh();

      expect(caps.audio.passthroughCodecs.value, desktopBitstreamCodecs);
      expect(caps.audio.passthroughCodecs.confidence, CapabilityConfidence.inferred);
      expect(caps.audio.carriesBitstream('truehd'), isTrue);
    });

    // Android TV and Fire TV get no better audio out of PS-5: there is no
    // Android equivalent of AppleAudioRoute yet. That is a missing source, not
    // a missing model, and unknown is a state the PS-6 planner has to handle
    // anyway.
    test('the channel count stays unknown off Apple', () async {
      final caps = await serviceFor(engine: PlayerEngine.exoPlayer, supportsAudioPassthrough: true).refresh();

      expect(caps.audio.maxChannels.isKnown, isFalse);
      expect(caps.audio.isMultichannel, isFalse);
    });

    test('a phone without passthrough infers an empty list', () async {
      final caps = await serviceFor().refresh();

      expect(caps.audio.passthroughCodecs.value, isEmpty);
      expect(caps.audio.passthroughCodecs.confidence, CapabilityConfidence.inferred);
    });
  });

  group('connection', () {
    // A private-address check on the server URL is not proof of a LAN: a VPN,
    // split DNS, a relay and plain local routing each break it. The property is
    // in the model so PS-6 has somewhere to read it; the value waits for a
    // source worth trusting.
    test('locality stays unknown in PS-5', () async {
      final caps = await serviceFor().refresh();

      expect(caps.connection.isLocal.isKnown, isFalse);
      expect(caps.connection.isLocal.confidence, CapabilityConfidence.unknown);
    });
  });

  group('the snapshot', () {
    test('starts unknown so consumers keep doing what they did before', () {
      expect(serviceFor().current, same(DeviceCapabilities.unknown));
      expect(DeviceCapabilitiesService.currentSnapshot.decoder.videoCodecs.isKnown, isFalse);
    });

    test('describes itself on one line for the startup log', () async {
      final caps = await serviceFor(isWindows: false, supportsAudioPassthrough: true).refresh();

      expect(caps.describe(), contains('decoder(mpv'));
      expect(caps.describe(), contains('inferred'));
    });
  });
}
