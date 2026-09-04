import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_toc.dart';
import 'package:pleya/books/book_toc_layout.dart';
import 'package:pleya/books/book_toc_view.dart';
import 'package:pleya/books/demo_book_tocs.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/books/books_toc_screen.dart';
import 'package:pleya/screens/books/widgets/book_cover.dart';
import 'package:pleya/screens/books/widgets/book_toc_rows.dart';

/// The iPhone 15 Pro frame golden 06 was drawn on, and its insets. The golden
/// puts the header band on 62, which is the top inset plus three, and the
/// action bar's hairline on 755, which is 852 minus its 97.
const Size _viewport = Size(393, 852);
const double _safeTop = 59;
const double _safeBottom = 34;

const _artwork = BookArtwork(
  base: Color(0xFFF4F2EC),
  accent: Color(0xFFE5140F),
  ink: Color(0xFF111111),
  // An orb cover upper-cases its own title and its author line, so a row's
  // `Atomic Habits` and `James Clear` are found on the row and not on the
  // artwork drawn 44 points to their left. Same trick golden 05's test uses.
  shape: BookArtworkShape.orb,
);

final _book = Book(
  id: 'atomic-habits',
  title: 'Atomic Habits',
  author: 'James Clear',
  artwork: _artwork,
  addedAt: DateTime.utc(2026, 8, 1),
);

BookToc get _toc => demoBookToc('atomic-habits')!;

Future<void> _pumpToc(WidgetTester tester, {BookToc? toc}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  const padding = FakeViewPadding(top: _safeTop, bottom: _safeBottom);
  tester.view.viewPadding = padding;
  tester.view.padding = padding;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: BooksTocScreen(book: _book, toc: toc ?? _toc),
    ),
  );
  await tester.pumpAndSettle();
}

List<BookTocRow> _rows({Set<String>? expanded}) {
  final toc = _toc;
  return BookTocView(book: _book, toc: toc, expanded: expanded ?? toc.initiallyExpanded).rows;
}

Finder _row(int index) => find.byType(BookTocRowWidget).at(index);

/// One row's own title, addressed by the string it carries so the lettering a
/// cover draws on itself is never mistaken for it.
Finder _titleFinder(Finder row, String title) => find.descendant(of: row, matching: find.text(title));

Text _titleOf(WidgetTester tester, Finder row, String title) => tester.widget<Text>(_titleFinder(row, title));

/// The row titles of golden 06a's tree, by index.
const String _bookTitle = 'Atomic Habits';
const String _introTitle = 'Introduction: My Story';
const String _firstPartTitle = 'The Fundamentals: Why Tiny Changes Make a Big Difference';
const String _openPartTitle = 'The 3rd Law: Make It Easy';
const String _chapter11 = '11. Walk Slowly, but Never Backward';
const String _chapter12 = '12. The Law of Least Effort';
const String _chapter13 = '13. How to Stop Procrastinating by Using the Two-Minute Rule';

