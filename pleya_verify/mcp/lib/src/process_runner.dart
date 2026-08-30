import 'dart:io';

/// The outcome of running one subprocess to completion: never a scenario
/// verdict, just what the operating system reported.
class ProcessRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ProcessRunResult({required this.exitCode, required this.stdout, required this.stderr});
}

/// Everything [VerifyCli] needs to start a subprocess, kept behind an
/// interface so wrapper tests can inject a fake instead of actually spawning
/// `dart run bin/verify.dart` (a full scenario run needs a simulator or a
/// real macOS build, far too slow and non-deterministic for a unit test).
abstract class ProcessRunner {
  Future<ProcessRunResult> run(List<String> args, {required String workingDirectory});
}

/// Spawns the real `dart` executable resolving this MCP server itself ran
/// under. Never a shell, and never string-concatenated: [args] goes to
/// [Process.run] as a plain argument list, so a scenario name or path can
/// never be interpreted as shell syntax.
class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessRunResult> run(List<String> args, {required String workingDirectory}) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      args,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    return ProcessRunResult(
      exitCode: result.exitCode,
      stdout: result.stdout is String ? result.stdout as String : result.stdout.toString(),
      stderr: result.stderr is String ? result.stderr as String : result.stderr.toString(),
    );
  }
}
