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

  /// Gives `sidebar.rail` a measurable rect, so geometry predicates have
  /// something to evaluate against.
  final bool boundsForSidebar;

  /// Gives `sidebar.rail` a `state` map, so `state`/`focused` predicates
  /// have something to evaluate against.
  final Map<String, Object?>? stateForSidebar;
  final bool focusedForSidebar;

  FakeDriver({
    this.readyScreens = const {'screen.main'},
    this.failWaitUntil = false,
    this.failLaunch = false,
    this.boundsForSidebar = false,
    this.stateForSidebar,
    this.focusedForSidebar = false,
  });

  @override
  String get target => 'macos';

  @override
  VerifyClient? get client => null;

  @override
  VerifyInstance? get instance => const VerifyInstance(port: 47319, protocolVersion: 1, pid: 4242, source: 'fake');

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
      {
        'id': 'sidebar.rail',
        'role': 'sidebar',
        'focused': focusedForSidebar,
        if (boundsForSidebar) 'bounds': {'x': 0.0, 'y': 0.0, 'width': 200.0, 'height': 800.0},
        if (stateForSidebar != null) 'state': stateForSidebar,
      },
    ],
    'discovered': [],
    'duplicates': [],
  };

  @override
  Future<Map<String, Object?>> focus() async => {'focused': false};

  @override
  Future<Map<String, Object?>> viewport() async => {'available': true, 'width': 1280.0, 'height': 800.0};

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

  test('a verb the engine genuinely has no case for fails cleanly instead of silently no-opping', () async {
    // Every verb the validator's vocabulary advertises (`model.dart`'s
    // setupVerbs/stepVerbs) has a real case in run_scenario.dart's switch —
    // see `validator_test.dart`'s parity test for that invariant. This
    // exercises the engine's own default-case guard directly, bypassing
    // validation, so a *future* vocabulary/engine drift (a verb added to
    // one without the other) still fails the run cleanly rather than
    // reaching an engine no-op or a null dereference.
    final scenario = parseScenarioString(
      'name: fixture.unimplemented_verb\ntarget: macos\nsteps:\n  - swipe: left\n',
      sourcePath: 'inline.yaml',
    );
    final driver = FakeDriver();

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.unimplemented_verb\n...',
      driver: driver,
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('does not implement verb "swipe"'));
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

  group('verbs that used to reach UnsupportedError only after a full build', () {
    // `fixture_mutate` and `open` were in the validator's vocabulary but had
    // no engine case, so a scenario using them validated fine and then died
    // at runtime — after a build, install and launch. These now fail on
    // their own preconditions, with a message that names what is missing.
    test('open before launch names the missing step rather than dereferencing null', () async {
      final scenario = parseScenarioString(
        'name: fixture.open_no_launch\ntarget: macos\nsetup:\n  - open: screen.discover\nsteps:\n'
        '  - assert: {id: screen.main}\n',
        sourcePath: 'inline.yaml',
      );

      final result = await runScenario(
        scenario: scenario,
        scenarioSource: 'name: fixture.open_no_launch\n...',
        driver: FakeDriver(),
        repoRoot: repoRoot,
      );

      expect(result.passed, isFalse);
      expect(result.failureMessage, contains('needs a launched app'));
    });
  });

  test(
    'a fixture_mutate response is redacted before it reaches the manifest, not written verbatim',
    () async {
      // `fixture.mutate` is a generic pass-through to the fixture server's
      // own control plane (see its doc) — a future op is free to echo back
      // whatever the caller sent it, and `/__verify/echo` stands in for
      // exactly that here. Proves the fix at the real boundary: a live
      // fixture server, the real `runScenario` engine, and the actual
      // bytes written to `manifest.json` — not just `redactJson` in
      // isolation (see `redact_test.dart` for that).
      final scenario = parseScenarioString(
        'name: fixture.redact_mutate\ntarget: macos\nsteps:\n'
        '  - fixture_mutate: {op: echo, nested: {oldPassword: "hunter2-super-secret", '
        'userAccessToken: "eyJ-plaintext-token"}}\n',
        sourcePath: 'inline.yaml',
      );

      final result = await runScenario(
        scenario: scenario,
        scenarioSource: 'name: fixture.redact_mutate\n...',
        driver: FakeDriver(),
        // Not the fake `repoRoot` every other test in this file uses: this
        // scenario needs `_needsFixture` to spawn a *real*
        // `pleya_verify/fixture_server` process, so it needs the real repo
        // root to find that package under — the same `../..` convention
        // `bin/verify.dart`'s own `_repoRoot` uses from this package's
        // directory. `.build/pleya-verify/` is gitignored, so the evidence
        // bundle this writes under the real repo root is harmless.
        repoRoot: Directory('../..'),
      );

      expect(result.passed, isTrue, reason: result.failureMessage);
      final manifest = File('${result.bundleDir.path}/manifest.json').readAsStringSync();
      expect(manifest, isNot(contains('hunter2-super-secret')));
      expect(manifest, isNot(contains('eyJ-plaintext-token')));
      expect(manifest, contains('[REDACTED]'));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a geometry assertion records its measurements in the manifest, passing ones included', () async {
    // A passing measurement is the baseline a later regression is compared
    // against, so it belongs in the bundle just as much as a failing one.
    final scenario = parseScenarioString(
      'name: fixture.geometry\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, insideViewport: true}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.geometry\n...',
      driver: FakeDriver(boundsForSidebar: true),
      repoRoot: repoRoot,
    );

    expect(result.passed, isTrue, reason: result.failureMessage);
    final manifest = File('${result.bundleDir.path}/manifest.json').readAsStringSync();
    expect(manifest, contains('"predicate": "insideViewport"'));
    expect(manifest, contains('"ok": true'));
  });

  test('a failing geometry assertion fails the run and says by how much', () async {
    final scenario = parseScenarioString(
      'name: fixture.geometry_fail\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, minimumTapTarget: 999}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.geometry_fail\n...',
      driver: FakeDriver(boundsForSidebar: true),
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('minimumTapTarget'));
    expect(result.failureMessage, contains('smaller than'));
  });

  test('a state assertion records its measurement in the manifest, passing ones included', () async {
    final scenario = parseScenarioString(
      'name: fixture.state\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, state: {collapsed: true}}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.state\n...',
      driver: FakeDriver(stateForSidebar: const {'collapsed': true}),
      repoRoot: repoRoot,
    );

    expect(result.passed, isTrue, reason: result.failureMessage);
    final manifest = File('${result.bundleDir.path}/manifest.json').readAsStringSync();
    expect(manifest, contains('"predicate": "state"'));
    expect(manifest, contains('"key": "collapsed"'));
    expect(manifest, contains('"ok": true'));
  });

  test('a failing state assertion fails the run and names the actual value', () async {
    final scenario = parseScenarioString(
      'name: fixture.state_fail\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, state: {collapsed: true}}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.state_fail\n...',
      driver: FakeDriver(stateForSidebar: const {'collapsed': false}),
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('state(sidebar.rail.collapsed)'));
    expect(result.failureMessage, contains('expected true'));
  });

  test('asserting state on a node with no state callback fails clearly', () async {
    final scenario = parseScenarioString(
      'name: fixture.state_missing\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, state: {collapsed: true}}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.state_missing\n...',
      driver: FakeDriver(),
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('does not publish an AutomationNode.state'));
  });

  test('a focused assertion fails the run when focus is elsewhere', () async {
    final scenario = parseScenarioString(
      'name: fixture.focused_fail\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, focused: true}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.focused_fail\n...',
      driver: FakeDriver(focusedForSidebar: false),
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('focused(sidebar.rail)'));
  });

  test('geometry and state predicates on the same step both land in the manifest', () async {
    final scenario = parseScenarioString(
      'name: fixture.mixed\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, insideViewport: true, state: {collapsed: true}}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.mixed\n...',
      driver: FakeDriver(boundsForSidebar: true, stateForSidebar: const {'collapsed': true}),
      repoRoot: repoRoot,
    );

    expect(result.passed, isTrue, reason: result.failureMessage);
    final manifest = File('${result.bundleDir.path}/manifest.json').readAsStringSync();
    expect(manifest, contains('"geometry"'));
    expect(manifest, contains('"state"'));
  });

  test('a {{fixture_id:...}} in an assert step fails clearly rather than comparing the literal text', () async {
    // Before this, assert steps never went through resolvePlaceholders at
    // all — only sign_in/fixture_mutate did — so a `{{fixture_id:kind/slug}}`
    // inside `state:` silently compared the *literal placeholder string*
    // against whatever the driver reported, instead of resolving it. That
    // failure mode is strictly worse: a scenario with a real typo would
    // report "expected {{fixture_id:x}}" instead of naming the actual
    // resolution problem. No fixture verb here, so resolution still fails —
    // the point is *how* it fails.
    final scenario = parseScenarioString(
      'name: fixture.placeholder\ntarget: macos\nsteps:\n'
      '  - assert: {id: sidebar.rail, state: {item_id: "{{fixture_id:movie/aurora}}"}}\n',
      sourcePath: 'inline.yaml',
    );

    final result = await runScenario(
      scenario: scenario,
      scenarioSource: 'name: fixture.placeholder\n...',
      driver: FakeDriver(stateForSidebar: const {'item_id': 'not-a-placeholder'}),
      repoRoot: repoRoot,
    );

    expect(result.passed, isFalse);
    expect(result.failureMessage, contains('does not match anything the fixture seeded'));
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
