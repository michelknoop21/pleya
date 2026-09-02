import 'dart:io';

import 'package:pleya_verify_runner/src/driver/ios_simulator_driver.dart';
import 'package:pleya_verify_runner/src/driver/macos_driver.dart';
import 'package:pleya_verify_runner/src/driver/tvos_simulator_driver.dart';
import 'package:test/test.dart';

/// What a `press` actually turns into on the wire, per target.
///
/// The tvOS half runs the driver against a stand-in `scripts/tvos_sim.sh`
/// that records its argv, because the thing worth testing is the argument
/// construction: a long press that quietly loses its `--hold-ms` is a short
/// press, and a scenario asserting "long SELECT opens the context menu"
/// would then fail for a reason that has nothing to do with the app.
void main() {
  late Directory repoRoot;
  late File argvLog;

  setUp(() {
    repoRoot = Directory.systemTemp.createTempSync('pleya-verify-press-');
    argvLog = File('${repoRoot.path}/argv.log');
    final script = File('${repoRoot.path}/scripts/tvos_sim.sh')..parent.createSync(recursive: true);
    script.writeAsStringSync('#!/bin/sh\necho "\$@" >> "${argvLog.path}"\n');
    Process.runSync('chmod', ['+x', script.path]);
  });

  tearDown(() => repoRoot.deleteSync(recursive: true));

  TvosSimulatorDriver tvos() =>
      TvosSimulatorDriver(repoRoot: repoRoot, deviceUdidOverride: '00000000-0000-0000-0000-000000000000');

  group('tvOS', () {
    test('a short press is `key <name>` with no duration flag', () async {
      await tvos().press('down');
      expect(argvLog.readAsStringSync().trim(), 'key down');
    });

    test('a long press carries --hold-ms, in milliseconds', () async {
      await tvos().press('select', hold: const Duration(milliseconds: 1200));
      expect(argvLog.readAsStringSync().trim(), 'key select --hold-ms 1200');
    });

    test('menu is dispatched like any other key — Back is not a special case', () async {
      await tvos().press('menu');
      expect(argvLog.readAsStringSync().trim(), 'key menu');
    });

    test('a non-zero exit from the script fails the press instead of passing silently', () async {
      File('${repoRoot.path}/scripts/tvos_sim.sh').writeAsStringSync('#!/bin/sh\nexit 3\n');
      Process.runSync('chmod', ['+x', '${repoRoot.path}/scripts/tvos_sim.sh']);
      await expectLater(
        tvos().press('select', hold: const Duration(milliseconds: 900)),
        throwsA(isA<StateError>().having((e) => '$e', 'message', contains('--hold-ms 900'))),
      );
    });
  });

  group('targets that press through the transport', () {
    test('macOS rejects a hold rather than degrading it to a short press', () {
      expect(
        () => MacosDriver(repoRoot: repoRoot).press('select', hold: const Duration(milliseconds: 900)),
        throwsA(isA<UnsupportedError>().having((e) => '$e', 'message', contains('no down/up split'))),
      );
    });

    test('the iOS simulator rejects a hold the same way', () {
      expect(
        () => IosSimulatorDriver(repoRoot: repoRoot).press('select', hold: const Duration(milliseconds: 900)),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
