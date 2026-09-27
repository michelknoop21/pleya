import 'dart:io';

import 'package:pleya_verify_runner/src/driver/bounded_process.dart';
import 'package:test/test.dart';

/// Every driver's external tool call goes through [runBounded]. A call that
/// never returns must end the run with an error that names it, and must not
/// leave the process behind (27 September 2026: one `simctl` call held an iOS
/// run for 1 h 40 min and outlived the run itself).
void main() {
  test('a call that finishes returns its exit code and output', () async {
    final result = await runBounded('sh', ['-c', 'echo hello; exit 3']);

    expect(result.exitCode, 3);
    expect((result.stdout as String).trim(), 'hello');
  });

  test('a call that outlives its ceiling is killed and reported by name', () async {
    // A shell with a child, like `scripts/tvos_sim.sh` running `xcodebuild`:
    // the `echo` after `sleep` keeps the shell from exec-ing into the child.
    // The odd sleep length is what `pgrep` looks for afterwards.
    const child = 'sleep 2987';

    await expectLater(
      // Two levels deep, like `xcrun` -> `simctl`.
      runBounded('sh', ['-c', 'sh -c "$child; echo inner"; echo outer'], timeout: const Duration(milliseconds: 300)),
      throwsA(isA<ProcessTimeoutException>().having((e) => e.toString(), 'message', contains(child))),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stillRunning = await Process.run('pgrep', ['-f', child]);
    expect(stillRunning.exitCode, isNot(0), reason: 'no process in the tree may survive the run');
  });

  test(
    'a child that keeps the output pipe open after its parent exited still hits the ceiling',
    () async {
      // `sleep` runs in the background and inherits stdout, so the pipe stays
      // open after `sh` itself has exited. Waiting for the exit code alone
      // returned here; waiting for the stream did not.
      const orphan = 'sleep 2986';
      try {
        await expectLater(
          runBounded('sh', ['-c', '$orphan & echo started'], timeout: const Duration(milliseconds: 500)),
          throwsA(isA<ProcessTimeoutException>()),
        );
      } finally {
        await Process.run('pkill', ['-9', '-f', orphan]);
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
