import 'dart:io';

import 'package:test/test.dart';

/// [C2], enforced by source scan rather than trust: a tvOS `press`/
/// `typeText`/`tap` must never route through the automation HTTP transport —
/// idb HID is the only valid input path (see the class doc on
/// `TvosSimulatorDriver`). Mirrors `test/no_bare_text_field_test.dart`'s
/// style: a plain text scan of the method body, not a full Dart parse.
void main() {
  for (final matches in [true, false]) {
    test('tvOS input ${matches ? "reuses" : "rejects"} a companion after checking its target', () async {
      final temp = Directory.systemTemp.createTempSync('pleya-idb-routing-');
      final target = 'pleya-routing-$pid-${matches ? "match" : "mismatch"}';
      final socketPath = '/tmp/idb/${target}_companion.sock';
      Directory('/tmp/idb').createSync(recursive: true);
      final socket = await ServerSocket.bind(InternetAddress(socketPath, type: InternetAddressType.unix), 0);
      addTearDown(() async {
        await socket.close();
        final socketFile = File(socketPath);
        if (socketFile.existsSync()) socketFile.deleteSync();
        temp.deleteSync(recursive: true);
      });
      final fake = File('${temp.path}/idb')
        ..writeAsStringSync(r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['TASK_IDB_CALLS'], 'a') as log:
    log.write(' '.join(sys.argv[1:]) + '\n')
if '--companion' not in sys.argv:
    sys.exit(73)
if 'describe' in sys.argv:
    print(json.dumps({'udid': os.environ['TASK_IDB_TARGET']}))
''');
      await Process.run('chmod', ['+x', fake.path]);
      final source = File('../../scripts/tvos_sim.sh').readAsStringSync();
      final functions = source.substring(source.indexOf('IDB_READY=""'), source.indexOf('# HID usage codes;'));
      final result = await Process.run(
        'bash',
        ['-c', '$functions\nDEVICE="$target"\nidb_available && bounded_idb ui key 79'],
        environment: {
          'PATH': '${temp.path}:${Platform.environment['PATH']}',
          'TASK_IDB_TARGET': matches ? target : 'another-simulator',
          'TASK_IDB_CALLS': '${temp.path}/calls',
        },
      );
      final calls = File('${temp.path}/calls').readAsStringSync();
      if (matches) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(calls, contains('--companion $socketPath ui key 79'));
        expect(calls, isNot(contains('connect ')));
      } else {
        expect(result.exitCode, isNot(0));
        expect(calls, contains('connect $target'));
        expect(calls, isNot(contains('ui key')));
      }
    });
  }

  test('TvosSimulatorDriver.press/typeText/tap never reference VerifyClient or http', () {
    final source = File('lib/src/driver/tvos_simulator_driver.dart').readAsStringSync();
    final forbidden = ['VerifyClient', 'http.', 'package:http'];

    for (final methodStart in const [
      'Future<void> press(String key, {Duration? hold}) async {',
      'Future<void> typeText(String text) async {',
      'Future<void> tap(double x, double y, {Duration? hold}) {',
    ]) {
      final startIndex = source.indexOf(methodStart);
      expect(startIndex, isNonNegative, reason: 'method signature not found (did it change?): $methodStart');

      final bodyStart = source.indexOf('{', startIndex) + 1;
      var depth = 1;
      var i = bodyStart;
      while (depth > 0) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') depth--;
        i++;
      }
      final body = source.substring(bodyStart, i - 1);

      for (final token in forbidden) {
        expect(
          body.contains(token),
          isFalse,
          reason:
              '$methodStart contains "$token" — tvOS input must go through tvos_sim.sh (idb HID), never the '
              'transport ([C2]). Body:\n$body',
        );
      }
    }
  });
}
