import '../../media/device_capabilities.dart';

/// Builds the Jellyfin `DeviceProfile` from what this device can actually do.
///
/// Pure and side-effect free, in the shape of `decideAudioOutput`, so the whole
/// matrix of device against profile can be tested without a device and without
/// an HTTP client.
///
/// The rule that keeps this safe: **an unknown capability produces exactly the
/// value the app sent before PS-5.** Only a detected or inferred value may
/// differ from it. The `_legacy…` constants below are that frozen record; they
/// are not the same thing as the inferred baseline in
/// `device_capability_baseline.dart`, which is a belief about the player and
/// may widen when there is evidence to widen it.
Map<String, Object?> buildJellyfinDeviceProfile(DeviceCapabilities capabilities, {int? maxStreamingBitrate}) {
  final decoder = capabilities.decoder;
  return <String, Object?>{
    'Name': 'Pleya',
    'MaxStreamingBitrate': ?maxStreamingBitrate,
    // Conditions on profile, level, bit depth or HDR would each be a claim
    // about the decoder, and the decoder layer cannot make one yet: nothing
    // asks mpv for `decoder-list`. An invented condition is worse than none,
    // so this stays empty until a real limit is detected.
    'CodecProfiles': decoder.hasCodecShapeLimits ? _codecProfilesFor(decoder) : const <Map<String, Object?>>[],
    // Comma-separated codec lists are order-sensitive — first entry wins when
    // the server picks an output codec. HEVC is listed ahead of H.264 so a
    // server that has "Allow encoding in HEVC format" enabled will actually
    // emit HEVC instead of falling back to H.264.
    'TranscodingProfiles': <Map<String, Object?>>[
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': _legacyTranscodeVideoCodecs,
        'AudioCodec': _legacyTranscodeAudioCodecs,
      },
    ],
    // Declaring HEVC in DirectPlayProfile.VideoCodec stops the server from
    // forcing a transcode for HEVC sources whose container we already accept.
    //
    // The old comment here said mpv decodes HEVC on every platform we ship,
    // which was never true of a default Android install: `use_exoplayer`
    // defaults to true, so Android decodes with ExoPlayer. That is why the
    // list comes from the decoder layer, which reads the player engine, and
    // not from the platform.
    'DirectPlayProfiles': <Map<String, Object?>>[
      {
        'Type': 'Video',
        'Container': _join(decoder.containers.value, _legacyContainers),
        'VideoCodec': _join(decoder.videoCodecs.value, _legacyVideoCodecs),
        'AudioCodec': _join(decoder.audioCodecs.value, _legacyAudioCodecs),
      },
    ],
    'SubtitleProfiles': const <Map<String, Object?>>[
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'pgssub', 'Method': 'External'},
      {'Format': 'dvdsub', 'Method': 'External'},
      {'Format': 'dvbsub', 'Method': 'External'},
    ],
  };
}

String _join(Set<String>? known, String fallback) => known == null || known.isEmpty ? fallback : known.join(',');

/// Only reached once the decoder can state a real limit, which it cannot in
/// PS-5. Written out so the shape is settled rather than invented later under
/// time pressure.
List<Map<String, Object?>> _codecProfilesFor(DeviceDecoderCapabilities decoder) {
  final conditions = <Map<String, Object?>>[
    if (decoder.maxVideoLevel.isKnown)
      {
        'Condition': 'LessThanEqual',
        'Property': 'VideoLevel',
        'Value': '${decoder.maxVideoLevel.value}',
        'IsRequired': false,
      },
    if (decoder.maxBitDepth.isKnown)
      {
        'Condition': 'LessThanEqual',
        'Property': 'VideoBitDepth',
        'Value': '${decoder.maxBitDepth.value}',
        'IsRequired': false,
      },
    if (decoder.videoProfiles.isKnown)
      {
        'Condition': 'EqualsAny',
        'Property': 'VideoProfile',
        'Value': decoder.videoProfiles.value!.join('|'),
        'IsRequired': false,
      },
  ];
  if (conditions.isEmpty) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    {'Type': 'Video', 'Codec': _join(decoder.videoCodecs.value, _legacyVideoCodecs), 'Conditions': conditions},
  ];
}

// -- The frozen record of what the app sent before PS-5 --------------------
//
// These change only when someone deliberately decides the wire output should
// change, and never as a side effect of the model learning something. They are
// what an unknown capability falls back to.

const _legacyVideoCodecs = 'hevc,h264,h265,vp8,vp9,av1,mpeg4,mpeg2video';
const _legacyAudioCodecs = 'aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts';
const _legacyContainers = 'mp4,mkv,m4v,webm,mov,ts';
const _legacyTranscodeVideoCodecs = 'hevc,h264';
const _legacyTranscodeAudioCodecs = 'aac,mp3,ac3,eac3,flac,opus';
