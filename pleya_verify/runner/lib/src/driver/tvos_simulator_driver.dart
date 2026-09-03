import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../transport/verify_client.dart';
import 'instance_discovery.dart';
import 'screenshot_probe.dart';
import 'verification_driver.dart';

/// Drives a tvOS-simulator build of Pleya through `scripts/tvos_sim.sh` —
/// the fundament stays unmodified in shape (this driver is an additive
/// wrapper, not a rewrite); Fase 10 only added `device`, `run --env`,
/// `keys key:count` and `doctor --json` to it.
///
/// **[C2], structurally enforced:** [press], [typeText] and [tap] contain no
/// reference to [VerifyClient] or `package:http` — only a
/// `scripts/tvos_sim.sh` process wrapper via [_runTvosSim]. That is the only
/// valid tvOS input route: a real remote press travels
/// scenario -> this driver -> `tvos_sim.sh` -> idb HID -> UIKit -> the
/// geswizzelde `sendEvent:`-laag, never through the automation HTTP
/// transport. `pleya_verify/runner/test/driver_routing_test.dart` scans this
/// file's source for exactly that. [uiTree]/[focus]/[eventsSince]/[logs] are
/// the opposite: observation is not input, so those go through [client]
/// like every other driver. [screenshot] is always `xcrun simctl io …
/// screenshot`, the [C5] authoritative capture, never `/v1/screenshot`.
///
/// **Two isolation problems, proven necessary by hand, not assumed —
/// device *and* bundle id.** `tvos_sim.sh`'s own `resolve_device()` prefers
/// an already-booted simulator — correct for a human running
/// `check-keyboard`/`login` against their own working device, wrong for
/// this driver: a real run against that default policy landed on the
/// developer's demo-logged-in Apple TV and rendered real demo.pleya.app
/// content (a Blender Open Movie from an actual library) instead of the
/// fixture's seeded catalog. This driver never relies on that default — it
/// resolves (creating if needed) its own dedicated [_deviceName] simulator
/// and pins every `tvos_sim.sh` call to it via `TVOS_SIM_UDID`, the same
/// override knob a human already has.
///
/// A *second*, independent leak survived that fix: `tvos/Runner/
/// Runner.entitlements` (like macOS's and iOS's) declares
/// `com.apple.developer.ubiquity-kvstore-identifier` as
/// `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` — a sync identifier keyed
/// by bundle id, not by device. Running the real bundle id on a brand-new,
/// never-before-booted dedicated device still surfaced the same real
/// "applereview" Jellyfin session within seconds of first launch, before
/// any fixture sign-in ran. [build] therefore also copies the compiled
/// `.app`, rewrites `CFBundleIdentifier` to [verifyBundleId], and re-signs
/// ad hoc — [MacosDriver]'s already-validated technique, needed here for a
/// different reason than the one its own doc originally gave.
class TvosSimulatorDriver implements VerificationDriver {
  final Directory repoRoot;
  final String verifyBundleId;

  /// Escape hatch only — see [MacosDriver.portOverride] and
  /// `instance_discovery.dart`. Leave null so [launch] discovers the port
  /// the app actually bound.
  final int? portOverride;

  /// Paired with [portOverride] — see `instance_discovery.dart`'s auth note.
  /// `/v1/*` now requires a bearer token unconditionally, so bypassing
  /// discovery via [portOverride] with no token would just trade "wrong
  /// instance" for "every request 401s". Leave both null for the normal
  /// path, which reads the real per-launch token out of `instance.json`.
  final String? tokenOverride;
  final void Function(String line)? onDriverLog;
  final String? deviceUdidOverride;

  static const String _deviceName = 'Pleya Verify Apple TV 4K';
  static const String _deviceTypeId = 'com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K';
  static const String _realBundleId = 'nl.michelknoop.pleya';

  String? _resolvedUdid;
  final List<String> _driverLog = [];
  VerifyClient? _client;
  VerifyInstance? _instance;

  TvosSimulatorDriver({
    required this.repoRoot,
    this.verifyBundleId = 'nl.michelknoop.pleya.verify',
    this.portOverride,
    this.tokenOverride,
    this.onDriverLog,
    this.deviceUdidOverride,
  });

  @override
  String get target => 'tvos-sim';

  @override
  VerifyClient? get client => _client;

  @override
  VerifyInstance? get instance => _instance;

  @override
  String get inputRoute => 'idb';

  void _log(String line) {
    _driverLog.add(line);
    onDriverLog?.call(line);
  }

  @override
  List<String> get driverLog => List.unmodifiable(_driverLog);

  Directory get _sourceAppDir =>
      Directory('${repoRoot.path}/tvos/build/dd/Build/Products/Debug-appletvsimulator/Runner.app');

