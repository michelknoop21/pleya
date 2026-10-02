import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/search_relevance.dart';

/// Pins today's title-only ranking before anyone changes it. Every case names
/// the `_scoreNormalizedField` rule it lands in, and the score band that rule
/// produces, so a change to one rule fails exactly the rows it moves.
MediaItem _item(
  String id,
  String title, {
  MediaKind kind = MediaKind.movie,
  String? grandparentTitle,
  String? originalTitle,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: kind,
  title: title,
  grandparentTitle: grandparentTitle,
  originalTitle: originalTitle,
);

void main() {
  group('score bands per rule', () {
    final cases = <({String rule, MediaItem item, String query, double min, double max})>[
      (rule: 'exact', item: _item('1', 'Dune'), query: 'dune', min: 1000, max: 1000),
      (
        rule: 'exact after normalising punctuation',
        item: _item('2', 'Spider-Man'),
        query: 'spider man',
        min: 1000,
        max: 1000,
      ),
      (rule: 'equal without leading article', item: _item('3', 'The Matrix'), query: 'matrix', min: 980, max: 980),
      (rule: 'prefix', item: _item('4', 'Dune: Part Two'), query: 'dune', min: 900, max: 950),
      (
        rule: 'prefix without article',
        item: _item('5', 'The Dark Knight Rises'),
        query: 'dark knight',
        min: 880,
        max: 930,
      ),
      (rule: 'contains', item: _item('6', 'Blade Runner 2049'), query: 'runner', min: 800, max: 850),
      (
        rule: 'all tokens, any order',
        item: _item('7', 'Star Wars: A New Hope'),
        query: 'hope star',
        min: 700,
        max: 800,
      ),
      // The code's own bands for these two overlap (a token share floor of
      // 400-500 against a fuzzy score of up to 650), so each case is pinned on
      // its exact score; the order between them is pinned further down.
      (rule: 'some tokens', item: _item('8', 'Star Wars'), query: 'star trek', min: 450, max: 450),
      (rule: 'fuzzy only', item: _item('9', 'Gladiator'), query: 'gladiater', min: 487.5, max: 487.5),
      (
        rule: 'series title counts at 0.9',
        item: _item('10', 'Pilot', kind: MediaKind.episode, grandparentTitle: 'Dune'),
        query: 'dune',
        min: 900,
        max: 900,
      ),
      (
        rule: 'original title counts at 0.96',
        item: _item('11', 'Spirited Away', originalTitle: 'Sen to Chihiro'),
        query: 'sen to chihiro',
        min: 960,
        max: 960,
      ),
      (rule: 'nothing in common', item: _item('12', 'Casablanca'), query: 'xyz', min: 0, max: 50),
    ];

    for (final c in cases) {
      test(c.rule, () {
        final score = mediaSearchRelevanceScore(c.item, c.query);
        expect(score, inInclusiveRange(c.min, c.max), reason: '${c.item.title} for "${c.query}" scored $score');
      });
    }

    test('for one query, a shared token outranks a near miss without one', () {
      final shared = mediaSearchRelevanceScore(_item('8', 'Star Wars'), 'star trek');
      final nearMiss = mediaSearchRelevanceScore(_item('13', 'Stat Trak'), 'star trek');
      expect(shared, greaterThan(nearMiss), reason: 'some tokens $shared, fuzzy only $nearMiss');
    });

    test('an empty query scores zero', () {
      expect(mediaSearchRelevanceScore(_item('1', 'Dune'), '  '), 0);
    });
  });

  group('ordering', () {
    test('exact beats prefix beats contains beats fuzzy', () {
      final items = [
        _item('fuzzy', 'Dun'),
        _item('contains', 'Beyond Dune Sea'),
        _item('prefix', 'Dune: Part Two'),
        _item('exact', 'Dune'),
      ];
      expect(rankMediaSearchResults(items, 'dune').map((i) => i.id), ['exact', 'prefix', 'contains', 'fuzzy']);
    });

    // Ties keep the order the servers returned. For a single Plex server that
    // order is already Plex's own relevance, which is why no separate score
    // tie-breaker was added (MediaItem carries no score field).
    test('equal scores keep the incoming order', () {
      final items = [_item('a', 'Dune'), _item('b', 'Dune'), _item('c', 'Dune')];
      expect(rankMediaSearchResults(items, 'dune').map((i) => i.id), ['a', 'b', 'c']);
    });

    test('the limit is applied after ranking', () {
      final items = [_item('contains', 'Beyond Dune Sea'), _item('exact', 'Dune')];
      expect(rankMediaSearchResults(items, 'dune', limit: 1).map((i) => i.id), ['exact']);
    });

    test('an empty query keeps the incoming order and still honours the limit', () {
      final items = [_item('b', 'B'), _item('a', 'A'), _item('c', 'C')];
      expect(rankMediaSearchResults(items, '').map((i) => i.id), ['b', 'a', 'c']);
      expect(rankMediaSearchResults(items, '', limit: 2).map((i) => i.id), ['b', 'a']);
    });
  });
}
