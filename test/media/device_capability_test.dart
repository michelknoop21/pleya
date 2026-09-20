import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/device_capabilities.dart';

import 'device_capabilities_fixtures.dart';

void main() {
  group('Capability confidence', () {
    test('detected and inferred keep their own confidence', () {
      const detected = Capability<int>.detected(8);
      const inferred = Capability<int>.inferred(2);

      expect(detected.confidence, CapabilityConfidence.detected);
      expect(inferred.confidence, CapabilityConfidence.inferred);
      expect(detected.isOverride, isFalse);
      expect(inferred.isOverride, isFalse);
    });

    test('unknown has no value and is not known', () {
      const unknown = Capability<Set<String>>.unknown();

      expect(unknown.value, isNull);
      expect(unknown.isKnown, isFalse);
      expect(unknown.confidence, CapabilityConfidence.unknown);
    });
  });

  group('Capability override', () {
    // This is the correction that made the type worth having: an override used
    // to stamp `detected` on whatever it wrapped, so overriding an inferred
    // decoder list turned that list into a measurement. The PS-6 planner keys
    // its safe-side choice off exactly this field.
    test('an override reports the confidence of the observation it replaces', () {
      const inferred = Capability<int>.inferred(2);
      final overridden = inferred.overriddenWith(8);

      expect(overridden.value, 8);
      expect(overridden.confidence, CapabilityConfidence.inferred);
      expect(overridden.isOverride, isTrue);
    });

    test('overriding a detected value keeps detected', () {
      const detected = Capability<int>.detected(2);

      expect(detected.overriddenWith(8).confidence, CapabilityConfidence.detected);
    });

    test('overriding an unknown value stays unknown', () {
      const unknown = Capability<int>.unknown();
      final overridden = unknown.overriddenWith(1080);

      expect(overridden.value, 1080);
      expect(overridden.confidence, CapabilityConfidence.unknown);
      expect(overridden.isOverride, isTrue);
    });

    test('the detected value stays reachable, which is acceptance criterion 3', () {
      const detected = Capability<int>.detected(8);
      final overridden = detected.overriddenWith(2);

      expect(overridden.value, 2);
      expect(overridden.observedValue, 8);
      expect(overridden.observed?.confidence, CapabilityConfidence.detected);
    });

    test('overriding twice collapses to one level so detection is not buried', () {
      const detected = Capability<int>.detected(8);
      final twice = detected.overriddenWith(6).overriddenWith(2);

      expect(twice.value, 2);
      expect(twice.observedValue, 8);
      expect(twice.confidence, CapabilityConfidence.detected);
    });

    test('describe names both sides of an override', () {
      const detected = Capability<int>.detected(8);

      expect(detected.describe(), '8(detected)');
      expect(detected.overriddenWith(2).describe(), '2(override of 8/detected)');
      expect(const Capability<int>.unknown().describe(), '?(unknown)');
    });
  });

  group('layers', () {
    test('unknown capabilities carry no shape limits and no ceiling', () {
      expect(DeviceCapabilities.unknown.decoder.hasCodecShapeLimits, isFalse);
      expect(DeviceCapabilities.unknown.display.hasResolutionCeiling, isFalse);
      expect(DeviceCapabilities.unknown.audio.isMultichannel, isFalse);
      expect(DeviceCapabilities.unknown.audio.carriesBitstream('eac3'), isFalse);
    });

    test('an unknown channel count does not claim multichannel', () {
      expect(appleTv4kOnReceiver.audio.maxChannels.isKnown, isFalse);
      expect(appleTv4kOnReceiver.audio.isMultichannel, isFalse);
      expect(appleTv4kOnReceiver.audio.carriesBitstream('eac3'), isTrue);
      expect(appleTv4kOnReceiver.audio.carriesBitstream('truehd'), isFalse);
    });

    test('desktop carries TrueHD where Apple does not', () {
      expect(macOsDesktop.audio.carriesBitstream('truehd'), isTrue);
      expect(iPhoneWithAirPods.audio.carriesBitstream('eac3'), isFalse);
    });
  });

  group('acceptance criterion 1: two devices, demonstrably different', () {
    test('an Apple TV HD and an Apple TV 4K differ in the model', () {
      expect(appleTvHd.decoder.videoCodecs.value, isNot(contains('av1')));
      expect(appleTv4kOnReceiver.decoder.videoCodecs.value, contains('av1'));
      expect(appleTvHd.display.hasResolutionCeiling, isTrue);
      expect(appleTv4kOnReceiver.display.hasResolutionCeiling, isFalse);
    });

    test('the engine is a property of the app, not of the platform', () {
      expect(androidTvExoPlayer.decoder.engine, PlayerEngine.exoPlayer);
      expect(macOsDesktop.decoder.engine, PlayerEngine.mpv);
    });

    test('every fixture describes itself on one line', () {
      for (final entry in allDeviceFixtures.entries) {
        expect(entry.value.describe(), isNotEmpty, reason: entry.key);
      }
      expect(nothingKnown.describe(), contains('?(unknown)'));
    });
  });

  group('copyWith', () {
    test('replaces one layer and keeps the rest', () {
      final capped = macOsDesktop.copyWith(
        display: DeviceDisplayCapabilities(
          maxWidth: macOsDesktop.display.maxWidth.overriddenWith(1920),
          maxHeight: macOsDesktop.display.maxHeight.overriddenWith(1080),
        ),
      );

      expect(capped.display.maxHeight.value, 1080);
      expect(capped.display.maxHeight.observedValue, 1440);
      expect(capped.display.maxHeight.confidence, CapabilityConfidence.inferred);
      expect(capped.audio, same(macOsDesktop.audio));
      expect(capped.decoder, same(macOsDesktop.decoder));
    });
  });
}
