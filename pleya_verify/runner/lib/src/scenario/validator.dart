import '../engine/geometry_assertions.dart';
import '../engine/node_assertions.dart';
import 'automation_id_catalog.dart';
import 'automation_id_grammar.dart';
import 'model.dart';
import 'remote_keys.dart';
import 'walk_args.dart';

/// Structurally validates an already-parsed [Scenario]: the disjoint
/// setup/step vocabularies ([C9]), the tvOS tap-forbidden rule ([C2] —
/// `tap` has no meaning on a target with no touch surface, and more to the
/// point no scenario step may claim a route `TvosSimulatorDriver` doesn't
/// take), a required `timeout` on every `wait_until`, and that every `id:`
/// a step references exists in [catalog] — instance-suffixed
/// (`base[instance]`) only when the base id is `instanceable: true`. And an
/// `assert:` may only carry predicates the engine actually evaluates, with
/// values of the type it reads — an ignored key or a skipped value turns the
/// step into a green verdict for a claim never checked, which is the one
/// failure mode a verification tool must not have.
///
/// Returns an empty list when the scenario is valid.
List<ScenarioError> validateScenario(Scenario scenario, AutomationIdCatalog catalog) {
  final errors = <ScenarioError>[];

  for (final step in scenario.setup) {
    _validateVerb(
      step,
      scenario,
      allowed: setupVerbs,
      otherVocabulary: stepVerbs,
      otherVocabularyName: 'step',
      errors: errors,
    );
    _validateStepBody(step, scenario, catalog, errors);
  }

  for (final step in scenario.steps) {
    _validateVerb(
      step,
      scenario,
      allowed: stepVerbs,
      otherVocabulary: setupVerbs,
      otherVocabularyName: 'setup',
      errors: errors,
    );
    if (step.verb == 'tap' && _isTvosTarget(scenario.target)) {
      errors.add(
        ScenarioError(
          sourcePath: scenario.sourcePath,
          line: step.line,
          message:
              "'tap' is not a valid step on a tvOS target — tvOS has no touch surface in this API "
              '(see the tvOS-invoerroute-invariant, [C2])',
        ),
      );
    }
    if (step.verb == 'wait_until') {
      final args = step.args;
      if (args is! Map || !args.containsKey('timeout')) {
        errors.add(
          ScenarioError(
            sourcePath: scenario.sourcePath,
            line: step.line,
            message: 'wait_until requires a timeout field',
          ),
        );
      }
    }
    if (step.verb == 'press') {
      _validatePress(step, scenario, errors);
    }
    if (step.verb == 'assert') {
      _validateAssert(step, scenario, errors);
    }
    if (step.verb == 'walk') {
      _validateWalk(step, scenario, errors);
    }
    _validateStepBody(step, scenario, catalog, errors);
  }

  return errors;
}

void _validateVerb(
  ScenarioStep step,
  Scenario scenario, {
  required Set<String> allowed,
  required Set<String> otherVocabulary,
  required String otherVocabularyName,
  required List<ScenarioError> errors,
}) {
  if (allowed.contains(step.verb)) return;
  final message = otherVocabulary.contains(step.verb)
      ? "'${step.verb}' is a $otherVocabularyName verb, not valid here"
      : "unknown verb '${step.verb}'";
  errors.add(ScenarioError(sourcePath: scenario.sourcePath, line: step.line, message: message));
}

void _validateStepBody(ScenarioStep step, Scenario scenario, AutomationIdCatalog catalog, List<ScenarioError> errors) {
  for (final ref in _findIdRefs(step.args)) {
    final parsed = parseAutomationIdRef(ref);
    if (!catalog.contains(parsed.base)) {
      errors.add(
        ScenarioError(
          sourcePath: scenario.sourcePath,
          line: step.line,
          message: "unknown automation id '${parsed.base}' (from '$ref')",
        ),
      );
    } else if (parsed.instance != null && !catalog.isInstanceable(parsed.base)) {
      errors.add(
        ScenarioError(
          sourcePath: scenario.sourcePath,
          line: step.line,
          message: "'${parsed.base}' is not instanceable, so '$ref' is invalid",
        ),
      );
    }
  }
}

/// Walks a step's `args` (a scalar, a `Map`, or a `List`, arbitrarily
/// nested) for every `id:` field, so `assert: {node: {id: ...}}` is caught
/// the same as a top-level `assert: {id: ...}`.
///
/// A binary geometry predicate's value is an automation id too
/// (`notOverlapping: sidebar.rail`), just not under an `id` key. Those are
/// yielded as well, so a typo there fails validation in milliseconds rather
/// than after a full build, install and launch — the same reason every other
/// id reference is checked here.
Iterable<String> _findIdRefs(Object? args) sync* {
  if (args is Map) {
    // `walk`'s `stopAt`/`expect`/`allow` hold bare ids, not `{id: ...}` maps.
    yield* walkIdRefs(args);
    for (final entry in args.entries) {
      if (entry.key == 'id' && entry.value is String) yield entry.value as String;
      if (binaryGeometryPredicates.contains(entry.key) && entry.value is String) yield entry.value as String;
      yield* _findIdRefs(entry.value);
    }
  } else if (args is List) {
    for (final item in args) {
      yield* _findIdRefs(item);
    }
  }
}

