import 'package:pleya_verify_runner/src/engine/node_assertions.dart';
import 'package:test/test.dart';

Map<String, Object?> _node(String id, {Map<String, Object?>? state, bool? focused}) => {
  'id': id,
  'role': 'test',
  if (focused != null) 'focused': focused,
  if (state != null) 'state': state,
};

Map<String, Object?> _tree(List<Map<String, Object?>> declared, {List<Map<String, Object?>> discovered = const []}) => {
  'declared': declared,
  'discovered': discovered,
  'duplicates': const [],
};

void main() {
  group('a step with neither state nor focused', () {
    test('evaluates nothing', () {
      final results = evaluateNodeAssertions({'id': 'nav.discover'}, uiTree: _tree([_node('nav.discover')]));
      expect(results, isEmpty);
    });
  });

  group('state', () {
    test('passes when every requested key matches', () {
      final results = evaluateNodeAssertions(
        {
          'id': 'nav.discover',
          'state': {'collapsed': true},
        },
        uiTree: _tree([
          _node('nav.discover', state: {'selected': false, 'collapsed': true}),
        ]),
      );
      expect(results.single.ok, isTrue);
      expect(results.single.predicate, 'state');
      expect(results.single.key, 'collapsed');
      expect(results.single.actual, true);
    });

    test('fails and reports the actual value when a key does not match', () {
      final results = evaluateNodeAssertions(
        {
          'id': 'nav.discover',
          'state': {'collapsed': false},
        },
        uiTree: _tree([
          _node('nav.discover', state: {'collapsed': true}),
        ]),
      );
      expect(results.single.ok, isFalse);
      expect(results.single.actual, true);
      expect(results.single.expected, false);
      expect(results.single.message, contains('expected false'));
    });

    test('evaluates every requested key, not just the first', () {
      final results = evaluateNodeAssertions(
        {
          'id': 'library.grid',
          'state': {'child_count': 3, 'ready': true},
        },
        uiTree: _tree([
          _node('library.grid', state: {'child_count': 3, 'ready': false}),
        ]),
      );
      expect(results, hasLength(2));
      expect(results.firstWhere((r) => r.key == 'child_count').ok, isTrue);
      expect(results.firstWhere((r) => r.key == 'ready').ok, isFalse);
    });

    test('a node with no state callback raises rather than silently comparing null', () {
      expect(
        () => evaluateNodeAssertions({
          'id': 'sidebar.rail',
          'state': {'collapsed': true},
        }, uiTree: _tree([_node('sidebar.rail')])),
        throwsA(
          isA<NodeAssertionException>().having(
            (e) => e.message,
            'message',
            contains('does not publish an AutomationNode.state'),
          ),
        ),
      );
    });

    test('an id absent from the ui tree raises', () {
      expect(
        () => evaluateNodeAssertions({
          'id': 'nav.missing',
          'state': {'collapsed': true},
        }, uiTree: _tree(const [])),
        throwsA(isA<NodeAssertionException>().having((e) => e.message, 'message', contains('not in the UI tree'))),
      );
    });
  });

  group('focused', () {
    test('passes when the node reports the expected focus state', () {
      final results = evaluateNodeAssertions({
        'id': 'library.filter.sort',
        'focused': true,
      }, uiTree: _tree([_node('library.filter.sort', focused: true)]));
      expect(results.single.ok, isTrue);
      expect(results.single.predicate, 'focused');
    });

    test('a node with no explicit focused field reads as not focused', () {
      final results = evaluateNodeAssertions({
        'id': 'library.filter.sort',
        'focused': true,
      }, uiTree: _tree([_node('library.filter.sort')]));
      expect(results.single.ok, isFalse);
      expect(results.single.actual, false);
    });

    test('fails clearly when focus is somewhere else', () {
      final results = evaluateNodeAssertions({
        'id': 'library.filter.sort',
        'focused': true,
      }, uiTree: _tree([_node('library.filter.sort', focused: false)]));
      expect(results.single.ok, isFalse);
      expect(results.single.message, contains('expected true'));
    });
  });

  group('a predicate given the wrong YAML type', () {
    // The reason this group exists at all: `focused: yes` and `focused: on`
    // are booleans in YAML 1.1 and plain strings in the 1.2 core schema
    // `package:yaml` implements, and `focused: "true"` is a string in both.
    // All three are the shape a scenario author actually types. Silently
    // skipping the predicate turns each of them into a step that asserts
    // nothing and reports PASS, which is worse than no assertion at all:
    // the manifest then carries a green verdict for a claim never checked.
    test('focused as a string raises rather than evaluating nothing', () {
      expect(
        () => evaluateNodeAssertions({
          'id': 'nav.discover',
          'focused': 'true',
        }, uiTree: _tree([_node('nav.discover', focused: false)])),
        throwsA(isA<NodeAssertionException>().having((e) => e.message, 'message', contains('focused'))),
      );
    });

    test('focused as a number raises', () {
      expect(
        () => evaluateNodeAssertions({
          'id': 'nav.discover',
          'focused': 1,
        }, uiTree: _tree([_node('nav.discover', focused: true)])),
        throwsA(isA<NodeAssertionException>()),
      );
    });

    test('focused as null raises', () {
      expect(
        () => evaluateNodeAssertions({
          'id': 'nav.discover',
          'focused': null,
        }, uiTree: _tree([_node('nav.discover', focused: true)])),
        throwsA(isA<NodeAssertionException>()),
      );
    });

    test('state as a scalar raises rather than evaluating nothing', () {
      expect(
        () => evaluateNodeAssertions(
          {'id': 'nav.discover', 'state': true},
          uiTree: _tree([
            _node('nav.discover', state: {'collapsed': true}),
          ]),
        ),
        throwsA(isA<NodeAssertionException>().having((e) => e.message, 'message', contains('state'))),
      );
    });

    test('state as a list raises', () {
      expect(
        () => evaluateNodeAssertions(
          {
            'id': 'nav.discover',
            'state': ['collapsed'],
          },
          uiTree: _tree([
            _node('nav.discover', state: {'collapsed': true}),
          ]),
        ),
        throwsA(isA<NodeAssertionException>()),
      );
    });

    test('an empty state map raises: it claims a check and performs none', () {
      expect(
        () => evaluateNodeAssertions(
          {'id': 'nav.discover', 'state': <String, Object?>{}},
          uiTree: _tree([
            _node('nav.discover', state: {'collapsed': true}),
          ]),
        ),
        throwsA(isA<NodeAssertionException>()),
      );
    });
  });

  test('state and focused on the same step both evaluate', () {
    final results = evaluateNodeAssertions(
      {
        'id': 'nav.discover',
        'state': {'collapsed': false},
        'focused': true,
      },
      uiTree: _tree([
        _node('nav.discover', state: {'collapsed': false}, focused: true),
      ]),
    );
    expect(results, hasLength(2));
    expect(results.every((r) => r.ok), isTrue);
  });
}
