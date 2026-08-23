/// Hand-authored `DeviceCapabilities` for the devices that actually differ.
///
/// Modelled on `test/services/audio_output_decision_test.dart`, which tests the
/// audio matrix against four `const AppleAudioRoute` fixtures with no mocking
/// and no binding. Same idea here: the table tests for the two profile builders
/// need devices, not a device.
///
/// These are fixtures and not detection output. PS-5 detection cannot tell an
/// Apple TV HD from an Apple TV 4K, for instance; [appleTvHd] exists because
/// the model has to be able to express that difference (architecture chapter
/// 9.1 names exactly this pair) and because PS-6 needs the table row.
library;

import 'package:pleya/media/device_capabilities.dart';

/// Video codecs the Flutter player is credited with today, in wire order.
const kMpvVideoCodecs = {'hevc', 'h264', 'h265', 'vp8', 'vp9', 'av1', 'mpeg4', 'mpeg2video'};

/// Audio codecs the Flutter player decodes, in wire order.
const kMpvAudioCodecs = {'aac', 'mp3', 'mp2', 'ac3', 'eac3', 'flac', 'opus', 'vorbis', 'dts'};

/// Containers we declare for direct play, in wire order.
const kMpvContainers = {'mp4', 'mkv', 'm4v', 'webm', 'mov', 'ts'};

/// What the Apple system decoder takes as a bitstream. Matches
/// `appleBitstreamCodecs`.
const kAppleBitstream = {'ac3', 'eac3'};

/// What desktop device passthrough takes. Matches `desktopBitstreamCodecs`.
const kDesktopBitstream = {'ac3', 'eac3', 'dts', 'dtshd', 'truehd'};

const _mpvDecoder = DeviceDecoderCapabilities(
  engine: PlayerEngine.mpv,
  videoCodecs: Capability.inferred(kMpvVideoCodecs),
  audioCodecs: Capability.inferred(kMpvAudioCodecs),
  containers: Capability.inferred(kMpvContainers),
);

/// Apple TV 4K wired to an AV receiver.
///
/// Channels are [CapabilityConfidence.unknown] and not eight, which is the
/// measurement rather than the brochure: on this exact setup
/// `maximumOutputNumberOfChannels` reported 2 while the same session told mpv
/// it had 8, so the count is not usable on a digital port. `AppleAudioRoute`
/// documents that; the model refuses to launder it into a number.
const appleTv4kOnReceiver = DeviceCapabilities(
  decoder: _mpvDecoder,
  display: DeviceDisplayCapabilities.unknown,
  audio: DeviceAudioCapabilities(
    maxChannels: Capability.unknown(),
    passthroughCodecs: Capability.detected(kAppleBitstream),
  ),
  connection: DeviceConnectionCapabilities.unknown,
);

/// Apple TV HD: same app, older decoder, and a 1080p output.
const appleTvHd = DeviceCapabilities(
  decoder: DeviceDecoderCapabilities(
    engine: PlayerEngine.mpv,
    videoCodecs: Capability.inferred({'hevc', 'h264', 'h265', 'vp8', 'vp9', 'mpeg4', 'mpeg2video'}),
    audioCodecs: Capability.inferred(kMpvAudioCodecs),
    containers: Capability.inferred(kMpvContainers),
  ),
  display: DeviceDisplayCapabilities(maxWidth: Capability.detected(1920), maxHeight: Capability.detected(1080)),
  audio: DeviceAudioCapabilities(
    maxChannels: Capability.unknown(),
    passthroughCodecs: Capability.detected(kAppleBitstream),
  ),
  connection: DeviceConnectionCapabilities.unknown,
);

/// iPhone with AirPods: spatial, but a stereo route that takes no bitstream.
const iPhoneWithAirPods = DeviceCapabilities(
  decoder: _mpvDecoder,
  display: DeviceDisplayCapabilities.unknown,
  audio: DeviceAudioCapabilities(
    maxChannels: Capability.detected(2),
    passthroughCodecs: Capability.detected(<String>{}),
  ),
  connection: DeviceConnectionCapabilities.unknown,
);

/// macOS desktop. Passthrough is inferred rather than detected because
/// `AppleAudioRoute` is iOS and tvOS only; the desktop answer comes from
/// `PlatformDetector.supportsAudioPassthrough()`, which is platform knowledge
/// and not a route reading.
const macOsDesktop = DeviceCapabilities(
  decoder: _mpvDecoder,
  display: DeviceDisplayCapabilities(maxWidth: Capability.inferred(3440), maxHeight: Capability.inferred(1440)),
  audio: DeviceAudioCapabilities(
    maxChannels: Capability.unknown(),
    passthroughCodecs: Capability.inferred(kDesktopBitstream),
  ),
  connection: DeviceConnectionCapabilities(
    maxBitrateKbps: Capability.overridden(20000, observed: Capability.unknown()),
  ),
);

/// Android TV on ExoPlayer: a different decoder, and no audio source at all.
const androidTvExoPlayer = DeviceCapabilities(
  decoder: DeviceDecoderCapabilities(
    engine: PlayerEngine.exoPlayer,
    videoCodecs: Capability.inferred(kMpvVideoCodecs),
    audioCodecs: Capability.inferred(kMpvAudioCodecs),
    containers: Capability.inferred(kMpvContainers),
  ),
  display: DeviceDisplayCapabilities.unknown,
  audio: DeviceAudioCapabilities(
    maxChannels: Capability.unknown(),
    passthroughCodecs: Capability.inferred(kDesktopBitstream),
  ),
  connection: DeviceConnectionCapabilities.unknown,
);

/// Every layer unknown. The row that proves an unknown input still produces
/// exactly what the app sends today.
const nothingKnown = DeviceCapabilities.unknown;

/// The five devices, in the order the table tests walk them.
const allDeviceFixtures = <String, DeviceCapabilities>{
  'appleTv4kOnReceiver': appleTv4kOnReceiver,
  'appleTvHd': appleTvHd,
  'iPhoneWithAirPods': iPhoneWithAirPods,
  'macOsDesktop': macOsDesktop,
  'androidTvExoPlayer': androidTvExoPlayer,
};
