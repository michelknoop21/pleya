/// What the player on this device decodes and demuxes: one of the four layers
/// of `DeviceCapabilities`. Not `ServerCapabilities`, which describes a backend
/// rather than this device.
library;

import 'device_capability.dart';

/// Which player is in charge of decoding on this device.
///
/// This is a property of the app's own configuration, not of the platform:
/// Android ships ExoPlayer by default (`SettingsService.useExoPlayer`) and mpv
/// as a fallback, so "Android" alone does not answer the question. The old
/// comment above the Jellyfin profile claimed mpv decodes HEVC on every
/// platform we ship, which was never true for a default Android install.
enum PlayerEngine {
  /// libmpv / MPVKit. macOS, iOS, tvOS, Windows, Linux, and Android when the
  /// user turns ExoPlayer off.
  mpv,

  /// Android's ExoPlayer, the default on Android and Android TV.
  exoPlayer,
}

/// Codecs, containers and the codec-shape limits the decoder imposes.
///
/// Every list here is ordered, and the order is carried through to the wire:
/// comma-separated codec lists are order-sensitive on both backends, where the
/// first entry wins when a server picks an output codec.
class DeviceDecoderCapabilities {
  const DeviceDecoderCapabilities({
    required this.engine,
    required this.videoCodecs,
    required this.audioCodecs,
    required this.containers,
    this.videoProfiles = const Capability<Set<String>>.unknown(),
    this.maxVideoLevel = const Capability<int>.unknown(),
    this.maxBitDepth = const Capability<int>.unknown(),
  });

  /// Nothing is known about the decoder. Consumers keep whatever they send
  /// today.
  static const unknown = DeviceDecoderCapabilities(
    engine: PlayerEngine.mpv,
    videoCodecs: Capability<Set<String>>.unknown(),
    audioCodecs: Capability<Set<String>>.unknown(),
    containers: Capability<Set<String>>.unknown(),
  );

  final PlayerEngine engine;

  /// Video codecs the player decodes, in the order they go on the wire.
  final Capability<Set<String>> videoCodecs;

  /// Audio codecs the player decodes. Separate from
  /// `DeviceAudioCapabilities.passthroughCodecs`, which is about handing a
  /// compressed stream on untouched instead of decoding it.
  final Capability<Set<String>> audioCodecs;

  /// Containers the player demuxes and that we are willing to have a backend
  /// direct-play.
  ///
  /// This lives with the decoder because it is a demuxer property. It is in
  /// the model at all because a browser takes MP4 and WebM and no MKV while
  /// the Flutter player takes nearly everything, and chapter 10.4 of the
  /// architecture forbids the server-side planner from branching on client
  /// type. See chapter 11.1 of the masterplan proposal.
  final Capability<Set<String>> containers;

  /// Codec profiles the decoder accepts (`main`, `main10`, `high`, …).
  ///
  /// [CapabilityConfidence.unknown] everywhere in PS-5: nothing asks mpv for
  /// `decoder-list` or `hwdec-interop`, and only the performance overlay reads
  /// `hwdec-current` back. Pretending this was measured would make the PS-6
  /// planner choose on a guess, so it says unknown and marks where the next
  /// detection win is.
  final Capability<Set<String>> videoProfiles;

  /// Highest codec level, times ten: 51 is level 5.1. Unknown in PS-5, for the
  /// same reason as [videoProfiles].
  final Capability<int> maxVideoLevel;

  /// Highest bit depth the decoder handles. Unknown in PS-5.
  final Capability<int> maxBitDepth;

  /// True once the decoder can state a real shape limit. Until then a backend
  /// profile must not carry codec conditions, because an invented condition is
  /// worse than none.
  bool get hasCodecShapeLimits => videoProfiles.isKnown || maxVideoLevel.isKnown || maxBitDepth.isKnown;

  String describe() =>
      'decoder(${engine.name}: video=${videoCodecs.describe()}, '
      'audio=${audioCodecs.describe()}, containers=${containers.describe()})';
}
