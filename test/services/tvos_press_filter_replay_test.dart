// DBL1 negative control. Models station 3 (`tvosHandlePress`, `filterArrowPress`,
// `pressFilterDrop`, the RAIL2 delivery memory and `undoDropsReachingResponderChain`
// in tvos/Runner/PleyaFlutterViewController.swift) together with the parts of the engine it
// talks to (the two swizzle hops of `FlutterTvosHandlePressesEvent`, the pressed
// set with `tapIfMissingKeyDown`, and the `pressesBegan:` fallback), then replays
// three hardware logs through it. The Swift cannot run here; the last test pins
// the Swift lines this model mirrors, so removing one turns this file red.
//
// Fixtures are the `native press=` lines of logs oc8pw (build 303), v5okk
// (build 306) and 76ott (build 307). Only 76ott carries `ts=`
// (UIPress.timestamp). For oc8pw and v5okk the hook time `t=` is the only clock
// and it ticks in steps of about 20 ms: it cannot place a gap near 30 ms, so
// those two logs only check that nothing with a proxy gap of 40 ms or more is
// dropped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---- mirror of PleyaFlutterViewController.swift ---------------------------

const double bounceGapMs = 30.0;

String? pressFilterDrop({required double beganMs, required double? previousEndedMs}) {
  if (previousEndedMs == null) return null;
  final gap = beganMs - previousEndedMs;
  if (!(gap >= 0 && gap < bounceGapMs)) return null;
  return 'bounce gapMs=${gap.round()}';
}

enum Phase { began, changed, ended, cancelled }

const _arrows = {'up', 'down', 'left', 'right'};

class Press {
  Press(this.name, this.phase, this.ms, {this.claimable = true, this.at = ''});
  final String name;
  final Phase phase;
  final double ms; // UIPress.timestamp in ms
  /// false for a press the engine hands back to UIKit (Menu under passthrough).
  final bool claimable;
  final String at;
}

class _Delivery {
  _Delivery(this.phase, this.ms, this.result, this.dropped);
  final Phase phase;
  final double ms;
  final bool result;
  final bool dropped;
}

/// The engine as station 3 sees it.
class Engine {
  final pressed = <String>{};
  int downs = 0;
  int phantoms = 0;

  void down(String key) {
    if (pressed.add(key)) downs++;
  }

  void up(String key, {required bool tapIfMissing}) {
    if (!pressed.remove(key) && tapIfMissing) phantoms++;
  }

  /// `tvosHandlePressFromUIEvent:`.
  bool hook(Press p) {
    if (!p.claimable) return false;
    if (p.phase == Phase.began || p.phase == Phase.changed) {
      down(p.name);
    } else {
      up(p.name, tapIfMissing: true);
    }
    return true;
  }
}

class Station3 {
  Station3(this.engine, {this.filterEnabled = true});
  final Engine engine;

  /// false models the build before DBL1: the baseline a replay compares with.
  final bool filterEnabled;
  bool sessionActive = false;
  final lastDelivery = <String, _Delivery>{};
  final lastArrowEndedMs = <String, double>{};
  final droppedArrowLifecycles = <String, double>{};
  final drops = <String>[];

  String? filterArrowPress(Press p) {
    if (!filterEnabled || !_arrows.contains(p.name)) return null;
    switch (p.phase) {
      case Phase.began:
        droppedArrowLifecycles.remove(p.name);
        if (sessionActive) return null;
        final reason = pressFilterDrop(beganMs: p.ms, previousEndedMs: lastArrowEndedMs[p.name]);
        if (reason == null) return null;
        droppedArrowLifecycles[p.name] = p.ms;
        return 'drop $reason type=${p.name}';
      case Phase.ended:
      case Phase.cancelled:
        lastArrowEndedMs[p.name] = p.ms;
        final began = droppedArrowLifecycles.remove(p.name);
        if (began == null) return null;
        return 'drop lifecycle type=${p.name} holdMs=${(p.ms - began).round()}';
      case Phase.changed:
        return droppedArrowLifecycles.containsKey(p.name) ? 'drop lifecycle type=${p.name}' : null;
    }
  }

  /// `tvosHandlePress(fromUIEvent:)`.
  bool handle(Press p) {
    final previous = lastDelivery[p.name];
    final isRepeat = previous != null && previous.phase == p.phase && previous.ms == p.ms;
    if (isRepeat && previous.dropped) return true;
    final filter = isRepeat ? null : filterArrowPress(p);
    if (filter != null) {
      drops.add('${p.at} $filter');
      lastDelivery[p.name] = _Delivery(p.phase, p.ms, true, true);
      return true;
    }
    if (!sessionActive) {
      if (isRepeat) return previous.result;
      final result = engine.hook(p);
      lastDelivery[p.name] = _Delivery(p.phase, p.ms, result, false);
      return result;
    }
    return false;
  }

