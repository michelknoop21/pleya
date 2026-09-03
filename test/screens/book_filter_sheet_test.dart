import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/books_home_provider.dart';
import 'package:pleya/screens/books/all_books_screen.dart';
import 'package:pleya/screens/books/widgets/book_filter_sheet.dart';
import 'package:provider/provider.dart';

/// The frame golden 03 was drawn on.
const Size _viewport = Size(393, 852);

/// Where the golden puts the sheet's top edge on that frame.
const double _sheetTop = 252;

Future<void> _pumpAllBooks(WidgetTester tester) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final provider = BooksHomeProvider(source: const DemoBooksSource());
  await provider.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<BooksHomeProvider>.value(
      value: provider,
      child: MaterialApp(theme: ThemeData.dark(), home: const AllBooksScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The pill on Alle boeken, not the sheet's own heading, which carries the
/// same word.
Finder get _filtersPill => find.descendant(of: find.byType(AllBooksScreen), matching: find.text(t.books.filters)).first;

Future<void> _openSheet(WidgetTester tester) async {
  await _pumpAllBooks(tester);
  await tester.tap(_filtersPill);
  await tester.pumpAndSettle();
}

void main() {
  group('geometry, measured against golden 03', () {
    testWidgets('the sheet opens at the height the golden gives it', (tester) async {
      await _openSheet(tester);

      final box = tester.getRect(find.byType(BookFilterSheet));

      expect(box.height, closeTo(_viewport.height - _sheetTop, 0.5));
      expect(box.top, closeTo(_sheetTop, 0.5));
      expect(box.width, _viewport.width);
    });

    testWidgets('the first group and the first choice sit on the golden lines', (tester) async {
      // Measured on 04-filters-sheet.png: group mid 334.3, option mid 337.2.
      // Two panes that start on the same line but run at different pitches.
      await _openSheet(tester);

      expect(tester.getCenter(find.text(t.books.filterStatus)).dy, closeTo(334.75, 2));
      expect(tester.getCenter(find.text(t.books.statusAll)).dy, closeTo(336.75, 2));
    });

    testWidgets('the rail is 131 wide and the choices start at its far side', (tester) async {
      await _openSheet(tester);

      // Rail text at the sheet's 20 pt margin, option text at 131 + 1 divider
      // + 16 margin + 16 padding.
      expect(tester.getTopLeft(find.text(t.books.filterStatus)).dx, closeTo(20, 1));
      expect(tester.getTopLeft(find.text(t.books.statusAll)).dx, closeTo(164, 2));
    });

    testWidgets('group rows run at 43.5 and choices at 47.5', (tester) async {
      await _openSheet(tester);

      final statusY = tester.getCenter(find.text(t.books.filterStatus)).dy;
      final genreY = tester.getCenter(find.text(t.books.filterGenre)).dy;
      final allY = tester.getCenter(find.text(t.books.statusAll)).dy;
      final unreadY = tester.getCenter(find.text(t.books.statusUnread)).dy;

      expect(genreY - statusY, closeTo(43.5, 0.5));
      expect(unreadY - allY, closeTo(47.5, 0.5));
    });

    testWidgets('Toepassen is a 130 by 40 pill at the right margin', (tester) async {
      await _openSheet(tester);

      final apply = tester.getRect(
        find.ancestor(of: find.text(t.books.filtersApply), matching: find.byType(Container)).first,
      );

      expect(apply.width, 130);
      expect(apply.height, 40);
      expect(_viewport.width - apply.right, closeTo(20, 0.5));
    });
  });

  group('the sheet is a draft', () {
    testWidgets('choosing changes nothing until Toepassen', (tester) async {
      // Golden 03's third decision. The count in the sheet moves, the shelf
      // behind it does not.
      await _openSheet(tester);
      final before = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();

      await tester.tap(find.text(t.books.statusUnread));
      await tester.pumpAndSettle();

      expect(find.text(t.books.filtersChosen(count: 1)), findsOneWidget);
      // Alle boeken still says what it said: the sheet covers most of it, but
      // its result line is what the grid is actually filtered by.
      expect(before.contains(t.books.bookCountLabel(count: 12)), isTrue);
      expect(find.text(t.books.bookCountLabel(count: 12)), findsOneWidget);
    });

    testWidgets('Toepassen applies it and the pill takes the badge', (tester) async {
      await _openSheet(tester);

      await tester.tap(find.text(t.books.statusRead));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.books.filtersApply));
      await tester.pumpAndSettle();

      // Two finished books in the fixture, and the result line names the cut.
      expect(find.text(t.books.bookCountLabel(count: 2)), findsOneWidget);
      expect(find.text(t.books.statusRead), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('dismissing is not clearing', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.text(t.books.statusRead));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.books.filtersApply));
      await tester.pumpAndSettle();

      // Reopen, stage something else, then leave by the barrier.
      await tester.tap(_filtersPill);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.books.statusUnread));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(196, 60));
      await tester.pumpAndSettle();

      expect(find.text(t.books.bookCountLabel(count: 2)), findsOneWidget);
    });

    testWidgets('Wissen empties the draft, and is inert while there is none', (tester) async {
      await _openSheet(tester);

      final atRest = tester.widget<Text>(find.text(t.books.filtersClear));
      expect(atRest.style?.color?.a, closeTo(0.5, 0.01));

      await tester.tap(find.text(t.books.statusUnread));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(t.books.filtersClear)).style?.color?.a, 1);

      await tester.tap(find.text(t.books.filtersClear));
      await tester.pumpAndSettle();
      expect(find.text(t.books.filtersChosen(count: 1)), findsNothing);
    });
  });

  group('groups', () {
    testWidgets('the rail carries what the shelf can answer, in golden order', (tester) async {
      await _openSheet(tester);

      final labels = [
        t.books.filterStatus,
        t.books.filterGenre,
        t.books.filterSeries,
        t.books.filterAuthor,
        t.books.filterLanguage,
      ];
      var previous = 0.0;
      for (final label in labels) {
        final y = tester.getCenter(find.text(label)).dy;
        expect(y, greaterThan(previous), reason: '$label is out of order');
        previous = y;
      }
    });

    testWidgets('switching group swaps the right pane and keeps the left one still', (tester) async {
      await _openSheet(tester);
      final statusY = tester.getCenter(find.text(t.books.filterStatus)).dy;

      await tester.tap(find.text(t.books.filterGenre));
      await tester.pumpAndSettle();

      expect(find.text(t.books.statusAll), findsNothing);
      expect(find.text('Sciencefiction'), findsOneWidget);
      expect(tester.getCenter(find.text(t.books.filterStatus)).dy, statusY);
    });

    testWidgets('a group counts its own choices in the rail', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.text(t.books.filterGenre));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sciencefiction'));
      await tester.tap(find.text('Fantasy'));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsWidgets);
      expect(find.text(t.books.filtersChosen(count: 2)), findsOneWidget);
    });
  });
}
