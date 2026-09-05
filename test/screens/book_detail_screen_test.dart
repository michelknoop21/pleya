import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_detail_layout.dart';
import 'package:pleya/books/book_reader_page.dart';
import 'package:pleya/books/demo_book_reader.dart';
import 'package:pleya/books/book_text_search.dart';
import 'package:pleya/books/book_toc.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/books_home_provider.dart';
import 'package:pleya/screens/books/all_books_screen.dart';
import 'package:pleya/screens/books/book_detail_screen.dart';
import 'package:pleya/screens/books/books_home_screen.dart';
import 'package:pleya/screens/books/book_reader_screen.dart';
import 'package:pleya/screens/books/books_search_screen.dart';
import 'package:pleya/screens/books/widgets/book_cover.dart';
import 'package:pleya/screens/books/widgets/book_description.dart';
import 'package:pleya/screens/books/widgets/book_detail_actions.dart';
import 'package:pleya/screens/books/widgets/book_search_row.dart';
import 'package:pleya/screens/books/widgets/continue_reading_card.dart';
import 'package:provider/provider.dart';

/// The iPhone 15 Pro frame golden 05 was drawn on, and its safe-area inset.
/// The golden puts the header band on 62, which is that inset plus three.
const Size _viewport = Size(393, 852);
const double _safeTop = 59;

const _artwork = BookArtwork(
  base: Color(0xFF3A1A0B),
  accent: Color(0xFFE08A3C),
  ink: Color(0xFFF7E2C6),
  // An orb cover upper-cases its own title, so `find.text('Dune')` finds the
  // page's title and not the one drawn on the artwork, and it draws no author
  // line at all.
  shape: BookArtworkShape.orb,
);

const _series = [BookSeries(id: 'dune', title: 'Dune', bookCount: 6, artwork: _artwork)];

/// 05a: a book halfway read, in a series. The canonical state.
final _reading = Book(
  id: 'dune',
  title: 'Dune',
  author: 'Frank Herbert',
  artwork: _artwork,
  addedAt: DateTime.utc(2026, 8, 1),
  seriesId: 'dune',
  seriesIndex: 1,
  progress: 0.48,
  chapterLabel: 'Hoofdstuk 12',
  genres: const ['Sciencefiction'],
  year: 1965,
  pages: 616,
  description:
      'Ver weg in de toekomst krijgt Paul Atreides, een briljante en begaafde jongeman, een lot dat groter is dan hij '
      'ooit had kunnen bevroeden. Hij moet afreizen naar de gevaarlijkste planeet van het universum.',
);

/// 05b: never opened, in no series. A short title on purpose — the test font
/// draws every glyph a full em wide, so a long one would wrap at 30 pt and
/// move the whole column down for a reason the golden does not have.
final _unread = Book(
  id: 'mary',
  title: 'Mary',
  author: 'Andy Weir',
  artwork: _artwork,
  addedAt: DateTime.utc(2026, 8, 2),
  genres: const ['Sciencefiction'],
  year: 2021,
  pages: 496,
  description:
      'Ryland Grace wordt wakker aan boord van een schip dat hij zich niet herinnert, met twee dode bemanningsleden '
      'naast zich en geen idee wie hij is.',
);

Future<void> _pumpDetail(WidgetTester tester, Book book, {List<BookSeries> series = _series}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(top: _safeTop);
  tester.view.padding = const FakeViewPadding(top: _safeTop);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: BookDetailScreen(book: book, series: series),
    ),
  );
  await tester.pumpAndSettle();
}

/// The top edge of a block, in frame points.
double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// A source that answers when the test says so.
///
/// `DemoBooksSource` resolves in a microtask, so the window between the tap and
/// the `Navigator.push` closes before a second tap can land — which is exactly
/// why the missing guard was invisible. `BooksSource` is the documented seam
/// for a real source, and a real source takes time. A `Completer` rather than a
/// `Future.delayed`: `testWidgets` runs on a fake clock, so a delayed future
/// never fires unless the test pumps it, and holding the completer makes the
/// window explicit instead of timed.
class _GatedBooksSource implements BooksSource {
  _GatedBooksSource();

  static const _demo = DemoBooksSource();

  /// One per call to [readerPage], so a test can count how many opens actually
  /// started — the sharpest form of "the second tap did nothing".
  final pageRequests = <Completer<BookReaderPage?>>[];

  void answerLastPage(String bookId) => pageRequests.last.complete(demoBookReaderPage(bookId));

  @override
  Future<List<Book>> books() => _demo.books();

  @override
  Future<List<BookSeries>> series() => _demo.series();

  @override
  Future<BookToc?> tableOfContents(String bookId) => _demo.tableOfContents(bookId);

