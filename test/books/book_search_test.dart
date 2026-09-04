import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_search.dart';
import 'package:pleya/books/books_source.dart';

const _art = BookArtwork(base: Color(0xFF000000), accent: Color(0xFFFFFFFF), ink: Color(0xFFFFFFFF));
final _epoch = DateTime.utc(2026, 9, 1);

Book _book(String title, {String author = 'Author', String? seriesId}) =>
    Book(id: title, title: title, author: author, artwork: _art, addedAt: _epoch, seriesId: seriesId);

const _ranking = LocalBookSearchRanking();

void main() {
  group('the canonical query from golden 04', () {
    late BookSearchResults results;

    setUp(() async {
      const source = DemoBooksSource();
      results = _ranking.search(query: 'dune', books: await source.books(), series: await source.series());
    });

    test('three books, one author and one series, which is what the golden draws', () {
      // Closest first, and golden 04 draws them in exactly this order.
      expect(results.books.map((b) => b.title), ['Dune', 'Dune Messiah', 'Children of Dune']);
      expect(results.authors, ['Frank Herbert']);
      expect(results.series.map((s) => s.title), ['Dune']);
    });

    test('all four chips are there, and Alles is one of them', () {
      expect(results.availableCategories, [
        BookSearchCategory.all,
        BookSearchCategory.books,
        BookSearchCategory.authors,
        BookSearchCategory.series,
      ]);
    });

    test('choosing a chip narrows to one kind and leaves the rest alone', () {
      final books = results.within(BookSearchCategory.books);

      expect(books.books, results.books);
      expect(books.authors, isEmpty);
      expect(books.series, isEmpty);
      // The unfiltered results are untouched, so switching back costs nothing
      // and the chip row does not shrink under the reader's finger.
      expect(results.authors, isNotEmpty);
    });
  });

  group('what counts as a match', () {
    test('an author is a result because they wrote something that matched', () {
      // Frank Herbert's name does not contain `dune`. The strict reading gives
      // an empty author section on the one query where an author is obviously
      // the answer.
      final results = _ranking.search(
        query: 'dune',
        books: [_book('Dune', author: 'Frank Herbert')],
        series: const [],
      );

      expect(results.authors, ['Frank Herbert']);
    });

    test('an author whose own name matches is found without any matching title', () {
      final results = _ranking.search(
        query: 'tolkien',
        books: [_book('De Hobbit', author: 'J.R.R. Tolkien')],
        series: const [],
      );

      expect(results.authors, ['J.R.R. Tolkien']);
      // And their work comes along, because that is what the reader wanted.
      expect(results.books.map((b) => b.title), ['De Hobbit']);
    });

    test('the title that is the query comes first, then the ones that start with it', () {
      // Alphabetical alone puts `Dune` under `Children of Dune` when you
      // searched for `dune`, which is correct and useless.
      final results = _ranking.search(
        query: 'dune',
        books: [_book('Children of Dune'), _book('Dune Messiah'), _book('Dune'), _book('Dune Anders')],
        series: const [],
      );

      expect(results.books.map((b) => b.title), ['Dune', 'Dune Anders', 'Dune Messiah', 'Children of Dune']);
    });

    test('title matches come before books found only through their author', () {
      final results = _ranking.search(
        query: 'herbert',
        books: [
          _book('Zonder titelmatch', author: 'Frank Herbert'),
          _book('Herbert', author: 'Iemand Anders'),
        ],
        series: const [],
      );

      expect(results.books.map((b) => b.title), ['Herbert', 'Zonder titelmatch']);
    });

    test('a series matches on its own title as well as through its books', () {
      final results = _ranking.search(
        query: 'midden',
        books: [_book('De Hobbit', seriesId: 'midden-aarde')],
        series: const [BookSeries(id: 'midden-aarde', title: 'Midden-aarde', bookCount: 4, artwork: _art)],
      );

      expect(results.series.map((s) => s.title), ['Midden-aarde']);
    });

    test('case and diacritics do not decide anything', () {
      final results = _ranking.search(
        query: 'ALCHEMIST',
        books: [_book('De Alchemíst', author: 'Paulo Coelho')],
        series: const [],
      );

      expect(results.books, hasLength(1));
    });

    test('one letter is not a query', () {
      // It matches most of a shelf, which is a slower way of showing
      // everything than not searching at all.
      final books = [_book('Dune'), _book('Sapiens')];

      expect(_ranking.search(query: 'd', books: books, series: const []).isEmpty, isTrue);
      expect(_ranking.search(query: '  ', books: books, series: const []).isEmpty, isTrue);
      expect(_ranking.search(query: 'du', books: books, series: const []).books, hasLength(1));
    });

    test('nothing found means no chips at all', () {
      final results = _ranking.search(query: 'zzzz', books: [_book('Dune')], series: const []);

      expect(results.isEmpty, isTrue);
      expect(results.availableCategories, isEmpty);
    });

    test('a kind with no results gets no chip', () {
      // `search_screen.dart` already hides a chip that leads nowhere; a books
      // chip row follows the same rule. A book outside any series gives no
      // Boekenseries chip.
      final results = _ranking.search(
        query: 'sapiens',
        books: [_book('Sapiens', author: 'Yuval Noah Harari')],
        series: const [],
      );

      expect(results.availableCategories, [
        BookSearchCategory.all,
        BookSearchCategory.books,
        BookSearchCategory.authors,
      ]);
    });

    test('a matching book always brings its author along', () {
      // Worth naming rather than discovering later: every book has an author,
      // so the Auteurs section is never empty once a book matched. That is
      // wanted — it is the way into the rest of that author's work — but it
      // does mean the chip is all but permanent, and only Boekenseries really
      // comes and goes.
      final results = _ranking.search(
        query: 'sapiens',
        books: [_book('Sapiens', author: 'Harari')],
        series: const [],
      );

      expect(results.authors, ['Harari']);
    });
  });
}
