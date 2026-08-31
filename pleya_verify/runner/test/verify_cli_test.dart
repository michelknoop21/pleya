import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Runs `bin/verify.dart` as a real subprocess with the same `dart`
/// executable running this test — the CLI a scenario author or CI actually
/// invokes, not just the library functions it's built from.
Future<ProcessResult> _run(List<String> args) => Process.run(Platform.executable, ['run', 'bin/verify.dart', ...args]);

void main() {
  test('validate exits 0 on a valid scenario', () async {
    final result = await _run(['validate', 'test/fixtures/valid_scenario.yaml']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('OK: fixture.valid_scenario'));
  });

  test('validate exits 1 and reports file:line on an invalid scenario', () async {
    final result = await _run(['validate', 'test/fixtures/invalid_setup_verb.yaml']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('test/fixtures/invalid_setup_verb.yaml:7'));
  });

  test('validate --json emits structured errors', () async {
    final result = await _run(['validate', 'test/fixtures/invalid_wait_until_no_timeout.yaml', '--json']);
    expect(result.exitCode, 1);
    final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
    expect(decoded['ok'], false);
    final errors = decoded['errors'] as List<Object?>;
    expect(errors, hasLength(1));
    expect((errors.single as Map<String, Object?>)['message'], contains('requires a timeout field'));
  });

  test('validate --json on a scenario the parser rejects with a raw exception still emits one clean error object', () async {
    // Same backstop as the `run --json` case below, for `_runValidate`.
    final result = await _run(['validate', 'test/fixtures/malformed_yaml_syntax.yaml', '--json']);
    expect(result.exitCode, 70, reason: 'stderr: ${result.stderr}');
    final lines = (result.stdout as String).trim().split('\n');
    expect(lines, hasLength(1));
    final decoded = jsonDecode(lines.single) as Map<String, Object?>;
    expect(decoded['ok'], false);
    final errors = decoded['errors'] as List<Object?>;
    expect((errors.single as Map<String, Object?>)['message'], contains('parsing a flow mapping'));
  });

  test('validate on a missing file exits with EX_NOINPUT', () async {
    final result = await _run(['validate', 'test/fixtures/does_not_exist.yaml']);
    expect(result.exitCode, 66);
  });

  test('list targets prints the three known targets', () async {
    final result = await _run(['list', 'targets']);
    expect(result.exitCode, 0);
    expect(result.stdout, allOf(contains('macos'), contains('ios-sim'), contains('tvos-sim')));
  });

  test('list targets --json prints a JSON array', () async {
    final result = await _run(['list', 'targets', '--json']);
    expect(jsonDecode(result.stdout as String), ['macos', 'ios-sim', 'tvos-sim']);
  });

  test('list scenarios --dir on an empty/missing dir prints nothing to fail on', () async {
    final result = await _run(['list', 'scenarios', '--dir', 'test/fixtures/empty_dir_for_listing']);
    expect(result.exitCode, 0);
  });

  test('list scenarios --dir finds the fixture files', () async {
    final result = await _run(['list', 'scenarios', '--dir', 'test/fixtures']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('valid_scenario.yaml'));
  });

  test('run --json on a missing scenario file reports ERROR, not FAILED', () async {
    final result = await _run(['run', 'test/fixtures/does_not_exist.yaml', '--json']);
    expect(result.exitCode, 66);
    final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
    expect(decoded['ok'], false);
    expect(decoded['result'], 'ERROR');
    expect(decoded['scenario'], isNull);
    expect(decoded['bundle_dir'], isNull);
    expect(decoded['failure_message'], contains('no such file'));
    expect(decoded['exit_code'], 66);
    expect(decoded['command'], contains('test/fixtures/does_not_exist.yaml'));
  });

  test('run --json on a scenario with an invalid setup verb reports ERROR with the parse errors', () async {
    final result = await _run(['run', 'test/fixtures/invalid_setup_verb.yaml', '--json']);
    expect(result.exitCode, 1);
    final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
    expect(decoded['ok'], false);
    expect(decoded['result'], 'ERROR');
    final errors = decoded['errors'] as List<Object?>;
    expect(errors, isNotEmpty);
    expect((errors.single as Map<String, Object?>)['path'], 'test/fixtures/invalid_setup_verb.yaml');
  });

  test(
    'run --json on a scenario the parser rejects with a raw exception still emits one clean ERROR envelope',
    () async {
      // `test/fixtures/malformed_yaml_syntax.yaml` fails at `loadYamlNode`
      // itself — a YamlException, not the ScenarioParseException
      // `_runScenarioCommandBody`'s narrower catch expects. Before the
      // top-level dispatch/catch in bin/verify.dart, this crashed main()
      // uncaught: no JSON on stdout at all, just a stack trace and a
      // generic nonzero exit. Proves the backstop, not the narrower catch.
      final result = await _run(['run', 'test/fixtures/malformed_yaml_syntax.yaml', '--json']);
      expect(result.exitCode, 70, reason: 'stderr: ${result.stderr}');
      // Exactly one line of JSON on stdout — never a raw stack trace mixed
      // in, and never more than the single envelope the contract promises.
      final lines = (result.stdout as String).trim().split('\n');
      expect(lines, hasLength(1));
      final decoded = jsonDecode(lines.single) as Map<String, Object?>;
      expect(decoded['ok'], false);
      expect(decoded['result'], 'ERROR');
      expect(decoded['failure_message'], contains('parsing a flow mapping'));
    },
  );

  test('run --json on a scenario with no implemented driver reports ERROR with scenario/target populated', () async {
    final result = await _run(['run', 'test/fixtures/valid_scenario_unknown_target.yaml', '--json']);
    expect(result.exitCode, 64);
    final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
    expect(decoded['ok'], false);
    expect(decoded['result'], 'ERROR');
    expect(decoded['scenario'], 'fixture.valid_scenario_unknown_target');
    expect(decoded['target'], 'android-sim');
    expect(decoded['bundle_dir'], isNull);
  });
}
