import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../driver/instance_discovery.dart';
import '../driver/verification_driver.dart';
import '../fixture/fixture_server_handle.dart';
import '../redact.dart';
import '../scenario/model.dart';
import 'evidence_bundle.dart';

class ScenarioRunResult {
  final bool passed;
  final String? failureMessage;
  final Directory bundleDir;

  const ScenarioRunResult({required this.passed, this.failureMessage, required this.bundleDir});
}

/// Setup/step verbs whose dispatch needs a fixture server running —
/// [runScenario] only spawns one when a scenario actually uses one.
const Set<String> _fixtureVerbs = {'seed', 'sign_in', 'fixture_mutate'};

bool _needsFixture(Scenario scenario) =>
    [...scenario.setup, ...scenario.steps].any((s) => _fixtureVerbs.contains(s.verb));

/// Runs a validated [Scenario] against [driver] end to end, dispatching
/// `setup` then `steps` verbs in file order — there is no engine-injected
/// implicit launch: `install`/`launch` are explicit setup verbs a scenario
/// author sequences themselves, exactly as `reset_app` must precede
/// `launch` (it wipes app state a running app would just repersist) and
/// `sign_in` must follow it (it calls the app's own `/v1/signin`, which
/// does not exist before the app is up). Always collects final evidence
/// and tears down — even on failure — before writing the bundle to
/// `.build/pleya-verify/<run-id>/`.
Future<ScenarioRunResult> runScenario({
  required Scenario scenario,
  required String scenarioSource,
  required VerificationDriver driver,
  required Directory repoRoot,
}) async {
  final runId = '${scenario.name.replaceAll('.', '-')}-${DateTime.now().millisecondsSinceEpoch}';
  final bundle = EvidenceBundle(Directory('${repoRoot.path}/.build/pleya-verify/$runId'));
  final stopwatch = Stopwatch()..start();
  final stepRecords = <Map<String, Object?>>[];
  var passed = true;
  String? failureMessage;
  // Two flags, deliberately. [launchAttempted] is set *before* `launch()`
  // and gates teardown: a `launch()` that throws (a health-check timeout, an
  // identity mismatch) has usually already started a process, and gating
  // `terminate()` on success leaves it running. That leftover process then
  // owns the automation port and answers a later run's health check
  // convincingly — the exact contamination traced by hand in Fase 10.
  // [launched] gates only the transport evidence, which genuinely needs a
  // live client.
  var launchAttempted = false;
  var launched = false;
  FixtureServerHandle? fixture;
  VerifyInstance? instance;
  String? snapshotHash;

  Object resolvePlaceholders(Object? value, FixtureServerHandle? fixture, String? setupCode) {
    if (value is String) {
      if (value == '{{fixture}}') {
        return fixture?.baseUrl ?? (throw StateError('"{{fixture}}" used but no fixture server is running'));
      }
      if (value == '{{fixture_setup_code}}') {
        return setupCode ?? (throw StateError('"{{fixture_setup_code}}" used but no fixture server is running'));
      }
      return value;
    }
    if (value is Map<String, Object?>) {
      return {for (final e in value.entries) e.key: resolvePlaceholders(e.value, fixture, setupCode)};
    }
    return value ?? '';
  }

  Future<void> runStep(ScenarioStep step) async {
    final record = <String, Object?>{'verb': step.verb, 'line': step.line};
    try {
      switch (step.verb) {
        case 'reset_app':
          await driver.installFresh();
        case 'install':
          // The build driver.build() already produced is the "install" —
          // nothing further is needed on a target with no simulator to
          // install onto.
          break;
        case 'launch':
          launchAttempted = true;
          await driver.launch();
          launched = true;
          // Captured now, because terminate() clears it — the manifest has
          // to name the instance this run actually drove.
          instance = driver.instance;
          record['instance'] = instance?.toJson();
        case 'sign_in':
          final setupCode = fixture == null ? null : (await fixture.verifyState())['setupCode'] as String?;
          final args = resolvePlaceholders(step.args, fixture, setupCode) as Map<String, Object?>;
          final signinResult = await driver.client!.signin(
            baseUrl: args['base_url'] as String,
            username: args['username'] as String,
            password: args['password'] as String,
            setupCode: args['setup_code'] as String?,
          );
          if (signinResult['ok'] != true) {
            throw StateError('sign_in failed: ${signinResult['error']} (full response: $signinResult)');
          }
        case 'seed':
          if (step.args case final String fixtureName) {
            await fixture!.seed(fixtureName);
          } else {
            throw ArgumentError('seed needs a fixture name: ${step.args}');
          }
        case 'wait_until':
          await _dispatchWaitUntil(step, driver);
        case 'assert':
          await _dispatchAssert(step, driver);
        case 'snapshot':
          final name = step.args is String ? step.args as String : 'step-${step.line}';
          final bytes = await driver.screenshot();
          bundle.saveScreenshot(name, bytes);
          record['screenshot'] = '$name.png';
        case 'settle':
          // Bare `- settle` keeps the old fixed 500ms; `- settle: 3000` lets
          // a scenario wait out something with no automation-observable
          // signal of its own — e.g. IntroGate's ~2.8s cosmetic splash
          // overlay, which mounts *above* an already-ready screen rather
          // than gating it, so no `wait_until` can see it finish.
          await Future<void>.delayed(Duration(milliseconds: (step.args as int?) ?? 500));
        case 'press':
          record['input_route'] = driver.inputRoute;
          await driver.press(step.args as String);
        case 'tap':
          record['input_route'] = driver.inputRoute;
          final args = step.args as Map<String, Object?>;
          await driver.tap((args['x'] as num).toDouble(), (args['y'] as num).toDouble());
        case 'type':
          record['input_route'] = driver.inputRoute;
          await driver.typeText(step.args as String);
        default:
          throw UnsupportedError('the run-scenario engine does not implement verb "${step.verb}" yet');
      }
      record['ok'] = true;
    } catch (e) {
      record['ok'] = false;
      // Redacted at the point it enters the bundle: an error string can
      // quote a request URL or an Authorization header, and manifest.json
      // plus report.md are files a developer pastes into an issue.
      record['error'] = redact('$e');
      rethrow;
    } finally {
      stepRecords.add(record);
    }
  }

  try {
    await driver.build();
    if (_needsFixture(scenario)) {
      fixture = await FixtureServerHandle.start(
        fixtureServerPackageDir: Directory('${repoRoot.path}/pleya_verify/fixture_server'),
      );
    }
    for (final step in [...scenario.setup, ...scenario.steps]) {
      await runStep(step);
    }
  } catch (e) {
    passed = false;
    failureMessage = '$e';
  } finally {
    // Always written — even empty, and even if the app never launched (a
    // scenario can fail during build() itself) — per the plan's "volledige
    // bundel" requirement rather than a file silently missing.
    if (launched) {
      try {
        bundle.saveUiTree('final', await driver.uiTree());
      } catch (_) {
        bundle.saveUiTree('final', const {});
      }
      try {
        bundle.writeFocusTrace(await driver.focusLogSince(0));
      } catch (_) {
        bundle.writeFocusTrace(const []);
      }
      try {
        bundle.writeAppLog(await driver.logsSince(0));
      } catch (_) {
        bundle.writeAppLog(const []);
      }
    } else {
      bundle.saveUiTree('final', const {});
      bundle.writeFocusTrace(const []);
      bundle.writeAppLog(const []);
    }
    if (launchAttempted) {
      try {
        await driver.terminate();
      } catch (e) {
        // Never let teardown overwrite the real failure — record it and
        // move on, but do record it: a terminate that fails is how a
        // leftover process survives into the next run.
        stepRecords.add({'verb': 'terminate', 'ok': false, 'error': '$e'});
      }
    }
    if (fixture != null) {
      try {
        final state = await fixture.verifyState();
        snapshotHash = state['snapshotHash'] as String?;
        bundle.writeFixtureRequests(await fixture.requestsSince(0));
      } catch (_) {
        bundle.writeFixtureRequests(const []);
      }
      await fixture.stop();
    } else {
      bundle.writeFixtureRequests(const []);
    }
  }

  stopwatch.stop();

  final manifest = <String, Object?>{
    'run_id': runId,
    'git_commit': await _gitCommit(repoRoot),
    'dirty': await _gitDirty(repoRoot),
    'target': driver.target,
    'device': driver.target,
    'os': Platform.operatingSystemVersion,
    'scenario_hash': sha256.convert(utf8.encode(scenarioSource)).toString(),
    'snapshot_hash': snapshotHash,
    // Which app instance produced this evidence, and how it was identified.
    // Without it a bundle cannot answer "was this really the app you
    // launched?" — see instance_discovery.dart.
    'instance': instance?.toJson(),
    'result': passed ? 'PASS' : 'FAILED',
    'duration_ms': stopwatch.elapsedMilliseconds,
    if (failureMessage != null) 'failure_message': redact(failureMessage),
    'steps': stepRecords,
  };
  bundle.writeManifest(manifest);
  bundle.writeReport(_buildReport(scenario, manifest));
  bundle.writeResolvedScenario(scenarioSource);
  bundle.writeDriverLog(driver.driverLog);

  return ScenarioRunResult(passed: passed, failureMessage: failureMessage, bundleDir: bundle.dir);
}

