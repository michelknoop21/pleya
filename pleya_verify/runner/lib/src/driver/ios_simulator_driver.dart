import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../transport/verify_client.dart';
import 'instance_discovery.dart';
import 'verification_driver.dart';

/// Drives a local iOS-simulator build of Pleya via `xcrun simctl`.
///
/// **Bundle-id-rewrite trick, same as [MacosDriver] — proven necessary by
/// hand, not just assumed harmless.** The original reasoning here was that a
/// simulator device's on-disk container
/// (`~/Library/Developer/CoreSimulator/Devices/<udid>/data/…`) is isolated
/// by construction, so no rewrite would be needed. That reasoning missed a
/// second channel: `ios/Runner/Runner.entitlements` (and macOS's, and
/// tvOS's) all declare `com.apple.developer.ubiquity-kvstore-identifier` as
/// `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` — a cross-device sync
/// identifier keyed by bundle id, not by device. Running the *real* bundle
/// id (`nl.michelknoop.pleya`) on a brand-new, never-before-used **tvOS**
/// simulator surfaced a real signed-in "applereview" Jellyfin session within
/// seconds of first launch, before any fixture sign-in ran — proven by hand
/// during Fase 10, not hypothetical. iOS shares the identical entitlement
/// pattern, so it gets the identical fix even though a Fase-9 run happened
/// not to observe contamination (most likely timing, not a structural
/// difference): [build] copies the compiled `.app`, rewrites
/// `CFBundleIdentifier` to [verifyBundleId], and re-signs ad hoc — the same
/// technique [MacosDriver] already validated.
///
/// **Pointer/key input goes through the transport**, unlike the tvOS driver
/// (Fase 10): iOS-sim has no HID-injection requirement equivalent to the
/// tvOS-invoerroute-invariant ([C2]) — a touch-driven target's own
/// `/v1/input/*` is a faithful enough stand-in for a tap. [screenshot] still
/// always goes through `simctl io … screenshot`, the [C5] authoritative
/// capture, never `/v1/screenshot`.
class IosSimulatorDriver implements VerificationDriver {
  final Directory repoRoot;
  final String verifyBundleId;

  /// Escape hatch only — see [MacosDriver.portOverride] and
  /// `instance_discovery.dart`. Leave null so [launch] discovers the port
  /// the app actually bound.
  final int? portOverride;
  final void Function(String line)? onDriverLog;

  /// Overrides device auto-resolution — an already-booted iOS simulator, or
  /// (falling back) `PLEYA_VERIFY_IOS_UDID` env var. Mirrors
  /// `TVOS_SIM_UDID` in `scripts/tvos_sim.sh`.
  final String? deviceUdidOverride;

  String? _resolvedUdid;
  final List<String> _driverLog = [];
  VerifyClient? _client;
  VerifyInstance? _instance;

  IosSimulatorDriver({
    required this.repoRoot,
    this.verifyBundleId = 'nl.michelknoop.pleya.verify',
    this.portOverride,
    this.onDriverLog,
    this.deviceUdidOverride,
  });

  @override
  VerifyInstance? get instance => _instance;

  @override
  String get target => 'ios-sim';

  @override
  VerifyClient? get client => _client;

  @override
  String get inputRoute => 'transport';

  Directory get _sourceAppDir => Directory('${repoRoot.path}/build/ios/iphonesimulator/Runner.app');

  /// The isolated, re-signed copy this driver actually installs — kept
  /// outside any per-run evidence bundle so repeated runs reuse one build
  /// instead of copying+re-signing the `.app` every time.
  Directory get isolatedAppDir => Directory('${repoRoot.path}/.build/pleya-verify/ios-app/Runner.app');

  void _log(String line) {
    _driverLog.add(line);
    onDriverLog?.call(line);
  }

  @override
  List<String> get driverLog => List.unmodifiable(_driverLog);

