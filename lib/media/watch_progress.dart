/// Single source of truth for the "progress crossed the watched threshold"
/// decision. All comparison sites (online progress events, external-player
/// returns, offline queueing) must route through this so edge-case handling
/// (zero/unknown duration, exact-threshold) can't drift between paths.
bool isWatchedProgress({required int positionMs, required int durationMs, required double threshold}) {
  if (durationMs <= 0) return false;
  return positionMs / durationMs >= threshold;
}

/// How far apart two watch-state timestamps have to be before the newer one
/// may be believed over the older.
///
/// Zero would be wrong in both places this is used. A device reports its own
/// progress while playing, so the server's timestamp for the very playback a
/// local patch describes lands within seconds of the patch itself; and two
/// servers holding the same title clock the same viewing a few seconds apart
/// through nothing but network and scrobble latency. Inside the margin the
/// timestamps do not order the sources at all — they only say "around now" —
/// and treating them as an ordering is how a clock skew of a few seconds
/// silently decides which copy a card speaks for.
///
/// Beyond the margin the difference cannot be one viewing seen twice; it is a
/// second, later viewing, and then the newer state is the better one.
///
/// One value, deliberately: `WatchStateStore.serverWinsMargin` is this
/// constant, and hoofdstuk 13.2's tier 2 in `unified_watch_state.dart` is the
/// same constant again. A second skew threshold would be a second answer to
/// one question. Matches the progress tracker's own notify delta.
const Duration watchStateReliabilityMargin = Duration(seconds: 30);
