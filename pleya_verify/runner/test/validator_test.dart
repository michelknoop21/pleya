import 'dart:io';

import 'package:pleya_verify_runner/src/scenario/automation_id_catalog.dart';
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
}