  @override
  Future<DriverDoctorReport> doctor() async {
    final checks = <String, Object?>{};

    final flutterVersion = await _run('flutter', ['--version']);
    checks['flutter'] = flutterVersion.exitCode == 0;

    final xcodebuild = await _run('xcodebuild', ['-version']);
    checks['xcodebuild'] = xcodebuild.exitCode == 0;

    checks['sourceAppBuilt'] = _sourceAppDir.existsSync();
    checks['isolatedAppReady'] = isolatedAppDir.existsSync();

    String? deviceError;
    try {
      checks['device'] = await _resolveDevice();
    } catch (e) {
      deviceError = '$e';
      checks['device'] = false;
    }

    final ready = deviceError == null && checks.values.every((v) => v == true || v is! bool);
    return DriverDoctorReport(ready: ready, checks: checks);
  }

  @override
  Future<void> build() async {
    _log('flutter build ios --simulator --debug --dart-define=PLEYA_VERIFY=true');
    final gitCommit = await _gitCommit();
    final result = await _run('flutter', [
      'build',
      'ios',
      '--simulator',
      '--debug',
      '--dart-define=PLEYA_VERIFY=true',
      if (gitCommit != null) '--dart-define=GIT_COMMIT=$gitCommit',
    ], workingDirectory: repoRoot.path);
    _log(result.stdout.toString());
    if (result.exitCode != 0) {
      _log(result.stderr.toString());
      throw StateError('flutter build ios --simulator failed (exit ${result.exitCode})');
    }
    if (!_sourceAppDir.existsSync()) {
      throw StateError('flutter build ios --simulator reported success but ${_sourceAppDir.path} does not exist');
    }

    if (isolatedAppDir.existsSync()) {
      isolatedAppDir.deleteSync(recursive: true);
    }
    isolatedAppDir.parent.createSync(recursive: true);
    _log('copying ${_sourceAppDir.path} -> ${isolatedAppDir.path}');
    final copy = await _run('cp', ['-R', _sourceAppDir.path, isolatedAppDir.path]);
    if (copy.exitCode != 0) {
      throw StateError('cp of the app bundle failed (exit ${copy.exitCode}): ${copy.stderr}');
    }

    final infoPlist = File('${isolatedAppDir.path}/Info.plist');
    final rewrite = await _run('plutil', [
      '-replace',
      'CFBundleIdentifier',
      '-string',
      verifyBundleId,
      infoPlist.path,
    ]);
    if (rewrite.exitCode != 0) {
      throw StateError(
        'rewriting CFBundleIdentifier failed (exit ${rewrite.exitCode}): ${rewrite.stderr} — '
        'without it the app runs under the real bundle id and inherits the iCloud-KVS-synced session '
        'this class\'s doc describes',
      );
    }
    await _assertBundleId(infoPlist, expected: verifyBundleId);

    _log('codesign --force --deep --sign - ${isolatedAppDir.path}');
    final sign = await _run('codesign', ['--force', '--deep', '--sign', '-', isolatedAppDir.path]);
    if (sign.exitCode != 0) {
      throw StateError('codesign failed on the isolated app copy (exit ${sign.exitCode}): ${sign.stderr}');
    }
  }

  /// Reads the identifier back — a zero exit from `plutil -replace` says the
  /// command ran, not that the bundle carries the isolated identity, and that
  /// identity is the whole isolation guarantee.
  Future<void> _assertBundleId(File plist, {required String expected}) async {
    final read = await _run('plutil', ['-extract', 'CFBundleIdentifier', 'raw', plist.path]);
    final actual = (read.stdout as String).trim();
    if (read.exitCode != 0 || actual != expected) {
      throw StateError(
        '${plist.path} reports CFBundleIdentifier "$actual" after the rewrite, expected "$expected" — '
        'refusing to install, the isolation this driver depends on did not hold',
      );
    }
  }

  @override
  Future<void> installFresh() async {
    final udid = await _resolveDevice();
    await _boot(udid);
    await _run('xcrun', ['simctl', 'terminate', udid, verifyBundleId]);
    await _run('xcrun', ['simctl', 'uninstall', udid, verifyBundleId]);
    _log('installFresh: uninstalled $verifyBundleId from $udid');
  }

