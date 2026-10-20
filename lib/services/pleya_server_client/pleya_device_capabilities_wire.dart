import '../../media/device_capabilities.dart';

/// `DeviceCapabilities` in the wire form of `POST /playback/plan`.
///
/// One field per capability, each `{value, confidence, overridden}`. A value
/// nobody knows goes out as `null` with confidence `unknown`, which the server
/// reads as "reject nothing", the behaviour from before the plan existed.
Map<String, Object?> pleyaDeviceCapabilitiesToWire(DeviceCapabilities caps) {
  Map<String, Object?> cap<T>(Capability<T> c, Object? Function(T) encode) => {
    'value': c.value == null ? null : encode(c.value as T),
    'confidence': c.isKnown ? c.confidence.name : CapabilityConfidence.unknown.name,
    if (c.isOverride) 'overridden': true,
  };
  // Order is the client's and carries through, like on the other backends.
  List<String> ordered(Set<String> s) => s.toList();

  return {
    'decoder': {
      'video_codecs': cap<Set<String>>(caps.decoder.videoCodecs, ordered),
      'audio_codecs': cap<Set<String>>(caps.decoder.audioCodecs, ordered),
      'containers': cap<Set<String>>(caps.decoder.containers, ordered),
      'video_profiles': cap<Set<String>>(caps.decoder.videoProfiles, ordered),
      'max_bit_depth': cap<int>(caps.decoder.maxBitDepth, (v) => v),
    },
    'display': {'hdr_transfers': cap<Set<String>>(caps.display.hdrTransfers, ordered)},
    'audio': {
      'max_channels': cap<int>(caps.audio.maxChannels, (v) => v),
      'passthrough_codecs': cap<Set<String>>(caps.audio.passthroughCodecs, ordered),
    },
    'connection': {
      'is_local': cap<bool>(caps.connection.isLocal, (v) => v),
      'max_bitrate_kbps': cap<int>(caps.connection.maxBitrateKbps, (v) => v),
    },
  };
}
