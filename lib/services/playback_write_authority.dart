import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

/// Why the authority changed hands. Carried into logs so a lost write can be
/// traced back to the observation that caused it.
enum PlaybackAuthorityChange { taken, revoked }

/// A local observation of whether this player may still write watch state.
///
/// **This promises no exclusivity.** It is a guess assembled from what this
/// device happened to see, and it can miss or arrive late: a delayed or absent
/// socket event, a Plex notification without usable session or account
/// information, two players starting within the same instant, a connection
/// that drops. In any of those cases two devices can both believe they may
/// write. An atomically granted lease belongs on the server side (PS-4); until
/// then this only narrows the window, and the report suppression in
/// [PlaybackProgressTracker] does the rest of the work.
///
/// The rules:
///  * whoever explicitly starts, resumes or seeks takes the authority and
///    reports immediately;
///  * observing a `playing` from another session for the same item revokes it;
///    the player keeps running, it just stops writing;
///  * a revoked session sends no `progress`, no `paused` and, most importantly,
///    no `stopped` — a late stop report is what puts the old position back;
///  * resuming after a pause fetches fresh progress *first* and only then takes
///    the authority back, which is what [retakeAfterRefresh] enforces;
///  * with no observation source wired up, nothing is ever revoked. That is
///    acceptable because the removal of the paused heartbeat already takes away
///    the repeated write.
class ObservedPlaybackAuthority extends ChangeNotifier {
  ObservedPlaybackAuthority({required this.sessionId, required this.itemId});

  /// Identifies this player's playback session. Compared against the session
  /// id on an observed event so a device never revokes itself.
  final String sessionId;

  /// The item this authority is about. An event for a different item is not
  /// this player's business.
  final String itemId;

  bool _isHeld = true;
  String? _revokedBySessionId;

  /// Whether this player may still write watch state.
  bool get isHeld => _isHeld;

  bool get isRevoked => !_isHeld;

  /// The foreign session that took over, when the authority was revoked by an
  /// observation rather than by a direct [revoke] call.
  String? get revokedBySessionId => _revokedBySessionId;

  /// Take, or take back, the authority after a deliberate user action: start,
  /// resume, or seek.
  ///
  /// Resuming after a pause must call [retakeAfterRefresh] instead, so the
  /// fresh backend position is read before this player starts writing over it.
  void take({required String reason}) {
    if (_isHeld && _revokedBySessionId == null) return;
    _isHeld = true;
    _revokedBySessionId = null;
    _log(PlaybackAuthorityChange.taken, reason);
    notifyListeners();
  }

  /// Read the backend's current state, then take the authority back.
  ///
  /// The order is the point. Taking first and refreshing after leaves a window
  /// in which this player reports a position it has not yet reconciled, which
  /// is the same overwrite the whole mechanism exists to prevent. A failing
  /// refresh does not take the authority: without knowing the current state
  /// there is nothing to write safely.
  Future<void> retakeAfterRefresh(Future<void> Function() refreshBackendState, {required String reason}) async {
    await refreshBackendState();
    take(reason: reason);
  }

  /// Give up the authority. The player keeps running; it just stops writing.
  void revoke({required String reason, String? bySessionId}) {
    if (!_isHeld) return;
    _isHeld = false;
    _revokedBySessionId = bySessionId;
    _log(PlaybackAuthorityChange.revoked, reason);
    notifyListeners();
  }

  /// Handle an observed `playing` for some item on some session.
  ///
  /// Returns whether it revoked the authority. Events for another item, and
  /// events echoing this player's own session, are ignored.
  bool observeForeignPlaying({required String itemId, required String sessionId}) {
    if (itemId != this.itemId) return false;
    if (sessionId == this.sessionId) return false;
    if (!_isHeld) return false;
    revoke(reason: 'observed playing from session $sessionId', bySessionId: sessionId);
    return true;
  }

  void _log(PlaybackAuthorityChange change, String reason) {
    appLogger.i('Playback write authority ${change.name} for item $itemId (session $sessionId): $reason');
  }
}
