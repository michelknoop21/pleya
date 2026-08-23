import '../../media/device_capabilities.dart';
import '../../media/media_source_info.dart';
import '../../models/plex/plex_config.dart';
import '../../models/transcode_quality_preset.dart';
import '../../utils/codec_utils.dart';

/// The Plex transcode request, built from what this device can do.
///
/// Lifted out of `plex_client.dart`, which stood at 4397 lines. Everything
/// here is pure, so the whole matrix of device against request can be tested
/// without a client and without a server.
///
/// The rule that keeps this safe is the same one the Jellyfin builder follows:
/// **an unknown capability produces exactly the value the app sent before
/// PS-5.** Only a detected or inferred value may differ from it.

/// The `X-Plex-Client-Profile-Extra` clauses, in wire order.
///
/// The profile is built from scratch because we use the `Generic` base
/// platform (see [plexTranscodePlatformName]), which has no pre-installed
/// transcode targets. That forces `add-transcode-target` rather than
/// `append-transcode-target-codec`, which only edits existing targets and left
/// Plex returning decision code 2000, "neither direct play nor conversion is
/// available".
///
/// See openapi.md §"Profile Augmentations" for the DSL reference.
List<String> buildPlexProfileExtraClauses(DeviceCapabilities capabilities, TranscodeQualityPreset preset) {
  final clauses = <String>['add-settings(DirectPlayStreamSelection=true)'];

  // For non-original presets a bitrate limitation caps the video codec; with
  // `replace=true` it overrides any default limit. The ceiling comes from the
  // connection layer, which is where the quality preset now lives; an unknown
  // ceiling falls back to the preset itself, which is what produced the number
  // before PS-5.
  final ceilingKbps = plexMaxVideoBitrateKbps(capabilities, preset);
  if (!preset.isOriginal && ceilingKbps != null) {
    clauses.add(
      'add-limitation(scope=videoCodec&scopeName=*&type=upperBound'
      '&name=video.bitrate&value=$ceilingKbps&replace=true)',
    );
  }

  // Match Plex Desktop's stable HTTP/MKV transcode target. Codec-list commas
  // are pre-encoded as `%2C` — see the profile-extra encoding note below.
  clauses.add(
    'add-transcode-target(type=videoProfile&context=streaming'
    '&protocol=http&container=mkv&videoCodec=${_encodeList(_legacyTranscodeVideoCodecs)}'
    '&audioCodec=${_encodeList(_legacyTranscodeAudioCodecs)}'
    '&subtitleCodec=${_encodeList(_legacySubtitleCodecs)})',
  );
  clauses.add(
    'add-transcode-target-settings(type=videoProfile&context=streaming'
    '&protocol=http&CopyMatroskaAttachments=true)',
  );
  return clauses;
}

/// Where Plex should think this client sits.
///
/// Unknown produces `lan`, which is what the app sent unconditionally before
/// PS-5, and unknown is what the connection layer says today. Turning a
/// private-address check into `wan` is not a repair: a VPN, split DNS, a relay
/// and plain local routing each get it wrong, and Plex treats this as hard
/// input. The value is modelled so a trustworthy source can land on it later.
String plexProfileLocation(DeviceCapabilities capabilities) =>
    capabilities.connection.isLocal.value == false ? 'wan' : 'lan';

/// The bitrate ceiling for one request, in kbit/s.
///
/// The connection layer owns it, which is where the quality preset now lives.
/// An unknown ceiling falls back to the preset itself, which is exactly what
/// produced this number before PS-5.
int? plexMaxVideoBitrateKbps(DeviceCapabilities capabilities, TranscodeQualityPreset preset) =>
    capabilities.connection.maxBitrateKbps.value ?? preset.videoBitrateKbps;

String _encodeList(String commaSeparated) => commaSeparated.replaceAll(',', '%2C');

bool plexCanTranscodeSubtitleAsText(MediaSubtitleTrack track) => CodecUtils.isTextSubtitleCodec(track.codec);

bool plexShouldEmbedSubtitleInHttpTranscode(MediaSubtitleTrack? track) {
  if (track == null) return false;
  if (track.key != null && track.key!.isNotEmpty) return false;
  return CodecUtils.isEmbeddableSubtitleCodec(track.codec);
}

// -- The frozen record of what the app sent before PS-5 --------------------

const _legacyTranscodeVideoCodecs = 'h264,hevc,*';
const _legacyTranscodeAudioCodecs = 'opus,vorbis,flac,*';
const _legacySubtitleCodecs = 'ass,pgs,vobsub,*';

