import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// How long one call of the script may take before the test gives up on it.
///
/// This is a guard against a call that never returns, not the measurement.
/// `doctor` with a wedged idb takes about three seconds at best: two connects
/// of one second each, a pause between them and two Python starts. With five
/// seconds here the test failed whenever the machine was busy (13 October
/// 2026, load average above 80: 3.3 to 11.5 s for `doctor`, 1.1 to 10.4 s for
/// `key`). What proves the bound is asserted in the test: the script says it
/// cut idb off, and the fake idb did not live to [idbOutlivedAfterSeconds].
/// The wedge lasts four times this guard, so a script that waits for idb
/// still fails here.
const scriptGuard = Duration(seconds: 30);
const wedgeSeconds = 120;

/// A fake idb that is still alive this long after it started has outlived the
/// one-second ceiling the test sets. Far enough from one second that a busy
/// machine does not get there, and below the script's default of ten. A
/// ceiling between one and five seconds is not told apart from one second.
const idbOutlivedAfterSeconds = 5;

void main() {
  late Directory binDir;

  void writeExecutable(String name, String content) {
    final file = File('${binDir.path}/$name');
    file.writeAsStringSync(content);
    final chmod = Process.runSync('chmod', ['+x', file.path]);
    if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
  }

  setUp(() {
    binDir = Directory.systemTemp.createTempSync('pleya-fake-idb');
    writeExecutable('xcrun', '#!/bin/sh\nprintf "Fake Apple TV (FAKE-UDID) (Booted)\\n"\n');
  });

  tearDown(() => binDir.deleteSync(recursive: true));

  Future<({int exitCode, String output, String error})> runScript(List<String> args) async {
    final process = await Process.start(
      '../../scripts/tvos_sim.sh',
      args,
      environment: {
        'PATH': '${binDir.path}:${Platform.environment['PATH']}',
        'TVOS_SIM_UDID': 'FAKE-UDID',
        'TVOS_SIM_REQUIRE_IDB': '1',
        'TVOS_SIM_IDB_TIMEOUT_SEC': '1',
      },
    );
    // Collected as it arrives: when the guard fires, what the script wrote
    // until then is the only clue to where it stood.
    final output = StringBuffer();
    final error = StringBuffer();
    final outputDone = process.stdout.transform(utf8.decoder).forEach(output.write);
    final errorDone = process.stderr.transform(utf8.decoder).forEach(error.write);
    final exitCode = await process.exitCode.timeout(
      scriptGuard,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -999;
      },
    );
    if (exitCode != -999) await Future.wait([outputDone, errorDone]);
    return (exitCode: exitCode, output: output.toString(), error: error.toString());
  }

  test(
    'a hung idb connect is bounded and cannot fall back to host keyboard input',
    () async {
      // A watcher beside the wedge looks once, [idbOutlivedAfterSeconds]
      // after its idb started: it marks an idb that is still there, and
      // always records that it looked. It holds none of the script's pipes.
      final outlived = File('${binDir.path}/idb-outlived-ceiling');
      writeExecutable(
        'idb',
        '#!/bin/sh\n'
            '( sleep $idbOutlivedAfterSeconds; kill -0 \$\$ 2>/dev/null && touch "${outlived.path}"; '
            'touch "${binDir.path}/idb-watched-\$\$" ) >/dev/null 2>&1 &\n'
            'exec sleep $wedgeSeconds\n',
      );
      // Everything the AppleScript route would start leaves a marker. The
      // script silences osascript itself, so its stderr cannot be the proof;
      // and unfaked, `open -a Simulator` would open the real app.
      final fallback = File('${binDir.path}/fallback-called');
      writeExecutable('osascript', '#!/bin/sh\ntouch "${fallback.path}"\necho 0\n');
      writeExecutable('open', '#!/bin/sh\ntouch "${fallback.path}"\n');
      writeExecutable('caffeinate', '#!/bin/sh\ntouch "${fallback.path}"\n');

      final result = await runScript(['doctor', '--json']);
      expect(result.exitCode, 0, reason: 'doctor must finish despite a wedged idb connect\n${result.error}');
      // Both connects ended on the script's own one-second ceiling, not on idb.
      expect(result.error, contains('poging 1: idb connect FAKE-UDID timed out after 1s'));
      expect(result.error, contains('poging 2: idb connect FAKE-UDID timed out after 1s'));
      // The script is back before the watchers have looked: wait for both.
      bool bothLooked() => binDir.listSync().where((f) => f.path.contains('idb-watched-')).length >= 2;
      for (var waited = 0; !bothLooked() && waited < 200; waited++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(bothLooked(), true, reason: 'the watchers beside the two idb connects never reported');
      expect(outlived.existsSync(), false, reason: 'idb was still running $idbOutlivedAfterSeconds s after it started');
      expect(fallback.existsSync(), false, reason: 'doctor went down the AppleScript route');
      final body = jsonDecode(result.output) as Map<String, Object?>;
      expect(body['input'], 'none');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a failed idb key never silently falls back to AppleScript in Verify', () async {
    final idbCalls = File('${binDir.path}/idb-calls');
    writeExecutable('idb', '#!/bin/sh\necho "\$@" >> "${idbCalls.path}"\n[ "\$1" = connect ] && exit 0\nexit 7\n');
    final fallbackMarker = File('${binDir.path}/fallback-called');
    writeExecutable('osascript', '#!/bin/sh\ntouch "${fallbackMarker.path}"\nexit 0\n');
    // Unfaked, a regression on this route would open the real Simulator.
    writeExecutable('open', '#!/bin/sh\ntouch "${fallbackMarker.path}"\n');
    writeExecutable('caffeinate', '#!/bin/sh\ntouch "${fallbackMarker.path}"\n');

    final result = await runScript(['key', 'down']);
    expect(result.exitCode, isNot(0));
    expect(
      result.error,
      contains('Verify valt niet terug op AppleScript'),
      reason: idbCalls.existsSync() ? idbCalls.readAsStringSync() : 'idb was never called',
    );
    expect(fallbackMarker.existsSync(), false);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
