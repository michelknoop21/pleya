import 'dart:io';

import 'package:pleya_verify_runner/src/scenario/automation_id_catalog.dart';
import 'package:pleya_verify_runner/src/scenario/model.dart';
import 'package:pleya_verify_runner/src/scenario/parser.dart';
import 'package:pleya_verify_runner/src/scenario/validator.dart';
import 'package:test/test.dart';

void main() {
  // The real, committed catalog (`AutomationIds.catalog()`'s mirror) — a
  // scenario is validated against the same ids a live app would serve from
  // `GET /v1/automation_ids`, not a test double that could drift from it.
  final catalog = AutomationIdCatalog.fromFile(File('../automation_ids.yaml'));

  test('a valid scenario has no errors', () {
    final scenario = parseScenarioFile(File('test/fixtures/valid_scenario.yaml'));
    expect(validateScenario(scenario, catalog), isEmpty);
  });

  test('a step verb in setup is rejected on file+line', () {
    final scenario = parseScenarioFile(File('test/fixtures/invalid_setup_verb.yaml'));
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.sourcePath, 'test/fixtures/invalid_setup_verb.yaml');
    expect(errors.single.line, 7);
    expect(errors.single.message, contains("'press' is a step verb"));
  });

  test('an instance suffix on a non-instanceable base id is rejected', () {
    final scenario = parseScenarioFile(File('test/fixtures/invalid_instance_not_instanceable.yaml'));
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains("'library.grid' is not instanceable"));
  });

  test('tap on a tvOS target is rejected', () {
    final scenario = parseScenarioFile(File('test/fixtures/invalid_tap_on_tvos.yaml'));
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains("'tap' is not a valid step on a tvOS target"));
  });

  test('wait_until without a timeout is rejected', () {
    final scenario = parseScenarioFile(File('test/fixtures/invalid_wait_until_no_timeout.yaml'));
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains('requires a timeout field'));
  });

  test('an assert with a mistyped predicate name is rejected', () {
    // The false-PASS this guards: presence succeeds, no handler recognizes
    // `focussed`, so the step evaluates nothing and reports green. An assert
    // that checks nothing is worse than a missing assert — it leaves a
    // passing verdict in the manifest for a claim never made.
    final scenario = parseScenarioFile(File('test/fixtures/invalid_assert_unknown_predicate.yaml'));
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains("'focussed'"));
  });

  test('an assert whose focused value is not a boolean is rejected', () {
    final scenario = parseScenarioFile(File('test/fixtures/invalid_assert_focused_type.yaml'));
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains('focused'));
  });

  test('an unknown automation id is rejected', () {
    final scenario = parseScenarioString(
      'name: x\ntarget: macos\nsteps:\n  - assert: {id: nonexistent.thing}\n',
      sourcePath: 'inline.yaml',
    );
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains("unknown automation id 'nonexistent.thing'"));
  });

  test('an id nested under a non-top-level key is still checked', () {
    final scenario = parseScenarioString(
      'name: x\ntarget: macos\nsteps:\n  - wait_until: {node: {id: nonexistent.thing}, timeout: 1000}\n',
      sourcePath: 'inline.yaml',
    );
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains("unknown automation id 'nonexistent.thing'"));
  });

  test('an unknown verb (neither vocabulary) is rejected', () {
    final scenario = parseScenarioString(
      'name: x\ntarget: macos\nsteps:\n  - swipe: left\n',
      sourcePath: 'inline.yaml',
    );
    final errors = validateScenario(scenario, catalog);
    expect(errors, hasLength(1));
    expect(errors.single.message, contains("unknown verb 'swipe'"));
  });

  group('press', () {
    Scenario press(String target, String body) =>
        parseScenarioString('name: t\ntarget: $target\nsteps:\n  - press: $body\n', sourcePath: 'test.yaml');

    test('the scalar and map forms both validate on tvOS', () {
      expect(validateScenario(press('tvos-sim', 'down'), catalog), isEmpty);
      expect(validateScenario(press('tvos-sim', '{key: select, holdMs: 1200}'), catalog), isEmpty);
    });

    test('menu validates — the Mijn Pleya audit is impossible without Back', () {
      expect(validateScenario(press('tvos-sim', 'menu'), catalog), isEmpty);
    });

    test('a malformed key is rejected on file+line, not three minutes into a booted simulator', () {
      final errors = validateScenario(press('tvos-sim', 'sideways'), catalog);
      expect(errors, hasLength(1));
      expect(errors.single.line, 4);
      expect(errors.single.message, contains("unknown remote key 'sideways'"));
    });

    test('a hold outside a tvOS target is rejected rather than silently becoming a short press', () {
      final errors = validateScenario(press('macos', '{key: select, holdMs: 900}'), catalog);
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('only supported on a tvOS target'));
    });

    test('a short press on macOS is still fine', () {
      expect(validateScenario(press('macos', 'select'), catalog), isEmpty);
    });
  });

  test('every verb setupVerbs/stepVerbs advertise has a real case in the engine switch', () {
    // A verb that validates but has no engine case only fails after a full
    // build, install and launch (see `run_scenario_test.dart`'s "verbs that
    // used to reach UnsupportedError only after a full build" — the exact
    // failure mode `set_pref`/`focus`/`back` used to have before they were
    // removed). Source-scanned rather than run through the engine, so this
    // catches the drift the moment a verb is added to one side and not the
    // other, without needing a driver/build for every verb.
    final engineSource = File('lib/src/engine/run_scenario.dart').readAsStringSync();
    final caseVerbs = RegExp(r"case '([a-z_]+)':").allMatches(engineSource).map((m) => m.group(1)!).toSet();

    final advertisedVerbs = {...setupVerbs, ...stepVerbs};

    final advertisedButNotImplemented = advertisedVerbs.difference(caseVerbs);
    expect(
      advertisedButNotImplemented,
      isEmpty,
      reason:
          'setupVerbs/stepVerbs advertise a verb with no `case` in run_scenario.dart\'s switch — a scenario '
          'using it would validate fine and only fail after a full build/install/launch',
    );

    final implementedButNotAdvertised = caseVerbs.difference(advertisedVerbs);
    expect(
      implementedButNotAdvertised,
      isEmpty,
      reason:
          'run_scenario.dart implements a verb no scenario can ever reach — it is missing from '
          'setupVerbs/stepVerbs in model.dart',
    );
  });
}
