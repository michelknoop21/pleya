import 'package:pleya_verify_runner/src/engine/geometry_assertions.dart';
import 'package:test/test.dart';

Map<String, Object?> _node(String id, {double? x, double? y, double? w, double? h}) => {
  'id': id,
  'role': 'test',
  if (x != null) 'bounds': {'x': x, 'y': y, 'width': w, 'height': h},
};

Map<String, Object?> _tree(List<Map<String, Object?>> declared, {List<Map<String, Object?>> discovered = const []}) => {
  'declared': declared,
  'discovered': discovered,
  'duplicates': const [],
};

const _viewport = {'available': true, 'width': 1280.0, 'height': 800.0};

void main() {
  group('presence-only asserts evaluate nothing', () {
    test('a step with no geometry key returns no verdicts', () {
      final results = evaluateGeometryAssertions(
        {'id': 'discover.hero'},
        uiTree: _tree([_node('discover.hero', x: 0, y: 0, w: 100, h: 100)]),
        viewport: _viewport,
      );
      expect(results, isEmpty);
    });
  });

  group('insideViewport', () {
    test('passes for a node fully within the viewport', () {
      final results = evaluateGeometryAssertions(
        {'id': 'discover.hero', 'insideViewport': true},
        uiTree: _tree([_node('discover.hero', x: 10, y: 10, w: 400, h: 300)]),
        viewport: _viewport,
      );
      expect(results.single.verdict.ok, isTrue);
      expect(results.single.predicate, 'insideViewport');
      expect(results.single.subjectId, 'discover.hero');
    });

    test('fails with the overflow measured per edge, not just a bare false', () {
      final results = evaluateGeometryAssertions(
        {'id': 'discover.hero', 'insideViewport': true},
        uiTree: _tree([_node('discover.hero', x: 1000, y: 10, w: 400, h: 300)]),
        viewport: _viewport,
      );
      final verdict = results.single.verdict;
      expect(verdict.ok, isFalse);
      expect(verdict.message, contains('overflows'));
      expect((verdict.detail['overflow']! as Map)['right'], 120.0);
    });
  });

  group('minimumTapTarget', () {
    test('true uses the 44pt HIG default', () {
      final small = evaluateGeometryAssertions(
        {'id': 'discover.hero.play', 'minimumTapTarget': true},
        uiTree: _tree([_node('discover.hero.play', x: 0, y: 0, w: 40, h: 40)]),
        viewport: _viewport,
      );
      expect(small.single.verdict.ok, isFalse);
      expect(small.single.verdict.detail['minSize'], 44.0);
    });

    test('a number overrides the threshold', () {
      final results = evaluateGeometryAssertions(
        {'id': 'discover.hero.play', 'minimumTapTarget': 30},
        uiTree: _tree([_node('discover.hero.play', x: 0, y: 0, w: 40, h: 40)]),
        viewport: _viewport,
      );
      expect(results.single.verdict.ok, isTrue);
    });
  });

  group('binary predicates', () {
    final tree = _tree([
      _node('sidebar.rail', x: 0, y: 0, w: 200, h: 800),
      _node('discover.hero', x: 200, y: 0, w: 1080, h: 400),
      _node('library.grid', x: 200, y: 420, w: 1080, h: 380),
    ]);

    test('notOverlapping passes for adjacent, non-overlapping rects', () {
      final results = evaluateGeometryAssertions(
        {'id': 'discover.hero', 'notOverlapping': 'sidebar.rail'},
        uiTree: tree,
        viewport: _viewport,
      );
      expect(results.single.verdict.ok, isTrue);
      expect(results.single.otherId, 'sidebar.rail');
    });

    test('notOverlapping fails with the overlap size', () {
      final results = evaluateGeometryAssertions(
        {'id': 'discover.hero', 'notOverlapping': 'sidebar.rail'},
        uiTree: _tree([
          _node('sidebar.rail', x: 0, y: 0, w: 300, h: 800),
          _node('discover.hero', x: 200, y: 0, w: 1080, h: 400),
        ]),
        viewport: _viewport,
      );
      expect(results.single.verdict.ok, isFalse);
      expect(results.single.verdict.detail['overlapWidth'], 100.0);
    });

    test('below passes when the grid sits under the hero', () {
      final results = evaluateGeometryAssertions(
        {'id': 'library.grid', 'below': 'discover.hero'},
        uiTree: tree,
        viewport: _viewport,
      );
      expect(results.single.verdict.ok, isTrue);
    });

    test('a non-string value for a binary predicate is a broken assertion, not a failed one', () {
      expect(
        () => evaluateGeometryAssertions(
          {'id': 'discover.hero', 'notOverlapping': true},
          uiTree: tree,
          viewport: _viewport,
        ),
        throwsA(isA<GeometryAssertionException>().having((e) => e.message, 'message', contains('automation id'))),
      );
    });
  });

  test('several predicates on one step all evaluate, against one shared frame', () {
    final results = evaluateGeometryAssertions(
      {'id': 'discover.hero', 'insideViewport': true, 'notOverlapping': 'sidebar.rail', 'minimumTapTarget': 44},
      uiTree: _tree([
        _node('sidebar.rail', x: 0, y: 0, w: 200, h: 800),
        _node('discover.hero', x: 200, y: 0, w: 1080, h: 400),
      ]),
      viewport: _viewport,
    );

    expect(results.map((r) => r.predicate), containsAll(['insideViewport', 'notOverlapping', 'minimumTapTarget']));
    expect(results.every((r) => r.verdict.ok), isTrue);
  });

  group('un-evaluatable assertions read as broken, not as failures', () {
    test('an id absent from the tree', () {
      expect(
        () => evaluateGeometryAssertions(
          {'id': 'discover.hero', 'insideViewport': true},
          uiTree: _tree(const []),
          viewport: _viewport,
        ),
        throwsA(isA<GeometryAssertionException>().having((e) => e.message, 'message', contains('not in the UI tree'))),
      );
    });

    test('a registered node with no bounds — present but unmounted', () {
      // Distinct from "not there at all": one is a widget that never
      // rendered, the other an id that never existed, and merging them into
      // one message would send a reader after the wrong bug.
      expect(
        () => evaluateGeometryAssertions(
          {'id': 'discover.hero', 'insideViewport': true},
          uiTree: _tree([_node('discover.hero')]),
          viewport: _viewport,
        ),
        throwsA(isA<GeometryAssertionException>().having((e) => e.message, 'message', contains('no bounds'))),
      );
    });

    test('a viewport the app cannot report yet', () {
      expect(
        () => evaluateGeometryAssertions(
          {'id': 'discover.hero', 'insideViewport': true},
          uiTree: _tree([_node('discover.hero', x: 0, y: 0, w: 10, h: 10)]),
          viewport: const {'available': false},
        ),
        throwsA(isA<GeometryAssertionException>().having((e) => e.message, 'message', contains('available: false'))),
      );
    });
  });

  test('a discovered focusable is measurable too, not only a declared node', () {
    final results = evaluateGeometryAssertions(
      {'id': 'probe', 'insideViewport': true},
      uiTree: _tree(const [], discovered: [_node('probe', x: 5, y: 5, w: 50, h: 50)]),
      viewport: _viewport,
    );
    expect(results.single.verdict.ok, isTrue);
  });
}
