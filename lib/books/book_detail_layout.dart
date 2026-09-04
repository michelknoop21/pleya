import 'package:flutter/foundation.dart';

/// The blocks the detail page stacks under the cover, in the order approved
/// golden 05 puts them.
///
/// Progress is one block rather than two lines: the golden's own source hangs
/// `48% gelezen` and `Hoofdstuk 12` with no space between them, and a book
/// either has both or neither.
enum BookDetailBlock { title, author, series, progress, primary, secondary, stats, description }

/// One entry in the column: the space above it, and how tall it is.
@immutable
class BookDetailBlockMetrics {
  /// The space between the block above and this one. It belongs to this block,
  /// which is the whole point: a book that has no series loses the series line
  /// **and** the 2 pt above it, so everything below moves up by exactly what is
  /// missing.
  final double gapAbove;

  /// The block's own height with the fixture's single-line text. Text that
  /// wraps grows the real widget, and everything under it moves down with it;
  /// this is the number the golden was drawn on and the one [positions]
  /// predicts against.
  final double height;

  const BookDetailBlockMetrics({required this.gapAbove, required this.height});
}

/// Golden 05's geometry, as measured on `05a-book-detail.png` and its source.
///
/// The column under the cover is a sequence of elements that each own the space
/// above them. Nothing here stretches to fill a gap: when a book has no series
/// or no progress, the space they took lands as air at the bottom of the page
/// rather than being spread through the column. `05b` is that rule's evidence
/// and `05c` shows both states of the action block side by side.
class BookDetailLayout {
  const BookDetailLayout._();

  /// The frame the golden was drawn on.
  static const double pageMargin = 16;

  /// The header band: back and overflow, and no title — the comp puts none
  /// there, and the title stands 270 pt lower in 30 pt bold.
  static const double headerTop = 62;
  static const double headerHeight = 32;

  static const double coverTop = 104;
  static const double coverWidth = 150;
  static const double coverHeight = 225;
  static const double coverRadius = 10;

  /// 150 x 225 is 2:3, the ratio golden 02 fixed for the grid, at the width
  /// golden 01b gave a Boekenseries card.
  static const double coverBottom = coverTop + coverHeight;

  static const double actionHeight = 48;
  static const double actionRadius = 24;
  static const double statsHeight = 40;

  /// How many lines of blurb, in both states. Three is what fits above the bar
  /// in the state that carries progress, and it does not grow in the state that
  /// does not: an unstarted book gets air at the bottom, not a longer summary.
  static const int descriptionMaxLines = 3;

  static const double descriptionLineHeight = 21;

  static const Map<BookDetailBlock, BookDetailBlockMetrics> flow = {
    BookDetailBlock.title: BookDetailBlockMetrics(gapAbove: 20, height: 36),
    BookDetailBlock.author: BookDetailBlockMetrics(gapAbove: 4, height: 22),
    BookDetailBlock.series: BookDetailBlockMetrics(gapAbove: 2, height: 18),
    // 20 for the percentage, 18 for the chapter, and no space between them.
    // A source that reports progress without a chapter draws one line and the
    // column closes over the other by the same rule as a missing block.
    BookDetailBlock.progress: BookDetailBlockMetrics(gapAbove: 10, height: 38),
    BookDetailBlock.primary: BookDetailBlockMetrics(gapAbove: 24, height: actionHeight),
    BookDetailBlock.secondary: BookDetailBlockMetrics(gapAbove: 10, height: actionHeight),
    BookDetailBlock.stats: BookDetailBlockMetrics(gapAbove: 20, height: statsHeight),
    BookDetailBlock.description: BookDetailBlockMetrics(
      gapAbove: 20,
      height: descriptionMaxLines * descriptionLineHeight,
    ),
  };

  /// Where every present block lands, measured from the top of the frame.
  ///
  /// The prediction the widget is held against: with everything present it
  /// reproduces the numbers read off `05a` (title 349, pills 503 and 561, stats
  /// 629, description 689), and with a block left out everything below it moves
  /// up by that block's height plus its own gap.
  static Map<BookDetailBlock, double> positions({required Set<BookDetailBlock> present}) {
    final tops = <BookDetailBlock, double>{};
    var cursor = coverBottom;
    for (final entry in flow.entries) {
      if (!present.contains(entry.key)) continue;
      cursor += entry.value.gapAbove;
      tops[entry.key] = cursor;
      cursor += entry.value.height;
    }
    return tops;
  }
}
