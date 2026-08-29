import 'dart:io';
import 'dart:typed_data';

import 'package:pleya_verify_runner/src/driver/instance_discovery.dart';
import 'package:pleya_verify_runner/src/driver/verification_driver.dart';
import 'package:pleya_verify_runner/src/engine/run_scenario.dart';
import 'package:pleya_verify_runner/src/scenario/parser.dart';
import 'package:pleya_verify_runner/src/transport/verify_client.dart';
import 'package:test/test.dart';

/// An in-memory stand-in for a real driver, so the engine's dispatch logic,
/// bundle-writing, and PASS/FAIL determination are proven without needing a
/// macOS/Xcode build in `dart test` — that stays a manual, real-driver
/// proof (see docs/architecture/pleya-verify.md once Fase 15 lands, and the
/// Fase 8 commit message for how it was verified by hand).
class FakeDriver implements VerificationDriver {
  bool freshInstallDone = false;
  bool terminateCalled = false;
  final List<String> _log = [];
  final Set<String> readyScreens;
  final bool failWaitUntil;

  /// Simulates the real hazard: a `launch()` that starts a process and
  /// *then* throws (a health-check timeout, an instance-identity mismatch).
  final bool failLaunch;

  FakeDriver({this.readyScreens = const {'screen.main'}, this.failWaitUntil = false, this.failLaunch = false});

  @override
  String get target => 'macos';

  @override
  VerifyClient? get client => null;

  @override
  VerifyInstance? get instance =>
      const VerifyInstance(port: 47319, protocolVersion: 1, pid: 4242, source: 'fake');

  @override
  String get inputRoute => 'transport';

  @override
  List<String> get driverLog => List.unmodifiable(_log);

  @override
  Future<DriverDoctorReport> doctor() async => const DriverDoctorReport(ready: true, checks: {});

  @override
  Future<void> build() async => _log.add('build');

  @override
  Future<void> installFresh() async {
    freshInstallDone = true;
    _log.add('installFresh');
  }

  @override
  Future<void> launch({Duration timeout = const Duration(seconds: 20)}) async {
    _log.add('launch');
    if (failLaunch) {
      throw StateError('app did not respond on /v1/health within 20s');
    }
  }

  @override
  Future<void> terminate() async {
    terminateCalled = true;
    _log.add('terminate');
  }

  @override
  Future<Map<String, Object?>> uiTree() async => {
    'declared': [
      {'id': 'sidebar.rail', 'role': 'sidebar'},
    ],
    'discovered': [],
    'duplicates': [],
  };

  @override
  Future<Map<String, Object?>> focus() async => {'focused': false};

  @override
  Future<List<Map<String, Object?>>> screensSnapshot() async => [
    for (final id in readyScreens)
      if (!failWaitUntil) {'id': id, 'state': 'ready', 'ready': true},
  ];

  @override
  Future<List<Map<String, Object?>>> eventsSince(int since) async => const [];

  @override
  Future<List<Map<String, Object?>>> focusLogSince(int since) async => const [];

  @override
  Future<List<Map<String, Object?>>> logsSince(int since) async => const [];

  @override
  Future<Uint8List> screenshot() async => Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> press(String key) async {}

  @override
  Future<void> typeText(String text) async {}

  @override
  Future<void> tap(double x, double y) async {}
}

