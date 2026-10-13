import 'dart:io';

import 'package:pleya_verify_runner/src/driver/bounded_process.dart';
import 'package:pleya_verify_runner/src/driver/simulator_boot.dart';
import 'package:test/test.dart';

const udid = 'A3615395-EDA9-4A60-982A-D428BCC5719B';
const bundleId = 'nl.michelknoop.pleya.verify';

/// A simulator as the hosted CI runner showed it on 13 October 2026:
/// `bootstatus` returns, and the first `simctl` call after it then waits for
/// what is still starting. Here that wait is [settle]; a call whose ceiling is
/// shorter dies on it, as `runBounded` would make it.
class FakeSimulator {
  FakeSimulator({this.booted = false, this.installed = false, this.settle = Duration.zero, this.bootstatusExit = 0});

  bool booted;
  bool installed;
  Duration settle;
  int bootstatusExit;
  int listappsExit = 0;
  bool _settled = true;
  final calls = <String>[];
  final ceilings = <String, Duration>{};

  Future<ProcessResult> run(String executable, List<String> args, {Duration timeout = defaultProcessTimeout}) async {
    final verb = args[1];
    calls.add(verb == 'list' ? 'list' : verb);
    ceilings[verb] = timeout;
    switch (verb) {
      case 'list':
        return ProcessResult(
          1,
          0,
          booted ? '    iPhone 16e ($udid) (Booted)\n' : '    iPhone 16e ($udid) (Shutdown)\n',
          '',
        );
      case 'boot':
        return ProcessResult(1, 0, '', '');
      case 'bootstatus':
        booted = bootstatusExit == 0;
        _settled = false;
        return ProcessResult(1, bootstatusExit, '', bootstatusExit == 0 ? '' : 'Unable to boot');
    }
    if (!_settled) {
      if (settle > timeout) throw ProcessTimeoutException(executable: executable, arguments: args, timeout: timeout);
      _settled = true;
    }
    switch (verb) {
      case 'listapps':
        final app = installed ? '    "$bundleId" =     {\n        CFBundleIdentifier = "$bundleId";\n    };\n' : '';
        return ProcessResult(
          1,
          listappsExit,
          '{\n    "com.apple.Bridge" =     {\n        CFBundleIdentifier = "com.apple.Bridge";\n    };\n$app}\n',
          '',
        );
      case 'uninstall':
        installed = false;
        return ProcessResult(1, 0, '', '');
      default:
        return ProcessResult(1, verb == 'terminate' && !installed ? 3 : 0, '', '');
    }
  }
}

