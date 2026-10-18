import 'dart:io';

import 'bounded_process.dart';

// What the simulator drivers share around a boot: giving a freshly booted
// simulator a first call with the boot's ceiling, asking whether the app is on
// it, and timing every `simctl` call into the driver log.
//
// Why this exists: `simctl bootstatus -b` returns before a cold simulator is
// done. Measured on the hosted `macos-26` runner on 13 October 2026 (iPhone
// 16e, iOS 26.2, 24 cold boots): `bootstatus` returned after 80 to 114 s
// with exit 0, and the first `simctl` call after it then took another 25 to
// 94 s, whichever call it was (`terminate` of an app that was not
// installed, `listapps`, `spawn`). The drivers made that first call a
// `terminate` under [defaultProcessTimeout]. In CI that call was killed on its
// three minutes in 4 of 27 runs of `discover.layout`, in the first step,
// before the app was even installed. The probe never reproduced a call that
// long, so "slow, not stuck" is inferred from these numbers and not observed;
// the timing lines of [timedSimctl] are there to settle it on the next one.

/// Runs one external tool under a ceiling: the drivers' `_run`.
typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> args, {Duration timeout});

/// Ceiling for the first `simctl` call after a cold boot, the one that waits
/// for the simulator to finish coming up. It is part of the boot, so it gets
/// the boot's ceiling and not the three minutes of an ordinary call.
const Duration simulatorSettleTimeout = bootProcessTimeout;

/// Boots [udid] when it is not running yet and gives it time to answer.
///
/// A simulator that `simctl list` already reports as booted is left alone, as
/// before. That includes one that was booted moments ago by something else
/// and is still settling: its first call runs under the ordinary ceiling.
Future<void> bootSimulator({
  required String udid,
  required ProcessRunner run,
  required void Function(String line) log,
}) async {
  final list = await run('xcrun', ['simctl', 'list', 'devices']);
  final alreadyBooted = RegExp('$udid.*Booted').hasMatch(list.stdout as String);
  if (alreadyBooted) return;
  log('booting $udid');
  // No verdict on `boot` itself: it also exits non-zero for a device that is
  // already on its way up. `bootstatus` is the one that says how it ended.
  await run('xcrun', ['simctl', 'boot', udid]);
  final status = await run('xcrun', ['simctl', 'bootstatus', udid, '-b'], timeout: bootProcessTimeout);
  if (status.exitCode != 0) {
    throw StateError('simctl bootstatus failed for $udid (exit ${status.exitCode}): ${status.stderr}');
  }
  // The first call after `bootstatus` pays for whatever the simulator is still
  // starting. Make it a read with the boot's ceiling, so that wait does not
  // land on a call with three minutes. Its outcome is not judged: whatever ran
  // first before this call existed was not judged either.
  await run('xcrun', ['simctl', 'listapps', udid], timeout: simulatorSettleTimeout);
}

/// Whether [bundleId] is installed on the booted simulator [udid].
///
/// Answers `true` when the list cannot be trusted: a failed call, output
/// without a single app in it, or output that does not end where the property
/// list closes. The caller uses a `false` to skip an uninstall, and skipping
/// one that was needed would hand the next launch the data of an earlier run.
Future<bool> isAppInstalled({required String udid, required String bundleId, required ProcessRunner run}) async {
  final apps = await run('xcrun', ['simctl', 'listapps', udid]);
  final listing = apps.stdout as String;
  final complete = _anyApp.hasMatch(listing) && listing.trimRight().endsWith('}');
  if (apps.exitCode != 0 || !complete) return true;
  return listsBundleId(listing, bundleId);
}

final _anyApp = RegExp(r'^\s*CFBundleIdentifier = ', multiLine: true);

/// Whether the property list `simctl listapps` prints has an app with
/// [bundleId]. Matches the whole identifier, so `a.b` does not match `a.b.c`.
bool listsBundleId(String listapps, String bundleId) =>
    RegExp('^\\s*CFBundleIdentifier = "?${RegExp.escape(bundleId)}"?;\\s*\$', multiLine: true).hasMatch(listapps);

/// Leaves the booted simulator [udid] without [bundleId] and its data.
///
/// An app that is not there is not terminated and not uninstalled: on a fresh
/// simulator those two calls only wait.
Future<void> uninstallApp({
  required String udid,
  required String bundleId,
  required ProcessRunner run,
  required void Function(String line) log,
}) async {
  if (!await isAppInstalled(udid: udid, bundleId: bundleId, run: run)) {
    log('installFresh: $bundleId is not installed on $udid, nothing to remove');
    return;
  }
  await run('xcrun', ['simctl', 'terminate', udid, bundleId]);
  final uninstall = await run('xcrun', ['simctl', 'uninstall', udid, bundleId]);
  log(
    uninstall.exitCode == 0
        ? 'installFresh: uninstalled $bundleId from $udid'
        : 'installFresh: simctl uninstall of $bundleId on $udid exited ${uninstall.exitCode}',
  );
}