Future<void> _dispatchWaitUntil(ScenarioStep step, VerificationDriver driver) async {
  final args = step.args as Map<String, Object?>;
  final timeoutMs = (args['timeout'] as num).toInt();
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

  Future<bool> predicate() async {
    if (args['id'] case final String id) return _idReady(driver, id);
    if (args['event'] case final String eventName) {
      final events = await driver.eventsSince(0);
      return events.any((e) => e['name'] == eventName);
    }
    throw ArgumentError('wait_until needs an "id" or "event" field: $args');
  }

  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw StateError('wait_until timed out after ${timeoutMs}ms: $args');
}

Future<void> _dispatchAssert(ScenarioStep step, VerificationDriver driver) async {
  final args = step.args as Map<String, Object?>;
  final id = args['id'] as String;
  if (!await _idReady(driver, id)) {
    throw StateError('assert failed: "$id" is not ready/present');
  }
}

/// `screen.*` ids are checked against `/v1/screens` (readiness); anything
/// else against `/v1/ui_tree`'s declared nodes (mere presence — a
/// `FocusableWrapper`/`AutomationNode` id has no independent "ready" state
/// of its own the way an `AutomationScreen` does).
Future<bool> _idReady(VerificationDriver driver, String id) async {
  if (id.startsWith('screen.')) {
    final screens = await driver.screensSnapshot();
    return screens.any((s) => s['id'] == id && s['ready'] == true);
  }
  final tree = await driver.uiTree();
  final declared = (tree['declared'] as List).cast<Map<String, Object?>>();
  return declared.any((n) => n['id'] == id);
}

