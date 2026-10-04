import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/device_capabilities.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/services/audio_output_decision.dart';
import 'package:pleya/services/device_capability_overrides.dart';

import '../media/device_capabilities_fixtures.dart';

/// Acceptance criterion 3: an override is visible as an override, and the
/// detected value stays known.
void main() {
  DeviceCapabilities apply(
    DeviceCapabilities base,
    DeviceCapabilityOverrides overrides, {
    Set<String> platform = kAppleBitstream,
  }) {
    return applyCapabilityOverrides(base, overrides, platformBitstreamCodecs: platform);
  }

  group('no override', () {
    test('leaves every layer exactly as detection left it', () {
      final result = apply(appleTv4kOnReceiver, DeviceCapabilityOverrides.defaults);

      expect(result.audio.passthroughCodecs.isOverride, isTrue);
      expect(result.audio.passthroughCodecs.value, isEmpty);
      expect(result.display, same(appleTv4kOnReceiver.display));
      expect(result.connection, same(appleTv4kOnReceiver.connection));
    });

    test('auto with originalDolby keeps detection untouched', () {
      final result = apply(
        appleTv4kOnReceiver,
        const DeviceCapabilityOverrides(audioPriority: AudioPriority.originalDolby),
      );

      expect(result.audio.passthroughCodecs.isOverride, isFalse);
      expect(result.audio.passthroughCodecs.value, kAppleBitstream);
    });
  });

  group('audio overrides mirror decideAudioOutput', () {
    // Under evenVolume nothing is ever bitstreamed: a bitstream cannot be
    // levelled, and levelling is the whole point of that choice. The model has
    // to say the same thing playback does, or the two drift.
    test('auto with evenVolume clears passthrough and keeps the reading', () {
      final result = apply(appleTv4kOnReceiver, DeviceCapabilityOverrides.defaults);
      final passthrough = result.audio.passthroughCodecs;

      expect(passthrough.value, isEmpty);
      expect(passthrough.observedValue, kAppleBitstream);
      expect(passthrough.confidence, CapabilityConfidence.detected);
      expect(passthrough.isOverride, isTrue);
    });

    test('forcing PCM clears passthrough', () {
      final result = apply(
        macOsDesktop,
        const DeviceCapabilityOverrides(audioOutputMode: AudioOutputMode.pcm),
        platform: kDesktopBitstream,
      );

      expect(result.audio.passthroughCodecs.value, isEmpty);
      expect(result.audio.carriesBitstream('truehd'), isFalse);
      expect(result.audio.passthroughCodecs.observedValue, kDesktopBitstream);
    });

    test('forcing passthrough asserts the platform list, and no more', () {
      final result = apply(
        iPhoneWithAirPods,
        const DeviceCapabilityOverrides(audioOutputMode: AudioOutputMode.passthrough),
      );

      expect(result.audio.passthroughCodecs.value, kAppleBitstream);
      expect(result.audio.carriesBitstream('truehd'), isFalse);
      expect(result.audio.passthroughCodecs.observedValue, isEmpty);
    });

    // The correction that made Capability worth having: overriding an inferred
    // reading does not turn it into a measurement.
    test('an override of an inferred reading stays inferred', () {
      final result = apply(
        macOsDesktop,
        const DeviceCapabilityOverrides(audioOutputMode: AudioOutputMode.pcm),
        platform: kDesktopBitstream,
      );

      expect(result.audio.passthroughCodecs.confidence, CapabilityConfidence.inferred);
    });

    test('the channel count is never touched by an audio override', () {
      final result = apply(appleTvHd, const DeviceCapabilityOverrides(audioOutputMode: AudioOutputMode.pcm));

      expect(result.audio.maxChannels.isKnown, isFalse);
    });
  });

  group('display cap', () {
    test('caps an inferred resolution and keeps what was detected', () {
      final result = apply(
        macOsDesktop,
        const DeviceCapabilityOverrides(displayCap: DisplayResolutionCap.hd1080),
        platform: kDesktopBitstream,
      );

      expect(result.display.maxWidth.value, 1920);
      expect(result.display.maxHeight.value, 1080);
      expect(result.display.maxHeight.observedValue, 1440);
      expect(result.display.maxHeight.confidence, CapabilityConfidence.inferred);
    });

    // A ceiling, not a claim: asking for 4K on a 1080p panel is a no-op rather
    // than a promotion.
    test('a cap above the measured panel changes nothing', () {
      final result = apply(appleTvHd, const DeviceCapabilityOverrides(displayCap: DisplayResolutionCap.uhd2160));

      expect(result.display.maxHeight.value, 1080);
      expect(result.display.maxHeight.isOverride, isFalse);
    });

    test('a cap on an unknown display still produces a ceiling', () {
      final result = apply(
        appleTv4kOnReceiver,
        const DeviceCapabilityOverrides(displayCap: DisplayResolutionCap.hd1080),
      );

      expect(result.display.maxHeight.value, 1080);
      expect(result.display.maxHeight.isOverride, isTrue);
      expect(result.display.maxHeight.confidence, CapabilityConfidence.unknown);
      expect(result.display.hasResolutionCeiling, isTrue);
    });

    test('auto leaves the display alone', () {
      final result = apply(macOsDesktop, DeviceCapabilityOverrides.defaults, platform: kDesktopBitstream);

      expect(result.display.maxHeight.value, 1440);
      expect(result.display.maxHeight.isOverride, isFalse);
    });
  });

  group('quality preset on the connection layer', () {
    test('a capped preset becomes a bandwidth ceiling', () {
      final result = apply(
        nothingKnown,
        const DeviceCapabilityOverrides(qualityPreset: TranscodeQualityPreset.p1080_8mbps),
      );

      expect(result.connection.maxBitrateKbps.value, 8000);
      expect(result.connection.maxBitrateKbps.isOverride, isTrue);
      expect(result.connection.maxBitrateKbps.confidence, CapabilityConfidence.unknown);
    });

    test('original asks for no cap at all', () {
      final result = apply(nothingKnown, DeviceCapabilityOverrides.defaults);

      expect(result.connection.maxBitrateKbps.isKnown, isFalse);
      expect(result.connection.maxBitrateKbps.isOverride, isFalse);
    });

    test('locality is not something an override may invent', () {
      final result = apply(
        nothingKnown,
        const DeviceCapabilityOverrides(qualityPreset: TranscodeQualityPreset.p720_2mbps),
      );

      expect(result.connection.isLocal.isKnown, isFalse);
    });
  });

  group('the decoder layer takes no overrides', () {
    test('nothing a user can set changes what the player decodes', () {
      final result = apply(
        macOsDesktop,
        const DeviceCapabilityOverrides(
          audioOutputMode: AudioOutputMode.passthrough,
          displayCap: DisplayResolutionCap.hd1080,
          qualityPreset: TranscodeQualityPreset.p240_320,
        ),
        platform: kDesktopBitstream,
      );

      expect(result.decoder, same(macOsDesktop.decoder));
    });
  });
}
