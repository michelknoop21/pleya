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

  /// Whether a lifecycle transition that was queued earlier has been overtaken
  /// by the app coming back to the foreground.
  ///
  /// tvOS delivers `hidden`, `inactive` and `resumed` within a couple of
  /// milliseconds when the app returns, and lifecycle transitions run one after
  /// another, so the background handler can execute while the app is already on
  /// screen. On a device that pauses the player and ends the Plex session, that
  /// is a stop sent to a session that is playing: the server drops the stream
  /// from its dashboard and, because a stopped session is terminal, everything
  /// after it goes unreported.
  ///
  /// Only a *foreground* newer event supersedes. A `hidden` followed by
  /// `paused` is the ordinary way into the background and must still run.
  static bool isTransitionSuperseded({
    required int enqueuedSequence,
    required int latestSequence,
    required bool latestIsForeground,
  }) => latestSequence != enqueuedSequence && latestIsForeground;
}
