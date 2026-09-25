import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/device_capabilities.dart';
import 'package:pleya/screens/settings/playback_settings_screen.dart';
import 'package:pleya/services/device_capabilities_service.dart';
import 'package:pleya/services/device_capability_overrides.dart';

void main() {
  test('changing the Android player backend configures and refreshes decoder capabilities', () async {
    bool? configuredForExoPlayer;
    final service = DeviceCapabilitiesService(
      probe: const DevicePlatformProbe(
        engine: PlayerEngine.exoPlayer,
        isWindows: false,
        hasAppleAudioRoute: false,
        supportsAudioPassthrough: false,
      ),
    );

    await refreshDeviceCapabilitiesForPlayerBackend(
      true,
      configure: (useExoPlayer) {
        configuredForExoPlayer = useExoPlayer;
        return service;
      },
      overrides: DeviceCapabilityOverrides.defaults,
    );

    expect(configuredForExoPlayer, isTrue);
    expect(service.current.decoder.engine, PlayerEngine.exoPlayer);
    expect(service.current.decoder.videoCodecs.isKnown, isTrue);
  });
}