void main() {
  group('06a, the canonical state', () {
    testWidgets('every row lands where golden 06a puts it', (tester) async {
      await _pumpToc(tester);

      final predicted = BookTocLayout.positions(_rows());

      expect(find.byType(BookTocRowWidget), findsNWidgets(predicted.length));
      for (var i = 0; i < predicted.length; i++) {
        expect(tester.getTopLeft(_row(i)).dy, predicted[i], reason: 'row $i');
      }
      // 104 for the book row, 823 for the bottom of the conclusion — under a
      // bar that starts on 755, because the card ends where its content ends.
      expect(tester.getTopLeft(_row(0)).dy, 104);
      expect(tester.getRect(_row(predicted.length - 1)).bottom, 823);
    });

    testWidgets('the four row kinds keep their own heights', (tester) async {
      await _pumpToc(tester);

      expect(tester.getSize(_row(0)).height, 82);
      expect(tester.getSize(_row(1)).height, 47.5);
      expect(tester.getSize(_row(2)).height, 61);
      expect(tester.getSize(_row(6)).height, 44);
    });

    testWidgets('the header is one glyph and a left-aligned title', (tester) async {
      await _pumpToc(tester);

      final title = find.text(t.books.tableOfContents);
      expect(title, findsOneWidget);
      expect(tester.getTopLeft(title).dx, 56);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.getRect(find.byType(BookTocRowWidget).first).top, BookTocLayout.cardTop);
    });

    testWidgets('the card starts on the page margin and holds the book row first', (tester) async {
      await _pumpToc(tester);

      expect(tester.getRect(_row(0)).left, BookTocLayout.pageMargin);
      expect(tester.getRect(_row(0)).right, _viewport.width - BookTocLayout.pageMargin);
      expect(tester.getSize(find.byType(BookCover)), const Size(44, 66));
      expect(find.descendant(of: _row(0), matching: find.text('James Clear')), findsOneWidget);
    });

    testWidgets('a chapter is indented 28 past the layer above it, with the marker in the gutter', (tester) async {
      await _pumpToc(tester);

      final part = tester.getTopLeft(_titleFinder(_row(5), _openPartTitle)).dx;
      final chapter = tester.getTopLeft(_titleFinder(_row(6), _chapter11)).dx;

      expect(chapter - part, BookTocLayout.chapterIndent);
      // The dot on chapter 12, at 28 from the card's own left edge.
      final marker = find.descendant(of: _row(7), matching: find.byType(DecoratedBox));
      expect(tester.getTopLeft(marker.last).dx - tester.getRect(_row(7)).left, BookTocLayout.chapterMarkerLeft);
    });
  });

  group('the three positions, and what they do not say', () {
    testWidgets('behind is dimmed, the locator is white, ahead keeps the resting ink', (tester) async {
      await _pumpToc(tester);

      // Chapter 11 comes earlier in the book, 12 is where the reader stands,
      // 13 comes later.
      expect(_titleOf(tester, _row(6), _chapter11).style!.color!.a, closeTo(0.38, 0.01));
      expect(_titleOf(tester, _row(7), _chapter12).style!.color!.a, closeTo(1, 0.01));
      expect(_titleOf(tester, _row(8), _chapter13).style!.color!.a, closeTo(0.7, 0.01));
      expect(_titleOf(tester, _row(7), _chapter12).style!.fontWeight, FontWeight.w500);
    });

    testWidgets('no row claims anything was read: no check, no suffix, one percentage', (tester) async {
      await _pumpToc(tester);

      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.done), findsNothing);
      // `55% gelezen` stands once, in the footer. It is the publication-wide
      // totalProgression and not a claim about any single entry.
      expect(find.text(t.books.percentReadLong(percent: 55)), findsOneWidget);
      expect(find.textContaining(t.books.tocChapterRange(from: 11, to: 14)), findsOneWidget);
    });

    testWidgets('a title that does not fit breaks with an ellipsis on every level', (tester) async {
      await _pumpToc(tester);

      const titles = {0: _bookTitle, 1: _introTitle, 2: _firstPartTitle, 6: _chapter11};
      for (final entry in titles.entries) {
        final text = _titleOf(tester, _row(entry.key), entry.value);
        expect(text.maxLines, 1, reason: 'row ${entry.key}');
        expect(text.overflow, TextOverflow.ellipsis, reason: 'row ${entry.key}');
      }
    });
  });

  group('06b, the tree collapsed', () {
    testWidgets('closing the open part takes its chapters out and moves the marker up', (tester) async {
      await _pumpToc(tester);

      await tester.tap(_row(5));
      await tester.pumpAndSettle();

      final predicted = BookTocLayout.positions(_rows(expanded: const {}));
      expect(find.byType(BookTocRowWidget), findsNWidgets(predicted.length));
      for (var i = 0; i < predicted.length; i++) {
        expect(tester.getTopLeft(_row(i)).dy, predicted[i], reason: 'row $i');
      }
      // The reading position stays visible with everything closed: that is what
      // `06b` exists to prove.
      expect(tester.getRect(_row(predicted.length - 1)).bottom, 647);
    });

    testWidgets('a closed part still says what is in it, and opens again', (tester) async {
      await _pumpToc(tester);

      await tester.tap(_row(5));
      await tester.pumpAndSettle();
      expect(find.textContaining(t.books.tocChapterRange(from: 11, to: 14)), findsOneWidget);

      await tester.tap(_row(5));
      await tester.pumpAndSettle();
      expect(find.byType(BookTocRowWidget), findsNWidgets(_rows().length));
    });
  });

  group('the action bar', () {
    testWidgets('the hairline sits on 755 and the pill runs 771 to 811', (tester) async {
      await _pumpToc(tester);

      final pill = tester.getRect(
        find.ancestor(of: find.text(t.books.tocGoToPage), matching: find.byType(Container)).first,
      );
      final label = tester.getRect(find.text(t.books.percentReadLong(percent: 55)));

      // Golden 03's bar, to the point: the hairline on 755, 97 pt of bar, the
      // pill 40 tall from 771.
      expect(_viewport.height - _ActionBarProbe.height, 755);
      expect(_ActionBarProbe.height, 97);
      expect(pill.top, 771);
      expect(pill.bottom, 811);
      expect(pill.right, _viewport.width - BookTocLayout.pageMargin);
      expect(label.left, BookTocLayout.pageMargin);
      expect(label.center.dy, closeTo(pill.center.dy, 0.5));
    });

    testWidgets('it does not move with the list', (tester) async {
      await _pumpToc(tester);

      final before = tester.getRect(find.text(t.books.tocGoToPage));
      await tester.drag(find.byType(BooksTocScreen), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.text(t.books.tocGoToPage)), before);
      // What was under the bar is reachable by scrolling.
      expect(tester.getRect(_row(12)).bottom, lessThan(823));
    });

    testWidgets('it stays on 755 with the tree collapsed, when the card no longer fills the page', (tester) async {
      await _pumpToc(tester);

      final before = tester.getRect(find.text(t.books.tocGoToPage));
      await tester.tap(_row(5));
      await tester.pumpAndSettle();

      // Eight collapsed rows end the card on 647, and a bar that follows the
      // content up would hang in the middle of the screen. Golden 06b's empty
      // space under the card is the point: the card says how much is in it and
      // the bar does not move.
      expect(tester.getRect(find.text(t.books.tocGoToPage)), before);
      expect(tester.getRect(_row(8)).bottom, 647);
    });

    testWidgets('a publication without page navigation keeps the label and loses the button', (tester) async {
      final toc = _toc;
      await _pumpToc(
        tester,
        toc: BookToc(nodes: toc.nodes, locator: toc.locator),
      );

      expect(find.text(t.books.tocGoToPage), findsNothing);
      expect(find.text(t.books.percentReadLong(percent: 55)), findsOneWidget);
    });
  });

  group('what this golden stops at', () {
    testWidgets('a chapter, the book row and Ga naar pagina are drawn and open nothing', (tester) async {
      await _pumpToc(tester);

      final before = BookTocLayout.positions(_rows());

      await tester.tap(_row(7));
      await tester.pumpAndSettle();
      await tester.tap(_row(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.books.tocGoToPage));
      await tester.pumpAndSettle();

      // Choosing a chapter jumps into the reader, and the reader is panel 7
      // with its own golden. `Ga naar pagina` opens something golden 06 has
      // not decided either.
      expect(find.byType(BooksTocScreen), findsOneWidget);
      expect(find.byType(BookTocRowWidget), findsNWidgets(before.length));
      expect(tester.getTopLeft(_row(7)).dy, before[7]);
    });
  });
}

/// The bar's height at this frame's bottom inset, so the hairline's position can
/// be asserted without reaching into a private widget.
class _ActionBarProbe {
  static const double height =
      BookTocLayout.hairlineThickness +
      BookTocLayout.actionRowTop +
      BookTocLayout.actionRowHeight +
      BookTocLayout.actionRowGap +
      _safeBottom;
}
