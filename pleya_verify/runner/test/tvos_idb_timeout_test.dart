import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

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
    final output = process.stdout.transform(utf8.decoder).join();
    final error = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -999;
      },
    );
    return (
      exitCode: exitCode,
      output: exitCode == -999 ? '' : await output,
      error: exitCode == -999 ? '' : await error,
    );
  }

  test('a hung idb connect is bounded and cannot fall back to host keyboard input', () async {
    writeExecutable('idb', '#!/bin/sh\nexec sleep 30\n');
    writeExecutable('osascript', '#!/bin/sh\necho SHOULD_NOT_RUN >&2\nexit 91\n');

    final result = await runScript(['doctor', '--json']);
    expect(result.exitCode, 0, reason: 'doctor must finish despite a wedged idb connect');
    final body = jsonDecode(result.output) as Map<String, Object?>;
    expect(body['input'], 'none');
  });

  test('a failed idb key never silently falls back to AppleScript in Verify', () async {
    final idbCalls = File('${binDir.path}/idb-calls');
    writeExecutable('idb', '#!/bin/sh\necho "\$@" >> "${idbCalls.path}"\n[ "\$1" = connect ] && exit 0\nexit 7\n');
    final fallbackMarker = File('${binDir.path}/fallback-called');
    writeExecutable('osascript', '#!/bin/sh\ntouch "${fallbackMarker.path}"\nexit 0\n');

    final result = await runScript(['key', 'down']);
    expect(result.exitCode, isNot(0));
    expect(
      result.error,
      contains('Verify valt niet terug op AppleScript'),
      reason: idbCalls.existsSync() ? idbCalls.readAsStringSync() : 'idb was never called',
    );
    expect(fallbackMarker.existsSync(), false);
  });
}
