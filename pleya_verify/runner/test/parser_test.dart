import 'dart:io';

import 'package:pleya_verify_runner/src/scenario/parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses a valid scenario into name/target/setup/steps', () {
    final scenario = parseScenarioFile(File('test/fixtures/valid_scenario.yaml'));
    expect(scenario.name, 'fixture.valid_scenario');
    expect(scenario.target, 'macos');
    expect(scenario.setup.map((s) => s.verb), ['reset_app', 'seed']);
    expect(scenario.steps.map((s) => s.verb), ['press', 'wait_until', 'assert', 'assert']);
  });

  test('a bare verb has null args and the correct 1-based line', () {
    final scenario = parseScenarioFile(File('test/fixtures/valid_scenario.yaml'));
    final resetApp = scenario.setup.first;
    expect(resetApp.args, isNull);
    expect(resetApp.line, 4); // `  - reset_app` is line 4 in the fixture.
  });

  test('a single-value verb args round-trips the scalar', () {
    final scenario = parseScenarioFile(File('test/fixtures/valid_scenario.yaml'));
    final seed = scenario.setup[1];
    expect(seed.args, 'catalog.shows.v1');
  });

  test('a map-value verb args round-trips as a plain Map', () {
    final scenario = parseScenarioFile(File('test/fixtures/valid_scenario.yaml'));
    final waitUntil = scenario.steps[1];
    expect(waitUntil.args, {'event': 'focus.changed', 'timeout': 5000});
  });

  test('missing name fails with a ScenarioParseException', () {
    expect(
      () => parseScenarioString('target: macos\nsteps:\n  - press: down\n', sourcePath: 'inline.yaml'),
      throwsA(isA<ScenarioParseException>()),
    );
  });

  test('missing steps fails with a ScenarioParseException', () {
    expect(
      () => parseScenarioString('name: x\ntarget: macos\n', sourcePath: 'inline.yaml'),
      throwsA(isA<ScenarioParseException>()),
    );
  });

  test('a setup/step entry with two keys fails with file+line', () {
    const yaml = 'name: x\ntarget: macos\nsteps:\n  - press: down\n    tap: {x: 1, y: 2}\n';
    try {
      parseScenarioString(yaml, sourcePath: 'inline.yaml');
      fail('expected ScenarioParseException');
    } on ScenarioParseException catch (e) {
      expect(e.error.sourcePath, 'inline.yaml');
      expect(e.error.line, 4);
      expect(e.error.message, contains('exactly one verb key'));
    }
  });
}
