/// Guards the "capture prior value → apply override → restore on release"
/// pattern (hold-to-2x rate, background pause, etc.) against the bug class
/// where a re-entrant start overwrites the captured prior value with the
/// already-overridden one, making the override stick forever.
///
/// Rules enforced:
/// - [engage] captures at most once; re-entrant calls are no-ops (`false`).
/// - [release] returns the captured value exactly once and re-arms.
class TemporaryOverride<T> {
  bool _active = false;
  T? _prior;

  bool get isActive => _active;

  /// Captured prior value while active, else null.
  T? get prior => _active ? _prior : null;

  /// Capture [current] as the value to restore later. Returns false (and
  /// keeps the original capture) when already engaged.
  bool engage(T current) {
    if (_active) return false;
    _active = true;
    _prior = current;
    return true;
  }

  /// End the override: returns the captured prior value, or null when not
  /// engaged (double release is a safe no-op).
  T? release() {
    if (!_active) return null;
    _active = false;
    final value = _prior;
    _prior = null;
    return value;
  }
}
