/// Coarse bucket for a raw mpv/transcoder error line, so the player can show
/// one short, actionable sentence instead of the raw log text. Keeping the
/// pattern-matching bounded to [classifyPlaybackFailure] means mpv-specific
/// heuristics live in exactly one place instead of spreading `contains()`
/// checks across the player screen.
enum PlaybackFailureKind {
  /// The server answered, but the media file itself is out of reach: a disk
  /// that did not mount after a reboot, a share that is offline, a file that
  /// was moved. Plex tells us up front via `checkFiles=1`; Jellyfin only
  /// tells us by answering 404 on the stream URL.
  fileUnavailable,
  segmentUnavailable,
  connectionLost,
  codecUnsupported,
  serverError,
  unknown,
}

/// Classifies [rawMessage] (an mpv log line or player error text, possibly
/// several recent lines joined) into a [PlaybackFailureKind]. The raw text
/// itself is never shown to the user — only the classification is; the
/// caller logs the original line separately.
PlaybackFailureKind classifyPlaybackFailure(String rawMessage) {
  final m = rawMessage.toLowerCase();
  if (m.contains('http 500') || m.contains('server error') || m.contains(': 500')) {
    return PlaybackFailureKind.serverError;
  }
  if (m.contains('codec') || m.contains('unsupported') || m.contains('decoder')) {
    return PlaybackFailureKind.codecUnsupported;
  }
  // A 404 on the whole file is a different story from a 404 on one HLS
  // segment: the first means the server cannot find the media at all, the
  // second is a transcoder that is behind. Only the whole-file case gets
  // the "file unavailable" wording, so an HLS hiccup keeps its own message.
  if (_looksLikeMissingFile(m) && !_looksLikeHlsFragment(m)) {
    return PlaybackFailureKind.fileUnavailable;
  }
  if (m.contains('segment') || m.contains('.ts') || m.contains('404') || m.contains('playlist')) {
    return PlaybackFailureKind.segmentUnavailable;
  }
  if (m.contains('connection') ||
      m.contains('reset') ||
      m.contains('timed out') ||
      m.contains('timeout') ||
      m.contains('refused') ||
      m.contains('unreachable')) {
    return PlaybackFailureKind.connectionLost;
  }
  return PlaybackFailureKind.unknown;
}

bool _looksLikeMissingFile(String m) =>
    m.contains('404') ||
    m.contains('not found') ||
    m.contains('no such file') ||
    m.contains('file not found') ||
    m.contains('does not exist') ||
    m.contains('enoent');

/// Whether the failure is about one piece of a stream rather than the media.
///
/// A bare `.ts` deliberately does not qualify on its own. It is both an HLS
/// segment extension and a perfectly ordinary container for a recorded
/// broadcast, so treating it as HLS made "no such file: Nieuws.ts" read as
/// "the transcoder is behind" — over exactly the unmounted-disk case DEC-078
/// added the file-unavailable wording for. A real segment failure carries the
/// vocabulary of one: the playlist it came from, or the word itself.
bool _looksLikeHlsFragment(String m) => m.contains('.m3u8') || m.contains('segment') || m.contains('playlist');
