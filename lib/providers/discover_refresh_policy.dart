import 'dart:async';

import '../utils/app_logger.dart';

/// Returning to Home (tab switch, back from the player or a detail page, app
/// resume) reloads the rows when they are older than this.
const kHomeRefreshOnReturn = Duration(minutes: 2);

/// While Home is on screen and the app is in the foreground, a silent reload
/// runs at most this often. Also the default threshold of
/// `DiscoverProvider.refreshIfStale`.
const kHomeRefreshInterval = Duration(minutes: 5);

/// When the Home rows were last fully loaded, measured on an injectable clock
/// so tests can move time without waiting.
class DiscoverRefreshPolicy {
  DiscoverRefreshPolicy({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _lastFullLoadAt;

  /// Called at the end of a load in which every client answered every surface.
  void markFullLoad() => _lastFullLoadAt = _now();

  /// Whether a full reload is due. Content that never finished a full load
  /// (a snapshot whose network pass failed) counts as stale once it is on
  /// screen; with nothing on screen the initial load belongs to whoever
  /// started it, not to this check.
  bool isStale(Duration maxAge, {required bool hasContent}) {
    final last = _lastFullLoadAt;
    if (last == null) return hasContent;
    return _now().difference(last) >= maxAge;
  }
}

/// One full load pass's bookkeeping: which surfaces every asked server
/// answered. Only a complete pass counts as a full load (so a missing server
/// is asked again on the next trigger), and a silent pass keeps a surface as
/// it was when a server did not answer it: the rows on screen beat a partial
/// list.
class DiscoverPassAudit {
  DiscoverPassAudit({required this.silent, required Set<String> Function() asked}) : _asked = asked;

  final bool silent;
  final Set<String> Function() _asked;
  bool _complete = true;

  bool get complete => _complete;

  /// Whether to keep the old [surface] instead of the answer in [succeeded].
  bool keepOld(Set<String> succeeded, String surface) {
    final missing = _asked().difference(succeeded);
    if (missing.isEmpty) return false;
    _complete = false;
    if (!silent) return false;
    appLogger.w('DiscoverProvider: silent refresh kept $surface, no answer from $missing');
    return true;
  }
}

/// Fires [onTick] every [interval] while [update] says Home is active. Owned
/// by the Home screen, which knows both halves of "active": the destination is
/// on screen and the app is in the foreground.
class HomeRefreshTicker {
  HomeRefreshTicker(this.onTick, {this.interval = kHomeRefreshInterval});

  final void Function() onTick;
  final Duration interval;
  Timer? _timer;

  bool get isRunning => _timer != null;

  void update({required bool active}) {
    if (active == isRunning) return;
    if (active) {
      _timer = Timer.periodic(interval, (_) => onTick());
    } else {
      dispose();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
