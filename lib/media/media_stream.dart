/// Type of an embedded or sidecar stream within a media file.
enum MediaStreamKind { video, audio, subtitle, unknown }

/// A single audio, video, or subtitle stream inside a media part.
class MediaStream {
  /// Backend-opaque stream identifier.
  final String id;
  final MediaStreamKind kind;
  final int? index;
  final String? codec;
  final String? language;
  final String? languageCode;
  final String? title;
  final String? displayTitle;
  final bool selected;

  // Audio
  final int? channels;

  /// Codec profile as the server reports it — Plex `audioProfile`, Jellyfin
  /// `Profile`. This is where Atmos actually announces itself (`ec-3` with
  /// profile `atmos` / `dd+atmos`), rather than in the codec or the title.
  final String? profile;

  /// Channel layout label, e.g. `5.1(side)`, `7.1`. Jellyfin reports it
  /// directly; useful for distinguishing a real 7.1 bed from a 5.1 one.
  final String? channelLayout;

  // Video
  final double? frameRate;
  final bool hdr;
  final bool dolbyVision;
  final int? dolbyVisionProfile;

  // Subtitle
  final bool forced;

  /// Backend-resolved location for true sidecar subtitle download. Null for
  /// embedded streams, even when Jellyfin can expose them through temporary
  /// external delivery URLs during playback negotiation.
  final String? sidecarPath;

  const MediaStream({
    required this.id,
    required this.kind,
    this.index,
    this.codec,
    this.language,
    this.languageCode,
    this.title,
    this.displayTitle,
    this.selected = false,
    this.channels,
    this.profile,
    this.channelLayout,
    this.frameRate,
    this.hdr = false,
    this.dolbyVision = false,
    this.dolbyVisionProfile,
    this.forced = false,
    this.sidecarPath,
  });

  bool get isExternal => sidecarPath != null && sidecarPath!.isNotEmpty;
}
