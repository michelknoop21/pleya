import 'package:flutter/foundation.dart';

import '../media/device_capabilities.dart';
import '../models/transcode_quality_preset.dart';
import 'audio_output_decision.dart';
import 'settings_service.dart';

/// The user settings that sit on top of a detected capability.
///
/// Three of these already existed and are taken over rather than duplicated:
/// `audio_output_mode`, `audio_priority` and `default_quality_preset`. The
/// fourth, [displayCap], is new, because acceptance criterion 3 asks for an
/// override that is visibly an override on a layer where there was none.
///
/// An override never erases what detection said. `Capability.observed` keeps
/// it, so "stereo because you set it that way" stays sayable, and the
/// confidence of the observation carries through: overriding an inferred value
/// does not turn it into a measurement.
@immutable
class DeviceCapabilityOverrides {
  const DeviceCapabilityOverrides({
    this.audioOutputMode = AudioOutputMode.auto,
    this.audioPriority = AudioPriority.evenVolume,
    this.qualityPreset = TranscodeQualityPreset.original,
    this.displayCap = DisplayResolutionCap.auto,
  });

  /// Reads the four settings that already exist for this. Three of them
  /// predate PS-5 and keep their own screens; only their meaning as an
  /// override lands here.
  factory DeviceCapabilityOverrides.fromSettings([SettingsService? service]) {
    final settings = service ?? SettingsService.instance;
    return DeviceCapabilityOverrides(
      audioOutputMode: settings.read(SettingsService.audioOutputMode),
      audioPriority: settings.read(SettingsService.audioPriority),
      qualityPreset: settings.read(SettingsService.defaultQualityPreset),
      displayCap: settings.read(SettingsService.displayMaxResolution),
    );
  }

  /// Every setting on its shipped default.
  ///
  /// Not the same as "no override". The audio default is auto plus
  /// evenVolume, and under evenVolume nothing is ever bitstreamed, so the
  /// default already overrides the passthrough list to empty. That is the
  /// point: it is the user's choice, it is visible as an override, and the
  /// route reading stays underneath it.
  static const defaults = DeviceCapabilityOverrides();

  final AudioOutputMode audioOutputMode;
  final AudioPriority audioPriority;

  /// Keeps its second role out of this model on purpose.
  /// `playback_source_resolver.dart` reads the preset directly to decide
  /// whether a downloaded copy beats the server stream, and that is a source
  /// choice rather than a capability. Only the bandwidth meaning moves here.
  final TranscodeQualityPreset qualityPreset;

  final DisplayResolutionCap displayCap;
}

/// Applies [overrides] to [detected].
///
/// Pure, in the shape of `decideAudioOutput`, so the whole matrix can be tested
/// without a device and without settings.
///
/// [platformBitstreamCodecs] is what this platform can bitstream at all:
/// `appleBitstreamCodecs` on iOS and tvOS, `desktopBitstreamCodecs` where the
/// output does real device passthrough. Forcing passthrough asserts that list;
/// it cannot conjure a codec the platform has no path for.
DeviceCapabilities applyCapabilityOverrides(
  DeviceCapabilities detected,
  DeviceCapabilityOverrides overrides, {
  required Set<String> platformBitstreamCodecs,
}) {
  return detected.copyWith(
    display: _applyDisplay(detected.display, overrides.displayCap),
    audio: _applyAudio(detected.audio, overrides, platformBitstreamCodecs),
    connection: _applyConnection(detected.connection, overrides.qualityPreset),
  );
}

DeviceDisplayCapabilities _applyDisplay(DeviceDisplayCapabilities display, DisplayResolutionCap cap) {
  if (cap.isAuto) return display;
  return DeviceDisplayCapabilities(
    maxWidth: _capped(display.maxWidth, cap.width!),
    maxHeight: _capped(display.maxHeight, cap.height!),
    refreshRatesHz: display.refreshRatesHz,
    hdrTransfers: display.hdrTransfers,
  );
}

/// A ceiling, not a claim. Asking for 2160 on a panel that measured 1080 is a
/// no-op rather than a promotion, and the measurement stays reachable either
/// way.
Capability<int> _capped(Capability<int> observed, int ceiling) {
  final current = observed.value;
  if (current != null && current <= ceiling) return observed;
  return observed.overriddenWith(ceiling);
}

/// Mirrors the truth table of `decideAudioOutput`, so what the model says this
/// device carries and what playback actually does cannot drift apart.
DeviceAudioCapabilities _applyAudio(
  DeviceAudioCapabilities audio,
  DeviceCapabilityOverrides overrides,
  Set<String> platformBitstreamCodecs,
) {
  final passthrough = switch (overrides.audioOutputMode) {
    AudioOutputMode.pcm => audio.passthroughCodecs.overriddenWith(const <String>{}),
    AudioOutputMode.passthrough => audio.passthroughCodecs.overriddenWith(platformBitstreamCodecs),
    // Auto follows the priority the user set once. Under evenVolume nothing is
    // ever bitstreamed, because a bitstream cannot be levelled and levelling is
    // the whole point of that choice.
    AudioOutputMode.auto =>
      overrides.audioPriority == AudioPriority.originalDolby
          ? audio.passthroughCodecs
          : audio.passthroughCodecs.overriddenWith(const <String>{}),
  };

  return DeviceAudioCapabilities(maxChannels: audio.maxChannels, passthroughCodecs: passthrough);
}

DeviceConnectionCapabilities _applyConnection(DeviceConnectionCapabilities connection, TranscodeQualityPreset preset) {
  final kbps = preset.videoBitrateKbps;
  if (kbps == null) return connection;
  return DeviceConnectionCapabilities(
    isLocal: connection.isLocal,
    maxBitrateKbps: connection.maxBitrateKbps.overriddenWith(kbps),
  );
}