/// Runs [body] and, for a `simctl` call, logs how long it took and how it
/// ended. A run that fails on a ceiling then shows which calls were slow
/// before it, instead of only the one that was killed.
Future<ProcessResult> timedSimctl(
  String executable,
  List<String> args,
  void Function(String line) log,
  Future<ProcessResult> Function() body,
) async {
  if (executable != 'xcrun' || args.isEmpty || args.first != 'simctl') return body();
  final command = args.join(' ');
  final watch = Stopwatch()..start();
  try {
    final result = await body();
    log('[${watch.elapsedMilliseconds} ms, exit ${result.exitCode}] $command');
    return result;
  } on ProcessTimeoutException {
    log('[${watch.elapsedMilliseconds} ms, killed on its ceiling] $command');
    rethrow;
  }
}

/// Ceiling for `simctl launch`. A launch on a healthy runner takes about 18 s;
/// on the hosted `macos-26` runner it was killed on the three minutes of
/// [defaultProcessTimeout] in `discover.layout` on 16 October 2026, in three
/// PR checks (#340, #346, #348), and `app.log` was empty: no app output was
/// seen. The calls around it were slow too in those runs (`terminate` 23 and
/// 49 s against 1.7 s, `bootstatus` 82 and 97 s against 65 s), and the
/// simulator answered a `terminate` right after. What it was, a slow launch or
/// a stuck one, was not observed. The ceiling is longer than an ordinary call
/// and one retry follows a timeout; neither is proven to be enough, which is
/// what the diagnosis lines of [launchApp] are for.
///
/// The worst case of one [launchApp] is this ceiling, three diagnosis commands
/// of [_launchDiagnosisTimeout], a terminate of [_launchTerminateTimeout] and
/// this ceiling again: about ten minutes, against three before. The macOS job
/// has thirty for its build and both scenarios.
const Duration simulatorLaunchTimeout = Duration(minutes: 4);

/// How long the iOS simulator driver waits for the launched app to announce
/// itself and answer `/v1/health`. The 20 s every other driver uses was too
/// short on a loaded CI runner (16 Oct): after a 130 s `simctl launch` the
/// app needed 37 s between two log lines. The driver logs how long it took,
/// so a runner that gets slower still shows up in driver.log.
const Duration simulatorHealthTimeout = Duration(seconds: 60);

/// Ceiling for each of the diagnosis commands [launchApp] runs after a launch
/// that timed out. They must not turn a slow simulator into a longer wait.
const Duration _launchDiagnosisTimeout = Duration(seconds: 20);

/// Ceiling for the terminate that precedes the retry. In the runs that failed it
/// took 23 and 49 s, so a minute is room; it is not allowed three.
const Duration _launchTerminateTimeout = Duration(minutes: 1);

/// How many lines of a diagnosis command go into the driver log.
const int _launchDiagnosisLines = 40;

/// Launches [bundleId] on the booted simulator [udid].
///
/// A `simctl launch` that outlives [simulatorLaunchTimeout] is killed by the
/// runner and ends in a [ProcessTimeoutException]. That is retried once: the
/// state of the machine and the simulator goes into the driver log, the app is
/// terminated (its outcome and its own timeout are not judged, the launch that
/// follows is), and `simctl launch` runs again under the same ceiling. A second
/// timeout is thrown as it is. A launch that returns a non-zero exit code is not
/// retried: that is an answer from the simulator, and the caller reports it.
Future<ProcessResult> launchApp({
  required String udid,
  required String bundleId,
  required ProcessRunner run,
  required void Function(String line) log,
}) async {
  Future<ProcessResult> launch() => run('xcrun', ['simctl', 'launch', udid, bundleId], timeout: simulatorLaunchTimeout);
  try {
    return await launch();
  } on ProcessTimeoutException catch (e) {
    log('launch: $e; retrying once after a terminate');
  }
  await _logLaunchDiagnosis(udid: udid, run: run, log: log);
  try {
    await run('xcrun', ['simctl', 'terminate', udid, bundleId], timeout: _launchTerminateTimeout);
  } on ProcessTimeoutException catch (e) {
    log('launch: terminate before the retry timed out ($e)');
  } on Exception catch (e) {
    log('launch: terminate before the retry failed ($e)');
  }
  return launch();
}

/// Writes what is known about the machine and the simulator to the driver log,
/// so a launch that timed out can be told apart as "slow host" or "stuck
/// simulator" on the next run. It runs after the stranded launch was killed, so
/// it shows the state then and can miss a load that was already gone. Every
/// command is bounded, none is judged, and none can fail the launch: a command
/// that is missing, fails to start or answers with something else is logged.
Future<void> _logLaunchDiagnosis({
  required String udid,
  required ProcessRunner run,
  required void Function(String line) log,
}) async {
  final commands = <List<String>>[
    ['uptime'],
    ['xcrun', 'simctl', 'list', 'devices'],
    // The busiest processes of the host by CPU: a runner that is slow for
    // everything shows up here, a stuck simulator does not.
    ['ps', '-Aro', 'pid,etime,pcpu,pmem,comm'],
  ];
  for (final command in commands) {
    try {
      final result = await run(command.first, command.sublist(1), timeout: _launchDiagnosisTimeout);
      final lines = result.stdout.toString().trimRight().split('\n');
      log('launch diagnosis: ${command.join(' ')} (exit ${result.exitCode}, ${lines.length} lines)');
      lines.take(_launchDiagnosisLines).forEach((line) => log('  $line'));
    } on ProcessTimeoutException {
      log('launch diagnosis: ${command.join(' ')} did not answer within $_launchDiagnosisTimeout');
    } on Exception catch (e) {
      log('launch diagnosis: ${command.join(' ')} could not be run ($e)');
    }
  }
}
