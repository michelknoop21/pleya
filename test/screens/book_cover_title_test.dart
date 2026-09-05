import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/screens/books/widgets/book_cover.dart';

/// A cover title may wrap between its words and may not break inside one.
///
/// Golden 02 rejected `CHILDRE / N OF / DUNE` once, and the fix made the size
/// follow the title's length. That answers how many lines a title needs; it does
/// not answer whether a word fits one of them. `De Alchemist` is twelve glyphs,
/// so it kept 16 pt and the wide letter-spacing an orb title gets, and the shelf
/// drew `DE ALCH / EMIST`. This is the check that keeps the second question
/// answered too.
///
/// The real Inter is loaded, because the fit is a font metric: the test font
/// draws every glyph a full em wide and would make every title overflow.
const Size _viewport = Size(393, 852);

/// One cell of golden 02's grid: 393 less two 16 pt margins and two 10 pt gaps,
/// over three columns.
const double _gridTile = (393 - 32 - 20) / 3;

const _orb = BookArtwork(
  base: Color(0xFF3A1A0B),
  accent: Color(0xFFE08A3C),
  ink: Color(0xFFF7E2C6),
  shape: BookArtworkShape.orb,
);

Future<void> _loadInterfaceFace() async {
  final loader = FontLoader('Inter');
  for (final name in ['Inter-Regular.otf', 'Inter-Medium.otf', 'Inter-Bold.otf']) {
    final bytes = File('assets/fonts/$name').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<Text> _pumpCover(WidgetTester tester, String title, {double width = _gridTile, double scale = 1.0}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter')),
      home: MediaQuery(
        data: MediaQueryData(size: _viewport, textScaler: TextScaler.linear(scale)),
        // Under a `Scaffold`, the way every books screen sits: that is what puts
        // the theme's Inter in the ambient `DefaultTextStyle` the cover reads
        // its face from.
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: width * 3 / 2,
              child: BookCover(artwork: _orb, title: title),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<Text>(find.text(title.toUpperCase()));
}

/// How many lines the title actually takes, laid out exactly as the cover lays
/// it out, and whether any of them ends inside a word.
({int lines, bool breaksAWord}) _layout(Text text, double width, {double scale = 1.0}) {
  final painter = TextPainter(
    text: TextSpan(text: text.data, style: text.style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: text.maxLines,
    textScaler: TextScaler.linear(scale),
  )..layout(maxWidth: width);
  final lines = painter.computeLineMetrics().length;
  // A word is broken when a line boundary lands between two non-space
  // characters. `getLineBoundary` at the start of each line but the first gives
  // that boundary back out of the same layout.
  var broken = false;
  for (var i = 1; i < lines; i++) {
    final metrics = painter.computeLineMetrics()[i];
    final offset = painter.getPositionForOffset(Offset(metrics.left + 0.5, metrics.baseline - metrics.ascent + 1));
    final at = offset.offset;
    if (at > 0 && at < text.data!.length) {
      final before = text.data![at - 1];
      final here = text.data![at];
      if (before.trim().isNotEmpty && here.trim().isNotEmpty) broken = true;
    }
  }
  painter.dispose();
  return (lines: lines, breaksAWord: broken);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadInterfaceFace();
  });

  group('a cover title wraps between words, never inside one', () {
    // The shelf of golden 02, every title that has to fit a grid cell.
    const titles = [
      'Dune',
      '1984',
      'Sapiens',
      'De Hobbit',
      'De Alchemist',
      'Atomic Habits',
      'Dune Messiah',
      'Brave New World',
      'Children of Dune',
      'Project Hail Mary',
      'De Zeven Zussen',
      'De ontdekking van de hemel',
    ];

    for (final title in titles) {
      testWidgets('$title fits the grid cell without breaking a word', (tester) async {
        final text = await _pumpCover(tester, title);
        final result = _layout(text, _gridTile - 16);

        expect(result.breaksAWord, isFalse, reason: '$title breaks inside a word');
        expect(result.lines, lessThanOrEqualTo(3), reason: '$title needs more than the three lines it gets');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the fit only shrinks what has to shrink', () {
    testWidgets('a title whose longest word already fits keeps the size the length table gives it', (tester) async {
      // Four glyphs, so the table's largest step, and `DUNE` is well inside the
      // measure: nothing to correct. Pumped at the reference cover, where the
      // cover's own scale is 1 and the size is the table's own number.
      final text = await _pumpCover(tester, 'Dune', width: 110);
      expect(text.style!.fontSize, 24);
      expect(text.style!.letterSpacing, 2.4);
    });

    testWidgets('De Alchemist is stepped down from the 16 the table gives it', (tester) async {
      final text = await _pumpCover(tester, 'De Alchemist', width: 110);
      expect(text.style!.fontSize, lessThan(16));
      // And the letter-spacing comes down with it: it is part of a word's set
      // width, so leaving it would undo the correction.
      expect(text.style!.letterSpacing, lessThan(2.4));
    });
  });

  group('the fit follows the cover and the reader', () {
    testWidgets('a rail cover and a grid cover are the same design at two sizes', (tester) async {
      final grid = await _pumpCover(tester, 'De Alchemist');
      final rail = await _pumpCover(tester, 'De Alchemist', width: 110);

      // Type scales with the cover, so the ratio holds rather than the number.
      expect(grid.style!.fontSize! / _gridTile, closeTo(rail.style!.fontSize! / 110, 0.001));
    });

    testWidgets('Larger Text does not put the title back through the edge', (tester) async {
      for (final scale in [1.0, 1.15, 1.3]) {
        final text = await _pumpCover(tester, 'De Alchemist', scale: scale);
        final result = _layout(text, _gridTile - 16, scale: scale);
        expect(result.breaksAWord, isFalse, reason: 'breaks inside a word at text scale $scale');
      }
    });
  });
}
