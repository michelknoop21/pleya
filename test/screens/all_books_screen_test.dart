import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/books_home_provider.dart';
import 'package:pleya/screens/books/all_books_screen.dart';
import 'package:provider/provider.dart';

/// The frame golden 02 was drawn on, and the bar the shell draws over it.
const Size _viewport = Size(393, 852);
const double _tabBarHeight = 83;

Future<BooksHomeProvider> pumpAllBooks(WidgetTester tester) async {
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
  return provider;
}

void main() {
  testWidgets('the grid is three columns on the golden viewport', (tester) async {
    // Measured on the Unified set's own Alle films: 16 pt margins, 10 pt
    // gutters, 114 pt covers. Four columns would leave 83 pt and cut a title
    // after about eleven characters.
    await pumpAllBooks(tester);

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

    expect(delegate.crossAxisCount, 3);
    expect(delegate.crossAxisSpacing, 10);
    // (393 - 32 margins - 20 gutters) / 3
    expect((_viewport.width - 32 - 20) / 3, closeTo(113.67, 0.01));
  });

  testWidgets('it sorts title A–Z, which is what the sort pill claims', (tester) async {
    await pumpAllBooks(tester);

    expect(find.text(t.books.sortTitleAsc), findsOneWidget);
    final provider = BooksHomeProvider(source: const DemoBooksSource());
    await provider.load();
    final titles = provider.rows.allByTitle.map((b) => b.title).toList();

    expect(titles, orderedEquals([...titles]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))));
  });

  testWidgets('it counts what it shows', (tester) async {
    final provider = await pumpAllBooks(tester);

    expect(find.text(t.books.bookCountLabel(count: provider.rows.all.length)), findsOneWidget);
  });

  testWidgets('no film metadata reaches the grid', (tester) async {
    // A bookshelf, not a film catalogue: no year, runtime, resolution or
    // rating. The demo set has books from 1949 onward, so a stray year would
    // show up here.
    await pumpAllBooks(tester);

    for (final year in ['1949', '1965', '2011', '2018', '2021']) {
      expect(find.textContaining(year), findsNothing, reason: '$year leaked into the grid');
    }
  });

  testWidgets('a long title wraps to two lines and then truncates', (tester) async {
    await pumpAllBooks(tester);

    final title = tester.widget<Text>(find.byKey(Key(AllBooksScreen.captionKey('ontdekking-van-de-hemel'))));

    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('scrolling brings the last row clear of the tab bar', (tester) async {
    // The requirement attached to goldens 01b and 02: the bar may cover the
    // last row on the way past, never for good.
    await pumpAllBooks(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    final last = find.byKey(Key(AllBooksScreen.captionKey('sapiens')));
    expect(last, findsOneWidget);
    expect(
      tester.getBottomLeft(last).dy,
      lessThanOrEqualTo(_viewport.height - _tabBarHeight),
      reason: 'the last row cannot be scrolled clear of the tab bar',
    );
  });
}
