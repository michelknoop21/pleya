import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_detail_layout.dart';
import 'package:pleya/books/book_detail_view.dart';
import 'package:pleya/i18n/strings.g.dart';

const _artwork = BookArtwork(
  base: Color(0xFF3A1A0B),
  accent: Color(0xFFE08A3C),
  ink: Color(0xFFF7E2C6),
  shape: BookArtworkShape.orb,
);

Book _book({
  String id = 'dune',
  String? seriesId = 'dune',
  int? seriesIndex = 1,
  double? progress = 0.48,
  String? chapter = 'Hoofdstuk 12',
  int? year = 1965,
  int? pages = 616,
  List<String> genres = const ['Sciencefiction'],
  String? description = 'Ver weg in de toekomst.',
}) => Book(
  id: id,
  title: 'Dune',
  author: 'Frank Herbert',
  artwork: _artwork,
  addedAt: DateTime.utc(2026, 8, 1),
  seriesId: seriesId,
  seriesIndex: seriesIndex,
  progress: progress,
  chapterLabel: chapter,
  genres: genres,
  year: year,
  pages: pages,
  description: description,
);

const _series = [BookSeries(id: 'dune', title: 'Dune', bookCount: 6, artwork: _artwork)];

void main() {
  group('the column golden 05 hangs off the cover', () {
    test('with everything present it reproduces the numbers read off 05a', () {
      final tops = BookDetailLayout.positions(present: BookDetailBlock.values.toSet());

      expect(BookDetailLayout.coverBottom, 329);
      expect(tops[BookDetailBlock.title], 349);
      expect(tops[BookDetailBlock.author], 389);
      expect(tops[BookDetailBlock.series], 413);
      expect(tops[BookDetailBlock.progress], 441);
      expect(tops[BookDetailBlock.primary], 503);
      expect(tops[BookDetailBlock.secondary], 561);
      expect(tops[BookDetailBlock.stats], 629);
      expect(tops[BookDetailBlock.description], 689);
    });

    test('a missing block takes its own whitespace with it', () {
      // The rule 05b is evidence for: nothing stretches to fill the gap, so
      // everything below moves up by exactly the block plus the space above it.
      final full = BookDetailLayout.positions(present: BookDetailBlock.values.toSet());
      final withoutSeries = BookDetailLayout.positions(
        present: BookDetailBlock.values.toSet()..remove(BookDetailBlock.series),
      );

      const seriesCost = 2 + 18.0;
      for (final block in [
        BookDetailBlock.progress,
        BookDetailBlock.primary,
        BookDetailBlock.secondary,
        BookDetailBlock.stats,
        BookDetailBlock.description,
      ]) {
        expect(withoutSeries[block], full[block]! - seriesCost, reason: '$block did not move up by the series block');
      }
      expect(withoutSeries[BookDetailBlock.series], isNull);
      // Above the gap nothing moves.
      expect(withoutSeries[BookDetailBlock.title], full[BookDetailBlock.title]);
      expect(withoutSeries[BookDetailBlock.author], full[BookDetailBlock.author]);
    });

    test('the unstarted state of 05b: neither series nor progress, and 68 pt up', () {
      final tops = BookDetailLayout.positions(
        present: BookDetailBlock.values.toSet()
          ..remove(BookDetailBlock.series)
          ..remove(BookDetailBlock.progress),
      );

      expect(tops[BookDetailBlock.title], 349);
      expect(tops[BookDetailBlock.author], 389);
      expect(tops[BookDetailBlock.primary], 435);
      expect(tops[BookDetailBlock.secondary], 493);
      expect(tops[BookDetailBlock.stats], 561);
      expect(tops[BookDetailBlock.description], 621);
    });

    test('the 24 pt between the identity block and the first action holds in both states', () {
      // What 05c shows side by side: the gap above the primary action is the
      // block's own and does not change with what stands above it.
      final withProgress = BookDetailLayout.positions(present: BookDetailBlock.values.toSet());
      final without = BookDetailLayout.positions(
        present: BookDetailBlock.values.toSet()
          ..remove(BookDetailBlock.series)
          ..remove(BookDetailBlock.progress),
      );

      expect(withProgress[BookDetailBlock.primary]! - (withProgress[BookDetailBlock.progress]! + 38), 24);
      expect(without[BookDetailBlock.primary]! - (without[BookDetailBlock.author]! + 22), 24);
    });
  });

  group('what a book brings to the page', () {
    test('the series line is the title and the position in it', () {
      expect(BookDetailView.of(_book(), series: _series).seriesLabel, 'Dune #1');
    });

    test('without a position it is the series title alone', () {
      expect(BookDetailView.of(_book(seriesIndex: null), series: _series).seriesLabel, 'Dune');
    });

    test('a series this profile cannot name gets no line rather than an invented one', () {
      expect(BookDetailView.of(_book(), series: const []).seriesLabel, isNull);
      expect(BookDetailView.of(_book()).blocks, isNot(contains(BookDetailBlock.series)));
    });

    test('a book in no series has no series block', () {
      expect(BookDetailView.of(_book(seriesId: null), series: _series).seriesLabel, isNull);
    });

    test('progress is both lines or neither', () {
      final view = BookDetailView.of(_book(), series: _series);
      expect(view.progress?.percent, t.books.percentReadLong(percent: 48));
      expect(view.progress?.chapter, 'Hoofdstuk 12');

      expect(BookDetailView.of(_book(progress: null)).progress, isNull);
    });

    test('a finished book carries no progress block', () {
      // The same 0.995 bound Verder lezen uses: there is nothing to continue.
      expect(BookDetailView.of(_book(progress: 1)).progress, isNull);
    });

    test('the stats are year, genre and pages, in that order, with genre the wide one', () {
      final stats = BookDetailView.of(_book()).stats;

      expect(stats.map((s) => s.key), ['year', 'genre', 'pages']);
      expect(stats.map((s) => s.value), ['1965', 'Sciencefiction', '616']);
      expect(stats.map((s) => s.label), [t.books.statYear, t.books.statGenre, t.books.statPages]);
      expect(stats.where((s) => s.isWide).single.key, 'genre');
      expect(stats.firstWhere((s) => s.isWide).flex / stats.first.flex, closeTo(1.45, 0.001));
    });

    test('an edition with no page count falls back to two columns', () {
      final stats = BookDetailView.of(_book(pages: null)).stats;

      expect(stats.map((s) => s.key), ['year', 'genre']);
      expect(BookDetailView.of(_book(pages: null)).blocks, contains(BookDetailBlock.stats));
    });

    test("it never reads 0 Pages", () {
      // Pages is bibliographical metadata, never derived from the reader's own
      // pagination, so a zero is a source with nothing to say.
      expect(BookDetailView.of(_book(pages: 0)).stats.map((s) => s.key), ['year', 'genre']);
    });

    test('the first genre, not all of them', () {
      final stats = BookDetailView.of(_book(genres: const ['Sciencefiction', 'Literatuur'])).stats;

      expect(stats.firstWhere((s) => s.key == 'genre').value, 'Sciencefiction');
    });

    test('the primary action names its own state', () {
      expect(BookDetailView.of(_book()).primaryActionLabel, t.books.readContinue);
      expect(BookDetailView.of(_book(progress: null)).primaryActionLabel, t.books.read);
    });

    test('a book with no blurb loses the description block and its gap', () {
      expect(BookDetailView.of(_book(description: null)).blocks, isNot(contains(BookDetailBlock.description)));
      expect(BookDetailView.of(_book(description: '   ')).blocks, isNot(contains(BookDetailBlock.description)));
    });
  });
}
