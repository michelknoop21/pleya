import '../engine/geometry_assertions.dart';
import 'automation_id_catalog.dart';
import 'automation_id_grammar.dart';
import 'model.dart';
import 'remote_keys.dart';

/// Structurally validates an already-parsed [Scenario]: the disjoint
/// setup/step vocabularies ([C9]), the tvOS tap-forbidden rule ([C2] —
/// `tap` has no meaning on a target with no touch surface, and more to the
/// point no scenario step may claim a route `TvosSimulatorDriver` doesn't
/// take), a required `timeout` on every `wait_until`, and that every `id:`
/// a step references exists in [catalog] — instance-suffixed
/// (`base[instance]`) only when the base id is `instanceable: true`.
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
