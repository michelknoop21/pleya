import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_text_search.dart';
import 'package:pleya/books/book_text_search_layout.dart';
import 'package:pleya/books/demo_book_text_search.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/books/book_text_search_screen.dart';
import 'package:pleya/screens/books/widgets/book_text_search_row.dart';

/// The iPhone 15 Pro frame approved golden 09 was drawn on, and its insets. The
/// golden puts the header band on 62, which is the top inset plus three, the
/// field on 109, the count on 161 and the card on 191.
const Size _viewport = Size(393, 852);
const double _safeTop = 59;
const double _safeBottom = 34;

const _artwork = BookArtwork(
  base: Color(0xFF3A1A0B),
  accent: Color(0xFFE08A3C),
  ink: Color(0xFFF7E2C6),
  shape: BookArtworkShape.orb,
);

final _book = Book(
  id: 'dune',
  title: 'Dune',
  author: 'Frank Herbert',
  artwork: _artwork,
  addedAt: DateTime.utc(2026, 8, 1),
);

/// The interface face, loaded from the repository so a row wraps here the way it
/// wraps in the app and in the golden.
///
/// This screen's whole geometry is a consequence of how many lines an excerpt
/// takes: the test font draws every glyph a full em wide, and under it the
/// second result — the one the golden measures at 70 — would wrap onto a second
/// line and every row after it would sit at the wrong height. `Inter-Regular.otf`
/// is the same file `pubspec.yaml` ships and the same one the golden's source
/// loads.
Future<void> _loadInterfaceFace() async {
  final loader = FontLoader('Inter');
  for (final name in ['Inter-Regular.otf', 'Inter-Medium.otf', 'Inter-Bold.otf']) {
    final bytes = File('assets/fonts/$name').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// The iOS software keyboard on this frame, in points: 291 of keys plus the
/// 45pt suggestion bar above them. The simulator will not show it — idb types
/// as a hardware keyboard and iOS suppresses the on-screen one — but the app
/// never sees the keyboard itself, only the bottom inset it takes, so that is
/// what a test has to reproduce.
const double _keyboardInset = 336;

Future<void> _pumpSearch(
  WidgetTester tester, {
  String query = 'desert',
  BookTextSearch? search,
  double scale = 1.0,
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  const viewPadding = FakeViewPadding(top: _safeTop, bottom: _safeBottom);
  tester.view.viewPadding = viewPadding;
  // With the keyboard up the home indicator sits behind it, so iOS reports no
  // bottom padding and the whole gap arrives as an inset instead.
  tester.view.padding = keyboardInset > 0 ? const FakeViewPadding(top: _safeTop) : viewPadding;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      // The app's own face, so a row's line count here is the app's line count.
      theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter')),
      home: Builder(
        // Layered on the view's own padding rather than replacing the whole
        // MediaQueryData: the insets are what put the header on 62.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: BookTextSearchScreen(book: _book, search: search ?? const DemoBookTextSearch(), initialQuery: query),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(int index) => find.byType(BookTextSearchRow).at(index);

/// Which of the row's two `Text.rich`es is the excerpt: the second one.
String _excerptOf(WidgetTester tester, int index) =>
    tester.widget<Text>(find.descendant(of: _row(index), matching: find.byType(Text)).at(1)).textSpan!.toPlainText();

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadInterfaceFace();
  });

  group('09a, the canonical state', () {
    testWidgets('the four bands land on the golden\'s own numbers', (tester) async {
      await _pumpSearch(tester);

      // Golden 06's pushed-page header: the band 62 to 94, the arrow on 16 and
      // the title on 56.
      final title = tester.getRect(find.text(t.books.searchInBook));
      expect(title.left, 56);
      expect(title.center.dy, closeTo(BookTextSearchLayout.headerTop + BookTextSearchLayout.headerHeight / 2, 1.5));
      final field = tester.getRect(find.byType(TextField));
      expect(field.center.dy, closeTo(BookTextSearchLayout.fieldTop + BookTextSearchLayout.fieldHeight / 2, 0.5));
      final count = tester.getRect(find.text(t.books.searchInBookResults(count: 12)));
      expect(count.top, BookTextSearchLayout.countTop);
      expect(count.height, BookTextSearchLayout.countHeight);
      expect(count.left, BookTextSearchLayout.pageMargin);
      expect(tester.getRect(_row(0)).top, BookTextSearchLayout.cardTop);
    });

    testWidgets('twelve results, and the count says so', (tester) async {
      await _pumpSearch(tester);

      expect(find.byType(BookTextSearchRow), findsNWidgets(12));
      expect(find.text(t.books.searchInBookResults(count: 12)), findsOneWidget);
      // One kind of result, so no category chips: a chip row with one chip is
      // not a filter. This is not golden 04.
      expect(find.text(t.books.searchAuthors), findsNothing);
      expect(find.text(t.books.bookSeries), findsNothing);
    });

    testWidgets('every row lands where the frame puts it, and the eighth is cut by the bottom edge', (tester) async {
      await _pumpSearch(tester);

      // The prediction, fed the line count each row actually drew — so this
      // compares the table against the rendering rather than against itself.
      final drawn = [
        for (var i = 0; i < 12; i++) tester.getSize(_row(i)).height == BookTextSearchLayout.oneLineRowHeight ? 1 : 2,
      ];
      final predicted = BookTextSearchLayout.positions(drawn);
      for (var i = 0; i < 12; i++) {
        expect(tester.getRect(_row(i)).top, predicted[i], reason: 'row $i');
      }

      // And the numbers read off the golden: the second result is the one
      // one-line excerpt in the set, so it is 70 tall and the third row starts
      // on 352.
      expect(drawn, [2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]);
      expect(tester.getRect(_row(1)).top, 282);
      expect(tester.getSize(_row(1)).height, 70);
      expect(tester.getRect(_row(2)).top, 352);
      expect(tester.getRect(_row(7)).top, 807);
      expect(tester.getRect(_row(7)).top, lessThan(_viewport.height));
      expect(tester.getRect(_row(11)).bottom, BookTextSearchLayout.cardTop + 1071);
    });

    testWidgets('the card runs to the page margins with no gaps between its rows', (tester) async {
      await _pumpSearch(tester);

      expect(tester.getRect(_row(0)).left, BookTextSearchLayout.pageMargin);
      expect(tester.getRect(_row(0)).right, _viewport.width - BookTextSearchLayout.pageMargin);
      // A separator with a height of its own would push every row after the
      // first one point down; the hairline is drawn inside the row's top edge.
      for (var i = 1; i < 12; i++) {
        expect(tester.getRect(_row(i)).top, tester.getRect(_row(i - 1)).bottom, reason: 'row $i');
      }
    });

    testWidgets('the list can be scrolled clear of the home indicator', (tester) async {
      await _pumpSearch(tester);

      await tester.drag(find.byType(BookTextSearchScreen), const Offset(0, -600));
      await tester.pumpAndSettle();

      // What ran on under the bottom edge is reachable, which is the allowance
      // golden 01b and 02 already made for the tab bar.
      expect(tester.getRect(_row(11)).bottom, lessThanOrEqualTo(_viewport.height - _safeBottom));
    });
  });

  group('09b, the shapes of a row', () {
    testWidgets('the first line is the chapter with the page label as a suffix', (tester) async {
      await _pumpSearch(tester);

      // `Hoofdstuk 3` and `Hoofdstuk 30` are both in this list, which is why
      // the row is read out rather than searched for by substring.
      expect(find.textContaining('Hoofdstuk 3'), findsNWidgets(2));
      // Composed rather than written by the fixture: the chapter comes from the
      // publication, the page word from the interface language.
      final location = tester
          .widget<Text>(find.descendant(of: _row(0), matching: find.byType(Text)).first)
          .textSpan!
          .toPlainText();
      expect(location, 'Hoofdstuk 3 · ${t.books.readerPage(page: '41')}');
    });

    testWidgets('a publication without a page-list keeps its chapter and loses the suffix', (tester) async {
      await _pumpSearch(tester, search: const _NoPageListSearch());

      final location = tester
          .widget<Text>(find.descendant(of: _row(0), matching: find.byType(Text)).first)
          .textSpan!
          .toPlainText();
      expect(location, 'Hoofdstuk 12');
      expect(location, isNot(contains('·')));
    });

    testWidgets('the match is amber ink on medium and never a filled block', (tester) async {
      await _pumpSearch(tester);

      final excerpt = tester.widget<Text>(find.descendant(of: _row(0), matching: find.byType(Text)).at(1));
      final marked = <String>[];
      excerpt.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.style?.color == BookTextSearchLayout.match) {
          marked.add(span.text ?? '');
          expect(span.style!.fontWeight, FontWeight.w500);
          // Ink, not fill. A filled marker on a reading surface means a passage
          // the reader marked themselves.
          expect(span.style!.backgroundColor, isNull);
        }
        return true;
      });
      expect(marked, ['desert']);
    });

    testWidgets('two matches in one excerpt are both amber', (tester) async {
      await _pumpSearch(tester);

      final excerpt = tester.widget<Text>(find.descendant(of: _row(10), matching: find.byType(Text)).at(1));
      var marked = 0;
      excerpt.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.style?.color == BookTextSearchLayout.match) marked++;
        return true;
      });
      expect(marked, 2);
    });

    testWidgets('an excerpt that overruns is clipped at the second line', (tester) async {
      await _pumpSearch(tester);

      final excerpt = tester.widget<Text>(find.descendant(of: _row(2), matching: find.byType(Text)).at(1));
      expect(excerpt.maxLines, BookTextSearchLayout.excerptMaxLines);
      expect(excerpt.overflow, TextOverflow.ellipsis);
      // The row stays 91: clipping is what it does with a window that overruns,
      // rather than growing a third line.
      expect(tester.getSize(_row(2)).height, BookTextSearchLayout.twoLineRowHeight);
    });

    testWidgets('two results on the same page are two rows with their own excerpts', (tester) async {
      await _pumpSearch(tester);

      expect(_excerptOf(tester, 4), contains('felt the tremor'));
      expect(_excerptOf(tester, 5), contains('In the silence'));
      // Both say `Hoofdstuk 12 · Pagina 248`, which is why neither is addressed
      // by that label.
      expect(find.textContaining('Hoofdstuk 12'), findsNWidgets(2));
    });

    testWidgets('there is no chevron behind a row', (tester) async {
      await _pumpSearch(tester);
      expect(find.byIcon(Symbols.chevron_right_rounded), findsNothing);
    });
  });

  group('the count, and what it refuses to claim', () {
    testWidgets('an empty field says nothing and draws no card', (tester) async {
      await _pumpSearch(tester, query: '');

      expect(find.byType(BookTextSearchRow), findsNothing);
      expect(find.text(t.books.searchInBookNoResults), findsNothing);
      expect(find.textContaining('gevonden'), findsNothing);
      expect(find.textContaining('found'), findsNothing);
    });

    testWidgets('a single letter is not a query either', (tester) async {
      await _pumpSearch(tester, query: 'd');

      expect(find.byType(BookTextSearchRow), findsNothing);
      // `Geen resultaten gevonden` here would be a claim about a search that
      // never ran.
      expect(find.text(t.books.searchInBookNoResults), findsNothing);
    });

    testWidgets('a query that ran and found nothing gets the line and no card', (tester) async {
      await _pumpSearch(tester, query: 'ornithopter');

      expect(find.text(t.books.searchInBookNoResults), findsOneWidget);
      expect(find.byType(BookTextSearchRow), findsNothing);
      // The approved furniture saying what is true, and deliberately not an
      // empty state: golden 09 holds that one open.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('one result is one result and not `1 results`', (tester) async {
      await _pumpSearch(tester, query: 'caravan');

      expect(find.byType(BookTextSearchRow), findsOneWidget);
      expect(find.text(t.books.searchInBookOneResult), findsOneWidget);
    });
  });

  group('typing', () {
    testWidgets('the list follows the field, and the clear glyph empties both', (tester) async {
      await _pumpSearch(tester, query: '');

      await tester.enterText(find.byType(TextField), 'desert');
      await tester.pumpAndSettle();
      expect(find.byType(BookTextSearchRow), findsNWidgets(12));

      await tester.enterText(find.byType(TextField), 'caravan');
      await tester.pumpAndSettle();
      expect(find.byType(BookTextSearchRow), findsOneWidget);

      await tester.tap(find.byIcon(Symbols.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(BookTextSearchRow), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });
  });

  group('text scale', () {
    /// Nothing in `lib/` clamps `textScaler`, so iOS Larger Text arrives at full
    /// strength. The row's heights are content rather than a box for exactly
    /// that reason: at 1.3 a result is taller than 91 instead of clipping its
    /// own excerpt against a constant that was right at 1.0.
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('a row lays out without overflowing at text scale $scale', (tester) async {
        await _pumpSearch(tester, scale: scale);

        expect(tester.takeException(), isNull);
        expect(find.byType(BookTextSearchRow), findsNWidgets(12));
        // The count line grows with the setting too, rather than clipping in a
        // box that was the right size at 1.0.
        final count = tester.getRect(find.text(t.books.searchInBookResults(count: 12)));
        expect(count.height, closeTo(BookTextSearchLayout.countHeight * scale, 1.0));
        final height = tester.getSize(_row(0)).height;
        if (scale == 1.0) {
          expect(height, BookTextSearchLayout.twoLineRowHeight, reason: 'golden 09 was measured on 91 and still is');
        } else {
          expect(height, greaterThan(BookTextSearchLayout.twoLineRowHeight), reason: 'the row absorbs the setting');
        }
      });
    }
  });

  group('the field is a query field, not a prose field', () {
    /// Typing golden 09's own term on a real keyboard gets `dessert` offered
    /// over `desert`, and the suggestion bubble lands on the count line. Taking
    /// it searches a word the reader never asked for. Found by making a scenario
    /// type instead of seeding the query; the app already turns autocorrect off
    /// for URLs, passwords and PINs.
    testWidgets('autocorrect is off', (tester) async {
      await _pumpSearch(tester, query: '');
      expect(tester.widget<TextField>(find.byType(TextField)).autocorrect, isFalse);
    });
  });

  group('with the software keyboard up', () {
    /// What the keyboard covers, and whether the results behind it can be
    /// reached. The simulator refuses to show the on-screen keyboard while idb
    /// is attached (it types as hardware), so the run's screenshots cannot
    /// answer this; the inset can, because that is the only form the keyboard
    /// reaches the app in.
    testWidgets('it takes the lower half of the page', (tester) async {
      await _pumpSearch(tester, keyboardInset: _keyboardInset);

      final fold = _viewport.height - _keyboardInset;
      final visible = [
        for (var i = 0; i < 12; i++)
          if (tester.getRect(_row(i)).bottom <= fold) i,
      ];
      // Three of the twelve rows survive; the other nine sit behind the keys.
      expect(visible, [0, 1, 2]);
    });

    testWidgets('the last result can still be scrolled clear of it', (tester) async {
      await _pumpSearch(tester, keyboardInset: _keyboardInset);

      // Far enough to hit the end of the list, whatever the row heights are.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();

      final last = tester.getRect(_row(11));
      expect(last.bottom, lessThanOrEqualTo(_viewport.height - _keyboardInset));
      expect(last.top, greaterThanOrEqualTo(0));
    });

    /// The header is not part of the scrolling content by accident: it scrolls
    /// away with everything else, which is what frees the room above the keys.
    testWidgets('the field itself is above the keyboard while typing', (tester) async {
      await _pumpSearch(tester, keyboardInset: _keyboardInset);

      expect(tester.getRect(find.byType(TextField)).bottom, lessThan(_viewport.height - _keyboardInset));
    });
  });

  group('what this golden stops at', () {
    testWidgets('a row is drawn and opens nothing', (tester) async {
      await _pumpSearch(tester);

      final before = tester.getRect(_row(0));
      await tester.tap(_row(0));
      await tester.pumpAndSettle();

      // Where the reader travels to a locator is one of the things golden 09
      // leaves open, so there is nothing here to travel with.
      expect(find.byType(BookTextSearchScreen), findsOneWidget);
      expect(tester.getRect(_row(0)), before);
    });
  });
}

/// A source whose publication ships no `page-list`, for golden 09b's last
/// specimen. Not a variant of the fixture: the absence of a page label is a
/// property of the publication, so it arrives through the seam like everything
/// else does.
class _NoPageListSearch implements BookTextSearch {
  const _NoPageListSearch();

  @override
  int get minQueryLength => 2;

  @override
  List<BookSearchHit> search({required String bookId, required String query}) => const [
    BookSearchHit(
      locator: BookLocator('dune/ch12#p01'),
      chapterLabel: 'Hoofdstuk 12',
      excerpt: '… felt the tremor of the desert under his feet, a rhythm he had come to know …',
      matchRanges: [BookMatchRange(24, 30)],
    ),
  ];
}
