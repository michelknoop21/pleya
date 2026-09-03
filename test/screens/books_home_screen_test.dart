import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/books_home_provider.dart';
import 'package:pleya/screens/books/books_home_screen.dart';
import 'package:pleya/theme/mono_theme.dart' show kAccent;
import 'package:provider/provider.dart';

/// The iPhone 15 Pro frame golden 01b was drawn on, and the height of the
/// bottom bar the shell draws over this screen.
const Size _viewport = Size(393, 852);
const double _tabBarHeight = 83;

Future<void> pumpBooksHome(WidgetTester tester) async {
  tester.view.physicalSize = _viewport * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _viewport;
  addTearDown(tester.view.reset);

  final provider = BooksHomeProvider(source: const DemoBooksSource());
  await provider.load();

  await tester.pumpWidget(
    ChangeNotifierProvider<BooksHomeProvider>.value(
      value: provider,
      child: MaterialApp(theme: ThemeData.dark(), home: const BooksHomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it is the three rails golden 01b puts on the page, in its order', (tester) async {
    await pumpBooksHome(tester);

    final headings = [t.books.continueReading, t.books.recentlyAdded, t.books.bookSeries];
    final tops = [for (final heading in headings) tester.getTopLeft(find.text(heading)).dy];

    expect(find.text(t.navigation.books), findsOneWidget);
    expect(find.text('${t.books.allBooks} ›'), findsOneWidget);
    expect(tops, orderedEquals([...tops]..sort()), reason: 'rails are out of order: $tops');
  });

  testWidgets('a continue-reading card names the chapter next to the percentage', (tester) async {
    await pumpBooksHome(tester);

    expect(find.text('48% · Hoofdstuk 12'), findsOneWidget);
  });

  testWidgets('the Boekenseries rail is partly behind the bar at rest', (tester) async {
    // Golden 01b's first frame: the last rail runs under the tab bar, and that
    // is what says the page scrolls.
    await pumpBooksHome(tester);

    // Position, not existence: a sliver off the bottom of the viewport is
    // still in the tree, so `findsNothing` would be measuring the wrong thing.
    final seriesHeading = tester.getTopLeft(find.text(t.books.bookSeries)).dy;
    final firstCount = tester.getTopLeft(find.text(t.books.bookCount(count: 6))).dy;

    expect(seriesHeading, lessThan(_viewport.height - _tabBarHeight), reason: 'the rail heading should be visible');
    expect(
      firstCount,
      greaterThan(_viewport.height - _tabBarHeight),
      reason: 'the series metadata should start below the tab bar at rest',
    );
  });

  testWidgets('scrolling brings the last rail fully clear of the bar', (tester) async {
    // The implementation requirement attached to approved golden 01b: the bar
    // may cover content on the way past, never for good. Without the bottom
    // padding this screen adds, `Dune · 6 boeken` can never be read.
    await pumpBooksHome(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final count = find.text(t.books.bookCount(count: 6));
    expect(count, findsOneWidget);
    expect(
      tester.getBottomLeft(count).dy,
      lessThanOrEqualTo(_viewport.height - _tabBarHeight),
      reason: 'the last rail cannot be scrolled clear of the tab bar',
    );
  });

  testWidgets('a continue-reading card draws a progress bar with real height', (tester) async {
    // Regression: the bar laid out 113 x 0 because a Row centres its children
    // and a ColoredBox has no height of its own. It passed every assertion
    // about the card and shipped with no progress on it; comparing the
    // simulator screenshot against approved golden 01b is what found it.
    await pumpBooksHome(tester);

    final bar = find.byWidgetPredicate((w) => w is ColoredBox && w.color == kAccent);

    expect(bar, findsWidgets);
    final size = tester.getSize(bar.first);
    expect(size.height, greaterThan(0), reason: 'the progress bar has no height');
    expect(size.width, greaterThan(0));
  });

  testWidgets('a profile without books gets no rails and no see-all link', (tester) async {
    final provider = BooksHomeProvider(source: const EmptyBooksSource());
    await provider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<BooksHomeProvider>.value(
        value: provider,
        child: MaterialApp(theme: ThemeData.dark(), home: const BooksHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.navigation.books), findsOneWidget);
    expect(find.text(t.books.continueReading), findsNothing);
    expect(find.text('${t.books.allBooks} ›'), findsNothing);
  });
}
