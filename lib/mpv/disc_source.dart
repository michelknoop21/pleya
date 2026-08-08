import 'dart:io';

/// The two disc structures a media folder can hold.
enum DiscKind {
  /// BDMV — a Blu-ray, either as a `.iso` disc image or an unpacked folder.
  bluray,

  /// VIDEO_TS — a DVD. Recognised so it can be refused with a real message
  /// where mpv has no DVD support, rather than failing as a corrupt stream.
  dvd,
}

/// A path that has to be handed to mpv as a *disc*, not as a file.
///
/// mpv cannot demux a disc image: an `.iso` is a UDF filesystem, and the video
/// lives in playlists inside it. libbluray reads that structure — including
/// straight out of an image file, without mounting — but only when mpv is told
/// the path is a device and asked for a `bd://` URL.
class DiscSource {
  final DiscKind kind;

  /// What `bluray-device` is set to: the image file, or the folder holding
  /// `BDMV` (not `BDMV` itself).
  final String devicePath;

  /// The URL to load. `longest` is mpv's own default title choice, spelled out
  /// so the behaviour is readable and a title picker has somewhere to slot in.
  final String mpvUri;

  const DiscSource({required this.kind, required this.devicePath, required this.mpvUri});

  @override
  String toString() => 'DiscSource(${kind.name}, device: $devicePath, uri: $mpvUri)';
}

/// Thrown when the disc is understood but this build cannot play it, so the
/// player can say why instead of surfacing a stream error.
class UnsupportedDiscException implements Exception {
  final DiscKind kind;

  const UnsupportedDiscException(this.kind);

  @override
  String toString() => 'Unsupported disc type: ${kind.name}';
}

/// Whether this platform's mpv build can play a DVD.
///
/// The Apple builds come from MPVKit, whose enabled-features list has no
/// `dvdnav`/`dvdread` and which bundles no libdvdnav — a DVD would fail with a
/// stream error. Windows pulls the official mpv-player-windows builds, which do
/// include it, and Linux links whatever libmpv the distro ships (normally with
/// DVD support).
bool get platformSupportsDvd => !Platform.isIOS && !Platform.isMacOS;

/// Classifies [path] as a disc, or null when it is an ordinary media file.
///
/// [directoryExists] is injected so the rules stay testable without touching a
/// real filesystem; it defaults to a plain directory check.
DiscSource? detectDiscSource(String path, {bool Function(String path)? directoryExists}) {
  final exists = directoryExists ?? (p) => Directory(p).existsSync();

  final cleaned = _stripTrailingSeparators(_stripFileScheme(path));
  if (cleaned.isEmpty) return null;

  final name = _basename(cleaned).toUpperCase();

  // A disc image. Blu-ray and DVD images are indistinguishable by name — you
  // would have to parse the filesystem inside to tell them apart — so this
  // assumes Blu-ray and lets a DVD image surface as a playback error.
  if (name.endsWith('.ISO')) {
    return DiscSource(kind: DiscKind.bluray, devicePath: cleaned, mpvUri: 'bd://longest');
  }

  // The structure folder itself was picked: the device is its parent.
  if (name == 'BDMV') {
    return DiscSource(kind: DiscKind.bluray, devicePath: _dirname(cleaned), mpvUri: 'bd://longest');
  }
  if (name == 'VIDEO_TS') {
    return DiscSource(kind: DiscKind.dvd, devicePath: _dirname(cleaned), mpvUri: 'dvdnav://');
  }

  // An unpacked disc folder.
  if (exists('$cleaned/BDMV')) {
    return DiscSource(kind: DiscKind.bluray, devicePath: cleaned, mpvUri: 'bd://longest');
  }
  if (exists('$cleaned/VIDEO_TS')) {
    return DiscSource(kind: DiscKind.dvd, devicePath: cleaned, mpvUri: 'dvdnav://');
  }

  return null;
}

String _stripFileScheme(String path) => path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;

String _stripTrailingSeparators(String path) {
  var end = path.length;
  // Keep a bare "/" intact; it is a path, not a trailing separator.
  while (end > 1 && (path[end - 1] == '/' || path[end - 1] == r'\')) {
    end--;
  }
  return path.substring(0, end);
}

String _basename(String path) {
  final cleaned = _stripTrailingSeparators(path);
  final cut = cleaned.lastIndexOf(RegExp(r'[/\\]'));
  return cut < 0 ? cleaned : cleaned.substring(cut + 1);
}

String _dirname(String path) {
  final cleaned = _stripTrailingSeparators(path);
  final cut = cleaned.lastIndexOf(RegExp(r'[/\\]'));
  if (cut < 0) return '.';
  return cut == 0 ? '/' : cleaned.substring(0, cut);
}