String _buildReport(Scenario scenario, Map<String, Object?> manifest) {
  final buffer = StringBuffer()
    ..writeln('# ${scenario.name}')
    ..writeln()
    ..writeln('- target: ${scenario.target}')
    ..writeln('- result: **${manifest['result']}**')
    ..writeln('- duration: ${manifest['duration_ms']}ms')
    ..writeln('- git commit: ${manifest['git_commit']} (dirty: ${manifest['dirty']})')
    ..writeln();
  if (manifest['failure_message'] != null) {
    buffer
      ..writeln('## Failure')
      ..writeln()
      ..writeln('```')
      ..writeln(manifest['failure_message'])
      ..writeln('```')
      ..writeln();
  }
  buffer.writeln('## Steps');
  for (final raw in manifest['steps'] as List<Map<String, Object?>>) {
    final ok = raw['ok'] == true ? 'PASS' : 'FAIL';
    buffer.writeln('- [$ok] `${raw['verb']}` (line ${raw['line']})${raw['error'] != null ? ' — ${raw['error']}' : ''}');
  }
  return buffer.toString();
}

Future<String?> _gitCommit(Directory repoRoot) async {
  final result = await Process.run('git', ['rev-parse', 'HEAD'], workingDirectory: repoRoot.path);
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trim();
}

Future<bool> _gitDirty(Directory repoRoot) async {
  final result = await Process.run('git', ['status', '--porcelain'], workingDirectory: repoRoot.path);
  return (result.stdout as String).trim().isNotEmpty;
}
