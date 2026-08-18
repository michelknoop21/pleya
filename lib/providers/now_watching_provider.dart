// A named parameter cannot be a private initializing formal, so the resolver
// callbacks below are assigned in the initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../media/watch_session.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/now_watching_service.dart';
import '../services/tautulli/tautulli_client.dart';
import '../utils/app_logger.dart';

/// Polls Tautulli for what is playing right now, at a tempo that follows who is
/// looking.
///
/// Two speeds, because two questions. The presence control in the app bar only
/// needs to know *whether* anyone is streaming, which can be a minute stale
/// without anyone noticing. An open panel shows progress bars, and those go
/// wrong fast, so it runs on the same five seconds the server-tasks panel
/// already uses.
///
/// Nobody looking is no traffic at all: with zero subscribers the timer is
/// cancelled rather than left ticking, and it stops again whenever the app
/// leaves the foreground.
///
/// Everything here is admin data. [enabled] is answered by the owner check the
/// caller passes in, and a false answer means no timer, no request and no
/// state, not a hidden widget over a live poller.
class NowWatchingProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  NowWatchingProvider({
    required TautulliClient? Function() client,
    required bool Function() enabled,
    int? Function()? selfUserId,
    MediaServerClient? Function()? artworkClient,
    NowWatchingService service = const NowWatchingService(),
  }) : _client = client,
       _enabled = enabled,
       _selfUserId = selfUserId,
       _artworkClient = artworkClient,
       _service = service {
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  /// How often the presence control refreshes on its own. A minute late on
  /// "someone started watching" costs nothing; a request every few seconds for
  /// a question nobody asked costs battery.
  static const Duration ambientInterval = Duration(seconds: 60);

  /// How often an open panel refreshes, matching `ServerActivitiesButton`.
  static const Duration detailInterval = Duration(seconds: 5);

  /// One failed poll keeps the last picture, since a single dropped request on
  /// a phone changing networks is not evidence that everyone stopped watching.
  /// Two in a row clears it.
  static const int failuresBeforeClearing = 2;

  final TautulliClient? Function() _client;
  final bool Function() _enabled;
  final int? Function()? _selfUserId;
  final MediaServerClient? Function()? _artworkClient;
  final NowWatchingService _service;

  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  Duration? _timerInterval;
  bool _inFlight = false;
  bool _foreground = true;
  int _ambientWatchers = 0;
  int _detailWatchers = 0;
  int _failures = 0;

  NowWatching _now = NowWatching.empty;
  NowWatching get now => _now;

  /// Whether the presence control should exist at all.
  bool get hasOthers => _now.hasOthers;

  List<WatchSession> get sessions => _now.sessions;

  /// The interval currently in force, or null when nothing is polling. Exposed
  /// for tests and for the diagnostics screen; the UI does not need it.
  Duration? get pollInterval => _timerInterval;

  /// Register a surface that only needs to know whether anyone is watching.
  /// Balance every call with [releaseAmbient].
  void watchAmbient() {
    _ambientWatchers++;
    _sync(refreshNow: _ambientWatchers == 1 && _detailWatchers == 0);
  }

  void releaseAmbient() {
    if (_ambientWatchers > 0) _ambientWatchers--;
    _sync();
  }

  /// Register an open panel or screen, which needs live progress.
  void watchDetail() {
    _detailWatchers++;
    // Opening a panel is a deliberate act, so it gets an answer immediately
    // rather than up to a minute after the last ambient tick.
    _sync(refreshNow: true);
  }

  void releaseDetail() {
    if (_detailWatchers > 0) _detailWatchers--;
    _sync();
  }

  /// Poll once outside the schedule, e.g. on pull-to-refresh.
  Future<void> refresh() => _poll();

  /// The title behind a session, so a row can open its detail page.
  ///
  /// Tautulli reports a Plex rating key and nothing the app can navigate to, so
  /// the item is fetched from the same server the artwork comes from. Null when
  /// that lookup fails, which leaves the row inert instead of opening the wrong
  /// page.
  Future<MediaItem?> resolveItem(String ratingKey) async {
    final client = _artworkClient?.call();
    if (client == null) return null;
    try {
      return await client.fetchItem(ratingKey);
    } catch (e) {
      appLogger.d('Could not resolve the title behind a session', error: e);
      return null;
    }
  }

  Duration? get _wantedInterval {
    if (!_foreground || !_enabled()) return null;
    if (_detailWatchers > 0) return detailInterval;
    if (_ambientWatchers > 0) return ambientInterval;
    return null;
  }

  void _sync({bool refreshNow = false}) {
    final wanted = _wantedInterval;

    if (wanted == null) {
      _timer?.cancel();
      _timer = null;
      _timerInterval = null;
      return;
    }

    if (_timerInterval != wanted) {
      _timer?.cancel();
      _timerInterval = wanted;
      _timer = Timer.periodic(wanted, (_) => unawaited(_poll()));
    }

    if (refreshNow) unawaited(_poll());
  }

  Future<void> _poll() async {
    if (isDisposed || _inFlight) return;
    final client = _client();
    if (client == null || !_enabled()) {
      // The answer can turn to no mid-session: a server goes offline, a profile
      // switch lands on one this user does not administer, Tautulli is
      // disconnected. Clear, forget the failure streak, and stop the timer
      // rather than leave it ticking on nothing for the rest of the session.
      _failures = 0;
      _apply(NowWatching.empty);
      _sync();
      return;
    }

    _inFlight = true;
    try {
      final result = await _service.resolve(
        client,
        selfUserId: _selfUserId?.call(),
        artworkClient: _artworkClient?.call(),
      );
      if (isDisposed) return;
      if (result == null) {
        _failures++;
        if (_failures >= failuresBeforeClearing) _apply(NowWatching.empty);
        return;
      }
      _failures = 0;
      _apply(result);
    } finally {
      _inFlight = false;
    }
  }

  void _apply(NowWatching next) {
    if (identical(next, _now)) return;
    final changed = !_sameShape(_now, next);
    _now = next;
    if (changed) safeNotifyListeners();
  }

  /// Only a poll that changed nothing at all stays silent. Anything the panel
  /// draws counts, [WatchSession.sameRender] included: a comparison narrowed to
  /// the fields the app bar happens to use spares it a repaint every five
  /// seconds and leaves the open panel with a countdown standing still.
  static bool _sameShape(NowWatching a, NowWatching b) {
    if (a.sessions.length != b.sessions.length) return false;
    if (a.totalBandwidthKbps != b.totalBandwidthKbps) return false;
    if (a.lanBandwidthKbps != b.lanBandwidthKbps) return false;
    if (a.wanBandwidthKbps != b.wanBandwidthKbps) return false;
    if (a.ownSessionCount != b.ownSessionCount) return false;
    for (var i = 0; i < a.sessions.length; i++) {
      if (!WatchSession.sameRender(a.sessions[i], b.sessions[i])) return false;
    }
    return true;
  }

  void _onLifecycle(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    // Coming back from the background asks straight away: whatever was on
    // screen when the phone went in a pocket is worthless now.
    _sync(refreshNow: foreground);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lifecycle.dispose();
    super.dispose();
  }
}