void main() {
  group('bootSimulator', () {
    test('a cold boot waits on a read with the boot ceiling before it returns', () async {
      final sim = FakeSimulator();

      await bootSimulator(udid: udid, run: sim.run, log: (_) {});

      expect(sim.calls, ['list', 'boot', 'bootstatus', 'listapps']);
      expect(sim.ceilings['bootstatus'], bootProcessTimeout);
      expect(sim.ceilings['listapps'], simulatorSettleTimeout);
    });

    test('a simulator that is already running is not booted and not waited on', () async {
      final sim = FakeSimulator(booted: true);

      await bootSimulator(udid: udid, run: sim.run, log: (_) {});

      expect(sim.calls, ['list']);
    });

    test('a boot that bootstatus reports as failed ends the run by name', () async {
      final sim = FakeSimulator(bootstatusExit: 149);

      await expectLater(
        bootSimulator(udid: udid, run: sim.run, log: (_) {}),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('bootstatus failed'))),
      );
      expect(sim.calls, isNot(contains('listapps')));
    });

    test('a settle call that fails does not end the run', () async {
      final sim = FakeSimulator()..listappsExit = 1;

      await bootSimulator(udid: udid, run: sim.run, log: (_) {});

      expect(sim.calls.last, 'listapps');
    });
  });

  // The failure this file exists for: `reset_app` on a cold simulator whose
  // first call after `bootstatus` takes longer than an ordinary call may.
  test('reset on a cold simulator that settles slower than an ordinary ceiling still completes', () async {
    final sim = FakeSimulator(settle: defaultProcessTimeout + const Duration(seconds: 20));
    final log = <String>[];

    await bootSimulator(udid: udid, run: sim.run, log: log.add);
    await uninstallApp(udid: udid, bundleId: bundleId, run: sim.run, log: log.add);

    expect(sim.calls, ['list', 'boot', 'bootstatus', 'listapps', 'listapps']);
    expect(log.last, contains('not installed'));
  });

  test('a simulator that settles slower than the boot ceiling still fails, on the call that waited', () async {
    final sim = FakeSimulator(settle: simulatorSettleTimeout + const Duration(seconds: 1));

    await expectLater(
      bootSimulator(udid: udid, run: sim.run, log: (_) {}),
      throwsA(isA<ProcessTimeoutException>().having((e) => e.arguments, 'arguments', contains('listapps'))),
    );
  });

  group('uninstallApp', () {
    test('an app that is not installed is neither terminated nor uninstalled', () async {
      final sim = FakeSimulator(booted: true);

      await uninstallApp(udid: udid, bundleId: bundleId, run: sim.run, log: (_) {});

      expect(sim.calls, ['listapps']);
    });

    test('an installed app is terminated and uninstalled', () async {
      final sim = FakeSimulator(booted: true, installed: true);
      final log = <String>[];

      await uninstallApp(udid: udid, bundleId: bundleId, run: sim.run, log: log.add);

      expect(sim.calls, ['listapps', 'terminate', 'uninstall']);
      expect(sim.installed, isFalse);
      expect(log.single, contains('uninstalled'));
    });

    test('an uninstall that fails is logged as failed, not as done', () async {
      final log = <String>[];
      Future<ProcessResult> run(String _, List<String> args, {Duration timeout = defaultProcessTimeout}) async =>
          ProcessResult(1, args[1] == 'uninstall' ? 1 : 0, '', '');

      await uninstallApp(udid: udid, bundleId: bundleId, run: run, log: log.add);

      expect(log.single, contains('exited 1'));
      expect(log.single, isNot(contains('uninstalled')));
    });

    test('when the app list cannot be read the uninstall is not skipped', () async {
      final sim = FakeSimulator(booted: true, installed: true)..listappsExit = 1;

      await uninstallApp(udid: udid, bundleId: bundleId, run: sim.run, log: (_) {});

      expect(sim.calls, ['listapps', 'terminate', 'uninstall']);
    });
  });

  group('isAppInstalled on output it cannot trust', () {
    Future<bool> installedGiven(String stdout, {int exit = 0}) => isAppInstalled(
      udid: udid,
      bundleId: bundleId,
      run: (_, _, {Duration timeout = defaultProcessTimeout}) async => ProcessResult(1, exit, stdout, ''),
    );

    test('empty output counts as installed, so the uninstall is not skipped', () async {
      expect(await installedGiven(''), isTrue);
    });

    test('output in another format counts as installed', () async {
      expect(await installedGiven('{"com.apple.Bridge": {"CFBundleIdentifier": "com.apple.Bridge"}}'), isTrue);
    });

    test('a list that was cut off before it closed counts as installed', () async {
      final captured = File('test/fixtures/simctl_listapps_ios27.txt').readAsStringSync();
      final cutOff = captured.substring(0, captured.indexOf('"nl.michelknoop.pleya"'));

      expect(await installedGiven(cutOff), isTrue);
    });

    test('captured simctl output is trusted: the installed app is found, another is not', () async {
      final captured = File('test/fixtures/simctl_listapps_ios27.txt').readAsStringSync();

      expect(await installedGiven(captured), isTrue);
      expect(await installedGiven(captured.replaceAll('pleya.verify', 'pleya.other')), isFalse);
    });

    test('a list with apps but without this one counts as not installed', () async {
      expect(await installedGiven('{\n    Plain =     {\n        CFBundleIdentifier = Plain;\n    };\n}\n'), isFalse);
    });
  });

  // What `xcrun simctl listapps` printed on an iOS 27.0 simulator on 13 October
  // 2026, cut down to three apps. The hand-written listings above only prove
  // the pattern against an idea of the format; this proves it against the tool.
  group('listsBundleId on captured simctl output', () {
    final captured = File('test/fixtures/simctl_listapps_ios27.txt').readAsStringSync();

    test('finds an installed user app and a system app', () {
      expect(listsBundleId(captured, 'nl.michelknoop.pleya.verify'), isTrue);
      expect(listsBundleId(captured, 'nl.michelknoop.pleya'), isTrue);
      expect(listsBundleId(captured, 'com.apple.Bridge'), isTrue);
    });

    test('does not find an app that is not in the list', () {
      expect(listsBundleId(captured, 'nl.michelknoop.pleya.verif'), isFalse);
      expect(listsBundleId(captured, 'michelknoop.pleya.verify'), isFalse);
      expect(listsBundleId(captured, 'nl.michelknoop.pleya.verify.other'), isFalse);
    });
  });

  group('listsBundleId', () {
    const listing = '''
{
    "nl.michelknoop.pleya.verify.extension" =     {
        CFBundleIdentifier = "nl.michelknoop.pleya.verify.extension";
        CFBundleName = Extension;
    };
    Plain =     {
        CFBundleIdentifier = Plain;
    };
}
''';

    test('matches the whole identifier, quoted or bare', () {
      expect(listsBundleId(listing, 'nl.michelknoop.pleya.verify.extension'), isTrue);
      expect(listsBundleId(listing, 'Plain'), isTrue);
    });

    test('does not match an app whose identifier only starts or ends with it', () {
      expect(listsBundleId(listing, 'nl.michelknoop.pleya.verify'), isFalse);
      expect(listsBundleId(listing, 'pleya.verify.extension'), isFalse);
      expect(listsBundleId(listing, 'nl.michelknoop.pleyaXverify.extension'), isFalse);
    });
  });

  group('timedSimctl', () {
    test('logs how long a simctl call took and how it ended', () async {
      final log = <String>[];

      final result = await timedSimctl('xcrun', ['simctl', 'terminate', udid, bundleId], log.add, () async {
        return ProcessResult(1, 3, '', '');
      });

      expect(result.exitCode, 3);
      expect(log.single, matches(RegExp('^\\[\\d+ ms, exit 3\\] simctl terminate $udid $bundleId\$')));
    });

    test('logs a call that was killed on its ceiling and passes the error on', () async {
      final log = <String>[];
      const args = ['simctl', 'terminate', udid, bundleId];

      await expectLater(
        timedSimctl('xcrun', args, log.add, () async {
          throw const ProcessTimeoutException(executable: 'xcrun', arguments: args, timeout: defaultProcessTimeout);
        }),
        throwsA(isA<ProcessTimeoutException>()),
      );
      expect(log.single, contains('killed on its ceiling'));
    });

    test('leaves other tools out of the log', () async {
      final log = <String>[];

      await timedSimctl('codesign', ['--force'], log.add, () async => ProcessResult(1, 0, '', ''));
      await timedSimctl('xcrun', ['xcodebuild'], log.add, () async => ProcessResult(1, 0, '', ''));

      expect(log, isEmpty);
    });
  });
}
