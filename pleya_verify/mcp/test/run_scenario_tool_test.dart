import 'dart:convert';

import 'package:pleya_verify_mcp/src/process_runner.dart';
import 'package:pleya_verify_mcp/src/tools/run_scenario_tool.dart';
import 'package:pleya_verify_mcp/src/verify_cli.dart';
import 'package:test/test.dart';

import 'fake_process_runner.dart';

const _scenarioListJson = '["../scenarios/macos.smoke.boot.yaml"]';

void main() {
  test('rejects a missing "scenario" argument before touching the CLI', () async {
    final runner = FakeProcessRunner((args) => throw StateError('the CLI should never be invoked'));
    final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');
    final tool = buildRunScenarioTool(cli);

    await expectLater(tool.handler(const {}), throwsA(isA<VerifyCliUsageError>()));
    expect(runner.calls, isEmpty);
  });

  test('rejects a non-string "scenario" argument before touching the CLI', () async {
    final runner = FakeProcessRunner((args) => throw StateError('the CLI should never be invoked'));
    final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');
    final tool = buildRunScenarioTool(cli);

    await expectLater(tool.handler({'scenario': 42}), throwsA(isA<VerifyCliUsageError>()));
  });

  test('a PASS outcome comes back as a JSON-safe map with the CLI\'s own fields', () async {
    final runResponse = jsonEncode({
      'ok': true,
      'result': 'PASS',
      'scenario': 'macos.smoke.boot',
      'target': 'macos',
      'bundle_dir': '.build/pleya-verify/x',
      'failure_message': null,
    });
    final runner = FakeProcessRunner((args) {
      if (args[2] == 'list') return ProcessRunResult(exitCode: 0, stdout: _scenarioListJson, stderr: '');
      return ProcessRunResult(exitCode: 0, stdout: runResponse, stderr: '');
    });
    final cli = VerifyCli(runner: runner, runnerPackageDir: '/repo/pleya_verify/runner');
    final tool = buildRunScenarioTool(cli);

    final result = await tool.handler({'scenario': 'macos.smoke.boot'});

    expect(result['ok'], true);
    expect(result['result'], 'PASS');
    expect(result['bundle_dir'], '.build/pleya-verify/x');
    expect(result['command'], isA<String>());
  });
}
