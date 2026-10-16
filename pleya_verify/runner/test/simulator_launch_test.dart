import 'dart:io';

import 'package:pleya_verify_runner/src/driver/bounded_process.dart';
import 'package:pleya_verify_runner/src/driver/simulator_boot.dart';
import 'package:test/test.dart';

const udid = 'A3615395-EDA9-4A60-982A-D428BCC5719B';
const bundleId = 'nl.michelknoop.pleya.verify';

enum Outcome { launches, exits, timesOut }

/// `simctl launch` as the hosted CI runner showed it on 16 October 2026: where
/// a healthy launch returns in about 18 s, some ran into their ceiling with an
/// empty app log, while `terminate` still answered right after.
class FakeLaunchSimulator {
  FakeLaunchSimulator(this.launches, {this.terminateTimesOut = false});

  /// What each successive `simctl launch` does.
  final List<Outcome> launches;
  final bool terminateTimesOut;
  final calls = <String>[];
  final ceilings = <String, Duration>{};

  int get launchCount => calls.where((c) => c == 'launch').length;

  Future<ProcessResult> run(String executable, List<String> args, {Duration timeout = defaultProcessTimeout}) async {
    final verb = executable == 'xcrun' ? args[1] : executable;
    calls.add(verb);
    ceilings[verb] = timeout;
    switch (verb) {
      case 'launch':
        final outcome = launches[launchCount - 1];
        switch (outcome) {
          case Outcome.timesOut:
            throw ProcessTimeoutException(executable: executable, arguments: args, timeout: timeout);
          case Outcome.exits:
            return ProcessResult(1, 1, '', 'The operation couldn’t be completed.');
          case Outcome.launches:
            return ProcessResult(1, 0, '$bundleId: 4242\n', '');
        }
      case 'terminate':
        if (terminateTimesOut) throw ProcessTimeoutException(executable: executable, arguments: args, timeout: timeout);
        return ProcessResult(1, 0, '', '');
      case 'uptime':
        return ProcessResult(1, 0, ' 12:31  up 2:11, 2 users, load averages: 31.2 28.9 20.4\n', '');
      case 'ps':
        return ProcessResult(1, 0, '  PID ELAPSED %CPU %MEM COMM\n 4242 03:00 99.0 1.0 launchd_sim\n', '');
      case 'list':
        return ProcessResult(1, 0, '    iPhone 16e ($udid) (Booted)\n', '');
    }
    return ProcessResult(1, 0, '', '');
  }
}

void main() {
  group('launchApp', () {
    test('a launch that answers runs once, under a ceiling above the three minutes of an ordinary call', () async {
      final sim = FakeLaunchSimulator([Outcome.launches]);
      final log = <String>[];

      final result = await launchApp(udid: udid, bundleId: bundleId, run: sim.run, log: log.add);

      expect(result.exitCode, 0);
      expect(sim.calls, ['launch']);
      expect(sim.ceilings['launch'], simulatorLaunchTimeout);
      expect(simulatorLaunchTimeout, greaterThan(defaultProcessTimeout));
      expect(log, isEmpty);
    });

    test('a launch that times out is terminated and tried once more', () async {
      final sim = FakeLaunchSimulator([Outcome.timesOut, Outcome.launches]);
      final log = <String>[];

      final result = await launchApp(udid: udid, bundleId: bundleId, run: sim.run, log: log.add);

      expect(result.exitCode, 0);
      expect(sim.launchCount, 2);
      expect(sim.calls.indexOf('terminate'), greaterThan(sim.calls.indexOf('launch')));
      expect(sim.calls.lastIndexOf('launch'), greaterThan(sim.calls.indexOf('terminate')));
      expect(sim.ceilings['launch'], simulatorLaunchTimeout);
    });

    test('the retry leaves the host and simulator state in the log', () async {
      final sim = FakeLaunchSimulator([Outcome.timesOut, Outcome.launches]);
      final log = <String>[];

      await launchApp(udid: udid, bundleId: bundleId, run: sim.run, log: log.add);

      expect(log.first, contains('retrying once'));
      expect(log.any((l) => l.contains('launch diagnosis: uptime')), isTrue);
      expect(log.any((l) => l.contains('load averages: 31.2')), isTrue);
      expect(log.any((l) => l.contains('launch diagnosis: xcrun simctl list devices')), isTrue);
      expect(log.any((l) => l.contains('launchd_sim')), isTrue);
      // Bounded: a diagnosis command must not turn a slow runner into a longer wait.
      expect(sim.ceilings['uptime'], lessThan(defaultProcessTimeout));
      expect(sim.ceilings['ps'], lessThan(defaultProcessTimeout));
    });

    test('a second timeout is thrown, and there is no third launch', () async {
      final sim = FakeLaunchSimulator([Outcome.timesOut, Outcome.timesOut, Outcome.launches]);

      await expectLater(
        launchApp(udid: udid, bundleId: bundleId, run: sim.run, log: (_) {}),
        throwsA(isA<ProcessTimeoutException>()),
      );

      expect(sim.launchCount, 2);
    });

    test('a launch that exits non-zero is an answer and is not retried', () async {
      final sim = FakeLaunchSimulator([Outcome.exits, Outcome.launches]);

      final result = await launchApp(udid: udid, bundleId: bundleId, run: sim.run, log: (_) {});

      expect(result.exitCode, 1);
      expect(sim.calls, ['launch']);
    });

    test('a terminate that times out does not stop the retry', () async {
      final sim = FakeLaunchSimulator([Outcome.timesOut, Outcome.launches], terminateTimesOut: true);
      final log = <String>[];

      final result = await launchApp(udid: udid, bundleId: bundleId, run: sim.run, log: log.add);

      expect(result.exitCode, 0);
      expect(sim.launchCount, 2);
      expect(log.any((l) => l.contains('terminate before the retry timed out')), isTrue);
    });
  });
}
