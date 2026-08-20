/// Coarse bucket for a raw mpv/transcoder error line, so the player can show
/// one short, actionable sentence instead of the raw log text. Keeping the
/// pattern-matching bounded to [classifyPlaybackFailure] means mpv-specific
/// heuristics live in exactly one place instead of spreading `contains()`
/// checks across the player screen.
enum PlaybackFailureKind { segmentUnavailable, connectionLost, codecUnsupported, serverError, unknown }

/// Classifies [rawMessage] (an mpv log line or player error text) into a
/// [PlaybackFailureKind]. The raw text itself is never shown to the user —
/// only the classification is; the caller logs the original line separately.
PlaybackFailureKind classifyPlaybackFailure(String rawMessage) {
  final m = rawMessage.toLowerCase();
  if (m.contains('http 500') || m.contains('server error') || m.contains(': 500')) {
    return PlaybackFailureKind.serverError;
  }
  if (m.contains('codec') || m.contains('unsupported') || m.contains('decoder')) {
    return PlaybackFailureKind.codecUnsupported;
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
