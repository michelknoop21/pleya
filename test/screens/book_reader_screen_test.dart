import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_reader_layout.dart';
import 'package:pleya/books/book_reader_page.dart';
import 'package:pleya/books/book_toc.dart';
import 'package:pleya/books/demo_book_reader.dart';
import 'package:pleya/books/demo_book_tocs.dart';
import 'package:pleya/screens/books/book_reader_screen.dart';
import 'package:pleya/screens/books/books_toc_screen.dart';
import 'package:pleya/screens/books/widgets/book_reader_chrome.dart';

/// The iPhone 15 Pro frame approved golden 07 was drawn on, and its insets. The
/// golden puts the chrome on 62, which is the top inset plus three, and the
/// footer's own top on 752, which is 852 less the bottom inset, the label's band
/// and the air under it.
const Size _viewport = Size(393, 852);
const double _safeTop = 59;
const double _safeBottom = 34;

const _artwork = BookArtwork(
  base: Color(0xFF1B1B1B),
  accent: Color(0xFFE5140F),
  ink: Color(0xFFF4F2EC),
  shape: BookArtworkShape.orb,
);

final _book = Book(
  id: 'dune',
  title: 'Dune',
  author: 'Frank Herbert',
  artwork: _artwork,
  addedAt: DateTime.utc(2026, 8, 1),
);

BookReaderPage get _page => demoBookReaderPage('dune')!;

Future<void> _pumpReader(WidgetTester tester, {BookToc? toc}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  const padding = FakeViewPadding(top: _safeTop, bottom: _safeBottom);
  tester.view.viewPadding = padding;
  tester.view.padding = padding;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: BookReaderScreen(book: _book, page: _page, toc: toc),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _glyph(BookReaderGlyph glyph) => find.byWidgetPredicate((w) => w is BookReaderGlyphIcon && w.glyph == glyph);

/// The reading face, loaded from the repository so the page lays out here the
/// way it lays out in the app and in the golden.
///
/// Without it every assertion about the column would be about the test font's
/// square glyphs, and the one number that matters on this screen is where the
/// text lands. `assets/fonts/Literata-Variable.ttf` is the same file
/// `pubspec.yaml` ships and the same one the golden's source loads.
Future<void> _loadReadingFace() async {
  final bytes = File('assets/fonts/Literata-Variable.ttf').readAsBytesSync();
  final loader = FontLoader('Literata')..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadReadingFace();
  });

  group('the canonical state, 07a', () {
    testWidgets('draws the running head and the footer of the golden', (tester) async {
      await _pumpReader(tester);
      expect(find.text('DUNE · CHAPTER 12'), findsOneWidget);
      expect(find.text('48% · Page 248 of 616'), findsOneWidget);
    });

    testWidgets('lands the four bands on the golden\'s own numbers', (tester) async {
      await _pumpReader(tester);
      expect(tester.getTopLeft(find.byType(BookReaderRunningHead)).dy, 124);
      expect(tester.getTopLeft(find.byType(BookReaderColumn)).dy, 188);
      // The column's measure is wider than the chrome's margin: 32 against 24.
      expect(tester.getTopLeft(find.byType(BookReaderColumn)).dx, 32);
      expect(tester.getTopLeft(find.byType(BookReaderFoot)).dy, 752);
      // The back glyph is 24 on a 26 slot that starts at the chrome's own
      // margin of 24, so its box begins one point in from it.
      final back = tester.getRect(_glyph(BookReaderGlyph.back));
      expect(back.left, BookReaderLayout.chromeMargin + 1);
      expect(back.top, 66);
      expect(back.size, const Size(24, 24));
    });

    testWidgets('draws four glyphs and only one magnifier', (tester) async {
      await _pumpReader(tester);
      expect(find.byType(BookReaderGlyphIcon), findsNWidgets(4));
      expect(_glyph(BookReaderGlyph.search), findsOneWidget);
      expect(_glyph(BookReaderGlyph.bookmark), findsOneWidget);
    });

    /// The page comes from the fixture as a page and there is no pagination
    /// under it, so the one thing that has to hold is that it fits the band it
    /// is given. A page taller than its column would be silently clipped.
    testWidgets('the page fits between the running head and the footer', (tester) async {
      await _pumpReader(tester);
      final column = tester.getRect(find.byType(BookReaderColumn));
      expect(column.bottom, lessThanOrEqualTo(752));
      expect(tester.takeException(), isNull);
    });
  });

  group('07b, the chrome comes and goes and the page does not move', () {
    /// The one behaviour `07b` exists to prove. Measured on the rects rather
    /// than read off the tree: a page that repaginates when you touch it loses
    /// your place, and no assertion about widget structure would catch that.
    testWidgets('the column and the running head keep their exact rects', (tester) async {
      await _pumpReader(tester);
      final columnBefore = tester.getRect(find.byType(BookReaderColumn));
      final headBefore = tester.getRect(find.byType(BookReaderRunningHead));

      await tester.tapAt(const Offset(196, 650));
      await tester.pumpAndSettle();

      expect(find.byType(BookReaderFoot), findsNothing);
      expect(tester.getRect(find.byType(BookReaderColumn)), columnBefore);
      expect(tester.getRect(find.byType(BookReaderRunningHead)), headBefore);
    });

    testWidgets('the running head stays and the chrome goes', (tester) async {
      await _pumpReader(tester);
      expect(find.byType(BookReaderGlyphIcon), findsNWidgets(4));

      await tester.tapAt(const Offset(196, 650));
      await tester.pumpAndSettle();

      // The running head is the page's own header, the line a printed book
      // carries at the top of every page. It is not a control and it stays.
      expect(find.text('DUNE · CHAPTER 12'), findsOneWidget);
      expect(find.byType(BookReaderGlyphIcon), findsNothing);
      expect(find.byType(BookReaderFoot), findsNothing);

      await tester.tapAt(const Offset(196, 650));
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderGlyphIcon), findsNWidgets(4));
    });
  });

  group('the doors', () {
    testWidgets('the inhoudsopgave glyph pushes golden 06 as a page', (tester) async {
      await _pumpReader(tester, toc: demoBookToc('atomic-habits'));
      await tester.tap(_glyph(BookReaderGlyph.toc));
      await tester.pumpAndSettle();
      expect(find.byType(BooksTocScreen), findsOneWidget);
    });

    /// Drawn because the golden draws it, and inert for a publication that
    /// declares no navigation. The same treatment `Ga naar pagina` got in golden
    /// 06: the control keeps its slot and does not invent a destination.
    testWidgets('it opens nothing for a publication without navigation', (tester) async {
      await _pumpReader(tester);
      await tester.tap(_glyph(BookReaderGlyph.toc));
      await tester.pumpAndSettle();
      expect(find.byType(BooksTocScreen), findsNothing);
      expect(find.byType(BookReaderScreen), findsOneWidget);
    });

    /// `Zoeken in boek` is panel 9 and the bookmark model is not designed, so
    /// neither glyph goes anywhere. A tap on one of them falls through to the
    /// page and moves the chrome, which is what a control with no function yet
    /// should do rather than swallow the touch.
    testWidgets('the search and bookmark glyphs open nothing', (tester) async {
      await _pumpReader(tester);
      await tester.tap(_glyph(BookReaderGlyph.search));
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsOneWidget);
      expect(find.byType(BooksTocScreen), findsNothing);
    });
  });
}
