// DBL1 negative control: replays the press lines of three hardware logs
// through a 1:1 mirror of the station-3 filter in tvos/Runner/AppDelegate.swift
// (`pressFilterDrop` and `filterArrowPress`). The Swift side cannot run here;
// the last test pins the calibration constants of both sides together.
//
// Fixtures are the `native press=` lines of logs oc8pw (build 303), v5okk
// (build 306) and 76ott (build 307), resp/gr stripped. Only 76ott carries
// `ts=` (UIPress.timestamp) and the gamepad fields; for oc8pw and v5okk the
// hook time `t=` stands in for UIKit time, and that clock ticks in steps of
// about 20 ms, so a gap there is only known to within 20 ms.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

// ---- mirror of AppDelegate.swift, keep in step --------------------------

const double bounceGapMs = 35.0;
const double clicklessEdge = 0.8;

String? pressFilterDrop({
  required double beganMs,
  required double? previousEndedMs,
  required bool clicked,
  required double? clickpadThumb,
}) {
  if (previousEndedMs != null) {
    final gap = beganMs - previousEndedMs;
    if (gap >= 0 && gap < bounceGapMs) return 'bounce gapMs=${gap.round()}';
  }
  if (!clicked && clickpadThumb != null && clickpadThumb >= clicklessEdge) {
    return 'no-click edge=${clickpadThumb.toStringAsFixed(2)}';
  }
  return null;
}

const _arrows = {'up', 'down', 'left', 'right'};

class _Filter {
  final lastArrowEndedMs = <String, double>{};
  final droppedArrowLifecycles = <String, double>{};

  String? filterArrowPress(_Press p) {
    if (!_arrows.contains(p.name)) return null;
    switch (p.phase) {
      case 0:
        droppedArrowLifecycles.remove(p.name);
        final reason = pressFilterDrop(
          beganMs: p.atMs,
          previousEndedMs: lastArrowEndedMs[p.name],
          clicked: p.clicked,
          clickpadThumb: p.clickpadThumb,
        );
        if (reason == null) return null;
        droppedArrowLifecycles[p.name] = p.atMs;
        return 'drop $reason type=${p.name}';
      case 3:
      case 4:
        lastArrowEndedMs[p.name] = p.atMs;
        final began = droppedArrowLifecycles.remove(p.name);
        if (began == null) return null;
        return 'drop lifecycle type=${p.name} holdMs=${(p.atMs - began).round()}';
      default:
        return droppedArrowLifecycles.containsKey(p.name) ? 'drop lifecycle type=${p.name}' : null;
    }
  }
}

// ---- log replay ----------------------------------------------------------

class _Press {
  _Press(this.at, this.name, this.phase, this.atMs, this.clicked, this.clickpadThumb);
  final String at;
  final String name;
  final int phase;
  final double atMs;
  final bool clicked;
  final double? clickpadThumb;
}

final _line = RegExp(r'^\[([\d:.]+)\] native press=(\w+)\(\d+\) phase=(\d+) uipress=\d+ t=(\d+)(?: ts=(\d+))?(.*)$');

/// [assumeClickpad]: 76ott predates the `gcD` field. It is an AppleTV14,1,
/// which ships with the USB-C Siri Remote, a GCDirectionalGamepad clickpad.
List<_Press> _load(String id, {bool assumeClickpad = false}) {
  final out = <_Press>[];
  for (final raw in File('test/fixtures/tvos_press/$id.txt').readAsLinesSync()) {
    final m = _line.firstMatch(raw);
    if (m == null) continue;
    final hw = {for (final f in RegExp(r'(gc\w)=(\S+)').allMatches(m[6]!)) f[1]!: f[2]!};
    final x = double.tryParse(hw['gcX'] ?? '');
    final y = double.tryParse(hw['gcY'] ?? '');
    final clickpad = hw['gcD'] == '1' || (hw['gcD'] == null && assumeClickpad);
    out.add(
      _Press(
        m[1]!,
        m[2]!,
        int.parse(m[3]!),
        double.parse(m[5] ?? m[4]!),
        // No gcA in the log means no knowledge: never judge it click-less.
        hw['gcA'] != '0',
        clickpad && x != null && y != null ? math.max(x.abs(), y.abs()) : null,
      ),
    );
  }
  return out;
}

