/// Setup vocabulary — disjoint from [stepVerbs] per [C9]: a scenario's
/// `setup:` block only prepares state, it never presses keys or asserts.
///
/// `set_pref` and `focus` used to be advertised here with no engine case in
/// `run_scenario.dart` and no defined semantics anywhere — a scenario using
/// either validated fine and only found out it was unimplemented after a
/// full build, install and launch (`UnsupportedError`). Removed rather than
/// implemented: nothing defines what either verb should actually do. Add
/// them back only alongside a real engine case and a real contract for what
/// they mean.
const Set<String> setupVerbs = {'reset_app', 'seed', 'sign_in', 'open', 'install', 'launch', 'fixture_mutate'};

/// Step vocabulary — disjoint from [setupVerbs].
///
/// `back` had the same problem as `set_pref`/`focus` above — advertised,
/// validated, never implemented, never defined — and is removed for the
/// same reason.
const Set<String> stepVerbs = {'press', 'tap', 'type', 'wait_until', 'assert', 'snapshot', 'settle', 'fixture_mutate', 'overlay'};

/// One entry of a scenario's `setup:` or `steps:` list.
///
/// `args` is whatever followed the verb: `null` for a bare verb
/// (`- reset_app`), the scalar value for a single-value verb
/// (`- seed: catalog.shows.v1` -> `'catalog.shows.v1'`), or a
/// `Map<String, Object?>` for a verb with named fields
/// (`- wait_until: {event: focus.changed, timeout: 5000}`).
class ScenarioStep {
  final String verb;
  final Object? args;

  /// 1-based line in the source file, for error messages.
  final int line;

  const ScenarioStep({required this.verb, required this.args, required this.line});

  @override
  String toString() => 'ScenarioStep($verb, line: $line)';
}

/// A parsed (not yet validated) scenario file.
class Scenario {
  final String name;
  final String target;
  final List<ScenarioStep> setup;
  final List<ScenarioStep> steps;
  final String sourcePath;

  const Scenario({
    required this.name,
    required this.target,
    required this.setup,
    required this.steps,
    required this.sourcePath,
  });
}

/// A malformed or invalid scenario — carries enough to print
/// `file:line: message`, per the plan's requirement that a misplaced verb
/// fails with "bestandsnaam, regelnummer en uitleg".
class ScenarioError {
  final String sourcePath;
  final int? line;
  final String message;

  const ScenarioError({required this.sourcePath, this.line, required this.message});

  @override
  String toString() => line != null ? '$sourcePath:$line: $message' : '$sourcePath: $message';
}
