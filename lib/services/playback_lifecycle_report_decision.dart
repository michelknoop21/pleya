/// Whether a lifecycle transition should flush a final playback report.
enum PlaybackLifecycleReport {
  /// Write nothing. Either there is nothing new to say, or this player is no
  /// longer the one allowed to say it.
  none,

  /// Send exactly one `stopped` report and no more.
  finalReport,
}

/// Decides what the background, detach and dispose paths write.
///
/// Kept apart from the widget so the rules can be read, and tested, without a
/// player, a route or a lifecycle observer. The rules are few and the reason
/// each exists is specific:
///
///  * a revoked authority writes nothing at all, because its position predates
///    whatever took over;
///  * a position that has not moved since the last report has nothing to add,
///    and re-sending it is precisely the write that used to roll a further-along
///    device back;
///  * a player that was still playing writes once even at an unchanged
///    position, so the backend stops showing the session as live. That report
///    cannot roll anything back: it repeats a position already sent.
class PlaybackLifecycleReportDecision {
  const PlaybackLifecycleReportDecision._();

  static PlaybackLifecycleReport resolve({
    required bool authorityHeld,
    required bool wasPlaying,
    required bool positionChanged,
  }) {
    if (!authorityHeld) return PlaybackLifecycleReport.none;
    if (positionChanged) return PlaybackLifecycleReport.finalReport;
    if (wasPlaying) return PlaybackLifecycleReport.finalReport;
    return PlaybackLifecycleReport.none;
  }
}
