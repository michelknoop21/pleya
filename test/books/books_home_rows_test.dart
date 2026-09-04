import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_reader_page.dart';
import 'package:pleya/books/book_toc.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/providers/books_home_provider.dart';

const _art = BookArtwork(base: Color(0xFF101010), accent: Color(0xFFE5140F), ink: Color(0xFFFFFFFF));

Book book(String id, {double? progress, int daysAgo = 0, String? chapter}) => Book(
  id: id,
  title: id,
  author: 'auteur',
  artwork: _art,
  progress: progress,
  chapterLabel: chapter,
  addedAt: DateTime.utc(2026, 9, 1).subtract(Duration(days: daysAgo)),
);

void main() {
  group('Verder lezen', () {
    test('holds only books that were actually started', () {
      final rows = BooksHomeProvider.buildRows(
        books: [book('unopened'), book('started', progress: 0.4), book('at-zero', progress: 0)],
        series: const [],
      );

      expect(rows.continueReading.map((b) => b.id), ['started']);
    });

    test('drops a book that is finished', () {
      // 100% is done. 99.6% is one page from the end and would come back as
      // unfinished work every time the shelf is drawn.
      final rows = BooksHomeProvider.buildRows(
        books: [book('done', progress: 1), book('all-but-done', progress: 0.996), book('nearly', progress: 0.98)],
        series: const [],
      );

      expect(rows.continueReading.map((b) => b.id), ['nearly']);
    });

    test('puts the furthest along first', () {
      final rows = BooksHomeProvider.buildRows(
        books: [book('a', progress: 0.1), book('b', progress: 0.8), book('c', progress: 0.4)],
        series: const [],
      );

      expect(rows.continueReading.map((b) => b.id), ['b', 'c', 'a']);
    });
  });

  group('Recent toegevoegd', () {
    test('is newest first and holds every book, read or not', () {
      final rows = BooksHomeProvider.buildRows(
        books: [book('old', daysAgo: 30), book('new', daysAgo: 1), book('mid', daysAgo: 10, progress: 0.5)],
        series: const [],
      );

      expect(rows.recentlyAdded.map((b) => b.id), ['new', 'mid', 'old']);
    });
  });

  group('Boekenseries', () {
    test('a series of one is not a series', () {
      final rows = BooksHomeProvider.buildRows(
        books: const [],
        series: const [
          BookSeries(id: 'solo', title: 'Solo', bookCount: 1, artwork: _art),
          BookSeries(id: 'real', title: 'Real', bookCount: 4, artwork: _art),
        ],
      );

      expect(rows.series.map((s) => s.id), ['real']);
    });
  });

  group('the percentage under a continue-reading title', () {
    test('rounds down, so it never claims a page the reader has not reached', () {
      expect(book('x', progress: 0.489).progressPercent, 48);
      expect(book('x', progress: 0.999).progressPercent, 99);
    });
  });

  group('the demo source', () {
    test('is the set golden 01b was drawn with, so the screenshot is comparable', () async {
      const source = DemoBooksSource();
      final rows = BooksHomeProvider.buildRows(books: await source.books(), series: await source.series());

      expect(rows.continueReading.map((b) => b.title), ['Dune', 'Project Hail Mary', 'Sapiens']);
      expect(rows.recentlyAdded.first.title, 'Project Hail Mary');
      expect(rows.series.map((s) => '${s.title} ${s.bookCount}'), [
        'Dune 6',
        'De Zeven Zussen 7',
        'Midden-aarde 4',
        'James Clear 2',
      ]);
    });

    test('Dune carries the chapter the golden shows', () async {
      final books = await const DemoBooksSource().books();
      final dune = books.firstWhere((b) => b.id == 'dune');

      expect(dune.progressPercent, 48);
      expect(dune.chapterLabel, 'Hoofdstuk 12');
    });
  });

  group('an empty source', () {
    test('produces no rows at all, which is what a profile without books has', () async {
      const source = EmptyBooksSource();
      final rows = BooksHomeProvider.buildRows(books: await source.books(), series: await source.series());

      expect(rows.isEmpty, isTrue);
    });
  });

  group('the provider', () {
    test('separates "nothing yet" from "nothing at all"', () async {
      final provider = BooksHomeProvider(source: const EmptyBooksSource());
      expect(provider.hasLoaded, isFalse);

      await provider.load();

      expect(provider.hasLoaded, isTrue);
      expect(provider.rows.isEmpty, isTrue);
    });

    test('a failing source leaves empty rows rather than a half-built page', () async {
      final provider = BooksHomeProvider(source: _FailingSource());

      await provider.load();

      expect(provider.hasLoaded, isTrue);
      expect(provider.rows.isEmpty, isTrue);
    });
  });
}

class _FailingSource implements BooksSource {
  @override
  Future<List<Book>> books() async => throw StateError('no source');

  @override
  Future<List<BookSeries>> series() async => const [];

  @override
  Future<BookToc?> tableOfContents(String bookId) async => null;

  @override
  Future<BookReaderPage?> readerPage(String bookId) async => null;
}
