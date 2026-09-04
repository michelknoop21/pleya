import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/books/book_reader_layout.dart';
import 'package:pleya/books/book_reader_page.dart';
import 'package:pleya/books/book_reader_theme.dart';
import 'package:pleya/books/demo_book_reader.dart';
import 'package:pleya/books/reader_settings.dart';
import 'package:pleya/books/reader_typography.dart';

void main() {
  group('BookReaderPosition, the footer contract of approved golden 07', () {
    /// The footer rounds this down and the scrubber turns it into a width.
    /// `Positioned(width: width * progress)` trips
    /// `BoxConstraints.tightFor`'s `width >= 0` assert on a negative and throws
    /// during layout on a NaN, so a source that gets the range wrong takes the
    /// reader's page down with it. The range is held here instead.
    test('a value outside 0..1 is held to the range rather than passed on', () {
      expect(BookReaderPosition.withoutPageList(totalProgression: -0.4).totalProgression, 0);
      expect(BookReaderPosition.withoutPageList(totalProgression: 1.8).totalProgression, 1);
      expect(BookReaderPosition.withoutPageList(totalProgression: double.nan).totalProgression, 0);
      expect(BookReaderPosition.withoutPageList(totalProgression: double.infinity).totalProgression, 1);
      expect(BookReaderPosition.withoutPageList(totalProgression: double.negativeInfinity).totalProgression, 0);
    });

    test('a value inside the range is untouched', () {
      expect(BookReaderPosition.withoutPageList(totalProgression: 0.489).totalProgression, 0.489);
      expect(BookReaderPosition.withoutPageList(totalProgression: 0).totalProgression, 0);
      expect(BookReaderPosition.withoutPageList(totalProgression: 1).totalProgression, 1);
    });

    test('the percentage follows the held value, so it can never read -40% or 180%', () {
      expect(BookReaderPosition.withoutPageList(totalProgression: -0.4).percent, 0);
      expect(BookReaderPosition.withoutPageList(totalProgression: 1.8).percent, 100);
      expect(BookReaderPosition.withoutPageList(totalProgression: double.nan).percent, 0);
    });

    test('the percentage is always there and is rounded down', () {
      const position = BookReaderPosition.withoutPageList(totalProgression: 0.489);
      expect(position.percent, 48);
      expect(position.footerLabel, '48%');
    });

    test('a page-list with a reliable terminal label carries both numbers', () {
      final position = BookReaderPosition.fromPageList(
        totalProgression: 0.48,
        currentLabel: '248',
        terminalLabel: '616',
      );
      expect(position.footerLabel, '48% · Page 248 of 616');
    });

    test('a page-list without a terminal label names the page and stops', () {
      final position = BookReaderPosition.fromPageList(totalProgression: 0.48, currentLabel: '248');
      expect(position.totalPageLabel, isNull);
      expect(position.footerLabel, '48% · Page 248');
    });

    /// A `page-list` is allowed to run `xiv, xv, 1, 2, …`, and then there is no
    /// `N` to speak of. The label is still the publication's own, so it is
    /// shown; the total is not invented to go with it.
    test('a terminal label that is not a number yields no total', () {
      final position = BookReaderPosition.fromPageList(
        totalProgression: 0.48,
        currentLabel: 'xiv',
        terminalLabel: 'A-3',
      );
      expect(position.totalPageLabel, isNull);
      expect(position.footerLabel, '48% · Page xiv');
    });

    /// The rule golden 05 and golden 06 both set, here as something the type
    /// system carries: there is no constructor that takes a page count.
    test('the fixture takes both numbers from the page-list', () {
      final page = demoBookReaderPage('dune')!;
      expect(page.position.pageLabel, '248');
      expect(page.position.totalPageLabel, '616');
      expect(page.position.footerLabel, '48% · Page 248 of 616');
    });

    test('a publication the fixture cannot open a page of answers null', () {
      expect(demoBookReaderPage('atomic-habits'), isNull);
    });
  });

  group('BookReaderPage.runningHead', () {
    test('composes the title and the chapter, upper-cased', () {
      expect(demoBookReaderPage('dune')!.runningHead, 'DUNE · CHAPTER 12');
    });

    test('a page in no numbered chapter carries the title alone', () {
      const page = BookReaderPage(
        bookTitle: 'Dune',
        paragraphs: [],
        position: BookReaderPosition.withoutPageList(totalProgression: 0),
      );
      expect(page.runningHead, 'DUNE');
    });
  });

  group('ReaderTypography, the cut approved golden 07 was drawn in', () {
    FontVariation variation(TextStyle style, String axis) => style.fontVariations!.firstWhere((v) => v.axis == axis);

    /// The regression check the approval asks for. Naming the family is not the
    /// same as drawing the golden: Literata is variable, Flutter applies no
    /// optical sizing of its own, and an unset `opsz` leaves the page in a cut
    /// meant for footnotes.
    test('the canonical style is Literata at 18 on 28, wght 400, opsz 18', () {
      final style = ReaderTypography.canonical(const Color(0xFF2A2117));
      expect(style.fontFamily, 'Literata');
      expect(style.fontSize, 18);
      expect(style.height, 28 / 18);
      expect(variation(style, 'wght').value, 400);
      expect(variation(style, 'opsz').value, 18);
    });

    /// The bug this caught: a `Text` merges the ambient `DefaultTextStyle` into
    /// its own, and the app's text theme carries Material's `letterSpacing: 0.3`.
    /// Interface tracking on a page of prose ran the reader's first line 11,7
    /// points wider than the approved golden, with the same words and the same
    /// breaks. A reading page inherits nothing.
    test('the reading style inherits nothing from the interface', () {
      final style = ReaderTypography.canonical(const Color(0xFF2A2117));
      expect(style.inherit, isFalse);
      expect(style.letterSpacing, 0);
      expect(style.wordSpacing, 0);
      // Half-leading, the way CSS distributes what a line band adds over the
      // font's own ascent and descent.
      expect(style.leadingDistribution, TextLeadingDistribution.even);
    });

    /// Not a promise that every future setting stays at 18. When a reader picks
    /// a larger size the optical size travels with it, which is the whole point
    /// of the axis; whether that coupling is automatic or steered is golden 08.
    test('optical size follows the reading size unless it is steered', () {
      final larger = ReaderTypography.styleFor(colour: const Color(0xFF000000), size: 22);
      expect(variation(larger, 'opsz').value, 22);

      final steered = ReaderTypography.styleFor(colour: const Color(0xFF000000), size: 22, opticalSize: 18);
      expect(variation(steered, 'opsz').value, 18);
    });
  });

  group('BookReaderLayout, measured on 07a', () {
    /// The frame the golden was shot on: 393 × 852, a top inset of 59 and a
    /// bottom inset of 34.
    const viewPadding = EdgeInsets.only(top: 59, bottom: 34);
    const frame = Size(393, 852);

    test('the chrome sits on 62 and the running head on 124', () {
      final chromeTop = BookReaderLayout.chromeTopFor(viewPadding);
      expect(chromeTop, 62);
      expect(chromeTop + BookReaderLayout.runningHeadTop, 124);
    });

    test('the column starts on 188', () {
      expect(BookReaderLayout.chromeTopFor(viewPadding) + BookReaderLayout.columnTop, 188);
    });

    test('the footer block starts on 752 and its label ends on 804', () {
      final footTop = BookReaderLayout.footTopFor(frame, viewPadding);
      expect(footTop, 752);
      expect(footTop + BookReaderLayout.footHeight, 804);
    });
  });

  group('ReaderSettings, the stops of approved golden 08', () {
    /// Each scale carries the state golden 07 was approved in, so the reader's
    /// own default is a stop and not a special case.
    test('the canonical state is golden 07', () {
      const settings = ReaderSettings.canonical;
      expect(settings.size, 18);
      expect(settings.lineHeight, 28);
      expect(settings.margin, 32);
      expect(settings.themeId, BookReaderThemeId.sepia);
    });

    test('the six sizes, three bands and four measures are the golden\'s own', () {
      expect(ReaderSettings.sizes, [15, 16.5, 18, 20, 22, 24]);
      expect(ReaderSettings.margins, [20, 26, 32, 40]);
      expect(ReaderSettings.leadings[1], 28 / 18);
      expect(ReaderSettings.leadings.first, lessThan(ReaderSettings.leadings[1]));
      expect(ReaderSettings.leadings.last, greaterThan(ReaderSettings.leadings[1]));
    });

    /// A third of a line more than the type size: golden 07's 24 on 18 and
    /// golden 08b's 32 on 24, from one rule rather than two numbers.
    test('the paragraph space travels with the type size', () {
      expect(const ReaderSettings().paragraphGap, 24);
      expect(const ReaderSettings(sizeIndex: 5).paragraphGap, 32);
    });

    /// Drawn and inert, and golden 08 leaves what it turns on open. A constant
    /// rather than a field, so nothing can set it by accident.
    test('the scroll mode cannot be turned on', () {
      expect(ReaderSettings.scrollMode, isFalse);
    });
  });

  group('BookReaderTheme, the shape specification of 07c', () {
    test('the three grounds, inks and marks are the golden\'s own', () {
      expect(BookReaderTheme.light.page, const Color(0xFFFFFFFF));
      expect(BookReaderTheme.light.mark, const Color(0xFFFFE9A8));
      expect(BookReaderTheme.sepia.page, const Color(0xFFF0E5D7));
      expect(BookReaderTheme.sepia.ink, const Color(0xFF2A2117));
      expect(BookReaderTheme.sepia.mark, const Color(0xFFFDDF9E));
      // The app's own non-OLED ground, so a dark reader lands on the surface
      // the rest of Pleya uses rather than on a second, nearly identical black.
      expect(BookReaderTheme.dark.page, const Color(0xFF141414));
    });

    test('only the dark theme asks for a light status bar', () {
      expect(BookReaderTheme.light.wantsLightStatusBar, isFalse);
      expect(BookReaderTheme.sepia.wantsLightStatusBar, isFalse);
      expect(BookReaderTheme.dark.wantsLightStatusBar, isTrue);
    });
  });
}
