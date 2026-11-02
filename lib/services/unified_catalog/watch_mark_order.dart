/// Which mark came last, per item. Marks and settled plays reach their copies
/// after a lookup that can take seconds, and two of them can answer in the
/// wrong order: the older one must not win on the copy.
library;

class WatchMarkOrder {
  WatchMarkOrder._();

  static const int _capacity = 256;
  static final Map<String, int> _latest = {};
  static int _clock = 0;

  static int get now => _clock;

  /// Records a mark on [key] and answers its stamp.
  static int next(String key) {
    _latest.remove(key);
    _latest[key] = ++_clock;
    if (_latest.length > _capacity) _latest.remove(_latest.keys.first);
    return _clock;
  }

  static bool isLatest(String key, int stamp) => _latest[key] == stamp;

  /// Whether [key] was marked after [stamp].
  static bool markedAfter(String key, int stamp) => (_latest[key] ?? 0) > stamp;
}
