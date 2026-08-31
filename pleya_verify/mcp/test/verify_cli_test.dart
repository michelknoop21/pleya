import 'dart:convert';

import 'package:pleya_verify_mcp/src/process_runner.dart';
import 'package:pleya_verify_mcp/src/verify_cli.dart';
import 'package:test/test.dart';

import 'fake_process_runner.dart';

const _scenarioListJson = '["../scenarios/macos.smoke.boot.yaml", "../scenarios/tvos.sidebar.collapse.yaml"]';

void main() {
  group('listScenarios', () {
    test('parses the CLI\'s scenario list and derives names from file stems', () async {
      final runner = FakeProcessRunner((args) => ProcessRunResult(exitCode: 0, stdout: _scenarioListJson, stderr: ''));
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      final scenarios = await cli.listScenarios();

      expect(scenarios.map((s) => s.name), ['macos.smoke.boot', 'tvos.sidebar.collapse']);
      expect(scenarios.map((s) => s.path), [
        '../scenarios/macos.smoke.boot.yaml',
        '../scenarios/tvos.sidebar.collapse.yaml',
      ]);
      expect(runner.calls.single, ['run', 'bin/verify.dart', 'list', 'scenarios', '--json']);
    });

    test('a non-zero exit is an infrastructure error, not an empty list', () async {
      final runner = FakeProcessRunner((args) => ProcessRunResult(exitCode: 1, stdout: '', stderr: 'boom'));
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      await expectLater(cli.listScenarios(), throwsA(isA<VerifyCliInfraError>()));
    });

    test('malformed JSON from the CLI is an infrastructure error', () async {
      final runner = FakeProcessRunner((args) => ProcessRunResult(exitCode: 0, stdout: 'not json', stderr: ''));
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      await expectLater(cli.listScenarios(), throwsA(isA<VerifyCliInfraError>()));
    });
  });

  group('runScenario', () {
    ProcessRunResult listResponse() => ProcessRunResult(exitCode: 0, stdout: _scenarioListJson, stderr: '');

    test('a PASS response from the CLI passes through unchanged', () async {
      final runResponse = jsonEncode({
        'ok': true,
        'result': 'PASS',
        'scenario': 'macos.smoke.boot',
        'target': 'macos',
        'bundle_dir': '.build/pleya-verify/macos-smoke-boot-123',
        'failure_message': null,
        'exit_code': 0,
        'command': ['dart', 'run', 'bin/verify.dart', 'run', '../scenarios/macos.smoke.boot.yaml', '--json'],
      });
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(exitCode: 0, stdout: runResponse, stderr: '');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      final outcome = await cli.runScenario('macos.smoke.boot');

      expect(outcome.ok, true);
      expect(outcome.result, 'PASS');
      expect(outcome.scenario, 'macos.smoke.boot');
      expect(outcome.target, 'macos');
      expect(outcome.bundleDir, '.build/pleya-verify/macos-smoke-boot-123');
      expect(outcome.failureMessage, isNull);
      expect(outcome.cliExitCode, 0);
      // Resolved from the discovered scenario path, never a caller-supplied
      // path, and never recomputed from anything but the CLI's own answer.
      expect(outcome.command, contains('../scenarios/macos.smoke.boot.yaml'));
    });

    test('a FAILED response stays FAILED: the wrapper never recomputes it', () async {
      final runResponse = jsonEncode({
        'ok': false,
        'result': 'FAILED',
        'scenario': 'tvos.sidebar.collapse',
        'target': 'tvos-sim',
        'bundle_dir': '.build/pleya-verify/tvos-sidebar-collapse-456',
        'failure_message': 'assert failed: state(nav.discover.collapsed): expected true',
        'exit_code': 1,
      });
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(exitCode: 1, stdout: runResponse, stderr: '');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      final outcome = await cli.runScenario('tvos.sidebar.collapse');

      expect(outcome.ok, false);
      expect(outcome.result, 'FAILED');
      expect(outcome.bundleDir, '.build/pleya-verify/tvos-sidebar-collapse-456');
      expect(outcome.failureMessage, contains('expected true'));
    });

    test('an unknown scenario name is a usage error before any run is attempted', () async {
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        throw StateError('run should never be attempted for an unresolved scenario name');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      await expectLater(cli.runScenario('no.such.scenario'), throwsA(isA<VerifyCliUsageError>()));
      // Only the discovery call happened; the wrapper never guesses a path.
      expect(runner.calls, hasLength(1));
    });

    test('malformed CLI JSON on a run is an infrastructure error, never a silent FAILED', () async {
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(exitCode: 0, stdout: 'not json at all', stderr: '');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      await expectLater(cli.runScenario('macos.smoke.boot'), throwsA(isA<VerifyCliInfraError>()));
    });

    test('an unexpected non-zero exit with valid FAILED JSON is a real FAIL, not an infra error', () async {
      final runResponse = jsonEncode({
        'ok': false,
        'result': 'FAILED',
        'scenario': 'macos.smoke.boot',
        'target': 'macos',
        'bundle_dir': '.build/pleya-verify/x',
        'failure_message': 'wait_until timed out',
      });
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(exitCode: 1, stdout: runResponse, stderr: '');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      final outcome = await cli.runScenario('macos.smoke.boot');
      expect(outcome.result, 'FAILED');
      expect(outcome.cliExitCode, 1);
    });

    test('a genuine subprocess crash (non-zero exit, empty stdout) is an infrastructure error', () async {
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(exitCode: 255, stdout: '', stderr: 'Unhandled exception:\nSegmentation fault');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      await expectLater(cli.runScenario('macos.smoke.boot'), throwsA(isA<VerifyCliInfraError>()));
    });

    test('stderr noise does not pollute stdout JSON parsing', () async {
      final runResponse = jsonEncode({
        'ok': true,
        'result': 'PASS',
        'scenario': 'macos.smoke.boot',
        'target': 'macos',
        'bundle_dir': '.build/pleya-verify/x',
        'failure_message': null,
      });
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(
          exitCode: 0,
          stdout: runResponse,
          stderr: 'some deprecation warning on stderr\nanother line',
        );
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      final outcome = await cli.runScenario('macos.smoke.boot');
      expect(outcome.result, 'PASS');
    });

    test('the pasteable command is present and matches the resolved scenario path', () async {
      final runResponse = jsonEncode({
        'ok': true,
        'result': 'PASS',
        'scenario': 'macos.smoke.boot',
        'target': 'macos',
        'bundle_dir': '.build/pleya-verify/x',
        'failure_message': null,
      });
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(exitCode: 0, stdout: runResponse, stderr: '');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      final outcome = await cli.runScenario('macos.smoke.boot');
      expect(
        outcome.command,
        'cd pleya_verify/runner && dart run bin/verify.dart run ../scenarios/macos.smoke.boot.yaml --json',
      );
    });

    test('scenario arguments are passed as an argv list, never a shell string', () async {
      final runResponse = jsonEncode({'ok': true, 'result': 'PASS'});
      final runner = FakeProcessRunner((args) {
        if (args[2] == 'list') return listResponse();
        return ProcessRunResult(exitCode: 0, stdout: runResponse, stderr: '');
      });
      final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');

      await cli.runScenario('macos.smoke.boot');

      // A plain List<String> argv, not a shell string: nothing here is ever
      // built by string-concatenating a scenario name into a shell command.
      final runCall = runner.calls.firstWhere((c) => c[2] == 'run');
      expect(runCall, ['run', 'bin/verify.dart', 'run', '../scenarios/macos.smoke.boot.yaml', '--json']);
    });
  });
}
