import 'dart:async';
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
  late File invocationLog;

  setUp(() {
    repoRoot = Directory.systemTemp.createTempSync('pleya-verify-press-');
    argvLog = File('${repoRoot.path}/argv.log');
    invocationLog = File('${repoRoot.path}/invocations.log');
    final script = File('${repoRoot.path}/scripts/tvos_sim.sh')..parent.createSync(recursive: true);
    script.writeAsStringSync('#!/bin/sh\necho "\$@" >> "${argvLog.path}"\n');
    Process.runSync('chmod', ['+x', script.path]);
  });

  tearDown(() => repoRoot.deleteSync(recursive: true));

  TvosSimulatorDriver tvos() =>
      TvosSimulatorDriver(repoRoot: repoRoot, deviceUdidOverride: '00000000-0000-0000-0000-000000000000');

  void recordTyping({bool failColon = false}) {
    final script = File('${repoRoot.path}/scripts/tvos_sim.sh');
    script.writeAsStringSync(
      '#!/bin/sh\n'
      'echo "\$@" >> "${argvLog.path}"\n'
      'printf \'%s\\n\' "\$#" "\${1-}" "\${2-}" "\$TVOS_SIM_UDID" "\$PWD" >> "${invocationLog.path}"\n'
      '${failColon ? 'if [ "\$2" = ":" ]; then echo "colon rejected" >&2; exit 3; fi\n' : ''}',
    );
  }

  List<List<String>> invocations() {
    if (!invocationLog.existsSync()) return [];
    final lines = invocationLog.readAsLinesSync();
    expect(lines.length % 5, 0);
    return [for (var n = 0; n < lines.length; n += 5) lines.sublist(n, n + 5)];
  }

  Future<void> observeDelays(Future<void> Function() action, List<int> completedCalls) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration == const Duration(milliseconds: 100)) {
          completedCalls.add(invocations().length);
          return parent.createTimer(zone, Duration.zero, callback);
        }
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );

  group('tvOS', () {
    test('URL text replays five exact chunks with pinned device and repository cwd', () async {
      recordTyping();
      final port = 20000 + DateTime.now().microsecondsSinceEpoch % 20000;
      final text = 'http://127.0.0.1:$port';
      final completedCalls = <int>[];
      await observeDelays(() => tvos().typeText(text), completedCalls);
      final calls = invocations();
      expect(calls.map((call) => call[2]), ['http', ':', '//127.0.0.1', ':', '$port']);
      expect(calls.map((call) => call[2]).join(), text);
      for (final call in calls) {
        expect(call[0], '2');
        expect(call[1], 'type');
        expect(call[3], '00000000-0000-0000-0000-000000000000');
        expect(Directory(call[4]).resolveSymbolicLinksSync(), repoRoot.resolveSymbolicLinksSync());
      }
      expect(completedCalls, [1, 2, 3, 4, 5]);
    });

    test('100 ms follows every successful chunk including the final chunk', () async {
      recordTyping();
      final completedCalls = <int>[];
      await observeDelays(() => tvos().typeText('a:b'), completedCalls);
      expect(completedCalls, [1, 2, 3]);
    });

    for (final text in ['Zoek Aurora en zoek Basalt.', '']) {
      test('plain or empty text keeps one unchanged type call: "$text"', () async {
        recordTyping();
        final completedCalls = <int>[];
        await observeDelays(() => tvos().typeText(text), completedCalls);
        expect(invocations().map((call) => call.sublist(0, 3)), [
          ['2', 'type', text],
        ]);
        expect(completedCalls, isEmpty);
      });
    }

    test('leading adjacent and trailing colons preserve characters without empty chunks', () async {
      recordTyping();
      final completedCalls = <int>[];
      await observeDelays(() => tvos().typeText(':a::b:'), completedCalls);
      expect(invocations().map((call) => call[2]), [':', 'a', ':', ':', 'b', ':']);
      expect(invocations().map((call) => call[2]).join(), ':a::b:');
      expect(completedCalls, [1, 2, 3, 4, 5, 6]);
    });

    test('failed colon propagates stderr and stops before any later chunk or delay', () async {
      recordTyping(failColon: true);
      final completedCalls = <int>[];
      await expectLater(
        observeDelays(() => tvos().typeText('http://127.0.0.1:34567'), completedCalls),
        throwsA(
          isA<StateError>()
              .having((e) => '$e', 'message', contains('exit 3'))
              .having((e) => '$e', 'stderr', contains('colon rejected')),
        ),
      );
      expect(invocations().map((call) => call[2]), ['http', ':']);
      expect(completedCalls, [1]);
    });

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
