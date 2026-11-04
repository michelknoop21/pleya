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

  test('a Verify Flutter build waits in the shared queue and preserves its result', () async {
    if (!Platform.isMacOS) return;
    final root = Directory.systemTemp.createTempSync('pleya-queue-driver-');
    final scripts = Directory('${root.path}/scripts')..createSync();
    final bin = Directory('${root.path}/bin')..createSync();
    final queue = File('${Directory.current.parent.parent.path}/scripts/heavy_queue.py');
    queue.copySync('${scripts.path}/heavy_queue.py');
    File('${queue.parent.path}/pleya_heavy_process.py').copySync('${scripts.path}/pleya_heavy_process.py');
    File('${queue.parent.path}/verify_queued_build.py').copySync('${scripts.path}/verify_queued_build.py');
    final marker = File('${root.path}/holding');
    final built = File('${root.path}/built');
    final flutter = File('${bin.path}/flutter')
      ..writeAsStringSync('#!/bin/sh\ntouch "${built.path}"\nprintf "built fixture\\n"\nexit 6\n');
    await Process.run('chmod', ['+x', flutter.path]);
    final environment = <String, String>{
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'PLEYA_HEAVY_QUEUE_DIR': '${root.path}/queue',
    };
    final holder = await Process.start(
      'python3',
      [
        '${scripts.path}/heavy_queue.py',
        'run',
        '--label',
        'fixture-holder',
        '--',
        'python3',
        '-c',
        'from pathlib import Path; import time; Path("${marker.path}").touch(); time.sleep(15)',
      ],
      environment: environment,
      includeParentEnvironment: false,
    );
    final holderOut = holder.stdout.drain<void>();
    final holderErr = holder.stderr.drain<void>();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!marker.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect(marker.existsSync(), isTrue, reason: 'fixture owns the queue before starting a build');
      final result = runBounded(
        'flutter',
        ['build', 'macos'],
        workingDirectory: root.path,
        environment: environment,
        includeParentEnvironment: false,
        timeout: const Duration(seconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(built.existsSync(), isFalse, reason: 'real driver build path must wait');
      holder.kill(ProcessSignal.sigterm);
      await holder.exitCode;
      final completed = await result;
      expect(completed.exitCode, 6);
      expect(completed.stdout, contains('built fixture'));
      expect(built.existsSync(), isTrue);
    } finally {
      holder.kill(ProcessSignal.sigterm);
      await holder.exitCode;
      await Future.wait([holderOut, holderErr]);
      root.deleteSync(recursive: true);
    }
  });

  test('a queued build also starts from a relative repository root', () async {
    // CI hands the drivers `../..` as repoRoot; the child runs inside that
    // directory, so the script paths must not be resolved a second time.
    if (!Platform.isMacOS) return;
    final root = Directory('.dart_tool').createTempSync('pleya-queue-relative-');
    expect(root.isAbsolute, isFalse);
    final scripts = Directory('${root.path}/scripts')..createSync();
    final bin = Directory('${root.path}/bin')..createSync();
    final queue = File('${Directory.current.parent.parent.path}/scripts/heavy_queue.py');
    for (final name in ['heavy_queue.py', 'pleya_heavy_process.py', 'verify_queued_build.py']) {
      File('${queue.parent.path}/$name').copySync('${scripts.path}/$name');
    }
    final flutter = File('${bin.path}/flutter')..writeAsStringSync('#!/bin/sh\nprintf "relative ok\\n"\nexit 0\n');
    await Process.run('chmod', ['+x', flutter.path]);
    try {
      final result = await runBounded(
        'flutter',
        ['build', 'macos'],
        workingDirectory: root.path,
        environment: {
          'PATH': '${bin.absolute.path}:${Platform.environment['PATH']}',
          'PLEYA_HEAVY_QUEUE_DIR': '${root.absolute.path}/queue',
        },
        includeParentEnvironment: false,
        timeout: const Duration(seconds: 10),
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('relative ok'));
    } finally {
      root.deleteSync(recursive: true);
    }
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