  @override
  Future<BookReaderPage?> readerPage(String bookId) {
    final completer = Completer<BookReaderPage?>();
    pageRequests.add(completer);
    return completer.future;
  }

  @override
  BookTextSearch? get textSearch => _demo.textSearch;
}

Finder get _primary => find.byType(BookDetailAction).at(0);
Finder get _secondary => find.byType(BookDetailAction).at(1);

void main() {
  group('05a, the canonical state', () {
    testWidgets('every block lands where golden 05a puts it', (tester) async {
      await _pumpDetail(tester, _reading);

      final predicted = BookDetailLayout.positions(present: BookDetailBlock.values.toSet());

      expect(_top(tester, find.byType(BookCover)), BookDetailLayout.coverTop);
      expect(tester.getSize(find.byType(BookCover)), const Size(150, 225));
      expect(_top(tester, find.text('Dune')), predicted[BookDetailBlock.title]);
      expect(_top(tester, find.text('Frank Herbert')), predicted[BookDetailBlock.author]);
      expect(_top(tester, find.text('Dune #1')), predicted[BookDetailBlock.series]);
      expect(_top(tester, find.byType(BookDetailProgress)), predicted[BookDetailBlock.progress]);
      expect(_top(tester, _primary), predicted[BookDetailBlock.primary]);
      expect(_top(tester, _secondary), predicted[BookDetailBlock.secondary]);
      expect(_top(tester, find.byType(BookDetailStats)), predicted[BookDetailBlock.stats]);
      expect(_top(tester, find.byType(BookDescription)), predicted[BookDetailBlock.description]);
    });

    testWidgets('the header is back and overflow on the golden band, and carries no title', (tester) async {
      await _pumpDetail(tester, _reading);

      // `Dune` appears once: as the 30 pt title 270 pt lower, not next to the
      // back arrow. The comp wins here, for the composition.
      expect(find.text('Dune'), findsOneWidget);
      expect(_top(tester, find.text('Dune')), greaterThan(BookDetailLayout.headerTop + 200));
    });

    testWidgets('progress is two lines of text and no bar', (tester) async {
      await _pumpDetail(tester, _reading);

      expect(find.text(t.books.percentReadLong(percent: 48)), findsOneWidget);
      expect(find.text('Hoofdstuk 12'), findsOneWidget);
      // The Verder-lezen card on Boeken-home has a bar; this page does not. A
      // rule across a centred column would be a third horizontal line right
      // above two full-width pills.
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('two pills, 48 tall, 10 apart, on the 16 pt page margin', (tester) async {
      await _pumpDetail(tester, _reading);

      final primary = tester.getRect(_primary);
      final secondary = tester.getRect(_secondary);

      expect(primary.height, BookDetailLayout.actionHeight);
      expect(secondary.height, BookDetailLayout.actionHeight);
      expect(secondary.top - primary.bottom, 10);
      expect(primary.left, BookDetailLayout.pageMargin);
      expect(primary.right, _viewport.width - BookDetailLayout.pageMargin);
    });

    testWidgets('the primary reads Lees verder and the secondary Downloaden', (tester) async {
      await _pumpDetail(tester, _reading);

      expect(find.text(t.books.readContinue), findsOneWidget);
      expect(find.text(t.books.download), findsOneWidget);
      expect(find.text(t.books.read), findsNothing);
    });

    testWidgets('the stats row is year, genre and pages with genre 1.45 times as wide', (tester) async {
      await _pumpDetail(tester, _reading);

      final year = tester.getRect(find.byKey(Key(BookDetailStats.columnKey('year'))));
      final genre = tester.getRect(find.byKey(Key(BookDetailStats.columnKey('genre'))));
      final pages = tester.getRect(find.byKey(Key(BookDetailStats.columnKey('pages'))));

      expect(genre.width / year.width, closeTo(1.45, 0.01));
      expect(pages.width, closeTo(year.width, 0.01));
      expect(tester.getSize(find.byType(BookDetailStats)).height, BookDetailLayout.statsHeight);
      expect(find.text('1965'), findsOneWidget);
      expect(find.text('616'), findsOneWidget);
    });

    testWidgets('the description is three lines with an inline meer', (tester) async {
      await _pumpDetail(tester, _reading);

      final size = tester.getSize(find.byType(BookDescription));

      expect(size.height, BookDetailLayout.descriptionMaxLines * BookDetailLayout.descriptionLineHeight);
      final text = tester.widget<Text>(find.descendant(of: find.byType(BookDescription), matching: find.byType(Text)));
      expect(text.textSpan!.toPlainText(), endsWith('… ${t.books.descriptionMore}'));
    });

    /// The clamp measures a paragraph with a `TextPainter` and then hands the
    /// same paragraph to a `Text`. If the two do not resolve to the same face,
    /// the search lands one line short of the truth and `… meer` is clipped off
    /// the bottom, because `Text.rich` inherits `TextOverflow.clip`.
    ///
    /// Not observable through geometry in a widget test: the test font draws
    /// every family identically, which is exactly why this shipped. So the
    /// assertion is on the style that reaches both sides.
    testWidgets('the paragraph that is measured carries the face it is painted in', (tester) async {
      tester.view.physicalSize = _viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          // The shape `monoTheme` has: a family on the theme, inherited by
          // everything under it through `DefaultTextStyle`.
          theme: ThemeData(fontFamily: 'Inter'),
          home: Scaffold(
            body: SizedBox(width: 300, child: BookDescription(text: _reading.description!)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.descendant(of: find.byType(BookDescription), matching: find.byType(Text)));

      expect(
        text.style?.fontFamily,
        'Inter',
        reason: 'the paint has to be told the face rather than inherit one the measurement never saw',
      );
      expect(
        (text.textSpan! as TextSpan).style?.fontFamily,
        'Inter',
        reason: 'the measured span itself carries the face, so TextPainter lays out what the screen shows',
      );
      for (final child in (text.textSpan! as TextSpan).children ?? const <InlineSpan>[]) {
        final style = (child as TextSpan).style;
        if (style != null) {
          expect(style.fontFamily, 'Inter', reason: 'the `meer` span is measured in the same face too');
        }
      }
    });
  });

  group('05b, a book that has not been started', () {
    testWidgets('no series line, no progress block, and the rest moves up by exactly that much', (tester) async {
      await _pumpDetail(tester, _unread, series: const []);

      final predicted = BookDetailLayout.positions(
        present: BookDetailBlock.values.toSet()
          ..remove(BookDetailBlock.series)
          ..remove(BookDetailBlock.progress),
      );

      expect(find.byType(BookDetailProgress), findsNothing);
      expect(find.text('Dune #1'), findsNothing);
      expect(_top(tester, find.text('Mary')), predicted[BookDetailBlock.title]);
      expect(_top(tester, find.text('Andy Weir')), predicted[BookDetailBlock.author]);
      expect(_top(tester, _primary), predicted[BookDetailBlock.primary]);
      expect(_top(tester, _secondary), predicted[BookDetailBlock.secondary]);
      expect(_top(tester, find.byType(BookDetailStats)), predicted[BookDetailBlock.stats]);
      expect(_top(tester, find.byType(BookDescription)), predicted[BookDetailBlock.description]);
    });

    testWidgets('the primary reads Lezen', (tester) async {
      await _pumpDetail(tester, _unread, series: const []);

      expect(find.text(t.books.read), findsOneWidget);
      expect(find.text(t.books.readContinue), findsNothing);
    });

    testWidgets('the description stays three lines and the winnings land as air at the bottom', (tester) async {
      await _pumpDetail(tester, _unread, series: const []);

      final reading = BookDetailLayout.positions(present: BookDetailBlock.values.toSet());
      final unread = tester.getRect(find.byType(BookDescription));

      expect(unread.height, BookDetailLayout.descriptionMaxLines * BookDetailLayout.descriptionLineHeight);
      // 68 pt higher than in 05a: the series block plus the progress block,
      // each with its own gap. Nothing between them stretched to take it up.
      expect(reading[BookDetailBlock.description]! - unread.top, 68);
    });

    testWidgets('the 24 pt between the identity block and the first pill is unchanged', (tester) async {
      await _pumpDetail(tester, _unread, series: const []);

      final author = tester.getRect(find.text('Andy Weir'));

      expect(_top(tester, _primary) - author.bottom, 24);
    });
  });

  group('the two-column fallback', () {
    testWidgets('an edition with no page count draws two columns, not an empty third', (tester) async {
      await _pumpDetail(
        tester,
        Book(
          id: 'brave',
          title: 'Mary',
          author: 'Aldous Huxley',
          artwork: _artwork,
          addedAt: DateTime.utc(2026, 8, 3),
          genres: const ['Sciencefiction'],
          year: 1932,
          description: 'Iedereen is gelukkig.',
        ),
        series: const [],
      );

      expect(find.byKey(Key(BookDetailStats.columnKey('pages'))), findsNothing);
      expect(find.text(t.books.statPages), findsNothing);
      expect(find.text('0'), findsNothing);

      final year = tester.getRect(find.byKey(Key(BookDetailStats.columnKey('year'))));
      final genre = tester.getRect(find.byKey(Key(BookDetailStats.columnKey('genre'))));
      expect(genre.width / year.width, closeTo(1.45, 0.01));
      expect(genre.right, closeTo(_viewport.width - BookDetailLayout.pageMargin, 0.01));
    });
  });

  group('what this golden stops at', () {
    testWidgets('the two pills are drawn and open nothing', (tester) async {
      await _pumpDetail(tester, _reading);

      await tester.tap(_primary);
      await tester.pumpAndSettle();
      await tester.tap(_secondary);
      await tester.pumpAndSettle();

      // The reader is panel 7 and has its own golden; what Downloaden means in
      // each of its states is PS-16. Neither is decided here.
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(
        _top(tester, _primary),
        BookDetailLayout.positions(present: BookDetailBlock.values.toSet())[BookDetailBlock.primary],
      );
    });

    testWidgets('nothing is squeezed in between the blocks golden 05 names', (tester) async {
      // In particular no way into the inhoudsopgave. Golden 05 leaves that
      // open on purpose: it belongs with the reader's chrome, and inventing an
      // entry here would answer a question golden 06 has not been asked yet.
      await _pumpDetail(tester, _reading);

      expect(BookDetailBlock.values.length, 8);
      expect(_top(tester, find.byType(BookDetailStats)) - tester.getRect(_secondary).bottom, 20);
      expect(_top(tester, find.byType(BookDescription)) - tester.getRect(find.byType(BookDetailStats)).bottom, 20);
    });
  });

  group('the three ways in', () {
    Future<BooksHomeProvider> provider() async {
      final value = BooksHomeProvider(source: const DemoBooksSource());
      await value.load();
      return value;
    }

    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = _viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<BooksHomeProvider>.value(
          value: await provider(),
          child: MaterialApp(theme: ThemeData.dark(), home: screen),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the Verder-lezen card on Boeken-home opens the book, series and all', (tester) async {
      await pumpScreen(tester, const BooksHomeScreen());

      // Furthest along first, so this is Dune — the book golden 05a is drawn
      // with, series line included.
      await tester.tap(find.byType(ContinueReadingCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(find.text('Dune #1'), findsOneWidget);
    });

    testWidgets('a cell in Alle boeken opens the book', (tester) async {
      await pumpScreen(tester, const AllBooksScreen());

      await tester.tap(find.byKey(Key(AllBooksScreen.captionKey('1984'))));
      await tester.pumpAndSettle();

      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(find.text('George Orwell'), findsWidgets);
    });

    testWidgets('a book row in Boeken zoeken opens the book, an author row does not', (tester) async {
      await pumpScreen(tester, const BooksSearchScreen(initialQuery: 'dune'));

      await tester.tap(find.descendant(of: find.byType(AuthorResultRow), matching: find.text('Frank Herbert')));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsNothing);

      await tester.tap(find.text('Dune Messiah'));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsOneWidget);
    });
  });

  /// One tap on `Lees verder` opens one reader.
  ///
  /// `_openReader` awaits the source for a page and then for a table of
  /// contents before it pushes, so without a guard the button stays live across
  /// that window and two taps push two `BookReaderScreen`s onto one navigator.
  group('the reading button opens one reader', () {
    Future<_GatedBooksSource> pumpGated(WidgetTester tester, {List<Route<dynamic>>? pushed}) async {
      tester.view.physicalSize = _viewport;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: _safeTop);
      addTearDown(tester.view.reset);

      final source = _GatedBooksSource();
      final provider = BooksHomeProvider(source: source);
      addTearDown(provider.dispose);
      await provider.load();

      await tester.pumpWidget(
        ChangeNotifierProvider<BooksHomeProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: ThemeData.dark(),
            navigatorObservers: [if (pushed != null) _PushRecorder(pushed)],
            home: BookDetailScreen(book: _reading, series: _series),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('a second tap inside the source window starts nothing', (tester) async {
      final pushed = <Route<dynamic>>[];
      final source = await pumpGated(tester, pushed: pushed);
      pushed.clear();

      await tester.tap(_primary);
      await tester.pump();
      expect(source.pageRequests, hasLength(1), reason: 'the first tap asked the source');

      // The source has not answered yet. This is the window.
      await tester.tap(_primary);
      await tester.pump();
      expect(
        source.pageRequests,
        hasLength(1),
        reason: 'the second tap must not start a second open while the first is still in flight',
      );

      source.answerLastPage(_reading.id);
      await tester.pumpAndSettle();

      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(pushed.whereType<MaterialPageRoute<dynamic>>(), hasLength(1));
    });

    testWidgets('the button works again after the reader is closed', (tester) async {
      final source = await pumpGated(tester);

      await tester.tap(_primary);
      await tester.pump();
      source.answerLastPage(_reading.id);
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsNothing);

      // A guard that never releases is a dead button, not a safe one.
      await tester.tap(_primary);
      await tester.pump();
      expect(source.pageRequests, hasLength(2));
      source.answerLastPage(_reading.id);
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
    });
  });
}

/// Counts pushed routes so a test can tell one reader from two.
class _PushRecorder extends NavigatorObserver {
  _PushRecorder(this.pushed);

  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}
