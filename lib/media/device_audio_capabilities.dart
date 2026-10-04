/// What the audio output on this device carries: one of the four layers of
/// `DeviceCapabilities`. Not `ServerCapabilities`, which describes a backend
/// rather than this device.
library;

import 'device_capability.dart';

/// Channel count and per-codec passthrough for the route audio is leaving by.
///
/// This is the layer where the app knows the most and the backends hear the
/// least. On Apple platforms `AppleAudioRoute` reports the route's channel
/// ceiling and whether it is a wired digital port that can carry a Dolby
/// bitstream, and none of that reaches Plex or Jellyfin today.
class DeviceAudioCapabilities {
  const DeviceAudioCapabilities({
    this.maxChannels = const Capability<int>.unknown(),
    this.passthroughCodecs = const Capability<Set<String>>.unknown(),
  });

  static const unknown = DeviceAudioCapabilities();

  /// Widest channel count the route accepts. Unknown off Apple platforms:
  /// there is no Android or desktop equivalent of `AppleAudioRoute` yet, so
  /// Android TV and Fire TV get no better audio out of PS-5. That is a missing
  /// source rather than a missing model, and the model does not have to change
  /// when the source arrives.
  final Capability<int> maxChannels;

  /// Codecs this route takes as a bitstream, in normalized spelling
  /// (`ac3`, `eac3`, `dts`, `dtshd`, `truehd`) as produced by
  /// `normalizeAudioCodec`.
  ///
  /// Carries the two existing audio overrides: forcing PCM clears it, forcing
  /// passthrough fills it, and either way `Capability.observed` keeps what the
  /// route actually said.
  final Capability<Set<String>> passthroughCodecs;

  /// True when the route is known to take more than stereo.
  bool get isMultichannel => (maxChannels.value ?? 0) > 2;

  /// Whether [codec] can go out as a bitstream. Unknown means no, because
  /// sending a bitstream to a route that never agreed to take one is silence,
  /// which is the lesson behind `decideAudioOutput`.
  bool carriesBitstream(String normalizedCodec) => passthroughCodecs.value?.contains(normalizedCodec) ?? false;

  String describe() => 'audio(channels=${maxChannels.describe()}, bitstream=${passthroughCodecs.describe()})';
}
