import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_toc.dart';
import 'package:pleya/books/book_toc_layout.dart';
import 'package:pleya/books/book_toc_view.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/books/demo_book_tocs.dart';
import 'package:pleya/i18n/strings.g.dart';

const _artwork = BookArtwork(base: Color(0xFFF4F2EC), accent: Color(0xFFE5140F), ink: Color(0xFF111111));

final _book = Book(
  id: 'atomic-habits',
  title: 'Atomic Habits',
  author: 'James Clear',
  artwork: _artwork,
  addedAt: DateTime.utc(2026, 8, 1),
);

BookToc get _toc => demoBookToc('atomic-habits')!;

BookTocView _view({Set<String>? expanded}) =>
    BookTocView(book: _book, toc: _toc, expanded: expanded ?? _toc.initiallyExpanded);

void main() {
  group('position against the locator', () {
    test('reading order is the loose entries and the chapters, parts excluded', () {
      final order = _toc.readingOrder;

      // A part is a grouping; a reader is never in one except through one of
      // its chapters, so it has no place of its own in reading order.
      expect(order.first, 'introduction');
      expect(order.last, 'conclusion');
      expect(order.where((id) => id.startsWith('ch-')).length, 20);
      expect(order.length, 22);
    });

    test('what comes earlier is behind, where the reader is is the locator, the rest is ahead', () {
      expect(_toc.positionOf('introduction'), BookTocPosition.behind);
      expect(_toc.positionOf('ch-11'), BookTocPosition.behind);
      expect(_toc.positionOf('ch-12'), BookTocPosition.atLocator);
      expect(_toc.positionOf('ch-13'), BookTocPosition.ahead);
      expect(_toc.positionOf('conclusion'), BookTocPosition.ahead);
    });

    test('a part is behind only when every chapter in it ends before the locator', () {
      final parts = {for (final node in _toc.nodes) node.id: node};

      expect(_toc.positionOfNode(parts['fundamentals']!), BookTocPosition.behind);
      expect(_toc.positionOfNode(parts['law-2']!), BookTocPosition.behind);
      // Chapters 11 to 14: chapter 11 is behind the locator and 13 and 14 are
      // ahead of it, so the part is neither. It holds the locator.
      expect(_toc.positionOfNode(parts['law-3']!), BookTocPosition.atLocator);
      expect(_toc.positionOfNode(parts['law-4']!), BookTocPosition.ahead);
    });

    test('without a locator nothing is behind', () {
      final toc = BookToc(nodes: _toc.nodes);

      expect(toc.positionOf('introduction'), BookTocPosition.ahead);
      expect(toc.positionOf('ch-1'), BookTocPosition.ahead);
      expect(toc.initiallyExpanded, isEmpty);
    });

    test('55% is totalProgression rounded down, and it is the only reading figure', () {
      expect(_toc.locator!.percent, 55);
      expect(const BookTocLocator(entryId: 'ch-1', totalProgression: 0.999).percent, 99);
    });
  });

  group('the tree the screen draws', () {
    test('it arrives with the part holding the locator open, and no other', () {
      expect(_toc.initiallyExpanded, {'law-3'});
    });

    test('06a: the book, the loose entries and six parts, with the open part\'s four chapters', () {
      final rows = _view().rows;

      expect(rows.map((r) => r.kind).toList(), [
        BookTocRowKind.book,
        BookTocRowKind.entry,
        BookTocRowKind.part,
        BookTocRowKind.part,
        BookTocRowKind.part,
        BookTocRowKind.part,
        BookTocRowKind.chapter,
        BookTocRowKind.chapter,
        BookTocRowKind.chapter,
        BookTocRowKind.chapter,
        BookTocRowKind.part,
        BookTocRowKind.part,
        BookTocRowKind.entry,
      ]);
      expect(rows[6].title, '11. Walk Slowly, but Never Backward');
      expect(rows[7].title, '12. The Law of Least Effort');
    });

    test('a part carries its range so a closed one still says what is in it', () {
      final part = _view().rows.firstWhere((r) => r.id == 'law-3');

      expect(part.subtitle, t.books.tocChapterRange(from: 11, to: 14));
    });

    test('the marker sits on the chapter when the part is open', () {
      final rows = _view().rows;

      expect(rows.where((r) => r.showsMarker).map((r) => r.id).toList(), ['ch-12']);
      expect(rows.firstWhere((r) => r.id == 'law-3').showsMarker, isFalse);
    });

    test('06b: collapsing everything moves the marker up to the part', () {
      final rows = _view(expanded: const {}).rows;

      expect(rows.where((r) => r.kind == BookTocRowKind.chapter), isEmpty);
      expect(rows.where((r) => r.showsMarker).map((r) => r.id).toList(), ['law-3']);
      expect(rows.length, 9);
    });

    test('hairlines mark the boundaries of the top layer and nothing else', () {
      final rows = _view().rows;

      expect(rows.first.startsSection, isFalse);
      expect(rows.where((r) => r.kind == BookTocRowKind.chapter).every((r) => !r.startsSection), isTrue);
      expect(
        rows
            .where((r) => r.kind == BookTocRowKind.part || r.kind == BookTocRowKind.entry)
            .every((r) => r.startsSection),
        isTrue,
      );
    });

    test('the footer label is the publication-wide percentage and the jump control is declared', () {
      final view = _view();

      expect(view.progressLabel, t.books.percentReadLong(percent: 55));
      expect(view.showsGoToPage, isTrue);
    });

    test('a publication without page navigation loses the button, not the label', () {
      final view = BookTocView(
        book: _book,
        toc: BookToc(nodes: _toc.nodes, locator: _toc.locator),
      );

      expect(view.showsGoToPage, isFalse);
      expect(view.progressLabel, t.books.percentReadLong(percent: 55));
    });
  });

  group('golden 06a\'s geometry', () {
    test('every row lands where the frame puts it', () {
      final tops = BookTocLayout.positions(_view().rows);

      expect(tops, [104, 186, 233.5, 294.5, 355.5, 416.5, 477.5, 521.5, 565.5, 609.5, 653.5, 714.5, 775.5]);
    });

    test('the card ends where its content ends, under a bar that starts on 755', () {
      final rows = _view().rows;

      // 823, and the fifth part is cut halfway through its second line by the
      // bar. Nothing is shortened to make the list fit above it.
      expect(BookTocLayout.cardTop + BookTocLayout.cardHeight(rows), 823);
    });

    test('06b: eight collapsed rows are eight rows and the card gets shorter', () {
      final tops = BookTocLayout.positions(_view(expanded: const {}).rows);

      expect(tops, [104, 186, 233.5, 294.5, 355.5, 416.5, 477.5, 538.5, 599.5]);
      expect(BookTocLayout.cardTop + BookTocLayout.cardHeight(_view(expanded: const {}).rows), 647);
    });

    test('the four row heights are the ones the golden measured', () {
      expect(BookTocLayout.heightOf(BookTocRowKind.book), 82);
      expect(BookTocLayout.heightOf(BookTocRowKind.entry), 47.5);
      expect(BookTocLayout.heightOf(BookTocRowKind.part), 61);
      expect(BookTocLayout.heightOf(BookTocRowKind.chapter), 44);
      expect(BookTocLayout.chapterIndent, 28);
    });
  });

  group('the fixture', () {
    test('one publication declares navigation and the rest honestly declare none', () async {
      const source = DemoBooksSource();

      expect(await source.tableOfContents('atomic-habits'), isNotNull);
      expect(await source.tableOfContents('dune'), isNull);
      expect(await const EmptyBooksSource().tableOfContents('atomic-habits'), isNull);
    });

    test('Atomic Habits keeps its place on the shelf: the locator is not a shelf progress', () async {
      final books = await const DemoBooksSource().books();
      final atomic = books.firstWhere((b) => b.id == 'atomic-habits');

      // Giving it 0.55 here would put it at the head of Verder lezen, ahead of
      // Dune at 0.48 — the row approved golden 01b fixes the first three cards
      // of. The reading position stays with the reader.
      expect(atomic.progress, isNull);
      expect(atomic.isInProgress, isFalse);
    });
  });
}
