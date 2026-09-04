import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book.dart';
import 'package:pleya/books/reader_settings.dart';
import 'package:pleya/screens/books/widgets/book_rail.dart';
import 'package:pleya/screens/books/widgets/reader_settings_sheet.dart';

/// Two tile budgets on the Boeken screens were written as the constant that
/// happens to be right at text scale 1.0, with a `Column` of text inside it.
/// Nothing in `lib/` clamps `textScaler`, so iOS Larger Text and Android
/// "Groot" arrive at full strength and the column asks for more than the box
/// gives: a `RenderFlex` overflow, striped in debug and silently clipped in
/// release.
///
/// 1.15 is the modest end of both settings, not the extreme; if the geometry
/// survives that it survives the common case. 1.0 is asserted alongside it,
/// because the number the approved goldens were measured with has to be the
/// number these still produce.
const Size _viewport = Size(393, 852);

Future<void> _pump(WidgetTester tester, Widget child, {required double scale}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: _viewport, textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _artwork = BookArtwork(base: Color(0xFF3A1A0B), accent: Color(0xFFE08A3C), ink: Color(0xFFF7E2C6));

final _items = [
  for (var i = 0; i < 3; i++)
    BookRailItem(id: 'b$i', artwork: _artwork, title: 'Boek $i', subtitle: 'Een schrijver met een lange naam'),
];

void main() {
  group('a rail tile on Boeken-home', () {
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('lays out without overflowing at text scale $scale', (tester) async {
        await _pump(tester, BookRail(items: _items), scale: scale);

        expect(
          tester.takeException(),
          isNull,
          reason: 'every tile of every rail on Boeken-home overflows when the budget ignores the scaler',
        );
      });
    }

    testWidgets('reserves exactly what the caption asks for, and 42 at scale 1.0', (tester) async {
      for (final scale in [1.0, 1.15, 1.3]) {
        await _pump(tester, BookRail(items: _items), scale: scale);
        final context = tester.element(find.byType(BookRail));

        final caption = BookRailMetrics.captionExtentFor(context);
        final needed =
            BookRailMetrics.coverCaptionGap +
            scale * BookRailMetrics.titleFontSize * BookRailMetrics.captionLineHeight +
            scale * BookRailMetrics.subtitleFontSize * BookRailMetrics.captionLineHeight;

        expect(caption, greaterThanOrEqualTo(needed), reason: 'the two caption lines have to fit at scale $scale');
        if (scale == 1.0) {
          expect(caption, 42, reason: 'golden 01b was measured on 42 and still is');
        }
        expect(
          tester.getSize(find.byType(BookRail)).height,
          BookRailMetrics.coverHeight + caption,
          reason: 'the rail reserves the cover plus that caption, nothing else',
        );
      }
    });
  });

  group('a theme tile in Leesinstellingen', () {
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('lays out without overflowing at text scale $scale', (tester) async {
        final settings = ValueNotifier(const ReaderSettings());
        addTearDown(settings.dispose);

        await _pump(
          tester,
          ReaderSettingsSheet(settings: settings, onChanged: (value) => settings.value = value),
          scale: scale,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'the three theme discs overflow their column as soon as the caption outgrows the budget',
        );
      });
    }

    testWidgets('the control grows with its caption, and is 66 at scale 1.0', (tester) async {
      for (final scale in [1.0, 1.15, 1.3]) {
        final settings = ValueNotifier(const ReaderSettings());
        addTearDown(settings.dispose);
        await _pump(
          tester,
          ReaderSettingsSheet(settings: settings, onChanged: (value) => settings.value = value),
          scale: scale,
        );
        final context = tester.element(find.byType(ReaderSettingsSheet));

        final height = ReaderSettingsSheet.themeControlHeightFor(context);
        final needed =
            ReaderSettingsSheet.themeDiscSize +
            ReaderSettingsSheet.themeCaptionGap +
            scale * ReaderSettingsSheet.themeCaptionFontSize * ReaderSettingsSheet.themeCaptionLineHeight;

        expect(height, greaterThanOrEqualTo(needed), reason: 'disc, gap and caption have to fit at scale $scale');
        if (scale == 1.0) {
          expect(height, 66, reason: 'golden 08 was measured on 66 and still is');
        }
        // Golden 08 leaves room between this group and the rule under it. The
        // growth has to stay inside that, or the sheet starts rewriting a
        // layout that was approved rather than absorbing a text setting.
        expect(
          ReaderSettingsSheet.groupTops.last + ReaderSettingsSheet.controlOffset + height,
          lessThanOrEqualTo(ReaderSettingsSheet.ruleTop),
          reason: 'the taller control still clears the rule at scale $scale',
        );
      }
    });
  });
}
