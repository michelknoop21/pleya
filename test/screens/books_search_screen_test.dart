import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/books_home_provider.dart';
import 'package:pleya/screens/books/books_search_screen.dart';
import 'package:pleya/screens/books/widgets/book_search_row.dart';
import 'package:provider/provider.dart';

/// The frame golden 04 was drawn on.
const Size _viewport = Size(393, 852);

Future<void> _pump(WidgetTester tester, {String query = 'dune'}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final provider = BooksHomeProvider(source: const DemoBooksSource());
  await provider.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<BooksHomeProvider>.value(
      value: provider,
      child: MaterialApp(theme: ThemeData.dark(), home: const BooksSearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
  if (query.isNotEmpty) {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('the canonical state', () {
    testWidgets('three sections, in the order golden 04 puts them', (tester) async {
      await _pump(tester);

      final books = tester.getCenter(find.text(t.navigation.books.toUpperCase())).dy;
      final authors = tester.getCenter(find.text(t.books.searchAuthors.toUpperCase())).dy;
      final series = tester.getCenter(find.text(t.books.bookSeries.toUpperCase())).dy;

      expect(books, lessThan(authors));
      expect(authors, lessThan(series));
    });

    testWidgets('the three results the golden draws, and nothing else', (tester) async {
      await _pump(tester);

      expect(find.text('Dune'), findsWidgets);
      expect(find.text('Dune Messiah'), findsOneWidget);
      expect(find.text('Children of Dune'), findsOneWidget);
      expect(find.text('Frank Herbert'), findsWidgets);
      expect(find.text('Sapiens'), findsNothing);
    });

    testWidgets('a book row carries the author and no third line', (tester) async {
      // Golden 02 kept year and genre off the shelf; a search result is that
      // same shelf in another shape. The demo set runs from 1949 onward, so a
      // stray year would show up here.
      await _pump(tester);

      for (final year in ['1949', '1965', '1969', '1976']) {
        expect(find.textContaining(year), findsNothing, reason: '$year leaked into a result row');
      }
    });

    testWidgets('a series row says how many books, an author row says nothing extra', (tester) async {
      await _pump(tester);

      expect(find.text(t.books.bookCountLabel(count: 6)), findsOneWidget);
      // The author's own row is the name alone. `Frank Herbert` appears on the
      // three book rows as their subtitle and once as an author row; none of
      // those four carries a count.
      expect(find.text(t.books.bookCountLabel(count: 3)), findsNothing);
    });
  });

  group('geometry, measured against golden 04', () {
    testWidgets('the leading shapes are the three sizes the golden fixes', (tester) async {
      await _pump(tester);

      final bookThumb = tester.getSize(find.byType(BookResultRow).first);
      final author = tester.getSize(find.byType(AuthorResultRow).first);
      final series = tester.getSize(find.byType(SeriesResultRow).first);

      expect(bookThumb.height, BookSearchRowMetrics.rowHeight);
      expect(author.height, BookSearchRowMetrics.authorRowHeight);
      expect(series.height, BookSearchRowMetrics.rowHeight);
    });

    testWidgets('titles line up across all three sections', (tester) async {
      // A series carries two more page blocks behind its cover, and an author
      // a circle instead of one. Neither may push its title out of the column
      // the book rows established.
      await _pump(tester);

      final bookTitle = tester.getTopLeft(find.text('Dune Messiah')).dx;
      final authorTitle = tester.getTopLeft(find.text('Frank Herbert').last).dx;
      final seriesTitle = tester.getTopLeft(find.text(t.books.bookCountLabel(count: 6))).dx;

      expect(authorTitle, closeTo(bookTitle, 0.5));
      expect(seriesTitle, closeTo(bookTitle, 0.5));
      // 91 on the screen: the card sits at the 16 pt page margin and the row
      // repeats it inside, then the 44 pt shape and the 15 pt gap. Measured at
      // exactly 91 on `05-zoeken.png`, where the separator starts on the same
      // line.
      expect(bookTitle, closeTo(BookSearchRowMetrics.pageMargin + BookSearchRowMetrics.separatorInset, 0.5));
    });
  });

  group('the chip row', () {
    testWidgets('it carries the four categories, Alles chosen', (tester) async {
      await _pump(tester);

      expect(find.text(t.books.statusAll), findsOneWidget);
      expect(find.text(t.navigation.books), findsOneWidget);
      expect(find.text(t.books.searchAuthors), findsOneWidget);
      expect(find.text(t.books.bookSeries), findsOneWidget);
    });

    testWidgets('choosing Boeken leaves one section standing', (tester) async {
      await _pump(tester);

      await tester.tap(find.text(t.navigation.books));
      await tester.pumpAndSettle();

      expect(find.text(t.navigation.books.toUpperCase()), findsOneWidget);
      expect(find.text(t.books.searchAuthors.toUpperCase()), findsNothing);
      expect(find.text(t.books.bookSeries.toUpperCase()), findsNothing);
      expect(find.text('Children of Dune'), findsOneWidget);
    });

    testWidgets('a chip that stops existing does not leave an empty screen behind', (tester) async {
      await _pump(tester);
      await tester.tap(find.text(t.books.bookSeries));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesResultRow), findsOneWidget);

      // `sapiens` has no series. The chosen chip is gone; the screen falls
      // back to Alles rather than showing nothing behind a chip that is not
      // there any more.
      await tester.enterText(find.byType(TextField), 'sapiens');
      await tester.pumpAndSettle();

      expect(find.text(t.books.bookSeries), findsNothing);
      expect(find.text('Sapiens'), findsWidgets);
    });

    testWidgets('an empty query draws no chips and no sections', (tester) async {
      await _pump(tester, query: '');

      expect(find.text(t.books.statusAll), findsNothing);
      expect(find.byType(BookResultRow), findsNothing);
    });
  });
}
