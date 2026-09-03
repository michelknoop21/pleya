import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_filter.dart';

const _art = BookArtwork(base: Color(0xFF000000), accent: Color(0xFFFFFFFF), ink: Color(0xFFFFFFFF));
final _epoch = DateTime.utc(2026, 9, 1);

Book _book(
  String id, {
  String author = 'Author',
  List<String> genres = const [],
  String? language,
  String? seriesId,
  double? progress,
  bool isDownloaded = false,
}) => Book(
  id: id,
  title: id,
  author: author,
  artwork: _art,
  addedAt: _epoch,
  genres: genres,
  language: language,
  seriesId: seriesId,
  progress: progress,
  isDownloaded: isDownloaded,
);

void main() {
  group('what counts as a choice', () {
    test('Alles is neutral and counts for nothing', () {
      // Golden 03a shows a tick beside Alles and no 1 beside Status. If the
      // neutral value counted, opening the sheet would immediately claim a
      // filter nobody set.
      expect(const BookFilter().chosenCount, 0);
      expect(const BookFilter().isEmpty, isTrue);
      expect(const BookFilter(status: BookStatusFilter.unread).chosenCount, 1);
    });

    test('the count is per value, not per group', () {
      const filter = BookFilter(status: BookStatusFilter.unread, genres: {'Sciencefiction', 'Fantasy'});

      expect(filter.chosenCount, 3);
      expect(filter.countFor(BookFilterGroup.status), 1);
      expect(filter.countFor(BookFilterGroup.genre), 2);
      expect(filter.countFor(BookFilterGroup.author), 0);
    });
  });

  group('status', () {
    final unopened = _book('unopened');
    final halfway = _book('halfway', progress: 0.48);
    final finished = _book('finished', progress: 1);
    final downloaded = _book('downloaded', isDownloaded: true);
    final books = [unopened, halfway, finished, downloaded];

    test('unread means not finished, so a book at 48% is reachable', () {
      // The alternative reading, unread = never opened, leaves every
      // in-progress book outside both Ongelezen and Gelezen.
      final ids = const BookFilter(status: BookStatusFilter.unread).apply(books).map((b) => b.id);

      expect(ids, containsAll(['unopened', 'halfway', 'downloaded']));
      expect(ids, isNot(contains('finished')));
    });

    test('read is only the finished ones', () {
      expect(const BookFilter(status: BookStatusFilter.read).apply(books).map((b) => b.id), ['finished']);
    });

    test('a book one page from the end counts as finished', () {
      // The same 0.995 bound Verder lezen uses, so a book cannot be both
      // still-being-read and not-yet-read.
      expect(_book('nearly', progress: 0.996).isFinished, isTrue);
      expect(_book('nearly', progress: 0.99).isFinished, isFalse);
    });

    test('downloaded is a different axis wearing the same group', () {
      expect(const BookFilter(status: BookStatusFilter.downloaded).apply(books).map((b) => b.id), ['downloaded']);
    });
  });

  group('combining', () {
    final books = [
      _book('a', genres: ['Sciencefiction'], author: 'Herbert', language: 'Engels'),
      _book('b', genres: ['Fantasy'], author: 'Tolkien', language: 'Nederlands'),
      _book('c', genres: ['Sciencefiction', 'Literatuur'], author: 'Huxley', language: 'Engels'),
    ];

    test('two values in one group widen the answer', () {
      expect(const BookFilter(genres: {'Sciencefiction', 'Fantasy'}).apply(books).map((b) => b.id), ['a', 'b', 'c']);
    });

    test('values in two groups narrow it', () {
      expect(const BookFilter(genres: {'Sciencefiction'}, languages: {'Engels'}).apply(books).map((b) => b.id), [
        'a',
        'c',
      ]);
      expect(const BookFilter(genres: {'Fantasy'}, languages: {'Engels'}).apply(books), isEmpty);
    });

    test('a book matches a genre group if it carries any of the chosen genres', () {
      expect(const BookFilter(genres: {'Literatuur'}).apply(books).map((b) => b.id), ['c']);
    });
  });

  group('toggling', () {
    test('a second tap on the same value removes it', () {
      const start = BookFilter();
      final on = start.toggle(BookFilterGroup.genre, 'Fantasy');
      final off = on.toggle(BookFilterGroup.genre, 'Fantasy');

      expect(on.genres, {'Fantasy'});
      expect(off, BookFilter.none);
    });

    test('status replaces rather than accumulates', () {
      final first = const BookFilter().toggle(BookFilterGroup.status, 'unread');
      final second = first.toggle(BookFilterGroup.status, 'read');

      expect(second.status, BookStatusFilter.read);
      expect(second.chosenCount, 1);
    });
  });

  group('the options a shelf offers', () {
    final books = [
      _book('a', genres: ['Sciencefiction'], author: 'Zwart', language: 'Engels', seriesId: 'dune'),
      _book('b', genres: ['fantasy'], author: 'Aap', language: 'Nederlands'),
    ];
    const series = [
      BookSeries(id: 'dune', title: 'Dune', bookCount: 6, artwork: _art),
      BookSeries(id: 'empty', title: 'Leeg', bookCount: 3, artwork: _art),
    ];

    test('they come from the books in hand, alphabetically and case-blind', () {
      final options = BookFilterOptions.from(books: books, series: series);

      expect(options.genres.map((o) => o.label), ['fantasy', 'Sciencefiction']);
      expect(options.authors.map((o) => o.label), ['Aap', 'Zwart']);
      expect(options.languages.map((o) => o.label), ['Engels', 'Nederlands']);
    });

    test('a series with nothing on this shelf is not offered', () {
      // It would be a filter that can only ever return an empty grid.
      final options = BookFilterOptions.from(books: books, series: series);

      expect(options.series.map((o) => o.label), ['Dune']);
    });

    test('a series filters on its id and shows its title', () {
      final options = BookFilterOptions.from(books: books, series: series);

      expect(options.series.single.value, 'dune');
      expect(options.series.single.label, 'Dune');
    });

    test('status is not derived from the shelf', () {
      expect(BookFilterOptions.from(books: books, series: series).forGroup(BookFilterGroup.status), isEmpty);
    });
  });

  test('the summary names status first, then the groups in rail order', () {
    // What Alle boeken prints on the right of its result line (golden 02c).
    final books = [
      _book('a', genres: ['Sciencefiction'], author: 'Herbert', language: 'Engels'),
    ];
    final options = BookFilterOptions.from(books: books, series: const []);
    const filter = BookFilter(status: BookStatusFilter.unread, languages: {'Engels'}, genres: {'Sciencefiction'});

    expect(filter.summaryLabels(statusLabel: (s) => s.name, options: options), ['unread', 'Sciencefiction', 'Engels']);
  });
}