  @override
  Future<void> launch({Duration timeout = const Duration(seconds: 20)}) async {
    if (!isolatedAppDir.existsSync()) {
      throw StateError('${isolatedAppDir.path} does not exist — call build() first');
    }
    final udid = await _resolveDevice();
    await _boot(udid);

    _log('installing ${isolatedAppDir.path} on $udid');
    final install = await _run('xcrun', ['simctl', 'install', udid, isolatedAppDir.path]);
    if (install.exitCode != 0) {
      throw StateError('simctl install failed (exit ${install.exitCode}): ${install.stderr}');
    }

    // Simulator networking shares the host's loopback stack — which is
    // exactly why the port matters: a leftover process anywhere on this Mac
    // can own the base port and answer as if it were this app. Clear the
    // announcement first, so whatever appears was written by this launch.
    final launchedAt = DateTime.now().subtract(const Duration(seconds: 1));
    final instanceFile = await _instanceFile(udid);
    if (instanceFile != null) clearInstanceFile(instanceFile);

    _log('launching $verifyBundleId on $udid');
    final launch = await _run('xcrun', ['simctl', 'launch', udid, verifyBundleId]);
    if (launch.exitCode != 0) {
      throw StateError('simctl launch failed (exit ${launch.exitCode}): ${launch.stderr}');
    }

    final instance = await _resolveInstance(udid: udid, launchedAt: launchedAt, timeout: timeout);
    _instance = instance;
    _log('resolved instance: $instance');
    _client = VerifyClient(baseUri: Uri.parse('http://127.0.0.1:${instance.port}'));

    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final health = await _client!.health();
        assertHealthIdentity(health, instance: instance, notBefore: launchedAt);
        _log('health check succeeded on port ${instance.port}');
        return;
      } on InstanceDiscoveryException {
        rethrow;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    throw StateError('app did not respond on /v1/health within $timeout (last error: $lastError)');
  }

  /// `getTemporaryDirectory()` inside a simulator app is `<data container>/
  /// tmp`, and `simctl get_app_container … data` is how the host names that
  /// container. Null when the container cannot be resolved (the app is not
  /// installed yet), which [launch] treats as "nothing stale to clear".
  Future<File?> _instanceFile(String udid) async {
    final result = await _run('xcrun', ['simctl', 'get_app_container', udid, verifyBundleId, 'data']);
    if (result.exitCode != 0) return null;
    final dataDir = (result.stdout as String).trim();
    if (dataDir.isEmpty) return null;
    return File('$dataDir/tmp/pleya-verify/instance.json');
  }

  Future<VerifyInstance> _resolveInstance({
    required String udid,
    required DateTime launchedAt,
    required Duration timeout,
  }) async {
    final override = portOverride;
    if (override != null) {
      return VerifyInstance(port: override, protocolVersion: 1, source: 'portOverride');
    }
    // Re-resolve after launch: the container exists by now even if it did
    // not before install.
    final file = await _instanceFile(udid);
    if (file == null) {
      throw InstanceDiscoveryException(
        'could not resolve the data container for $verifyBundleId on $udid — '
        'no way to read which port the app bound, and assuming the base port is how a run ends up '
        'driving a leftover instance',
      );
    }
    return awaitInstance(file: file, notBefore: launchedAt, timeout: timeout);
  }

  @override
  Future<void> terminate() async {
    final udid = _resolvedUdid;
    if (udid == null) return;
    _log('terminating $verifyBundleId on $udid');
    await _run('xcrun', ['simctl', 'terminate', udid, verifyBundleId]);
    _client?.close();
    _client = null;
    _instance = null;
  }

  @override
  Future<Map<String, Object?>> uiTree() => _requireClient().uiTree();

  @override
  Future<Map<String, Object?>> focus() => _requireClient().focus();

