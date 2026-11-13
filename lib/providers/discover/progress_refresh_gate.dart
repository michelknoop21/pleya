import '../../utils/watch_state_notifier.dart';

/// Decides whether a watch event is worth refetching Verder kijken for.
///
/// A running play reports progress every ten to forty seconds, and each report
/// used to refetch the row from every server: 92 times in a 68 minute session
/// on Apple TV, for a row nobody was looking at. The first report of a play
/// still refreshes (a rewatch has to surface), and so does the report that
/// ends it or crosses the watched threshold. The reports in between do not:
/// they change nothing the row shows that the closing report will not correct.
///
/// A report counts as "in between" while reports for the same title keep
/// arriving within [quietWindow] of each other. A separate one-shot report (an
/// external player, a copy mirrored from another server) therefore always
/// refreshes, unless it follows a report for that title this closely.
class ProgressRefreshGate {
  ProgressRefreshGate({this.quietWindow = const Duration(seconds: 90), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration quietWindow;
  final DateTime Function() _now;

  final Map<String, DateTime> _lastReport = {};
  final Set<String> _reportedWatched = {};

  bool shouldRefresh(WatchStateEvent event) {
    final key = event.globalKey;
    if (event.changeType != WatchStateChangeType.progressUpdate || event.isFinal) {
      _lastReport.remove(key);
      _reportedWatched.remove(key);
      return true;
    }
    final now = _now();
    final last = _lastReport[key];
    // A one-shot report (a mirrored copy, an external player) has no closing
    // report to clear it, so what went quiet is dropped here.
    if (_lastReport.length > 64) {
      _lastReport.removeWhere((_, at) => now.difference(at) >= quietWindow);
      _reportedWatched.retainAll(_lastReport.keys);
    }
    _lastReport[key] = now;
    // Crossing the watched threshold changes what the row shows; once.
    if (event.isNowWatched == true && _reportedWatched.add(key)) return true;
    return last == null || now.difference(last) >= quietWindow;
  }
}