  /// The isolated, re-signed copy this driver actually installs — kept
  /// outside any per-run evidence bundle so repeated runs reuse one build
  /// instead of copying+re-signing the `.app` every time.
  Directory get isolatedAppDir => Directory('${repoRoot.path}/.build/pleya-verify/tvos-app/Runner.app');

  @override
  Future<DriverDoctorReport> doctor() async {
    final checks = <String, Object?>{};

    final flutterVersion = await _run('flutter', ['--version']);
    checks['flutter'] = flutterVersion.exitCode == 0;
    final xcodebuild = await _run('xcodebuild', ['-version']);
    checks['xcodebuild'] = xcodebuild.exitCode == 0;

    String? deviceError;
    var udid = '';
    try {
      udid = await _resolveDevice();
      checks['device'] = udid;
    } catch (e) {
      deviceError = '$e';
      checks['device'] = false;
    }

    if (deviceError == null) {
      final scriptDoctor = await _runTvosSim(['doctor', '--json']);
      if (scriptDoctor.exitCode == 0) {
        final decoded = jsonDecode(scriptDoctor.stdout as String) as Map<String, Object?>;
        checks.addAll(decoded);
      } else {
        checks['tvos_sim.sh doctor'] = false;
      }
    }

    final ready =
        deviceError == null &&
        checks['flutter'] == true &&
        checks['xcodebuild'] == true &&
        checks['app_build'] == true &&
        checks['input'] == 'idb';
    return DriverDoctorReport(ready: ready, checks: checks);
  }

