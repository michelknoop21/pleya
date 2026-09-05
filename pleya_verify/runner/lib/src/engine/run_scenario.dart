import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../driver/instance_discovery.dart';
import '../driver/verification_driver.dart';
import '../fixture/fixture_server_handle.dart';
import '../focus_walk.dart';
import '../geometry.dart';
import '../redact.dart';
import '../transport/verify_client.dart';
import '../scenario/model.dart';
import '../scenario/remote_keys.dart';
import '../scenario/walk_args.dart';
import 'evidence_bundle.dart';
import 'geometry_assertions.dart';
import 'node_assertions.dart';

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

  Object resolvePlaceholders(
    Object? value,
    FixtureServerHandle? fixture,
    String? setupCode, {
    Map<String, String> seededIds = const {},
  }) {
    if (value is String) {
      if (value == '{{fixture}}') {
        return fixture?.baseUrl ?? (throw StateError('"{{fixture}}" used but no fixture server is running'));
      }
      if (value == '{{fixture_setup_code}}') {
        return setupCode ?? (throw StateError('"{{fixture_setup_code}}" used but no fixture server is running'));
      }
      // `{{fixture_id:season/testserie-s01}}` — fixture ids are truncated
      // sha256 hashes, so a scenario names the thing it means by the slug
      // the fixture seeded it under and the server hands back the id. See
      // `PleyaFakeServer.seededIds`.
      if (value.startsWith('{{fixture_id:') && value.endsWith('}}')) {
        final key = value.substring('{{fixture_id:'.length, value.length - 2);
        final id = seededIds[key];
        if (id == null) {
          throw StateError(
            '"$value" does not match anything the fixture seeded — known keys: ${seededIds.keys.join(', ')}',
          );
        }
        return id;
      }
      return value;
    }
    if (value is Map<String, Object?>) {
      return {
        for (final e in value.entries) e.key: resolvePlaceholders(e.value, fixture, setupCode, seededIds: seededIds),
      };
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
          final signinResult = await _requireClient(driver, 'sign_in').signin(
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
        case 'fixture_mutate':
          if (fixture == null) {
            throw StateError('fixture_mutate needs a fixture server, but this scenario never starts one');
          }
          final raw = step.args;
          if (raw is! Map<String, Object?> || raw['op'] is! String) {
            throw ArgumentError('fixture_mutate needs an "op" field naming a /__verify/ route: $raw');
          }
          final args =
              resolvePlaceholders(raw, fixture, null, seededIds: await fixture.seededIds()) as Map<String, Object?>;
          final op = args.remove('op') as String;
          record['op'] = op;
          // A generic pass-through to the fixture's own control plane (see
          // `fixture.mutate`'s doc) — a future op is free to echo back
          // whatever the caller sent it, including a credential-shaped
          // field, and this record lands straight in `manifest.json`. Same
          // invariant as `record['error']` below: redact at the point data
          // enters the bundle, not by trusting every future op to be benign.
          record['result'] = redactJson(await fixture.mutate(op, args));
        case 'open':
          final screen = step.args;
          if (screen is! String) {
            throw ArgumentError('open needs a screen id: $screen');
          }
          final result = await _requireClient(driver, 'open').open(screen);
          if (result['ok'] != true) {
            throw StateError('open "$screen" failed: ${result['error']} (full response: $result)');
          }
        case 'wait_until':
          await _dispatchWaitUntil(step, driver);
        case 'assert':
          // `{{fixture_id:kind/slug}}` is as legitimate inside an assert's
          // `state:`/binary-predicate values as it is inside `fixture_mutate`
          // — a scenario naming an item by the fixture's own seeded slug
          // rather than a hash it has no way to know. Resolved unconditionally
          // (a `{{fixture_id:...}}` in an assert step with no running fixture
          // throws the same clear error `fixture_mutate` already does).
          final resolvedArgs =
              resolvePlaceholders(
                    step.args,
                    fixture,
                    null,
                    seededIds: fixture == null ? const {} : await fixture.seededIds(),
                  )
                  as Map<String, Object?>;
          final (:geometry, :node) = await _dispatchAssert(resolvedArgs, driver);
          if (geometry.isNotEmpty) record['geometry'] = [for (final g in geometry) g.toJson()];
          if (node.isNotEmpty) record['state'] = [for (final n in node) n.toJson()];
        case 'overlay':
          // The diagnostic overlay draws ids and bounds *into the app's own
          // render tree*, so a screenshot taken while it is on shows what
          // the runner thinks it is measuring. Turn it on, capture, turn it
          // off — never leave it on across an assertion, because it changes
          // what is on screen.
          final raw = step.args;
          final overlayArgs = raw is Map<String, Object?> ? raw : {'enabled': raw == true};
          await _requireClient(driver, 'overlay').overlay(
            enabled: overlayArgs['enabled'] as bool?,
            showIds: overlayArgs['showIds'] as bool?,
            showBounds: overlayArgs['showBounds'] as bool?,
          );
        case 'snapshot':
          final name = step.args is String ? step.args as String : 'step-${step.line}';
          final bytes = await driver.screenshot();
          bundle.saveScreenshot(name, bytes);
          record['screenshot'] = '$name.png';
          // [C5]: every image in a bundle says where it came from. These are
          // always the platform compositor's own capture (screencapture,
          // simctl io) — never Flutter's `/v1/screenshot`, which is
          // diagnostic-only and would happily agree with a broken layout
          // because it renders from the same tree the layout came from.
          record['screenshot_source'] = 'platform-compositor';
          // A screenshot answers "what does it look like"; the audit question
          // "where exactly does the content edge sit" needs numbers, and the
          // only ui_tree a bundle used to keep was the one at teardown. So a
          // snapshot now captures the measurable half of the same moment
          // under the same name: the tree the screenshot was taken of, plus
          // the viewport it was measured against. Additive — every existing
          // scenario gains the dump without changing what it asserts.
          bundle.saveUiTree(name, {'viewport': await driver.viewport(), 'tree': await driver.uiTree()});
          record['ui_tree'] = '$name.json';
        case 'settle':
          // Bare `- settle` keeps the old fixed 500ms; `- settle: 3000` lets
          // a scenario wait out something with no automation-observable
          // signal of its own — e.g. IntroGate's ~2.8s cosmetic splash
          // overlay, which mounts *above* an already-ready screen rather
          // than gating it, so no `wait_until` can see it finish.
          await Future<void>.delayed(Duration(milliseconds: (step.args as int?) ?? 500));
        case 'walk':
          final walkRecord = await _dispatchWalk(step, driver, bundle);
          record.addAll(walkRecord);
        case 'press':
          final press = parsePressArgs(step.args);
          record['input_route'] = driver.inputRoute;
          record['key'] = press.key;
          if (press.hold != null) record['hold_ms'] = press.hold!.inMilliseconds;
          await _recordInput(driver, record, () => driver.press(press.key, hold: press.hold));
        case 'tap':
          record['input_route'] = driver.inputRoute;
          final args = step.args as Map<String, Object?>;
          await driver.tap((args['x'] as num).toDouble(), (args['y'] as num).toDouble());
        case 'type':
          record['input_route'] = driver.inputRoute;
          await _recordInput(driver, record, () => driver.typeText(step.args as String));
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
        // leftover process survives into the next run. Redacted the same
        // way every other step's `error` field is (see `runStep`'s catch
        // clause) — a terminate failure can quote the same URLs/headers a
        // step failure can.
        stepRecords.add({'verb': 'terminate', 'ok': false, 'error': redact('$e')});
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

/// Walks [step]'s direction, judging every hop in the frame the press was
/// issued in.
///
/// Two facts from the exploration shape this. Rects move under the press being
/// judged — a rail scrolls the moment focus enters it — so the *pre* frame is
/// the only honest one to measure against, and the landing has to be found
/// back in it by `node` number rather than by geometry. And a `discovered`
/// node has no identity of its own beyond that number, which is why
/// `AutomationRegistry` hands one out at all.
///
/// Fails fast: the first red hop throws with the source, the landing and every
/// passed-over candidate named, because a walk that carried on would measure
/// its remaining hops from a position the app should never have been in.
Future<Map<String, Object?>> _dispatchWalk(ScenarioStep step, VerificationDriver driver, EvidenceBundle bundle) async {
  final walk = parseWalkArgs(step.args);
  final direction = WalkDirection.parse(walk.direction)!;
  final allow = walk.allow.toSet();
  final name = 'walk-${step.line}';
  final deadline = DateTime.now().add(walk.timeout);

  final hops = <Map<String, Object?>>[];
  var stop = 'steps';
  var inconclusive = 0;

  Never failHop(String message, Map<String, Object?> hop) {
    hops.add(hop);
    bundle.saveWalk(name, {'direction': walk.direction, 'stop': 'failed', 'hops': hops});
    throw StateError(message);
  }

  for (var k = 1; k <= walk.steps; k++) {
    if (DateTime.now().isAfter(deadline)) {
      failHop('walk timed out after ${walk.timeout.inMilliseconds}ms at hop $k', {'hop': k, 'kind': 'timeout'});
    }

    final preTree = await driver.uiTree();
    final preViewportRaw = await driver.viewport();
    final preCandidates = walkCandidatesFrom(preTree);
    final preFocus = await driver.focus();
    final from = locateFocus(preFocus, preCandidates);
    final hop = <String, Object?>{'hop': k, 'direction': walk.direction};

    if (from == null) {
      failHop('walk hop $k has nothing focused to start from — the app has no primary focus', hop);
    }
    hop['from'] = from.toJson();

    await _recordInput(driver, hop, () => driver.press(direction.name));
    if (walk.settle > Duration.zero) await Future<void>.delayed(walk.settle);

    final postFocus = await driver.focus();
    final postTree = await driver.uiTree();
    final postCandidates = walkCandidatesFrom(postTree);
    final landed = locateFocus(postFocus, postCandidates);
    hop['to'] = landed?.toJson();

    // Every hop keeps the frame it was judged in, so a verdict can be
    // re-derived offline from the bundle alone.
    bundle.saveUiTree('$name-hop-$k', {
      'viewport': preViewportRaw,
      'pre': preTree,
      'focus_before': preFocus,
      'focus_after': postFocus,
    });

    if (landed == null || _sameNode(from, landed)) {
      // "A walk that does not move proves nothing" — but only on the first
      // hop. After a hop that did move, standing still is the edge of the
      // surface, which is an answer.
      hop['kind'] = 'edge';
      hop['message'] = 'the focus did not move';
      if (k == 1) {
        failHop('walk hop 1 did not move the focus, so this walk proves nothing', hop);
      }
      if (walk.stopAt != null) {
        failHop("walk reached the edge at hop $k without ever focusing '${walk.stopAt}'", hop);
      }
      if (walk.expect.isNotEmpty) {
        failHop('walk reached the edge at hop $k, but expect names ${walk.expect.length} landings', hop);
      }
      hops.add(hop);
      stop = 'edge';
      break;
    }

    final expectedId = walk.expect.length >= k ? walk.expect[k - 1] : null;
    if (expectedId != null && landed.id != expectedId) {
      hop['kind'] = 'expectMismatch';
      hop['message'] = "hop $k was expected to land on '$expectedId' and landed on ${landed.describe}";
      failHop(hop['message']! as String, hop);
    }

    // The landing, back in the frame the press was issued in. Absent means the
    // node was built by the scroll this press caused.
    final toInPre = _matchInPre(preCandidates, landed);
    if (toInPre != null &&
        ((landed.rect.left - toInPre.rect.left).abs() > 0.5 || (landed.rect.top - toInPre.rect.top).abs() > 0.5)) {
      // The landing moved under the press that reached it — a rail scrolling
      // itself into place. Worth recording next to the verdict, because it is
      // the reason the judgement is made in the pre-frame at all.
      hop['scrolled'] = true;
    }

    final viewport = _viewportRect(preViewportRaw, preTree);
    final verdict = judgeHop(
      from: from,
      to: toInPre,
      direction: direction,
      candidates: preCandidates,
      viewport: viewport,
      allow: allow,
      expected: expectedId != null,
    );
    hop['kind'] = verdict.kind.name;
    hop['message'] = verdict.message;
    if (verdict.passedOver.isNotEmpty) {
      hop['passedOver'] = [for (final n in verdict.passedOver) n.toJson()];
    }

    switch (verdict.kind) {
      case HopVerdictKind.inconclusive:
        inconclusive++;
      case HopVerdictKind.ok:
        break;
      case HopVerdictKind.skipped:
      case HopVerdictKind.notForward:
        bundle.saveUiTree('$name-hop-$k-post', postTree);
        try {
          bundle.saveScreenshot('$name-hop-$k', await driver.screenshot());
        } catch (_) {
          // A missing screenshot must not replace the real failure.
        }
        failHop(verdict.message, hop);
    }

    hops.add(hop);

    if (walk.stopAt != null && landed.id == walk.stopAt) {
      stop = 'stopAt';
      break;
    }
  }

  if (hops.isNotEmpty && inconclusive == hops.length) {
    bundle.saveWalk(name, {'direction': walk.direction, 'stop': 'failed', 'hops': hops});
    throw StateError(
      'every hop of this walk landed on a node that did not exist in the frame its press was issued in, so the '
      'walk judged nothing — raise `settle`, or walk a surface that does not rebuild under the press',
    );
  }
  if (walk.stopAt != null && stop != 'stopAt') {
    bundle.saveWalk(name, {'direction': walk.direction, 'stop': 'failed', 'hops': hops});
    throw StateError("walk finished its ${walk.steps} steps without ever focusing '${walk.stopAt}'");
  }

  final record = {'direction': walk.direction, 'stop': stop, 'hops': hops};
  bundle.saveWalk(name, record);
  return {'walk': '$name.json', 'stop': stop, 'hops': hops};
}

/// Two measurements of the same focusable. By number when both have one; a
/// rect otherwise, which is all a node with no `FocusNode` of its own leaves.
bool _sameNode(WalkNode a, WalkNode b) {
  if (a.node != null && b.node != null) return a.node == b.node;
  if (a.id != null && a.id == b.id) return true;
  return (a.rect.left - b.rect.left).abs() < 0.5 && (a.rect.top - b.rect.top).abs() < 0.5;
}

/// The landing as it stood *before* the press, or null when it was not there.
WalkNode? _matchInPre(List<WalkNode> preCandidates, WalkNode landed) {
  for (final c in preCandidates) {
    if (_sameNode(c, landed)) return c;
  }
  return null;
}

/// `/v1/viewport` as a rect in the same root space `/v1/ui_tree` reports
/// bounds in. Falls back to the union of everything measurable when the app
/// cannot answer, so a walk still runs on a target whose viewport endpoint is
/// unavailable rather than silently treating every candidate as offscreen.
GeoRect _viewportRect(Map<String, Object?> raw, Map<String, Object?> tree) {
  final width = raw['width'];
  final height = raw['height'];
  if (width is num && height is num) {
    return GeoRect(left: 0, top: 0, width: width.toDouble(), height: height.toDouble());
  }
  var right = 0.0;
  var bottom = 0.0;
  for (final node in walkCandidatesFrom(tree)) {
    if (node.rect.right > right) right = node.rect.right;
    if (node.rect.bottom > bottom) bottom = node.rect.bottom;
  }
  return GeoRect(left: 0, top: 0, width: right, height: bottom);
}

/// The transport client, or a message naming the verb that needed it.
/// `driver.client` is null until a successful `launch`, and a scenario that
/// forgets that step should read "sign_in needs a launched app", not a null
/// dereference from inside the engine.
VerifyClient _requireClient(VerificationDriver driver, String verb) {
  final client = driver.client;
  if (client == null) {
    throw StateError('$verb needs a launched app — add a `launch` step to this scenario\'s setup first');
  }
  return client;
}

Future<void> _dispatchWaitUntil(ScenarioStep step, VerificationDriver driver) async {
  final args = step.args as Map<String, Object?>;
  final timeoutMs = (args['timeout'] as num).toInt();
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

  Future<bool> predicate() async {
    if (args['focused'] case final String id) return (await _focusedIds(driver)).contains(id);
    if (args['id'] case final String id) return _idReady(driver, id);
    if (args['event'] case final String eventName) {
      final events = await driver.eventsSince(0);
      return events.any((e) => e['name'] == eventName);
    }
    throw ArgumentError('wait_until needs a "focused", "id" or "event" field: $args');
  }

  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw StateError('wait_until timed out after ${timeoutMs}ms: $args');
}

/// Presence first, then any geometry and/or `state`/`focused` predicates the
/// step carries. Returns the evaluated verdicts so the caller can record
/// them — including the passing ones, because "the hero is 12px inside the
/// viewport" is the measurement a later regression gets compared against.
///
/// A failing verdict throws with every measured value in the message: the
/// point of `GeometryVerdict`/`NodeAssertionResult` is that a red run
/// explains itself without anyone re-deriving the measurement by hand.
Future<({List<GeometryAssertionResult> geometry, List<NodeAssertionResult> node})> _dispatchAssert(
  Map<String, Object?> args,
  VerificationDriver driver,
) async {
  final id = args['id'] as String;
  if (!await _idReady(driver, id)) {
    throw StateError('assert failed: "$id" is not ready/present');
  }

  final hasGeometry = args.keys.any(geometryPredicates.contains);
  final hasNode = args.keys.any(nodeFieldPredicates.contains);
  if (!hasGeometry && !hasNode)
    return (geometry: const <GeometryAssertionResult>[], node: const <NodeAssertionResult>[]);

  // One fetch of each, shared by every predicate on this step: predicates
  // measured against different frames would not be comparable.
  final uiTree = await driver.uiTree();
  final geometry = hasGeometry
      ? evaluateGeometryAssertions(args, uiTree: uiTree, viewport: await driver.viewport())
      : const <GeometryAssertionResult>[];
  final node = hasNode ? evaluateNodeAssertions(args, uiTree: uiTree) : const <NodeAssertionResult>[];

  final failures = <String>[
    for (final r in geometry.where((r) => !r.verdict.ok))
      '${r.predicate}(${r.subjectId}${r.otherId == null ? '' : ', ${r.otherId}'}): ${r.verdict.message}',
    for (final r in node.where((r) => !r.ok))
      '${r.predicate}(${r.subjectId}${r.key == null ? '' : '.${r.key}'}): ${r.message}',
  ];
  if (failures.isNotEmpty) {
    throw StateError('assert failed: ${failures.join('; ')}');
  }
  return (geometry: geometry, node: node);
}

/// Which declared automation ids currently report `focused: true`.
///
/// `/v1/focus` answers with a `FocusNode.debugLabel`, not an id, so it can
/// say "something is focused" but not *what* in the vocabulary a scenario is
/// written in. `/v1/ui_tree`'s declared list carries both, so focus identity
/// comes from there. Plural because a duplicate id or a nested focus scope
/// can legitimately produce more than one, and collapsing that to a single
/// value would hide exactly the "two focus authorities" defect this round is
/// looking for.
Future<List<String>> _focusedIds(VerificationDriver driver) async {
  final tree = await driver.uiTree();
  final declared = (tree['declared'] as List?)?.cast<Map<String, Object?>>() ?? const [];
  return [
    for (final n in declared)
      if (n['focused'] == true) n['id'] as String,
  ];
}

/// One observation of everything an input could plausibly have changed.
Future<Map<String, Object?>> _observe(VerificationDriver driver) async {
  Future<T?> attempt<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  final screens = await attempt(driver.screensSnapshot);
  return {
    'focused_ids': await attempt(() => _focusedIds(driver)) ?? const <String>[],
    'focus': await attempt(driver.focus),
    'screens': [
      for (final s in screens ?? const <Map<String, Object?>>[])
        if (s['ready'] == true) s['id'],
    ],
    'route': await attempt(driver.route),
  };
}

/// Dispatches an input and records **what changed in the app because of
/// it** — the only evidence that distinguishes a working remote from a
/// driver call that returned zero while the app ignored it. A step that
/// merely says `press: down` and `ok: true` proves the process exited
/// cleanly, nothing more.
///
/// The wait after the input is bounded and *early-returning*, not a sleep:
/// it polls the same observation the record is built from and returns the
/// moment focus, the ready-screen set or the route differs from before, so
/// a responsive app costs one poll interval rather than the whole window.
/// When nothing changes it costs the full window and records
/// `changed: false` — which is a finding, not a timeout.
Future<void> _recordInput(
  VerificationDriver driver,
  Map<String, Object?> record,
  Future<void> Function() input, {
  Duration window = const Duration(milliseconds: 1500),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final before = await _observe(driver);
  final eventSeqBefore = await _currentEventSeq(driver);
  record['before'] = before;

  await input();

  final deadline = DateTime.now().add(window);
  var after = await _observe(driver);
  while (DateTime.now().isBefore(deadline) && _sameObservation(before, after)) {
    await Future<void>.delayed(pollInterval);
    after = await _observe(driver);
  }

  record['after'] = after;
  record['changed'] = !_sameObservation(before, after);
  record['events'] = [
    for (final e in await driver.eventsSince(eventSeqBefore)) {'name': e['name'], 'data': e['data']},
  ];
}

Future<int> _currentEventSeq(VerificationDriver driver) async {
  try {
    final events = await driver.eventsSince(0);
    if (events.isEmpty) return 0;
    return (events.last['seq'] as num).toInt();
  } catch (_) {
    return 0;
  }
}

/// Two observations are "the same" only when nothing a viewer could see has
/// moved.
///
/// `focused_ids` alone is not enough, and the gap showed up in real evidence:
/// walking the action bar inside Logs en diagnose moved the ring from one
/// button to the next while every declared id stayed unfocused, because those
/// buttons carry no automation id. The record said `changed: false` about a
/// press that plainly did something. `/v1/focus`'s label and rect answer for
/// everything that has no id of its own, which is most of the app.
bool _sameObservation(Map<String, Object?> a, Map<String, Object?> b) =>
    jsonEncode(a['focused_ids']) == jsonEncode(b['focused_ids']) &&
    jsonEncode(a['screens']) == jsonEncode(b['screens']) &&
    jsonEncode(a['route']) == jsonEncode(b['route']) &&
    jsonEncode(_focusIdentity(a['focus'])) == jsonEncode(_focusIdentity(b['focus']));

/// The parts of `/v1/focus` that say *which* thing is focused. `_statusCode`
/// and anything else the transport adds are deliberately not part of it.
Map<String, Object?>? _focusIdentity(Object? focus) {
  if (focus is! Map<String, Object?>) return null;
  return {'label': focus['label'], 'focused': focus['focused'], 'bounds': focus['bounds']};
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
    // A walk's finding is per hop, and a report that only said PASS/FAIL for
    // the whole step would hide which press went wrong.
    for (final hop in (raw['hops'] as List?) ?? const []) {
      final h = hop as Map<String, Object?>;
      buffer.writeln('  - hop ${h['hop']}: ${h['kind']} — ${h['message']}');
    }
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