  /// `pressesBegan` override: undo, then the engine's `maybeSynthesizeForPress:`.
  void pressesBegan(List<Press> presses) {
    for (final p in presses.where((p) => p.phase == Phase.began)) {
      if (droppedArrowLifecycles[p.name] == p.ms) {
        droppedArrowLifecycles.remove(p.name);
        lastDelivery.remove(p.name);
        drops.add('${p.at} undo mixed-event type=${p.name}');
      }
    }
    if (sessionActive) return; // forwarded to `next`, the engine is not involved
    for (final p in presses) {
      if (!p.claimable) continue;
      if (p.phase == Phase.began) engine.down(p.name);
      if (p.phase == Phase.ended || p.phase == Phase.cancelled) engine.up(p.name, tapIfMissing: false);
    }
  }

  /// One `sendEvent:`: the UIApplication hop, then (if a press went
  /// unclaimed) the UIWindow hop, then UIKit's responder chain.
  void sendEvent(List<Press> allPresses) {
    bool hop() {
      var unhandled = false;
      for (final p in allPresses) {
        if (!handle(p)) unhandled = true;
      }
      return !unhandled;
    }

    if (hop()) return;
    if (hop()) return;
    pressesBegan(allPresses);
  }
}

// ---- log replay --------------------------------------------------------

final _line = RegExp(r'^\[([\d:.]+)\] native press=(\w+)\(\d+\) phase=(\d+) uipress=\d+ t=(\d+)(?: ts=(\d+))?');

List<(Press, int)> _load(String id) => [
  for (final raw in File('test/fixtures/tvos_press/$id.txt').readAsLinesSync())
    if (_line.firstMatch(raw) case final m?)
      (
        Press(m[2]!, int.parse(m[3]!) == 0 ? Phase.began : Phase.ended, double.parse(m[5] ?? m[4]!), at: m[1]!),
        int.parse(m[4]!),
      ),
];

class _Result {
  _Result(this.station, this.engine, this.droppedBeganProxyGaps, this.arrowLifecycles);
  final Station3 station;
  final Engine engine;
  final List<int> droppedBeganProxyGaps; // t= gap of each dropped began to the previous ended
  final int arrowLifecycles;
  List<String> get droppedEndeds => [
    for (final d in station.drops)
      if (d.contains('drop lifecycle')) d.split(' ').first,
  ];
}

_Result _replay(String id, {bool filterEnabled = true}) {
  final engine = Engine();
  final s = Station3(engine, filterEnabled: filterEnabled);
  final lastEndedT = <String, int>{};
  final proxyGaps = <int>[];
  var lifecycles = 0;
  for (final (p, t) in _load(id)) {
    final dropsBefore = s.drops.length;
    s.sendEvent([p]);
    if (_arrows.contains(p.name) && p.phase == Phase.began) {
      lifecycles++;
      if (s.drops.length > dropsBefore) proxyGaps.add(t - lastEndedT[p.name]!);
    }
    if (p.phase == Phase.ended) lastEndedT[p.name] = t;
  }
  return _Result(s, engine, proxyGaps, lifecycles);
}

/// Against the same log without the filter: no extra phantom pair, no key
/// left held that was not held before (Select from a keyboard session is),
/// and exactly one Down fewer per dropped lifecycle.
void _expectNoHalfPairs(_Result r, _Result baseline) {
  expect(r.engine.phantoms, baseline.engine.phantoms, reason: 'tapIfMissingKeyDown never fires for a drop');
  expect(r.engine.pressed, baseline.engine.pressed, reason: 'no key left in the pressed set, no endless repeat');
  expect(r.engine.downs, baseline.engine.downs - r.droppedBeganProxyGaps.length);
}

