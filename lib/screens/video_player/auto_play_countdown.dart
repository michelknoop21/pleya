import 'dart:async';

/// One-second countdown that drives the Play Next card.
///
/// Idle is [remaining] `== -1`, which the card reads as "no countdown" — so a
/// prompt shown before the auto-play setting is known cannot flash a stale
/// number. [start] resets the value, ticks it down once a second and fires
/// [onElapsed] exactly once at zero; the timer is stopped before that callback
/// runs, so a re-entrant [start] from inside it behaves.
class AutoPlayCountdown {
  AutoPlayCountdown({this.seconds = 5});

  /// Value the countdown starts at.
  final int seconds;

  Timer? _timer;
  int _remaining = -1;

  /// Seconds left, or -1 while idle.
  int get remaining => _remaining;

  /// Whether a countdown is currently ticking.
  bool get isActive => _timer?.isActive == true;

  /// (Re)start the countdown. [onTick] fires for the initial value and for
  /// every second after it; [onElapsed] fires once when it reaches zero.
  void start({required void Function() onTick, required void Function() onElapsed}) {
    cancel();
    _remaining = seconds;
    onTick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remaining--;
      if (_remaining <= 0) {
        cancel();
        onTick();
        onElapsed();
        return;
      }
      onTick();
    });
  }

  /// Stop ticking and return to idle.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _remaining = -1;
  }
}