Map<String, String> buildPlexTranscodeParams({
  required PlexConfig config,
  required DeviceCapabilities capabilities,
  required String ratingKey,
  required int mediaIndex,
  int partIndex = 0,
  required TranscodeQualityPreset preset,
  required String sessionIdentifier,
  required String transcodeSessionId,
  int? audioStreamId,
  MediaSubtitleTrack? selectedSubtitleTrack,
  int? offsetMs,
}) {
  final isOriginal = preset.isOriginal;
  final selectedEmbeddedSubtitle = plexShouldEmbedSubtitleInHttpTranscode(selectedSubtitleTrack)
      ? selectedSubtitleTrack
      : null;
  // Only text subtitles get `advancedSubtitles=text`; image subtitles
  // (PGS/VOBSUB) are copied into the MKV as-is for the player to render.
  final embedSubtitleAsText =
      selectedEmbeddedSubtitle != null && plexCanTranscodeSubtitleAsText(selectedEmbeddedSubtitle);

  final clientProfileExtra = buildPlexProfileExtraClauses(capabilities, preset).join('+');

  // HTTP/MKV matches Plex Desktop and lets MPV see embedded subtitle streams.
  // HLS `subtitles=segmented` was accepted by Plex but produced manifests
  // with only video/audio renditions for MPV.
  return <String, String>{
    'hasMDE': '1',
    'path': '/library/metadata/$ratingKey',
    'mediaIndex': mediaIndex.toString(),
    'partIndex': partIndex.toString(),
    'protocol': 'http',
    'fastSeek': '1',
    'directPlay': isOriginal ? '1' : '0',
    'directStream': isOriginal ? '1' : '0',
    'subtitleSize': '100',
    'audioBoost': '100',
    'location': plexProfileLocation(capabilities),
    if (!isOriginal) 'maxVideoBitrate': ?plexMaxVideoBitrateKbps(capabilities, preset)?.toString(),
    'addDebugOverlay': '0',
    'autoAdjustQuality': '0',
    // Off in PS-5, unchanged. Handing a compressed audio stream on untouched
    // is a playback decision rather than a capability statement, and playback
    // decisions are PS-6.
    'directStreamAudio': '0',
    'mediaBufferSize': '102400',
    'session': transcodeSessionId,
    // Embed the selected subtitle in the MKV stream: text codecs are
    // converted to text, image codecs (PGS/VOBSUB) are copied as-is and
    // rendered by the player — never burned into the video. Unselected tracks
    // and keyed sidecars stay at `none`.
    'subtitles': selectedEmbeddedSubtitle != null ? 'embedded' : 'none',
    if (selectedEmbeddedSubtitle != null) 'subtitleStreamID': selectedEmbeddedSubtitle.id.toString(),
    if (embedSubtitleAsText) 'advancedSubtitles': 'text',
    // Preserve source timestamps for the HTTP/MKV stream so player seeks and
    // sidecar subtitles stay aligned with Plex source time.
    'copyts': '1',
    if (audioStreamId != null) 'audioStreamID': audioStreamId.toString(),
    'Accept-Language': 'en',
    'X-Plex-Session-Identifier': sessionIdentifier,
    'X-Plex-Client-Profile-Extra': clientProfileExtra,
    'X-Plex-Chunked': '1',
    'X-Plex-Features': 'external-media,indirect-media',
    'X-Plex-Model': 'standalone',
    'X-Plex-Language': 'en',
    'X-Plex-Product': config.product,
    'X-Plex-Version': config.version,
    'X-Plex-Client-Identifier': config.clientIdentifier,
    // Plex's server rejects unknown platform names with HTTP 400 and maps
    // known names to codec/bitrate base profiles. Our usual "Flutter"
    // platform, plus "MacOSX" / "Linux", are all rejected; swap to a
    // Plex-recognized name just for transcode requests. See
    // [plexTranscodePlatformName] for the mapping.
    'X-Plex-Platform': plexTranscodePlatformName(),
    if (config.device != null) 'X-Plex-Device': config.device!,
    if (offsetMs != null) 'offset': (offsetMs ~/ 1000).toString(),
    if (config.token != null) 'X-Plex-Token': config.token!,
  };
}

/// Platform name Plex Media Server accepts on the transcode decision
/// endpoint for arbitrary clients. Our default "Flutter" returns HTTP 400,
/// and the known-OS names (`MacOSX`, `Mac`, `Linux`) are also rejected.
/// `Generic` is accepted and comes with no preset transcode targets — we
/// build the profile ourselves via `X-Plex-Client-Profile-Extra` with
/// `add-transcode-target`.
String plexTranscodePlatformName() => 'Generic';

/// Strict percent-encoder matching Plex Web's URL encoder — escapes the
/// extra characters `(`, `)`, `*`, `'`, `!` that Dart's [Uri.encodeComponent]
/// leaves literal. Required for `X-Plex-Client-Profile-Extra` whose parens
/// and asterisks must appear as `%28`, `%29`, `%2A` on the wire.
String plexEncode(String value) {
  return Uri.encodeComponent(
    value,
  ).replaceAll('(', '%28').replaceAll(')', '%29').replaceAll('*', '%2A').replaceAll("'", '%27').replaceAll('!', '%21');
}
