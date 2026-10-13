import 'dart:io';

import 'bounded_process.dart';

// What the simulator drivers share around a boot: waiting until a freshly
// booted simulator answers, asking whether the app is on it, and timing every
// `simctl` call into the driver log.
//
// Why this exists: `simctl bootstatus -b` returns before a cold simulator is
// done. Measured on the hosted `macos-26` runner on 13 October 2026 (iPhone
// 16e, iOS 26.2, eighteen cold boots): `bootstatus` returned after 81 to
// 111 s with exit 0, and the first `simctl` call after it then took another
// 26 to 78 s, whichever call it was (`terminate` of an app that was not
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
  // starting. Make it a read with the boot's ceiling, so the calls that follow
  // run against a simulator that answers.
  // No verdict on the outcome: before this call existed, whatever ran first
  // was not judged either, and the calls after it say what is wrong by name.
  await run('xcrun', ['simctl', 'listapps', udid], timeout: simulatorSettleTimeout);
}

/// Whether [bundleId] is installed on the booted simulator [udid].
///
/// Answers `true` when the list cannot be trusted, which is a failed call or
/// output without a single app in it (a booted simulator always lists its
/// system apps): the caller uses a `false` to skip an uninstall, and skipping
/// one that was needed would hand the next launch the data of an earlier run.
Future<bool> isAppInstalled({required String udid, required String bundleId, required ProcessRunner run}) async {
  final apps = await run('xcrun', ['simctl', 'listapps', udid]);
  final listing = apps.stdout as String;
  if (apps.exitCode != 0 || !_anyApp.hasMatch(listing)) return true;
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
  await run('xcrun', ['simctl', 'uninstall', udid, bundleId]);
  log('installFresh: uninstalled $bundleId from $udid');
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
