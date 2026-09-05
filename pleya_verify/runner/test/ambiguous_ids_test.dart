import 'package:pleya_verify_runner/src/engine/ambiguous_ids.dart';
import 'package:pleya_verify_runner/src/engine/geometry_assertions.dart';
import 'package:pleya_verify_runner/src/engine/node_assertions.dart';
import 'package:test/test.dart';

/// Two nodes under one id, exactly as `AutomationRegistry.snapshot` emits it:
/// the second gets a positional `#2` and the base id is listed under
/// `duplicates`. The bounds differ so a resolved assertion can be told apart
/// from a refused one.
Map<String, Object?> _collidingTree() => {
  'declared': [
    {
      'id': 'books.search.result[dune]',
      'role': 'list.item',
      'focused': false,
      'state': {'kind': 'book'},
      'bounds': {'x': 16.0, 'y': 241.0, 'width': 361.0, 'height': 82.0},
    },
    {
      'id': 'books.search.result[dune]#2',
      'role': 'list.item',
      'focused': true,
      'state': {'kind': 'series'},
      'bounds': {'x': 16.0, 'y': 679.0, 'width': 361.0, 'height': 82.0},
    },
  ],
  'discovered': const [],
  'duplicates': const ['books.search.result[dune]'],
};

const _viewport = {'available': true, 'width': 393.0, 'height': 852.0};

void main() {
  group('the message', () {
    test('is null for an id that registered once', () {
      expect(ambiguousIdMessage('nav.books', _collidingTree()), isNull);
    });

    test('counts the registrations, not the duplicate entries', () {
      // One extra registration is one entry in `duplicates`, so two nodes.
      expect(ambiguousIdMessage('books.search.result[dune]', _collidingTree()), contains('registered 2 times'));
      expect(
        ambiguousIdMessage('a', {
          'duplicates': const ['a', 'a'],
        }),
        contains('registered 3 times'),
      );
    });

    test('survives a tree with no duplicates key at all', () {
      expect(ambiguousIdMessage('a', const {}), isNull);
    });
  });

  group('a geometry assertion on a duplicated id', () {
    test('is refused instead of resolving the first registration', () {
      expect(
        () => evaluateGeometryAssertions(
          {'id': 'books.search.result[dune]', 'insideViewport': true},
          uiTree: _collidingTree(),
          viewport: _viewport,
        ),
        throwsA(
          isA<GeometryAssertionException>().having(
            (e) => e.toString(),
            'message',
            contains('registered 2 times'),
          ),
        ),
      );
    });

    test('still measures the unambiguous ids around it', () {
      final results = evaluateGeometryAssertions(
        {'id': 'books.search.result[dune]#2', 'insideViewport': true},
        uiTree: _collidingTree(),
        viewport: _viewport,
      );
      expect(results.single.verdict.ok, isTrue);
    });
  });

  group('a node assertion on a duplicated id', () {
    test('is refused rather than reading the first node state', () {
      expect(
        () => evaluateNodeAssertions({
          'id': 'books.search.result[dune]',
          'state': {'kind': 'book'},
        }, uiTree: _collidingTree()),
        throwsA(
          isA<NodeAssertionException>().having((e) => e.toString(), 'message', contains('registered 2 times')),
        ),
      );
    });

    test('refuses a focused assertion on it too', () {
      expect(
        () => evaluateNodeAssertions({
          'id': 'books.search.result[dune]',
          'focused': false,
        }, uiTree: _collidingTree()),
        throwsA(isA<NodeAssertionException>()),
      );
    });
  });
}
