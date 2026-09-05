/// The `walk:` step's grammar, parsed once and read by both the validator and
/// the engine — the same split `remote_keys.dart` uses for `press:`, and for
/// the same reason: a malformed step must fail in the millisecond the file is
/// read, not three minutes into a booted simulator with the app already in
/// some other state.
library;

/// A parsed `walk:` step.
///
/// A walk presses [direction] up to [steps] times and judges every hop. What
/// it is looking for is a landing that is not the one a viewer would expect —
/// see `pleya_verify/focus_walk/SPEC.md`.
class WalkStep {
  final String direction;

  /// How many presses. Equal to `expect.length` when [expect] is given.
  final int steps;

  final Duration timeout;

  /// How long to let the app settle after each press before measuring. 400 ms
  /// covers a rail's scroll animation; a vertical walk over rails usually
  /// wants more.
  final Duration settle;

  /// Stop early, green, once this id has the focus. Mutually exclusive with
  /// [expect].
  final String? stopAt;

  /// Where every hop must land, in order. This is how a scenario states an
  /// intended jump: a hop that matches its entry is exempt from the
  /// forwardness check, never from the skipped-candidate check.
  final List<String> expect;

  /// Candidates that may be passed over, by automation id.
  final List<String> allow;

  const WalkStep({
    required this.direction,
    required this.steps,
    required this.timeout,
    required this.settle,
    this.stopAt,
    this.expect = const [],
    this.allow = const [],
  });

  @override
  String toString() => 'walk($direction x$steps)';
}

class WalkArgsException implements Exception {
  final String message;

  const WalkArgsException(this.message);

  @override
  String toString() => message;
}

const Set<String> _walkKeys = {'direction', 'steps', 'timeout', 'settle', 'stopAt', 'expect', 'allow'};
const Set<String> _walkDirections = {'up', 'down', 'left', 'right'};
const int _defaultSettleMs = 400;

WalkStep parseWalkArgs(Object? args) {
  if (args is! Map) {
    throw WalkArgsException('walk takes a map, as in `walk: {direction: right, steps: 5, timeout: 5000}`, got: $args');
  }
  final unknown = args.keys.where((k) => !_walkKeys.contains(k)).toList();
  if (unknown.isNotEmpty) {
    throw WalkArgsException(
      "walk does not accept ${unknown.map((k) => "'$k'").join(', ')} — valid fields are "
      '${(_walkKeys.toList()..sort()).join(', ')}',
    );
  }

  final direction = args['direction'];
  if (direction is! String || !_walkDirections.contains(direction)) {
    throw WalkArgsException(
      "walk needs a 'direction' of ${(_walkDirections.toList()..sort()).join(', ')}, got '$direction'",
    );
  }

  final expect = _stringList(args['expect'], 'expect');
  final allow = _stringList(args['allow'], 'allow');
  final stopAt = args['stopAt'];
  if (stopAt != null && stopAt is! String) {
    throw WalkArgsException("walk 'stopAt' names one automation id, got '$stopAt'");
  }
  if (stopAt != null && expect.isNotEmpty) {
    throw WalkArgsException(
      "walk cannot carry both 'stopAt' and 'expect' — the first says where to stop, the second says where every "
      'hop lands, and a walk that claims both is two different tests',
    );
  }

  final stepsRaw = args['steps'];
  final int steps;
  if (expect.isNotEmpty) {
    if (stepsRaw != null && stepsRaw != expect.length) {
      throw WalkArgsException(
        "walk 'steps' ($stepsRaw) disagrees with the ${expect.length} landings in 'expect'; leave steps out",
      );
    }
    steps = expect.length;
  } else {
    if (stepsRaw is! int || stepsRaw <= 0) {
      throw WalkArgsException(
        "walk needs a positive 'steps' count (or an 'expect' list, whose length is the count), got '$stepsRaw'",
      );
    }
    steps = stepsRaw;
  }

  final timeout = args['timeout'];
  if (timeout is! int || timeout <= 0) {
    throw WalkArgsException("walk requires a positive 'timeout' in milliseconds, got '$timeout'");
  }
  final settle = args['settle'] ?? _defaultSettleMs;
  if (settle is! int || settle < 0) {
    throw WalkArgsException("walk 'settle' is a whole number of milliseconds, got '$settle'");
  }

  return WalkStep(
    direction: direction,
    steps: steps,
    timeout: Duration(milliseconds: timeout),
    settle: Duration(milliseconds: settle),
    stopAt: stopAt as String?,
    expect: expect,
    allow: allow,
  );
}

/// Every automation id a `walk:` step names.
///
/// `stopAt`, `expect` and `allow` hold bare ids rather than `{id: ...}` maps,
/// so the validator's generic `id:`-walker cannot see them. Without this a
/// typo in an `expect` list would validate fine and then fail as a landing
/// mismatch minutes later, blaming the app for a scenario's spelling.
Iterable<String> walkIdRefs(Object? args) sync* {
  if (args is! Map) return;
  if (args['stopAt'] case final String id) yield id;
  for (final key in ['expect', 'allow']) {
    if (args[key] case final List list) {
      for (final entry in list) {
        if (entry is String) yield entry;
      }
    }
  }
}

List<String> _stringList(Object? raw, String field) {
  if (raw == null) return const [];
  if (raw is! List || raw.any((e) => e is! String)) {
    throw WalkArgsException("walk '$field' is a list of automation ids, got '$raw'");
  }
  return raw.cast<String>();
}
