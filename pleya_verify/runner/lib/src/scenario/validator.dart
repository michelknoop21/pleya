import 'automation_id_catalog.dart';
import 'automation_id_grammar.dart';
import 'model.dart';

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
Iterable<String> _findIdRefs(Object? args) sync* {
  if (args is Map) {
    for (final entry in args.entries) {
      if (entry.key == 'id' && entry.value is String) yield entry.value as String;
      yield* _findIdRefs(entry.value);
    }
  } else if (args is List) {
    for (final item in args) {
      yield* _findIdRefs(item);
    }
  }
}

bool _isTvosTarget(String target) => target.contains('tvos');
