import 'dart:convert';

import 'process_runner.dart';

/// Raised when the caller asked for something that is the caller's mistake
/// to fix (an unknown scenario name, most likely a typo). Never raised for
/// anything the CLI or the scenario itself did.
class VerifyCliUsageError implements Exception {
  final String message;
  const VerifyCliUsageError(this.message);

  @override
  String toString() => message;
}

/// Raised when the CLI subprocess itself could not be trusted: a non-zero
/// exit with no parseable JSON, an unexpected crash, `list scenarios` itself
/// failing. This is deliberately a different type than a scenario FAILED
/// result: a broken subprocess must never be reported as though a scenario
/// ran and failed its assertions.
class VerifyCliInfraError implements Exception {
  final String message;
  const VerifyCliInfraError(this.message);

  @override
  String toString() => message;
}

/// One `dart run bin/verify.dart run <scenario> --json` invocation, passed
/// through verbatim from the CLI's own JSON envelope (see
/// `pleya_verify/runner/bin/verify.dart`'s `_emitRunResult`). Nothing here
/// recomputes `passed`/`result`: they are read straight off what the CLI
/// already decided.
class ScenarioRunOutcome {
  /// `true` only when the CLI reported `result: "PASS"`.
  final bool ok;

  /// `PASS`, `FAILED`, or `ERROR` (a configuration/invocation problem the
  /// scenario itself never got to run against), verbatim from the CLI.
  final String result;

  final String? scenario;
  final String? target;
  final String? bundleDir;
  final String? failureMessage;
  final List<Object?>? errors;
  final int cliExitCode;

  /// The exact shell command a person can paste, from the repo root, to
  /// reproduce this run outside MCP.
  final String command;

  const ScenarioRunOutcome({
    required this.ok,
    required this.result,
    required this.scenario,
    required this.target,
    required this.bundleDir,
    required this.failureMessage,
    required this.errors,
    required this.cliExitCode,
    required this.command,
  });

  Map<String, Object?> toJson() => {
    'ok': ok,
    'result': result,
    'scenario': scenario,
    'target': target,
    'bundle_dir': bundleDir,
    'failure_message': failureMessage,
    if (errors != null) 'errors': errors,
    'cli_exit_code': cliExitCode,
    'command': command,
  };
}

/// One discovered scenario file, as `list scenarios --json` reports it.
/// The sole source of truth this package ever reads for "what scenarios
/// exist". There is no second, hand-maintained scenario registry here.
class ScenarioListEntry {
  /// The scenario's file stem (e.g. `macos.smoke.boot`), which the
  /// repository convention keeps identical to the scenario's own `name:`
  /// field. See `pleya_verify/scenarios/README.md`.
  final String name;

  /// Path to the `.yaml` file, relative to the runner package directory,
  /// exactly as `list scenarios --json` printed it.
  final String path;

  const ScenarioListEntry({required this.name, required this.path});
}

/// A thin subprocess wrapper around the existing Pleya Verify CLI. Every
/// method here shells out to `dart run bin/verify.dart ... --json` and
/// passes the result through: no scenario parsing, no fixture seeding, no
/// assertion evaluation, no PASS/FAIL recomputation lives in this class.
/// See `pleya_verify/mcp/README.md` for the full architecture note.
class VerifyCli {
  final ProcessRunner runner;

  /// Absolute path to `pleya_verify/runner`, every CLI subcommand's
  /// documented working-directory assumption (see
  /// `pleya_verify/runner/bin/verify.dart`'s top-of-file comment).
  final String runnerPackageDir;

  const VerifyCli({required this.runner, required this.runnerPackageDir});

  /// Runs [runner] and turns a [ProcessRunTimeoutException] into a
  /// [VerifyCliInfraError] — the same "the subprocess itself could not be
  /// trusted" category as a non-zero exit or non-JSON stdout below, never a
  /// scenario result. [RealProcessRunner] has already killed the child by
  /// the time this exception reaches here; this is purely about reporting.
  Future<ProcessRunResult> _runBounded(List<String> args) async {
    try {
      return await runner.run(args, workingDirectory: runnerPackageDir);
    } on ProcessRunTimeoutException catch (e) {
      throw VerifyCliInfraError('verify CLI "${args.join(' ')}" $e');
    }
  }

  /// Lists every scenario the CLI itself can discover under its default
  /// scenarios directory, the same call `pleya_verify/scenarios/README.md`
  /// already documents as "used by CI and the MCP layer".
  Future<List<ScenarioListEntry>> listScenarios() async {
    final args = ['run', 'bin/verify.dart', 'list', 'scenarios', '--json'];
    final result = await _runBounded(args);
    if (result.exitCode != 0) {
      throw VerifyCliInfraError(
        'verify CLI "list scenarios --json" exited ${result.exitCode}: ${result.stderr.trim()}',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException catch (e) {
      throw VerifyCliInfraError('verify CLI "list scenarios --json" did not print valid JSON: $e');
    }
    if (decoded is! List) {
      throw VerifyCliInfraError('verify CLI "list scenarios --json" did not print a JSON array: ${result.stdout}');
    }
    return [for (final entry in decoded) ScenarioListEntry(name: _stemOf(entry as String), path: entry)];
  }

  /// Runs one scenario by name (its file stem, e.g. `macos.smoke.boot`) via
  /// the existing CLI's `run <path> --json` and passes the result through
  /// unchanged. [scenarioName] is only ever matched against the whitelist
  /// [listScenarios] returns: it is never interpolated into a filesystem
  /// path directly, so a caller cannot walk outside the scenarios directory.
  Future<ScenarioRunOutcome> runScenario(String scenarioName) async {
    final scenarios = await listScenarios();
    final matches = scenarios.where((s) => s.name == scenarioName).toList();
    if (matches.isEmpty) {
      final known = scenarios.map((s) => s.name).toList()..sort();
      throw VerifyCliUsageError('unknown scenario "$scenarioName", known scenarios: ${known.join(', ')}');
    }
    // Scenario file stems are unique by repository convention (enforced by
    // `pleya_verify/scenarios/README.md`); more than one hit means the
    // scenarios directory itself is inconsistent, not something this layer
    // should silently pick one of.
    if (matches.length > 1) {
      throw VerifyCliInfraError(
        'scenario name "$scenarioName" matches more than one file: ${matches.map((s) => s.path).join(', ')}',
      );
    }
    final scenarioPath = matches.single.path;

    final args = ['run', 'bin/verify.dart', 'run', scenarioPath, '--json'];
    final result = await _runBounded(args);
    final command = 'cd pleya_verify/runner && dart ${args.join(' ')}';

    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      throw VerifyCliInfraError(
        'verify CLI produced non-JSON stdout (exit ${result.exitCode}); '
        'stdout: ${result.stdout.trim()}; stderr: ${result.stderr.trim()}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw VerifyCliInfraError('verify CLI --json output was not a JSON object: ${result.stdout.trim()}');
    }

    return ScenarioRunOutcome(
      ok: decoded['ok'] as bool? ?? false,
      result: decoded['result'] as String? ?? 'ERROR',
      scenario: decoded['scenario'] as String?,
      target: decoded['target'] as String?,
      bundleDir: decoded['bundle_dir'] as String?,
      failureMessage: decoded['failure_message'] as String?,
      errors: decoded['errors'] as List<Object?>?,
      cliExitCode: result.exitCode,
      command: command,
    );
  }

  static String _stemOf(String path) {
    final slash = path.lastIndexOf('/');
    final base = slash == -1 ? path : path.substring(slash + 1);
    final dot = base.lastIndexOf('.');
    return dot == -1 ? base : base.substring(0, dot);
  }
}
