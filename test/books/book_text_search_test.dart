import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book_text_search.dart';
import 'package:pleya/books/book_text_search_layout.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/books/demo_book_text_search.dart';

const _search = DemoBookTextSearch();

List<BookSearchHit> _desert() => _search.search(bookId: 'dune', query: 'desert');

/// The excerpt with its matched runs wrapped in `[]`, so an assertion reads like
/// the golden looks instead of like a list of integers.
String _marked(BookSearchHit hit) {
  final buffer = StringBuffer();
  var cursor = 0;
  for (final range in hit.matchRanges) {
    buffer.write(hit.excerpt.substring(cursor, range.start));
    buffer.write('[${hit.excerpt.substring(range.start, range.end)}]');
    cursor = range.end;
  }
  buffer.write(hit.excerpt.substring(cursor));
  return buffer.toString();
}

void main() {
  group('the fixture answers golden 09a', () {
    test('desert in Dune finds the twelve results the golden draws, in publication order', () {
      final hits = _desert();

      expect(hits.length, 12);
      expect(hits.map((h) => h.chapterLabel).toList(), [
        'Hoofdstuk 3',
        'Hoofdstuk 5',
        'Hoofdstuk 7',
        'Hoofdstuk 9',
        'Hoofdstuk 12',
        'Hoofdstuk 12',
        'Hoofdstuk 15',
        'Hoofdstuk 18',
        'Hoofdstuk 21',
        'Hoofdstuk 24',
        'Hoofdstuk 27',
        'Hoofdstuk 30',
      ]);
      // Publication order, not relevance. A place in a book is not a score, so
      // the page labels climb.
      expect(
        hits.map((h) => int.parse(h.pageLabel!)).toList(),
        ['41', '88', '132', '176', '248', '248', '302', '359', '415', '468', '502', '548'].map(int.parse).toList(),
      );
    });

    test('the first result is the row the golden measures', () {
      final hit = _desert().first;

      expect(hit.chapterLabel, 'Hoofdstuk 3');
      expect(hit.pageLabel, '41');
      expect(_marked(hit), '… the caravan moved after dark, when the [desert] gave back the day’s heat …');
    });

    /// The fifth and the sixth are the two sentences standing on the page golden
    /// 07 draws, which is what makes this list and the approved reader the same
    /// book — and they share a chapter *and* a page label, which is exactly why
    /// a result is addressed by its locator.
    test('two results share a place and are still two results', () {
      final hits = _desert();
      final fifth = hits[4];
      final sixth = hits[5];

      expect(fifth.chapterLabel, sixth.chapterLabel);
      expect(fifth.pageLabel, sixth.pageLabel);
      expect(fifth.locator, isNot(sixth.locator));
      expect(_marked(fifth), '… felt the tremor of the [desert] under his feet, a rhythm he had come to know …');
      expect(_marked(sixth), '… In the silence he heard the voice of the [desert], old and patient …');
    });

    /// Golden 09b's fourth specimen. More than one match per excerpt is the
    /// normal case, and a shape that carried one would have to drop the second.
    test('one excerpt carries two matches', () {
      final hit = _desert()[10];

      expect(hit.matchRanges.length, 2);
      expect(_marked(hit), '… many were lost in the [desert], and the [desert] kept no record of them …');
    });

    test('every locator is unique, so no two rows collide on one automation id', () {
      final locators = _desert().map((h) => h.locator.value).toList();
      expect(locators.toSet().length, locators.length);
    });

    test('a match range points at the query in the excerpt it belongs to', () {
      for (final hit in _desert()) {
        for (final range in hit.matchRanges) {
          expect(hit.excerpt.substring(range.start, range.end).toLowerCase(), 'desert');
        }
      }
    });
  });

  group('what does not produce results', () {
    test('a query below the floor is no query at all', () {
      expect(_search.search(bookId: 'dune', query: ''), isEmpty);
      expect(_search.search(bookId: 'dune', query: 'd'), isEmpty);
      expect(_search.search(bookId: 'dune', query: ' d '), isEmpty);
      // The floor, and one past it. The source says what it is, because how
      // short is too short is a property of the engine.
      expect(_search.minQueryLength, 2);
      expect(_search.search(bookId: 'dune', query: 'de'), isNotEmpty);
    });

    test('a publication the source cannot read answers with nothing rather than throwing', () {
      expect(_search.search(bookId: 'atomic-habits', query: 'desert'), isEmpty);
      expect(_search.search(bookId: 'no-such-book', query: 'desert'), isEmpty);
    });

    test('a query that simply finds nothing is empty too', () {
      expect(_search.search(bookId: 'dune', query: 'ornithopter'), isEmpty);
    });
  });

  group('folding', () {
    test('case and diacritics are ignored, the way the shelf ignores them', () {
      expect(_search.search(bookId: 'dune', query: 'DESERT').length, 12);
      expect(_search.search(bookId: 'dune', query: 'Désert').length, 12);
      expect(foldForSearch('Café'), 'cafe');
    });

    /// The property every match range rests on: fold the text, find the match in
    /// the folded text, draw it in the text the reader sees. A fold that changed
    /// length anywhere would misplace every highlight after that point.
    test('folding never changes the length of a string', () {
      const samples = ['Café', 'STRAßE', 'İstanbul', 'naïve', 'ØRSTED', '𐐷 surrogate pair', ''];
      for (final sample in samples) {
        expect(foldForSearch(sample).length, sample.length, reason: sample);
      }
    });

    test('a query is trimmed, and the text around a match is not', () {
      expect(_search.search(bookId: 'dune', query: '  desert  ').length, 12);
      expect(foldForSearch('  A  '), '  a  ');
    });
  });

  group('the source seam', () {
    test('a source with no e-books cannot search either', () {
      expect(const EmptyBooksSource().textSearch, isNull);
    });

    test('the fixed set can', () {
      expect(const DemoBooksSource().textSearch, isNotNull);
    });
  });

  group('the row table reproduces golden 09a', () {
    /// The twelve rows of the golden, by how many lines their excerpt takes.
    /// Only the second is a single line, which is why it is the one the README
    /// measures at 70.
    const lines = [2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2];

    test('the card starts on 191 and every row lands where the frame puts it', () {
      final tops = BookTextSearchLayout.positions(lines);

      expect(tops.first, 191);
      expect(tops[1], 282);
      expect(tops[2], 352);
      // The eighth row begins on 807 and is cut by the bottom edge.
      expect(tops[7], 807);
      expect(tops.length, 12);
    });

    test('the list is 1071 tall in a window that shows 661', () {
      expect(BookTextSearchLayout.cardHeight(lines), 1071);
      expect(852 - BookTextSearchLayout.cardTop, 661);
    });

    test('a row is 70 with one line of excerpt and 91 with two', () {
      expect(BookTextSearchLayout.heightFor(1), 70);
      expect(BookTextSearchLayout.heightFor(2), 91);
      // Clipped at two, so a longer window does not make a taller row.
      expect(BookTextSearchLayout.heightFor(5), 91);
      // And the number is the sum of its parts rather than a constant that
      // happens to match: padding, location line, gap, two excerpt lines.
      expect(
        BookTextSearchLayout.rowPaddingVertical * 2 +
            BookTextSearchLayout.locationHeight +
            BookTextSearchLayout.excerptGap +
            BookTextSearchLayout.excerptLineHeight * 2,
        91,
      );
    });
  });
}