/// A `press` names a key from the one shared remote vocabulary, and may only
/// ask for a hold on a target that can actually hold a key down.
///
/// Both halves move a failure that used to need a full build, install and
/// launch into the millisecond the file is read. `scripts/tvos_sim.sh` dies
/// with `onbekende toets` on a typo, and `/v1/input/key` answers 400
/// `unknownKey` — both of them minutes after the run started, and both after
/// the scenario has already changed the app's state.
void _validatePress(ScenarioStep step, Scenario scenario, List<ScenarioError> errors) {
  final PressStep press;
  try {
    press = parsePressArgs(step.args);
  } on PressArgsException catch (e) {
    errors.add(ScenarioError(sourcePath: scenario.sourcePath, line: step.line, message: e.message));
    return;
  }
  if (press.isLongPress && !_isTvosTarget(scenario.target)) {
    errors.add(
      ScenarioError(
        sourcePath: scenario.sourcePath,
        line: step.line,
        message:
            "a long press ('holdMs') is only supported on a tvOS target — '${scenario.target}' presses through "
            '/v1/input/key, which synthesizes one indivisible key press with no down/up split, so a hold there '
            'would silently be an ordinary press',
      ),
    );
  }
}

bool _isTvosTarget(String target) => target.contains('tvos');

/// Every key an `assert:` step may carry at the top level.
Set<String> get _assertKeys => {'id', ...geometryPredicates, ...nodeFieldPredicates};

/// Catches the two shapes of assert that pass while checking nothing.
///
/// An `assert:` step evaluates each predicate it recognizes and ignores the
/// rest, so a step whose only predicate is misspelled — `focussed`, `state s`,
/// `insideViewPort` — succeeds on presence alone and records a green verdict
/// for a claim nobody made. The same happens one level down: `focused` is read
/// as a boolean, and `yes`, `on` and `"true"` are all strings in the YAML 1.2
/// core schema `package:yaml` implements, so the habit carried over from
/// YAML 1.1 writes an assertion that is silently skipped.
///
/// `evaluateNodeAssertions` now raises on the value half at run time as well,
/// which is the backstop for args a scenario file did not spell out (a
/// `{{fixture_id:...}}` placeholder resolves after validation). This is the
/// millisecond-cost half: both mistakes are visible in the file, and finding
/// them there beats finding them after a build, an install and a launch —
/// the same reason `_validatePress` checks key names here.
void _validateAssert(ScenarioStep step, Scenario scenario, List<ScenarioError> errors) {
  final args = step.args;
  if (args is! Map) {
    errors.add(
      ScenarioError(
        sourcePath: scenario.sourcePath,
        line: step.line,
        message: 'assert needs a map with an id, got: $args',
      ),
    );
    return;
  }
  if (!args.containsKey('id')) {
    errors.add(ScenarioError(sourcePath: scenario.sourcePath, line: step.line, message: 'assert requires an id field'));
  }
  for (final key in args.keys) {
    if (_assertKeys.contains(key)) continue;
    errors.add(
      ScenarioError(
        sourcePath: scenario.sourcePath,
        line: step.line,
        message:
            "unknown assert predicate '$key' — an assert ignores what it does not recognize, so this step would "
            'pass on presence alone; valid keys are ${(_assertKeys.toList()..sort()).join(', ')}',
      ),
    );
  }
  if (args.containsKey('focused') && args['focused'] is! bool) {
    errors.add(
      ScenarioError(
        sourcePath: scenario.sourcePath,
        line: step.line,
        message:
            "assert 'focused' must be an unquoted true or false — YAML reads yes, on and \"true\" as strings, "
            'and a non-boolean here is skipped rather than checked',
      ),
    );
  }
  if (args.containsKey('state')) {
    final state = args['state'];
    if (state is! Map) {
      errors.add(
        ScenarioError(
          sourcePath: scenario.sourcePath,
          line: step.line,
          message: "assert 'state' must be a map of key/value pairs, as in `state: {collapsed: true}`",
        ),
      );
    } else if (state.isEmpty) {
      errors.add(
        ScenarioError(
          sourcePath: scenario.sourcePath,
          line: step.line,
          message: "assert 'state' is empty, which claims a check and performs none",
        ),
      );
    }
  }
}

/// A `walk:` obeys its own grammar ([parseWalkArgs]) and, like `press`, is
/// checked here so a malformed one costs a millisecond instead of a build, an
/// install and a launch.
void _validateWalk(ScenarioStep step, Scenario scenario, List<ScenarioError> errors) {
  try {
    parseWalkArgs(step.args);
  } on WalkArgsException catch (e) {
    errors.add(ScenarioError(sourcePath: scenario.sourcePath, line: step.line, message: e.message));
  }
}
