import 'dart:convert';
import 'dart:io';

import 'package:pleya_verify_runner/src/focus_walk.dart';
import 'package:pleya_verify_runner/src/geometry.dart';
import 'package:test/test.dart';

/// The oracle's rules live in `pleya_verify/focus_walk/SPEC.md` and its
/// vectors in `cases.json` next to it — deliberately outside this file, so a
/// rule change is a diff a reviewer can read without reading Dart, and so the
/// same vectors can one day be replayed against a captured bundle.
void main() {
  final file = File('${_repoRoot()}/pleya_verify/focus_walk/cases.json');

  test('the vector file is where the spec says it is', () {
    expect(file.existsSync(), isTrue, reason: '${file.path} is the vector set focus_walk.dart is judged by');
  });

  final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final cases = (doc['cases'] as List).cast<Map<String, Object?>>();

  test('every direction carries at least one ok and one skipped vector', () {
    for (final direction in WalkDirection.values) {
      final kinds = [
        for (final c in cases)
          if (c['direction'] == direction.name) (c['expect'] as Map)['kind'],
      ];
      expect(kinds, contains('ok'), reason: 'no healthy hop pinned for ${direction.name}');
      expect(kinds, contains('skipped'), reason: 'no skipped-candidate hop pinned for ${direction.name}');
    }
  });

  test('the set is big enough to be a set', () {
    expect(cases.length, greaterThanOrEqualTo(30));
  });

  for (final c in cases) {
    final name = c['name'] as String;
    test('$name — ${c['why']}', () {
      final expected = c['expect'] as Map<String, Object?>;
      final verdict = judgeHop(
        from: _node(c['from'] as Map<String, Object?>),
        to: c['to'] == null ? null : _node(c['to'] as Map<String, Object?>),
        direction: WalkDirection.parse(c['direction'] as String)!,
        candidates: [for (final raw in c['candidates'] as List) _node(raw as Map<String, Object?>)],
        viewport: GeoRect.fromJson((c['viewport'] as Map).cast<String, Object?>()),
        allow: {for (final id in (c['allow'] as List? ?? const [])) id as String},
        expected: c['expected'] == true,
      );

      expect(verdict.kind.name, expected['kind'], reason: verdict.message);
      expect(
        [for (final n in verdict.passedOver) n.id ?? 'node ${n.node}'],
        (expected['passedOver'] as List).cast<String>(),
        reason: verdict.message,
      );
      // A failing verdict has to name the thing on screen, or a red walk costs
      // an afternoon of re-deriving what it meant.
      if (!verdict.ok) expect(verdict.message, isNotEmpty);
    });
  }

  group('walkCandidatesFrom', () {
    test('merges declared and discovered on the node number, keeping the id', () {
      final tree = {
        'declared': [
          {'id': 'nav.series', 'node': 4, 'bounds': _b(374, 54, 110, 56)},
        ],
        'discovered': [
          {'label': 'FocusableWrapper', 'node': 4, 'bounds': _b(374, 54, 110, 56)},
          {'label': 'FocusableWrapper', 'node': 5, 'bounds': _b(508, 54, 110, 56)},
        ],
      };

      final candidates = walkCandidatesFrom(tree);

      expect(candidates, hasLength(2));
      expect(candidates.firstWhere((c) => c.node == 4).id, 'nav.series');
      expect(candidates.firstWhere((c) => c.node == 5).id, isNull);
    });

    test('drops what cannot take focus, and what has no bounds', () {
      final tree = {
        'declared': [
          {'id': 'a', 'node': 1, 'canRequestFocus': false, 'bounds': _b(0, 0, 10, 10)},
          {'id': 'b', 'node': 2},
        ],
        'discovered': [
          {'node': 3, 'bounds': _b(20, 0, 10, 10)},
        ],
      };

      expect(walkCandidatesFrom(tree).map((c) => c.node), [3]);
    });

    test('a node with no number is kept, because a rect is still a rect', () {
      final tree = {
        'declared': const [],
        'discovered': [
          {'label': 'old build', 'bounds': _b(0, 0, 10, 10)},
        ],
      };

      expect(walkCandidatesFrom(tree), hasLength(1));
    });
  });

  group('locateFocus', () {
    final candidates = [
      WalkNode(node: 4, id: 'nav.series', rect: const GeoRect(left: 374, top: 54, width: 110, height: 56)),
      WalkNode(node: 5, rect: const GeoRect(left: 508, top: 54, width: 110, height: 56)),
    ];

    test('matches on the node number even when the rect has moved', () {
      // The scroll case in one line: same node, different rect. A rect match
      // would have picked the neighbour.
      final found = locateFocus({'node': 4, 'bounds': _b(94, 54, 110, 56)}, candidates);
      expect(found?.id, 'nav.series');
    });

    test('falls back to an exact rect when there is no number', () {
      expect(locateFocus({'bounds': _b(508, 54, 110, 56)}, candidates)?.node, 5);
    });

    test('a focus that is not in the tree is still a usable source', () {
      final found = locateFocus({'label': 'elsewhere', 'bounds': _b(900, 900, 10, 10)}, candidates);
      expect(found, isNotNull);
      expect(found!.id, isNull);
      expect(found.rect.left, 900);
    });

    test('no focus at all is no node', () {
      expect(locateFocus(null, candidates), isNull);
    });
  });
}

WalkNode _node(Map<String, Object?> raw) => WalkNode(
  node: raw['node'] as int?,
  id: raw['id'] as String?,
  label: raw['label'] as String?,
  rect: GeoRect.fromJson((raw['bounds'] as Map).cast<String, Object?>()),
);

Map<String, Object?> _b(double x, double y, double w, double h) => {'x': x, 'y': y, 'width': w, 'height': h};

/// The runner package sits two levels below the repo root.
String _repoRoot() => Directory.current.path.endsWith('pleya_verify/runner')
    ? Directory.current.parent.parent.path
    : Directory.current.path;