  @override
  Future<void> build() async {
    await _resolveDevice();
    _log('PLEYA_VERIFY=true scripts/tvos_sim.sh build');
    final result = await _runTvosSim(['build'], extraEnv: {'PLEYA_VERIFY': 'true'});
    _log(result.stdout.toString());
    if (result.exitCode != 0) {
      _log(result.stderr.toString());
      throw StateError('scripts/tvos_sim.sh build failed (exit ${result.exitCode})');
    }
    if (!_sourceAppDir.existsSync()) {
      throw StateError('scripts/tvos_sim.sh build reported success but ${_sourceAppDir.path} does not exist');
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

    await _rewriteBundleIds();

    _log('codesign --force --deep --sign - ${isolatedAppDir.path}');
    final sign = await _run('codesign', ['--force', '--deep', '--sign', '-', isolatedAppDir.path]);
    if (sign.exitCode != 0) {
      throw StateError('codesign failed on the isolated app copy (exit ${sign.exitCode}): ${sign.stderr}');
    }
  }

  /// Unlike macOS's Runner (no embedded extensions), tvOS's ships a
  /// `TopShelfExtension.appex` under `PlugIns/` whose own `CFBundleIdentifier`
  /// (`nl.michelknoop.pleya.TopShelfExtension`) must stay nested under the
  /// app's — `simctl install` rejects the isolated copy with "Mismatched
  /// bundle IDs" otherwise (proven by hand: the first isolation attempt hit
  /// exactly this). Rewriting only the top-level `Info.plist` is therefore
  /// not enough; every embedded `.appex`'s identifier needs the same prefix
  /// swap.
  Future<void> _rewriteBundleIds() async {
    final infoPlist = File('${isolatedAppDir.path}/Info.plist');
    await _rewriteBundleId(infoPlist, to: verifyBundleId);

    final plugins = Directory('${isolatedAppDir.path}/PlugIns');
    if (!plugins.existsSync()) return;
    for (final entity in plugins.listSync()) {
      if (entity is! Directory || !entity.path.endsWith('.appex')) continue;
      final extPlist = File('${entity.path}/Info.plist');
      final current = await _run('plutil', ['-extract', 'CFBundleIdentifier', 'raw', extPlist.path]);
      if (current.exitCode != 0) {
        throw StateError(
          'could not read CFBundleIdentifier from ${extPlist.path} (exit ${current.exitCode}): '
          '${current.stderr}',
        );
      }
      final currentId = (current.stdout as String).trim();
      if (!currentId.startsWith('$_realBundleId.')) continue;
      final suffix = currentId.substring(_realBundleId.length);
      final newId = '$verifyBundleId$suffix';
      _log('rewriting ${entity.path} CFBundleIdentifier: $currentId -> $newId');
      await _rewriteBundleId(extPlist, to: newId);
    }
  }

  /// Rewrites and then reads back. A zero exit from `plutil -replace` says
  /// the command ran, not that the bundle now carries the isolated identity
  /// — and that identity is the entire isolation guarantee this class's doc
  /// describes: under the real identifier, the KVS entitlement pulled a real
  /// signed-in session onto a brand-new simulator within seconds.
  Future<void> _rewriteBundleId(File plist, {required String to}) async {
    final rewrite = await _run('plutil', ['-replace', 'CFBundleIdentifier', '-string', to, plist.path]);
    if (rewrite.exitCode != 0) {
      throw StateError(
        'rewriting CFBundleIdentifier in ${plist.path} failed (exit ${rewrite.exitCode}): '
        '${rewrite.stderr}',
      );
    }
    final read = await _run('plutil', ['-extract', 'CFBundleIdentifier', 'raw', plist.path]);
    final actual = (read.stdout as String).trim();
    if (read.exitCode != 0 || actual != to) {
      throw StateError(
        '${plist.path} reports CFBundleIdentifier "$actual" after the rewrite, expected "$to" — '
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

    // The simulator shares this Mac's loopback stack, so the base port can
    // be owned by an unrelated leftover process that answers /v1/health
    // convincingly. Clear the announcement first: whatever appears after
    // this point was written by the instance below.
    // A second of slack absorbs filesystem mtime granularity and any host/
    // guest clock skew. It does not weaken the leftover-instance check:
    // a process from an earlier run is minutes old, not sub-second.
    final launchedAt = DateTime.now().subtract(const Duration(seconds: 1));
    clearInstanceFile(await _instanceFiles(udid));

    _log('launching $verifyBundleId on $udid');
    final launch = await _run('xcrun', ['simctl', 'launch', udid, verifyBundleId]);
    if (launch.exitCode != 0) {
      throw StateError('simctl launch failed (exit ${launch.exitCode}): ${launch.stderr}');
    }

    final instance = await _resolveInstance(udid: udid, launchedAt: launchedAt, timeout: timeout);
    _instance = instance;
    _log('resolved instance: $instance');
    _client = VerifyClient(baseUri: Uri.parse('http://127.0.0.1:${instance.port}'), token: instance.token);

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

  /// Where `AutomationServer` publishes its port inside the simulator's data
  /// container, most-likely path first. `simctl get_app_container … data`
  /// names that container from the host.
  ///
  /// `path_provider`'s `getTemporaryDirectory()` maps to `NSCachesDirectory`
  /// on Apple platforms despite the name, so the file lands in
  /// `Library/Caches/pleya-verify/`, not `tmp/` — established by running it,
  /// after a first attempt that assumed otherwise found nothing and failed
  /// the launch. `tmp/` stays a second candidate so a `path_provider` change
  /// degrades into "still works". Empty when the container cannot be
  /// resolved (the app is not installed yet).
  Future<List<File>> _instanceFiles(String udid) async {
    final result = await _run('xcrun', ['simctl', 'get_app_container', udid, verifyBundleId, 'data']);
    if (result.exitCode != 0) return const [];
    final dataDir = (result.stdout as String).trim();
    if (dataDir.isEmpty) return const [];
    return [
      File('$dataDir/Library/Caches/pleya-verify/instance.json'),
      File('$dataDir/tmp/pleya-verify/instance.json'),
    ];
  }

  Future<VerifyInstance> _resolveInstance({
    required String udid,
    required DateTime launchedAt,
    required Duration timeout,
  }) async {
    final override = portOverride;
    if (override != null) {
      return VerifyInstance(port: override, protocolVersion: 1, token: tokenOverride, source: 'portOverride');
    }
    final files = await _instanceFiles(udid);
    if (files.isEmpty) {
      throw InstanceDiscoveryException(
        'could not resolve the data container for $verifyBundleId on $udid — '
        'no way to read which port the app bound, and assuming the base port is how a run ends up '
        'driving a leftover instance',
      );
    }
    return awaitInstance(candidates: files, notBefore: launchedAt, timeout: timeout);
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
  Future<Map<String, Object?>> viewport() => _requireClient().viewport();

  @override
  Future<Map<String, Object?>> route() => _requireClient().route();

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
      '${Directory.systemTemp.path}/pleya-verify-tvos-sim-screenshot-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    // The [C5] authoritative capture: CoreSimulator's own compositor, not
    // Flutter's `/v1/screenshot` (diagnostic-only).
    final result = await _run('xcrun', ['simctl', 'io', udid, 'screenshot', tempFile.path]);
    if (result.exitCode != 0 || !tempFile.existsSync()) {
      throw StateError('simctl io screenshot failed (exit ${result.exitCode}): ${result.stderr}');
    }
    final bytes = tempFile.readAsBytesSync();
    tempFile.deleteSync();
    assertNotBlankScreenshot(
      bytes,
      context: 'simctl io screenshot',
      hint: 'Check that the simulator is booted and has actually rendered a frame.',
    );
    return bytes;
  }

  // --- [C2]: no VerifyClient/http below this line. idb HID only. ---

  /// A [hold] becomes `tvos_sim.sh key <key> --hold-ms <n>`, which is
  /// `idb ui key --duration` underneath: one HID press held down for that
  /// long. That is the only shape tvOS reads as a long press — two short
  /// presses with a sleep between them are two activations, and the tile's
  /// ordinary action fires twice instead of a context menu opening once.
  /// The script refuses a hold when idb is unavailable rather than falling
  /// back to AppleScript, which can only tap.
  @override
  Future<void> press(String key, {Duration? hold}) async {
    final args = [
      'key',
      key,
      if (hold != null) ...['--hold-ms', '${hold.inMilliseconds}'],
    ];
    final result = await _runTvosSim(args);
    if (result.exitCode != 0) {
      throw StateError('scripts/tvos_sim.sh ${args.join(' ')} failed (exit ${result.exitCode}): ${result.stderr}');
    }
  }

  @override
  Future<void> typeText(String text) async {
    final result = await _runTvosSim(['type', text]);
    if (result.exitCode != 0) {
      throw StateError('scripts/tvos_sim.sh type failed (exit ${result.exitCode}): ${result.stderr}');
    }
  }

  @override
  Future<void> tap(double x, double y) {
    throw UnsupportedError('tap: tvOS has no touch surface — the scenario validator already rejects "tap" here');
  }

  // --- end [C2] boundary ---

  VerifyClient _requireClient() {
    final c = _client;
    if (c == null) throw StateError('driver not launched — call launch() first');
    return c;
  }

  /// Runs `scripts/tvos_sim.sh <args>` from [repoRoot], with `TVOS_SIM_UDID`
  /// pinned to this driver's dedicated device so the script never falls back
  /// to whatever the developer happens to have booted.
  Future<ProcessResult> _runTvosSim(List<String> args, {Map<String, String>? extraEnv}) async {
    final udid = await _resolveDevice();
    return _run(
      'scripts/tvos_sim.sh',
      args,
      workingDirectory: repoRoot.path,
      extraEnv: {'TVOS_SIM_UDID': udid, ...?extraEnv},
    );
  }

  Future<void> _boot(String udid) async {
    final list = await _run('xcrun', ['simctl', 'list', 'devices']);
    final alreadyBooted = RegExp('$udid.*Booted').hasMatch(list.stdout as String);
    if (alreadyBooted) return;
    _log('booting $udid');
    await _run('xcrun', ['simctl', 'boot', udid]);
    await _run('xcrun', ['simctl', 'bootstatus', udid, '-b']);
  }

  /// This driver's own dedicated simulator, created once and reused across
  /// runs — never the developer's ad-hoc/booted device. See the isolation
  /// doc on the class.
  Future<String> _resolveDevice() async {
    final cached = _resolvedUdid;
    if (cached != null) return cached;

    final override = deviceUdidOverride ?? Platform.environment['PLEYA_VERIFY_TVOS_UDID'];
    if (override != null && override.isNotEmpty) {
      _resolvedUdid = override;
      return override;
    }

    final listResult = await _run('xcrun', ['simctl', 'list', 'devices', 'available', '--json']);
    if (listResult.exitCode != 0) {
      throw StateError('xcrun simctl list devices failed (exit ${listResult.exitCode}): ${listResult.stderr}');
    }
    final decoded = jsonDecode(listResult.stdout as String) as Map<String, Object?>;
    final devicesByRuntime = decoded['devices'] as Map<String, Object?>;
    for (final entry in devicesByRuntime.entries) {
      if (!entry.key.contains('tvOS')) continue;
      for (final raw in entry.value as List) {
        final device = raw as Map<String, Object?>;
        if (device['name'] == _deviceName) {
          final udid = device['udid'] as String;
          _resolvedUdid = udid;
          return udid;
        }
      }
    }

    final runtime = await _resolveTvosRuntime();
    _log('creating dedicated simulator "$_deviceName" ($_deviceTypeId, $runtime)');
    final createResult = await _run('xcrun', ['simctl', 'create', _deviceName, _deviceTypeId, runtime]);
    if (createResult.exitCode != 0) {
      throw StateError('xcrun simctl create failed (exit ${createResult.exitCode}): ${createResult.stderr}');
    }
    final udid = (createResult.stdout as String).trim();
    _resolvedUdid = udid;
    return udid;
  }

  Future<String> _resolveTvosRuntime() async {
    final result = await _run('xcrun', ['simctl', 'list', 'runtimes', 'available', '--json']);
    if (result.exitCode != 0) {
      throw StateError('xcrun simctl list runtimes failed (exit ${result.exitCode}): ${result.stderr}');
    }
    final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
    final runtimes = (decoded['runtimes'] as List).cast<Map<String, Object?>>();
    final tvosRuntimes = runtimes.where((r) => (r['name'] as String).contains('tvOS')).toList();
    if (tvosRuntimes.isEmpty) throw StateError('no tvOS simulator runtime installed (xcrun simctl list runtimes)');
    return tvosRuntimes.last['identifier'] as String;
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? extraEnv,
  }) => Process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: extraEnv,
    includeParentEnvironment: true,
  );
}
