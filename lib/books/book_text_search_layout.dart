import 'package:flutter/painting.dart';

/// Golden 09's geometry, as measured on `09a-books-search-in-book.png` and its
/// source (`docs/assets/ebooks/northstar/src/09-books-search-in-book/`).
///
/// The same shape as `BookTocLayout`: a table of constants and one function that
/// predicts where every row lands, so the widget test and the widget read the
/// same numbers.
///
/// Almost nothing here is new. The header band is golden 06's, the field is the
/// one golden 04 measured off `05-zoeken.png`, the count sits on the band golden
/// 04 gives its chip row, and the card is golden 04's result card. What golden 09
/// adds is the row: two heights rather than one, because an excerpt is a window
/// and a window is not always two lines long.
class BookTextSearchLayout {
  const BookTextSearchLayout._();

  /// The frame the golden was drawn on: 393 × 852.
  static const double pageMargin = 16;

  /// The pushed-page header of golden 06: one back glyph on 16, the title on 56,
  /// the band 62 to 94. Not the comp's `Annuleer` beside the field — the two
  /// glyphs of the reader's chrome would otherwise open two different kinds of
  /// screen.
  static const double headerTop = 62;
  static const double headerHeight = 32;

  /// The field of `05-zoeken.png`: 16 pt margins, 36 tall, top on 109. The same
  /// object as golden 04's, so it keeps the same geometry.
  static const double fieldTop = 109;
  static const double fieldHeight = 36;
  static const double fieldRadius = 10;
  static const double fieldPadding = 16;
  static const double fieldGap = 12;
  static const double fieldGlyph = 17;

  /// `12 resultaten gevonden`, on the band golden 04 gives its chip row and
  /// golden 02 its `128 boeken`. There are no chips here: one publication
  /// returns one kind of thing, and a chip row with one chip is not a filter.
  static const double countTop = 161;
  static const double countHeight = 18;
  static const double countSize = 13;

  static const double cardTop = 191;
  static const double cardRadius = 12;

  /// A row is its padding, its location line, the gap, and one or two lines of
  /// excerpt. 14 + 18 + 3 + 21 + 14 = 70, and 91 with the second line.
  static const double rowPaddingVertical = 14;
  static const double rowPaddingHorizontal = 16;
  static const double locationHeight = 18;
  static const double locationSize = 13;
  static const double excerptGap = 3;
  static const double excerptLineHeight = 21;
  static const double excerptSize = 15;

  /// Two, and the second one clips. A fixed two-line row would give a short
  /// excerpt an empty line; golden 09b puts the three cases under each other to
  /// settle exactly that.
  static const int excerptMaxLines = 2;

  static const double oneLineRowHeight = 70;
  static const double twoLineRowHeight = 91;

  /// The hairline between rows, inset 16 from the card's left edge and running
  /// to its right one. Drawn inside the row's own top edge, so it adds nothing
  /// to the height.
  static const double hairlineInset = 16;
  static const double hairlineThickness = 1;

  static const Color surface = Color(0xFF1F1F1F);
  static const Color hairline = Color(0xFF2E2E2E);

  /// The amber the reader already owns. Golden 07 sets its dark-theme highlight
  /// on `rgba(245,197,66,.26)`; this is that colour as ink rather than as fill.
  /// One amber in the product, two forms — a filled block here would say the
  /// reader had marked the passage themselves.
  static const Color match = Color(0xFFF5C542);

  static double heightFor(int excerptLines) => excerptLines >= excerptMaxLines ? twoLineRowHeight : oneLineRowHeight;

  /// Where every row lands, measured from the top of the frame, given how many
  /// lines each row's excerpt takes.
  ///
  /// The prediction the widget is held against. With golden 09a's twelve results
  /// it reproduces the frame: the first row on 191, the second (the only
  /// one-line excerpt in the set) from 282 to 352, the eighth on 807 where the
  /// bottom edge cuts it, and a list 1071 tall in a window that shows 661.
  static List<double> positions(List<int> excerptLines) {
    final tops = <double>[];
    var cursor = cardTop;
    for (final lines in excerptLines) {
      tops.add(cursor);
      cursor += heightFor(lines);
    }
    return tops;
  }

  static double cardHeight(List<int> excerptLines) => excerptLines.fold(0, (total, lines) => total + heightFor(lines));
}