void main() {
  group('replay of the hardware logs', () {
    test('76ott (UIKit ts): the four flagged bounces are dropped whole, nothing else', () {
      final r = _replay('76ott');
      for (final d in r.station.drops) {
        // ignore: avoid_print
        print('76ott $d');
      }
      expect(r.droppedEndeds, ['12:47:30.523', '12:47:44.783', '12:48:10.263', '12:48:21.544']);
      expect(r.station.drops.length, 8, reason: 'each dropped began takes its ended along');
      expect(r.arrowLifecycles, 132);
      _expectNoHalfPairs(r, _replay('76ott', filterEnabled: false));
    });

    for (final id in ['oc8pw', 'v5okk']) {
      test('$id (t= proxy): no press with a proxy gap of 40 ms or more is dropped', () {
        final r = _replay(id);
        // ignore: avoid_print
        print(
          '$id lifecycles=${r.arrowLifecycles} dropped=${r.droppedBeganProxyGaps.length} '
          'proxyGaps=${r.droppedBeganProxyGaps}',
        );
        expect(r.droppedBeganProxyGaps.where((g) => g >= 40), isEmpty);
        _expectNoHalfPairs(r, _replay(id, filterEnabled: false));
      });
    }
  });

  group('lifecycle', () {
    late Engine engine;
    late Station3 s;
    setUp(() {
      engine = Engine();
      s = Station3(engine);
      s.sendEvent([Press('right', Phase.began, 1000)]);
      s.sendEvent([Press('right', Phase.ended, 1100)]);
    });

    test('the ended of a dropped began is dropped too, on both hops', () {
      s.sendEvent([Press('right', Phase.began, 1115)]);
      s.sendEvent([Press('right', Phase.ended, 1130)]);
      expect(engine.downs, 1);
      expect(engine.pressed, isEmpty);
      expect(engine.phantoms, 0);
      expect(s.drops, hasLength(2));
    });

    test('a cancelled ends a dropped lifecycle the same way', () {
      s.sendEvent([Press('right', Phase.began, 1115)]);
      s.sendEvent([Press('right', Phase.cancelled, 1130)]);
      expect(engine.pressed, isEmpty);
      expect(s.drops.last, contains('drop lifecycle'));
    });

    test('an ended without a dropped began passes to the engine', () {
      s.sendEvent([Press('right', Phase.began, 1200)]);
      expect(engine.pressed, {'right'});
      s.sendEvent([Press('right', Phase.ended, 1300)]);
      expect(engine.pressed, isEmpty);
      expect(engine.downs, 2);
      expect(s.drops, isEmpty);
    });

    test('a mixed event is never filtered: the drop is undone and the engine sees both halves', () {
      final menu = Press('menu', Phase.began, 1110, claimable: false);
      s.sendEvent([Press('right', Phase.began, 1115), menu]);
      expect(engine.pressed, {'right'}, reason: 'the pressesBegan: fallback sent the Down');
      expect(s.droppedArrowLifecycles, isEmpty);
      s.sendEvent([Press('right', Phase.ended, 1200), Press('menu', Phase.ended, 1190, claimable: false)]);
      expect(engine.pressed, isEmpty);
      expect(engine.phantoms, 0);
      expect(engine.downs, 2);
    });

    test('a dropped lifecycle whose ended comes in a mixed event stays whole on both hops', () {
      s.sendEvent([Press('right', Phase.began, 1115)]);
      s.sendEvent([Press('right', Phase.ended, 1130), Press('menu', Phase.began, 1125, claimable: false)]);
      expect(engine.phantoms, 0, reason: 'the UIWindow hop must not reach tapIfMissingKeyDown');
      expect(engine.pressed, isEmpty);
      expect(engine.downs, 1);
    });

    test('a began after a dropped lifecycle that never ended starts fresh', () {
      s.sendEvent([Press('right', Phase.began, 1115)]); // dropped, no ended ever comes
      s.sendEvent([Press('right', Phase.began, 1500)]);
      expect(engine.pressed, {'right'});
      s.sendEvent([Press('right', Phase.ended, 1600)]);
      expect(engine.pressed, isEmpty);
      expect(engine.downs, 2);
    });

    test('no new drop during a native session, but a dropped lifecycle keeps its ended', () {
      s.sendEvent([Press('right', Phase.began, 1115)]);
      s.sessionActive = true;
      s.sendEvent([Press('right', Phase.ended, 1130)]);
      expect(s.drops.last, contains('drop lifecycle'));
      s.sendEvent([Press('right', Phase.began, 1140)]);
      expect(s.drops, hasLength(2));
    });

    test('a re-press 30 ms or more after the release is kept', () {
      s.sendEvent([Press('right', Phase.began, 1130)]);
      expect(engine.pressed, {'right'});
      expect(s.drops, isEmpty);
    });

    test('select, menu and playPause are never filtered', () {
      for (final name in ['select', 'menu', 'playPause']) {
        s.sendEvent([Press(name, Phase.began, 2000)]);
        s.sendEvent([Press(name, Phase.ended, 2010)]);
        s.sendEvent([Press(name, Phase.began, 2015)]);
        s.sendEvent([Press(name, Phase.ended, 2020)]);
      }
      expect(s.drops, isEmpty);
    });
  });

  test('the Swift lines this model mirrors are still in PleyaFlutterViewController.swift', () {
    final swift = File('tvos/Runner/PleyaFlutterViewController.swift').readAsStringSync();
    for (final line in [
      'static let bounceGapMs = $bounceGapMs',
      'guard gap >= 0, gap < bounceGapMs else { return nil }',
      'case .began:\n      droppedArrowLifecycles[type] = nil\n      guard !NativeInputSession.isActive,',
      'case .ended, .cancelled:\n      lastArrowEndedMs[type] = atMs\n'
          '      guard let beganMs = droppedArrowLifecycles.removeValue(forKey: type) else { return nil }',
      'return droppedArrowLifecycles[type] == nil ? nil : "drop lifecycle type=',
      'let isRepeatDelivery = previous?.phase == press.phase && previous?.timestamp == press.timestamp',
      'if isRepeatDelivery, previous?.dropped == true {\n      return true',
      'return rememberDelivery(press, result: true, dropped: true)',
      'guard droppedArrowLifecycles[type] == press.timestamp * 1000 else { continue }',
      'override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {\n'
          '    undoDropsReachingResponderChain(presses)',
    ]) {
      expect(swift, contains(line));
    }
  });
}
