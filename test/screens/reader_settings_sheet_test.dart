import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/book_reader_page.dart';
import 'package:pleya/books/book_reader_theme.dart';
import 'package:pleya/books/demo_book_reader.dart';
import 'package:pleya/books/reader_settings.dart';
import 'package:pleya/screens/books/book_reader_screen.dart';
import 'package:pleya/screens/books/widgets/book_reader_chrome.dart';
import 'package:pleya/screens/books/widgets/reader_settings_sheet.dart';

/// The frame approved golden 08 was drawn on, and its insets.
const Size _viewport = Size(393, 852);
const double _safeTop = 59;
const double _safeBottom = 34;

final _book = Book(
  id: 'dune',
  title: 'Dune',
  author: 'Frank Herbert',
  artwork: const BookArtwork(base: Color(0xFF1B1B1B), accent: Color(0xFFE5140F), ink: Color(0xFFF4F2EC)),
  addedAt: DateTime.utc(2026, 8, 1),
);

BookReaderPage get _page => demoBookReaderPage('dune')!;

Future<void> _loadReadingFace() async {
  final bytes = File('assets/fonts/Literata-Variable.ttf').readAsBytesSync();
  await (FontLoader('Literata')..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

Future<void> _pumpReader(WidgetTester tester) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  const padding = FakeViewPadding(top: _safeTop, bottom: _safeBottom);
  tester.view.viewPadding = padding;
  tester.view.padding = padding;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: BookReaderScreen(book: _book, page: _page),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate((w) => w is BookReaderGlyphIcon && w.glyph == BookReaderGlyph.settings));
  await tester.pumpAndSettle();
}

/// One group of the sheet, addressed by the instance its automation node
/// carries, so a tap is aimed at a measured rect rather than at a coordinate
/// counted out by hand.
Rect _groupRect(WidgetTester tester, String instance) =>
    tester.getRect(find.byWidgetPredicate((w) => w is AutomationNode && w.instance == instance));

/// The style the page is actually drawn in, read off the render tree rather than
/// off the settings object: what this screen has to get right is the type on the
/// page, not the value in a field.
TextStyle _pageStyle(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byType(BookReaderColumn), matching: find.byType(RichText)).first,
  );
  return paragraph.text.style!;
}

double _axis(TextStyle style, String axis) => style.fontVariations!.firstWhere((v) => v.axis == axis).value;

int _paragraphCount(WidgetTester tester) =>
    find.descendant(of: find.byType(BookReaderColumn), matching: find.byType(RichText)).evaluate().length;

/// The rail runs between the two specimens: 14 for the small `A` and 14 of gap
/// on the left, 14 of gap and 20 for the large one on the right. Its far end is
/// the last stop, and the tap lands just inside it because a hit test is
/// exclusive at the right edge.
Future<void> _tapLargestSize(WidgetTester tester) async {
  final group = _groupRect(tester, 'size');
  await tester.tapAt(Offset(group.right - 35, group.bottom - 16));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadReadingFace();
  });

  group('the door, approved with golden 08', () {
    testWidgets('`Aa` opens the sheet and the sheet names its five groups', (tester) async {
      await _pumpReader(tester);
      expect(find.byType(ReaderSettingsSheet), findsNothing);

      await _openSheet(tester);

      expect(find.byType(ReaderSettingsSheet), findsOneWidget);
      expect(find.text('Reading settings'), findsOneWidget);
      for (final label in ['Text size', 'Line spacing', 'Margins', 'Theme', 'Scroll mode']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    /// The sheet has no scrim and does not cover the page: you are setting the
    /// text you are reading. Measured on the column's own rect, because "the
    /// widget is still mounted" would also be true under a black scrim.
    testWidgets('the page keeps its place and stays visible under the sheet', (tester) async {
      await _pumpReader(tester);
      final before = tester.getRect(find.byType(BookReaderColumn));

      await _openSheet(tester);

      expect(tester.getRect(find.byType(BookReaderColumn)), before);
      expect(find.text('DUNE · CHAPTER 12'), findsOneWidget);
      // The sheet's own top edge, on the frame the golden was drawn on.
      expect(
        tester.getTopLeft(find.byType(ReaderSettingsSheet)).dy,
        852 - ReaderSettingsSheet.contentHeight - _safeBottom,
      );
    });
  });

  group('what the settings do to the page', () {
    testWidgets('the canonical state is golden 07: 18 on 28, opsz 18, margin 32', (tester) async {
      await _pumpReader(tester);
      final style = _pageStyle(tester);
      expect(style.fontSize, 18);
      expect(style.height, 28 / 18);
      expect(_axis(style, 'opsz'), 18);
      expect(tester.getTopLeft(find.byType(BookReaderColumn)).dx, 32);
      expect(_paragraphCount(tester), 4);
    });

    /// The proposal golden 08 makes and Michel approved: the optical-size axis
    /// travels with the type size. At 24 points a page set in the cut for 18
    /// would be a text face doing work it was not drawn for.
    testWidgets('the largest stop takes the optical size with it', (tester) async {
      await _pumpReader(tester);
      await _openSheet(tester);

      await _tapLargestSize(tester);

      final style = _pageStyle(tester);
      expect(style.fontSize, 24);
      expect(_axis(style, 'opsz'), 24);
      expect(style.height, ReaderSettings.leadings[1]);
    });

    /// What approved golden 08b draws: at 24 points three of golden 07's four
    /// paragraphs land on the page and the marked one belongs to a page that does
    /// not exist yet. Measured rather than estimated: 259, 148 and 74 points of
    /// text with 32 between them is 545 in a column of 564, and the fourth would
    /// need 111 more. The first cut of that frame stopped a paragraph too early
    /// and was corrected against these numbers.
    testWidgets('a larger type leaves fewer paragraphs on the page', (tester) async {
      await _pumpReader(tester);
      await _openSheet(tester);

      await _tapLargestSize(tester);

      expect(_paragraphCount(tester), 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the theme changes the ground the page is printed on', (tester) async {
      await _pumpReader(tester);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, BookReaderTheme.sepia.page);

      await _openSheet(tester);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, BookReaderTheme.dark.page);
    });

    testWidgets('a wider measure moves the column in', (tester) async {
      await _pumpReader(tester);
      await _openSheet(tester);

      // The fourth cell of the margins row, which is the 40 pt measure.
      final group = _groupRect(tester, 'margins');
      final cell = (group.width - 24) / 4;
      await tester.tapAt(Offset(group.left + 3 * (cell + 8) + cell / 2, group.bottom - 18));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byType(BookReaderColumn)).dx, 40);
    });

    /// Drawn and inert. Vertical scrolling instead of turning pages is a second
    /// reading mode with its own page shape, and golden 08 leaves what the switch
    /// turns on open.
    testWidgets('the scroll switch does not move', (tester) async {
      await _pumpReader(tester);
      await _openSheet(tester);
      final before = _paragraphCount(tester);

      final group = _groupRect(tester, 'scroll');
      await tester.tapAt(Offset(group.right - 25, group.top + 15));
      await tester.pumpAndSettle();

      expect(ReaderSettings.scrollMode, isFalse);
      expect(_paragraphCount(tester), before);
      expect(find.byType(ReaderSettingsSheet), findsOneWidget);
    });
  });
}
