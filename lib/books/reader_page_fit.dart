import 'package:flutter/painting.dart';

import 'book_reader_page.dart';

/// How much of a page fits in the column it is given.
///
/// **This is not pagination and does not pretend to be.** Laying a publication
/// out into pages, holding the reader's place across a resetting, and producing
/// the page after this one is the reader engine, and that is PS-15. What this
/// does is the one thing a first page has to do: stop at the paragraph where the
/// column runs out, rather than draw through the footer or cut a line in half.
///
/// It is why approved golden 08b shows two paragraphs where `07a` shows four.
/// The type went from 18 to 24 points and the rest of the text belongs to a page
/// that does not exist yet.
class ReaderPageFit {
  const ReaderPageFit._();

  /// How many of [paragraphs] fit in [height], measured with the same style and
  /// width they will be drawn at.
  ///
  /// Always at least one: a column too short for even the first paragraph is a
  /// layout that has already gone wrong, and drawing nothing would hide it.
  static int paragraphCount({
    required List<BookReaderParagraph> paragraphs,
    required TextStyle style,
    required TextScaler scaler,
    required double width,
    required double height,
    required double gap,
  }) {
    if (paragraphs.isEmpty) return 0;
    var used = 0.0;
    var fitted = 0;
    for (final paragraph in paragraphs) {
      final painter = TextPainter(
        text: TextSpan(text: paragraph.text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: width);
      final next = used + (fitted == 0 ? 0 : gap) + painter.height;
      painter.dispose();
      if (fitted > 0 && next > height) break;
      used = next;
      fitted++;
    }
    return fitted;
  }
}
