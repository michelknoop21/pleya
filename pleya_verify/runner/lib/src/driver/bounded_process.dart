import 'dart:async';
import 'dart:io';

/// Ceiling for one external tool call a driver makes (`xcrun simctl`,
/// `plutil`, `codesign`, `git`, ...). Every one of them normally answers in
/// seconds.
///
/// Why a ceiling at all: `Process.run` waits for ever. On 27 September 2026 an
/// iOS run built the app, then sat for 1 h 40 min on one `simctl` call that
/// never returned; the scenario never failed, it just stopped, and the evidence
/// bundle stayed empty because `driver.log` is written at the end. A run that
/// cannot finish has to end with a result naming the command, not as silence:
/// the engine reports it as `FAILED` with the [ProcessTimeoutException] as
/// `failure_message`.
const Duration defaultProcessTimeout = Duration(minutes: 3);

/// `flutter build` and `scripts/tvos_sim.sh build` compile the whole app.
const Duration buildProcessTimeout = Duration(minutes: 30);

/// `simctl bootstatus -b` waits for a cold simulator to finish booting.
const Duration bootProcessTimeout = Duration(minutes: 5);

/// Thrown when a process outlived its ceiling. The process has already been
/// killed when this is thrown, so nothing is left running behind the run.
class ProcessTimeoutException implements Exception {
  const ProcessTimeoutException({required this.executable, required this.arguments, required this.timeout});

  final String executable;
  final List<String> arguments;
  final Duration timeout;

  @override
  String toString() =>
      'ProcessTimeoutException: `$executable ${arguments.join(' ')}` did not finish within $timeout and was killed';
}

/// `Process.run` with a ceiling. Same result shape and the same default
/// decoding, so a caller that checked `exitCode`/`stdout` keeps working.
Future<ProcessResult> runBounded(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Duration timeout = defaultProcessTimeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
  );
  final stdout = process.stdout.transform(systemEncoding.decoder).join();
  final stderr = process.stderr.transform(systemEncoding.decoder).join();
  // Exit code and both streams under the one ceiling: a grandchild that
  // inherited the pipe can keep `stdout` open after the process itself exited,
  // and that wait would be just as unbounded as the exit.
  final List<Object?> done;
  try {
    done = await Future.wait<Object?>([process.exitCode, stdout, stderr]).timeout(timeout);
  } on TimeoutException {
    // Nobody awaits the streams any more; a decode error on them must not
    // surface later as an uncaught error that takes the CLI down.
    unawaited(stdout.then<void>((_) {}, onError: (Object _) {}));
    unawaited(stderr.then<void>((_) {}, onError: (Object _) {}));
    _killTree(process.pid);
    throw ProcessTimeoutException(executable: executable, arguments: arguments, timeout: timeout);
  }
  return ProcessResult(process.pid, done[0]! as int, done[1], done[2]);
}

/// Kills [pid] and every process below it, deepest first.
///
/// One level is not enough: `xcrun simctl` runs `simctl` as a grandchild, and
/// `scripts/tvos_sim.sh` runs `xcodebuild` below itself. On 27 September 2026 a
/// `simctl uninstall` survived a kill of only the direct children and stayed
/// behind as an orphan.
///
/// Each process is stopped before its children are listed, so it cannot fork
/// a new one in between. A missing `pgrep` only loses the children; [pid]
/// itself is always killed.
void _killTree(int pid) {
  Process.killPid(pid, ProcessSignal.sigstop);
  try {
    final children = Process.runSync('pgrep', ['-P', '$pid']);
    for (final line in (children.stdout as String).split('\n')) {
      final child = int.tryParse(line.trim());
      if (child != null) _killTree(child);
    }
  } on ProcessException {
    // Fall through to the kill below.
  }
  Process.killPid(pid, ProcessSignal.sigkill);
}