  @override
  Future<List<Map<String, Object?>>> screensSnapshot() async {
    final result = await _requireClient().screens();
    return (result['screens'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<List<Map<String, Object?>>> eventsSince(int since) async {
    final result = await _requireClient().events(since: since);
    return (result['events'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<List<Map<String, Object?>>> focusLogSince(int since) async {
    final result = await _requireClient().focusLog(since: since);
    return (result['entries'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<List<Map<String, Object?>>> logsSince(int since) async {
    final result = await _requireClient().logs(since: since);
    return (result['entries'] as List).cast<Map<String, Object?>>();
  }

  @override
  Future<Uint8List> screenshot() async {
    final udid = await _resolveDevice();
    final tempFile = File(
      '${Directory.systemTemp.path}/pleya-verify-ios-sim-screenshot-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    // The [C5] authoritative capture: CoreSimulator's own compositor, not
    // Flutter's `/v1/screenshot` (diagnostic-only).
    final result = await _run('xcrun', ['simctl', 'io', udid, 'screenshot', tempFile.path]);
    if (result.exitCode != 0 || !tempFile.existsSync()) {
      throw StateError('simctl io screenshot failed (exit ${result.exitCode}): ${result.stderr}');
    }
    final bytes = tempFile.readAsBytesSync();
    tempFile.deleteSync();
    return bytes;
  }

  @override
  Future<void> press(String key) async {
    await _requireClient().inputKey(key);
  }

  @override
  Future<void> typeText(String text) {
    throw UnsupportedError(
      'typeText: no /v1/input/text endpoint exists yet — not needed by any Fase 8-11 scenario so far',
    );
  }

  @override
  Future<void> tap(double x, double y) async {
    await _requireClient().inputPointer(x, y);
  }

  VerifyClient _requireClient() {
    final c = _client;
    if (c == null) throw StateError('driver not launched — call launch() first');
    return c;
  }

  /// An already-booted iOS simulator wins (that is what a developer sees on
  /// screen), else the newest available iPhone runtime — resolved once and
  /// cached, mirroring `scripts/tvos_sim.sh`'s `resolve_device()`. Overrides:
  /// [deviceUdidOverride] constructor param, then `PLEYA_VERIFY_IOS_UDID`.
  Future<String> _resolveDevice() async {
    final cached = _resolvedUdid;
    if (cached != null) return cached;

    final override = deviceUdidOverride ?? Platform.environment['PLEYA_VERIFY_IOS_UDID'];
    if (override != null && override.isNotEmpty) {
      _resolvedUdid = override;
      return override;
    }

    final result = await _run('xcrun', ['simctl', 'list', 'devices', 'available', '--json']);
    if (result.exitCode != 0) {
      throw StateError('xcrun simctl list devices failed (exit ${result.exitCode}): ${result.stderr}');
    }
    final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
    final devicesByRuntime = decoded['devices'] as Map<String, Object?>;

    String? booted;
    String? fallback;
    for (final entry in devicesByRuntime.entries) {
      if (!entry.key.contains('iOS')) continue;
      for (final raw in entry.value as List) {
        final device = raw as Map<String, Object?>;
        final name = device['name'] as String;
        if (!name.startsWith('iPhone')) continue;
        final udid = device['udid'] as String;
        if (device['state'] == 'Booted') booted = udid;
        fallback = udid;
      }
    }
    final udid = booted ?? fallback;
    if (udid == null) {
      throw StateError('no iOS simulator found (xcrun simctl list devices available)');
    }
    _resolvedUdid = udid;
    return udid;
  }

  Future<void> _boot(String udid) async {
    final list = await _run('xcrun', ['simctl', 'list', 'devices']);
    final alreadyBooted = RegExp('$udid.*Booted').hasMatch(list.stdout as String);
    if (alreadyBooted) return;
    _log('booting $udid');
    await _run('xcrun', ['simctl', 'boot', udid]);
    await _run('xcrun', ['simctl', 'bootstatus', udid, '-b']);
  }

  Future<ProcessResult> _run(String executable, List<String> args, {String? workingDirectory}) =>
      Process.run(executable, args, workingDirectory: workingDirectory);

  Future<String?> _gitCommit() async {
    final result = await _run('git', ['rev-parse', 'HEAD'], workingDirectory: repoRoot.path);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }
}
