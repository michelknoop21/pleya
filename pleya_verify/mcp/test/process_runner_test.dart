import 'dart:io';

import 'package:pleya_verify_mcp/src/process_runner.dart';
import 'package:test/test.dart';

/// [RealProcessRunner.run] against a **real**, deliberately hanging
/// subprocess — the thing worth proving is that a wedged child both
/// produces a bounded infra-error and does not survive the call, not just
/// that a fake `Future` can be made to time out.
void main() {
  test(
    'a hung subprocess times out with ProcessRunTimeoutException and is actually killed',
    () async {
      final tempDir = Directory.systemTemp.createTempSync('pleya-verify-process-runner-test');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      // A script whose only two jobs are: announce its own pid, then hang
      // far longer than any timeout this test uses.
      final script = File('${tempDir.path}/hang.dart')
        ..writeAsStringSync('''
import 'dart:io';

void main(List<String> args) {
  File(args[0]).writeAsStringSync('\$pid');
  sleep(const Duration(hours: 1));
}
''');
      final pidFile = File('${tempDir.path}/pid');

      final runner = const RealProcessRunner(
        timeout: Duration(milliseconds: 300),
        terminationGrace: Duration(milliseconds: 300),
      );

      await expectLater(
        runner.run([script.path, pidFile.path], workingDirectory: tempDir.path),
        throwsA(
          isA<ProcessRunTimeoutException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains(script.path), contains('did not exit within')),
          ),
        ),
      );

      // By the time run() throws it has already awaited the child's real
      // exit (after SIGTERM, then SIGKILL) — no polling needed here.
      expect(pidFile.existsSync(), isTrue, reason: 'the hung process should have started and announced its pid');
      final pid = pidFile.readAsStringSync().trim();
      final aliveCheck = await Process.run('kill', ['-0', pid]);
      expect(aliveCheck.exitCode, isNot(0), reason: 'pid $pid should no longer exist after run() returned');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a subprocess that exits well within the deadline returns normally', () async {
    final runner = const RealProcessRunner(timeout: Duration(seconds: 10));
    final result = await runner.run(['--version'], workingDirectory: Directory.current.path);
    expect(result.exitCode, 0);
  });
}
