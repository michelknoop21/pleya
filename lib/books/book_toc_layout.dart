import 'package:flutter/painting.dart';

import 'book_toc_view.dart';

/// Golden 06's geometry, as measured on `06a-books-toc.png` and its source
/// (`docs/assets/ebooks/northstar/src/06-books-toc/toc.html`).
///
/// The same shape as `BookDetailLayout` with one difference that matters: the
/// detail page is a fixed sequence of blocks, and this list is variable. So the
/// table here is per **row kind** rather than per block, and [positions] walks
/// whatever rows the tree currently draws. Prediction and implementation read
/// the same table, which is the point of having one.
///
/// None of the numbers were invented. A book row is golden 04's book result
/// (82, cover 44 × 66). A part is the two-line row of `14-instellingen.png`,
/// measured at 60.7 and set to 61. A loose entry is the 47.5 option row of
/// `04-filters-sheet.png`. A chapter is 44, the smallest row iOS lets you tap.
class BookTocLayout {
  const BookTocLayout._();

  /// The frame the golden was drawn on: 393 × 852.
  static const double pageMargin = 16;

  /// The header band every screen in the set holds, back arrow at 16 and the
  /// title at 56. One dismiss glyph, and the title left of it rather than
  /// centred: this reads as a pushed page.
  static const double headerTop = 62;
  static const double headerHeight = 32;

  /// Where the card starts — the band golden 05 gives its cover.
  static const double cardTop = 104;
  static const double cardRadius = 12;

  static const double bookRowHeight = 82;
  static const double entryRowHeight = 47.5;
  static const double partRowHeight = 61;
  static const double chapterRowHeight = 44;

  /// How far a chapter's text sits in from the text of the layer above it.
  /// Two levels only: three indents on 393 pt turns a margin into a maze, so
  /// anything nested deeper collapses onto its chapter.
  static const double chapterIndent = 28;

  /// Where a chapter's marker sits, measured from the card's left edge: in the
  /// indent gutter between the page margin and the chapter's own text, so it
  /// reads as a mark in the margin rather than a bullet in the list.
  static const double chapterMarkerLeft = 28;
  static const double markerSize = 6;

  /// A hairline starts past the text inset and runs to the card's right edge,
  /// the way the set insets a separator. It is drawn **inside** the row's own
  /// top edge and adds nothing to its height: every row is exactly the height
  /// its kind says.
  static const double hairlineInset = 16;
  static const double hairlineThickness = 1;

  static const double coverWidth = 44;
  static const double coverHeight = 66;
  static const double coverRadius = 5;

  /// Between the cover and the text on the book row, and between the text and
  /// the chevron on a part.
  static const double coverGap = 15;
  static const double rowGap = 12;

  static const double chevronSize = 18;

  /// The action bar golden 03 approved for the filter sheet, to the point: a
  /// hairline, 15 pt, a 40 pt row, then the home indicator's room. On the
  /// golden's 34 pt bottom inset that is the measured 97, with the hairline on
  /// 755 and the pill from 771.
  ///
  /// Fixed rather than the last row of the card, because a table of contents is
  /// long and a jump control that scrolls away with the list is one you cannot
  /// reach from where you need it.
  static const double actionRowTop = 15;
  static const double actionRowHeight = 40;

  /// Seven and not the filter sheet's eight. Everything above this is golden
  /// 03's bar unchanged; with eight the whole band sits one point high — the
  /// hairline on 754 and the pill on 770 rather than golden 06's own 755 and
  /// 771. The point comes off the space under the pill, where nothing is drawn.
  static const double actionRowGap = 7;
  static const double actionPillRadius = actionRowHeight / 2;

  static const Color surface = Color(0xFF1F1F1F);
  static const Color hairline = Color(0xFF2E2E2E);
  static const Color pill = Color(0xFF2F2F2F);

  static double heightOf(BookTocRowKind kind) => switch (kind) {
    BookTocRowKind.book => bookRowHeight,
    BookTocRowKind.entry => entryRowHeight,
    BookTocRowKind.part => partRowHeight,
    BookTocRowKind.chapter => chapterRowHeight,
  };

  /// Where every row lands, measured from the top of the frame.
  ///
  /// The prediction the widget is held against. With golden 06a's tree it
  /// reproduces the numbers read off the frame: the book row 104 to 186, the
  /// introduction to 233.5, the four parts on 233.5, 294.5, 355.5 and 416.5,
  /// the open part's chapters from 477.5 on a 44 pt pitch, and the conclusion
  /// from 775.5 to 823 — under a bar that starts on 755, because the card ends
  /// where its content ends and nothing is shortened to make it fit.
  static List<double> positions(List<BookTocRow> rows) {
    final tops = <double>[];
    var cursor = cardTop;
    for (final row in rows) {
      tops.add(cursor);
      cursor += heightOf(row.kind);
    }
    return tops;
  }

  /// How tall the card is with these rows in it.
  static double cardHeight(List<BookTocRow> rows) => rows.fold(0, (total, row) => total + heightOf(row.kind));
}