class _Replay {
  final droppedBegans = <String>[]; // time of each dropped began line
  final droppedEndeds = <String>[]; // time of each dropped ended line
  final reasons = <String>[];
  int lifecycles = 0;
}

_Replay _replay(List<_Press> presses) {
  final f = _Filter();
  final r = _Replay();
  for (final p in presses) {
    if (p.phase == 0 && _arrows.contains(p.name)) r.lifecycles++;
    final drop = f.filterArrowPress(p);
    if (drop == null) continue;
    r.reasons.add('${p.at} $drop');
    (p.phase == 0 ? r.droppedBegans : r.droppedEndeds).add(p.at);
  }
  return r;
}

void main() {
  // The ended line of every NATIVE-BOUNCE that scripts/tvos_press_trace.sh
  // flags on these logs (the trace tags the ended, not the began).
  const flagged = {
    'oc8pw': [
      '23:21:52.031', '23:22:20.370', '23:22:38.750', '23:22:39.710', '23:23:12.089', //
      '23:23:13.510', '23:29:01.031', '23:29:07.631', '23:29:18.471', '23:29:39.010',
    ],
    'v5okk': ['10:20:00.357', '10:20:00.382', '10:20:06.537', '10:20:06.737', '10:20:06.776', '10:20:06.797'],
    '76ott': ['12:47:30.523', '12:47:44.783', '12:48:10.263', '12:48:21.544'],
  };

  test('76ott (UIKit ts + gamepad): every bounce dropped as a pair, no real press dropped', () {
    final r = _replay(_load('76ott', assumeClickpad: true));
    for (final line in r.reasons) {
      // ignore: avoid_print
      print('76ott $line');
    }
    expect(r.droppedEndeds, flagged['76ott']);
    expect(r.droppedBegans.length, r.droppedEndeds.length, reason: 'a dropped began must take its ended along');
    expect(r.lifecycles, 132);
  });

  test('oc8pw (t= proxy, no gamepad fields): all ten bounces dropped, nothing else', () {
    final r = _replay(_load('oc8pw'));
    expect(r.droppedEndeds, flagged['oc8pw']);
    expect(r.droppedBegans.length, r.droppedEndeds.length);
  });

  test('v5okk (t= proxy): the documented borderlines, otherwise the trace verdict', () {
    final r = _replay(_load('v5okk'));
    // Borderline 1: 10:20:00.357 is flagged by the trace (gap 40 <= its 40 ms
    // limit, hold 40) but kept here: its proxy gap is 40 ms, on a 20 ms clock
    // the true gap is 20-60 ms, so the log cannot say which side of 35 it was.
    // Borderline 2: 10:20:02.537 is dropped here but not flagged: proxy gap
    // 20 ms (true gap under 40 ms, below the fastest real re-press of 46 ms in
    // 76ott), hold 180 ms, longer than the trace's 40 ms bounce hold.
    expect(r.droppedEndeds, [
      '10:20:00.382',
      '10:20:02.537',
      '10:20:06.537',
      '10:20:06.737',
      '10:20:06.776',
      '10:20:06.797',
    ]);
    expect(r.droppedBegans.length, r.droppedEndeds.length);
  });

  test('select, menu and playPause are never filtered', () {
    final f = _Filter();
    for (final name in ['select', 'menu', 'playPause']) {
      expect(f.filterArrowPress(_Press('', name, 3, 1000, true, null)), isNull);
      expect(f.filterArrowPress(_Press('', name, 0, 1001, false, 1.0)), isNull);
    }
  });

  test('a press without a click is kept when no analog clickpad is connected (CEC, IR, digital remotes)', () {
    expect(pressFilterDrop(beganMs: 1000, previousEndedMs: null, clicked: false, clickpadThumb: null), isNull);
    expect(pressFilterDrop(beganMs: 1000, previousEndedMs: null, clicked: false, clickpadThumb: 0.79), isNull);
    expect(pressFilterDrop(beganMs: 1000, previousEndedMs: null, clicked: false, clickpadThumb: 0.9), isNotNull);
  });

  test('the calibration constants match AppDelegate.swift', () {
    final swift = File('tvos/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('static let bounceGapMs = $bounceGapMs'));
    expect(swift, contains('static let clicklessEdge = $clicklessEdge'));
    expect(swift, contains('if gap >= 0, gap < bounceGapMs {'));
    expect(swift, contains('if !clicked, let clickpadThumb, clickpadThumb >= clicklessEdge {'));
  });
}
