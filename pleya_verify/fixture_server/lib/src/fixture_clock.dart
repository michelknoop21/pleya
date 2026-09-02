/// A deterministic clock for [PleyaFakeServer]'s dynamic, control-plane-
/// driven content (e.g. `add_episode`'s `added_at`). Starts at a fixed
/// moment and only moves when told to — never off `DateTime.now()`, so two
/// runs that make the same calls produce byte-identical timestamps.
///
/// Content built once at fixture setup (the named `catalog.*` fixtures, the
/// existing hardcoded ISO strings in [PleyaFakeServer]) does not need this —
/// a fixed string literal is already deterministic. This exists for content
/// created *during* a scenario, where there is no literal to hardcode.
class FixtureClock {
  FixtureClock([DateTime? start]) : _start = _normalize(start), _now = _normalize(start);

  static DateTime _normalize(DateTime? start) => (start ?? DateTime.utc(2026, 1, 1)).toUtc();

  final DateTime _start;
  DateTime _now;

  DateTime get now => _now;

  /// Moves the clock forward. Never backward — a scenario's timestamps stay
  /// monotonic, matching every other monotonic `seq`/cursor in Pleya Verify.
  void advance(Duration by) {
    if (by.isNegative) {
      throw ArgumentError.value(by, 'by', 'FixtureClock only advances forward');
    }
    _now = _now.add(by);
  }

  /// Restores the moment this clock was constructed with — used by
  /// [PleyaFakeServer.reset] between scenarios.
  void resetToStart() {
    _now = _start;
  }
}
