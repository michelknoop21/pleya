import 'dart:io';

import 'package:pleya_verify_mcp/src/process_runner.dart';
import 'package:pleya_verify_mcp/src/verify_cli.dart';
import 'package:test/test.dart';

/// The one test in this suite that crosses the real subprocess boundary:
/// a real `dart` process running the real
/// `pleya_verify/runner/bin/verify.dart list scenarios --json` entrypoint,
/// through [RealProcessRunner] rather than a fake. Deliberately the cheapest
/// CLI subcommand available: no scenario execution, no simulator, no
/// `flutter build`, so this stays fast and deterministic in the normal
/// test run while still proving the wrapper talks to the actual CLI
/// correctly, not just to a script's idea of it.
void main() {
  test('VerifyCli.listScenarios() against the real verify.dart CLI finds the known scenarios', () async {
    final runnerPackageDir = '${Directory.current.path}/../runner';
    expect(Directory(runnerPackageDir).existsSync(), true, reason: 'expected to run from pleya_verify/mcp/');

    final cli = VerifyCli(runner: const RealProcessRunner(), runnerPackageDir: runnerPackageDir);
    final scenarios = await cli.listScenarios();

    expect(scenarios, isNotEmpty);
    expect(scenarios.map((s) => s.name), contains('macos.smoke.boot'));
    expect(scenarios.map((s) => s.name), contains('tvos.sidebar.collapse'));
    // Every path came from the CLI itself and stays resolvable relative to
    // the runner package directory it was printed from.
    for (final s in scenarios) {
      expect(File('$runnerPackageDir/${s.path}').existsSync(), true, reason: '${s.path} should exist on disk');
    }
  });
}
