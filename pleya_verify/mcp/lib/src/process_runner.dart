import 'dart:async';
import 'dart:io';

/// The outcome of running one subprocess to completion: never a scenario
/// verdict, just what the operating system reported.
class ProcessRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ProcessRunResult({required this.exitCode, required this.stdout, required this.stderr});
}

/// Thrown by [RealProcessRunner.run] when the subprocess did not exit within
/// its deadline. Deliberately a distinct type, never a [ProcessRunResult]
/// with some sentinel exit code: a hung `dart run bin/verify.dart` is an
/// infrastructure failure of this wrapper, not a scenario PASS/FAILED, and a
/// caller must not be able to mistake one for the other. By the time this is
/// thrown the child process has already been asked to exit — see [run]'s doc.
class ProcessRunTimeoutException implements Exception {
  final List<String> args;
  final String workingDirectory;
  final Duration timeout;

  const ProcessRunTimeoutException({required this.args, required this.workingDirectory, required this.timeout});

  @override
  String toString() =>
      'ProcessRunTimeoutException: `${args.join(' ')}` (in $workingDirectory) did not exit within $timeout';
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
/// [Process.start] as a plain argument list, so a scenario name or path can
/// never be interpreted as shell syntax.
///
/// **Bounded, unconditionally.** A plain `await Process.run(...)` (the
/// previous implementation) has no deadline of its own: a wedged
/// `verify.dart run` — a hung simulator boot, a fixture server that never
/// answers — blocks this call forever, and the child keeps running
/// regardless of whether anything is still waiting on it. [run] instead
/// starts the process, races its exit against [timeout], and on timeout
/// sends `SIGTERM` and then (if that does not land within
/// [terminationGrace]) `SIGKILL` before ever returning — so this method
/// never leaves an orphaned subprocess behind, and a caller either gets a
/// real [ProcessRunResult] or a [ProcessRunTimeoutException], never a hang.
class RealProcessRunner implements ProcessRunner {
  /// Generous relative to what a single `verify.dart run` does (build,
  /// install, launch, assert, teardown against a real simulator/macOS
  /// build), tight relative to "never" — the property this class exists to
  /// guarantee. The macOS/iOS-sim CI job budgets 30 minutes for two runs
  /// plus setup; 10 is comfortable headroom under that for one.
  final Duration timeout;

  /// How long [run] waits for a graceful `SIGTERM` exit before escalating to
  /// `SIGKILL` on a timed-out process.
  final Duration terminationGrace;

  const RealProcessRunner({this.timeout = const Duration(minutes: 10), this.terminationGrace = const Duration(seconds: 5)});

  @override
  Future<ProcessRunResult> run(List<String> args, {required String workingDirectory}) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      args,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture = process.stderr.transform(const SystemEncoding().decoder).join();

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(terminationGrace);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      // Drained so the streams' subscriptions close cleanly — their content
      // is irrelevant now, this call is about to throw regardless.
      await stdoutFuture;
      await stderrFuture;
      throw ProcessRunTimeoutException(args: args, workingDirectory: workingDirectory, timeout: timeout);
    }

    return ProcessRunResult(exitCode: exitCode, stdout: await stdoutFuture, stderr: await stderrFuture);
  }
}