void main() {
  late Directory repoRoot;

  setUp(() {
    repoRoot = Directory.systemTemp.createTempSync('pleya-verify-engine-test');
  });

  tearDown(() {
    if (repoRoot.existsSync()) repoRoot.deleteSync(recursive: true);
  });

  test('a passing scenario writes a bundle with result PASS and the expected files', () async {
    final scenario = parseScenarioString(
      'name: fixture.smoke\ntarget: macos\nsetup:\n  - reset_app\n  - launch\nsteps:\n  - wait_until: {id: screen.main, timeout: 2000}\n  - assert: {id: screen.main}\n  - snapshot: boot\n',
      sourcePath: 'inline.yaml',
    );
    final driver = FakeDriver();

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.smoke\n...',
      driver: driver,
      repoRoot: repoRoot,
    );

    expect(result.passed, isTrue);
    expect(driver.freshInstallDone, isTrue);

    expect(File('${result.bundleDir.path}/manifest.json').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/report.md').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/scenario.resolved.yaml').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/focus-trace.json').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/app.log').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/driver.log').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/fixture/requests.jsonl').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/screenshots/boot.png').existsSync(), isTrue);
    expect(File('${result.bundleDir.path}/ui-tree/final.json').existsSync(), isTrue);

    final manifest = File('${result.bundleDir.path}/manifest.json').readAsStringSync();
    expect(manifest, contains('"result": "PASS"'));
  });

  test('assert on an id the driver never reports fails the run and still writes a bundle', () async {
    final scenario = parseScenarioString(
      'name: fixture.smoke_fail\ntarget: macos\nsteps:\n  - assert: {id: screen.main}\n',
      sourcePath: 'inline.yaml',
    );
    final driver = FakeDriver(readyScreens: const {});

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.smoke_fail\n...',
      driver: driver,
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('assert failed'));
    expect(File('${result.bundleDir.path}/manifest.json').readAsStringSync(), contains('"result": "FAILED"'));
  });

  test('wait_until times out and the run fails with a clear message', () async {
    final scenario = parseScenarioString(
      'name: fixture.timeout\ntarget: macos\nsteps:\n  - wait_until: {id: screen.main, timeout: 200}\n',
      sourcePath: 'inline.yaml',
    );
    final driver = FakeDriver(readyScreens: const {}, failWaitUntil: true);

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.timeout\n...',
      driver: driver,
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('timed out'));
  });

  test('an unimplemented verb fails cleanly instead of silently no-opping', () async {
    final scenario = parseScenarioString(
      'name: fixture.open\ntarget: macos\nsetup:\n  - open: screen.discover\nsteps:\n  - assert: {id: screen.main}\n',
      sourcePath: 'inline.yaml',
    );
    final driver = FakeDriver();

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.open\n...',
      driver: driver,
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('does not implement verb "open"'));
  });

  test('a launch() that throws still gets terminated — no process left owning the port', () async {
    // The zombie mechanism behind the port-47317 contamination traced by
    // hand in Fase 10: `launch()` starts the app, then fails its health
    // check. Gating teardown on a *successful* launch leaves that process
    // running, and it answers the next run's health check convincingly.
    final scenario = parseScenarioString(
      'name: fixture.launch_fail\ntarget: macos\nsetup:\n  - launch\nsteps:\n  - assert: {id: screen.main}\n',
      sourcePath: 'inline.yaml',
    );
    final driver = FakeDriver(failLaunch: true);

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.launch_fail\n...',
      driver: driver,
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(driver.terminateCalled, isTrue, reason: 'a started-but-unhealthy app must still be torn down');
  });

  test('a run that never launched does not call terminate', () async {
    final scenario = parseScenarioString(
      'name: fixture.no_launch\ntarget: macos\nsteps:\n  - assert: {id: screen.main}\n',
      sourcePath: 'inline.yaml',
    );
    final driver = FakeDriver();

    await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.no_launch\n...',
      driver: driver,
      repoRoot: repoRoot,
    );

    expect(driver.terminateCalled, isFalse);
  });

  test('the manifest names the instance the run actually drove', () async {
    // Without this a bundle cannot answer "was this the app you launched?",
    // which is the question the port-discovery work exists to make
    // answerable.
    final scenario = parseScenarioString(
      'name: fixture.instance\ntarget: macos\nsetup:\n  - launch\nsteps:\n  - assert: {id: screen.main}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.instance\n...',
      driver: FakeDriver(),
      repoRoot: repoRoot,
    );

    final manifest = File('${result.bundleDir.path}/manifest.json').readAsStringSync();
    expect(manifest, contains('"port": 47319'));
    expect(manifest, contains('"source": "fake"'));
  });

  test('run-id directories are unique and land under .build/pleya-verify/', () async {
    final scenario = parseScenarioString(
      'name: fixture.dir\ntarget: macos\nsteps:\n  - assert: {id: screen.main}\n',
      sourcePath: 'inline.yaml',
    );
    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.dir\n...',
      driver: FakeDriver(),
      repoRoot: repoRoot,
    );
    expect(result.bundleDir.path, startsWith('${repoRoot.path}/.build/pleya-verify/fixture-dir-'));
  });
}
