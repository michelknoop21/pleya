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
}
