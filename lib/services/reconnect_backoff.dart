/// How long an automatic reconnect sweep leaves a server alone after it
/// stayed unreachable.
///
/// Every resume, health sweep and retry used to race all endpoint candidates
/// of a server that was simply down: about two seconds and a dozen requests
/// each time, for as long as the server stayed away. The first failed race is
/// followed by the next attempt at once, because that second try is what
/// catches a network stack that was not awake yet. From the second failure on
/// the wait doubles, up to [maxWait].
///
/// A different network ([reset]) or a user asking to reconnect clears it; a
/// success ([succeeded]) too.
class ReconnectBackoff {
  ReconnectBackoff({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const firstWait = Duration(seconds: 10);
  static const maxWait = Duration(minutes: 2);

  final Map<String, ({int failures, DateTime retryAt, DateTime failedAt})> _state = {};

  /// A full candidate race found no working endpoint for [serverId].
  void failed(String serverId) {
    final failures = (_state[serverId]?.failures ?? 0) + 1;
    final wait = failures < 2 ? Duration.zero : _waitFor(failures);
    final now = _now();
    _state[serverId] = (failures: failures, retryAt: now.add(wait), failedAt: now);
  }

  void succeeded(String serverId) => _state.remove(serverId);

  /// Forgets everything: the network changed, or somebody asked to retry.
  void reset() => _state.clear();

  /// How much longer an automatic sweep should leave [serverId] alone, or
  /// null when it may be tried now.
  ///
  /// A failure younger than [justFailed] does not count: the second attempt
  /// of a resume exists to catch a network stack that was not awake for the
  /// first, so it must not be blocked by the wait that first failure set.
  Duration? remaining(String serverId, {Duration justFailed = Duration.zero}) {
    final state = _state[serverId];
    if (state == null) return null;
    if (_now().difference(state.failedAt) < justFailed) return null;
    final left = state.retryAt.difference(_now());
    return left > Duration.zero ? left : null;
  }

  static Duration _waitFor(int failures) {
    // failures >= 2: 10s, 20s, 40s, 80s, then the cap.
    final doublings = failures - 2;
    if (doublings >= 4) return maxWait;
    final wait = firstWait * (1 << doublings);
    return wait > maxWait ? maxWait : wait;
  }
}
