import 'package:flutter/material.dart';

import '../../../books/book_detail_layout.dart';
import '../../../i18n/strings.g.dart';

/// The blurb from approved golden 05: 16 over 21, clamped to three lines with
/// an inline `meer` at the end of the last one.
///
/// Three lines in both states, also when there is room to spare. In `05a` three
/// is what fits above the bar; in `05b`, where the progress block falls away,
/// there are still three and the winnings land as air at the bottom of the
/// page. Same rule golden 04 applied: filling space because it is there lies
/// about how much there is to say.
///
/// `meer` is drawn and opens nothing. What stands below the fold is one of the
/// things golden 05 deliberately leaves open, and expanding in place would
/// answer it.
class BookDescription extends StatelessWidget {
  const BookDescription({super.key, required this.text, this.maxLines = BookDetailLayout.descriptionMaxLines});

  final String text;
  final int maxLines;

  static const double fontSize = 16;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      height: BookDetailLayout.descriptionLineHeight / fontSize,
      color: Colors.white.withValues(alpha: 0.78),
    );
    final moreStyle = style.copyWith(color: Colors.white.withValues(alpha: 0.5));
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final span = clamp(
          text: text,
          more: t.books.descriptionMore,
          style: style,
          moreStyle: moreStyle,
          maxLines: maxLines,
          maxWidth: constraints.maxWidth,
          scaler: scaler,
        );
        return Text.rich(span, maxLines: maxLines, textScaler: scaler);
      },
    );
  }

  /// The longest prefix of [text] that still leaves room for `… meer` on the
  /// last line, or the whole text when it already fits.
  ///
  /// Measured rather than estimated: `TextOverflow.ellipsis` would cut the
  /// `meer` span off along with the rest, so the cut has to be found before the
  /// paragraph is handed to a `Text`. A binary search over grapheme clusters,
  /// so it is a handful of layouts and never splits a character.
  @visibleForTesting
  static TextSpan clamp({
    required String text,
    required String more,
    required TextStyle style,
    required TextStyle moreStyle,
    required int maxLines,
    required double maxWidth,
    TextScaler scaler = TextScaler.noScaling,
  }) {
    bool fits(InlineSpan span) {
      final painter = TextPainter(text: span, maxLines: maxLines, textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout(maxWidth: maxWidth);
      final exceeded = painter.didExceedMaxLines;
      painter.dispose();
      return !exceeded;
    }

    final full = TextSpan(text: text, style: style);
    if (fits(full)) return full;

    TextSpan truncated(int graphemes) => TextSpan(
      style: style,
      children: [
        TextSpan(text: '${_cut(text, graphemes)}… '),
        TextSpan(text: more, style: moreStyle),
      ],
    );

    final total = text.characters.length;
    var low = 0;
    var high = total;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fits(truncated(mid))) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return truncated(low);
  }

  /// [graphemes] characters of [text], ending on a word boundary so the ellipsis
  /// does not land inside a word.
  static String _cut(String text, int graphemes) {
    final head = text.characters.take(graphemes).toString();
    final lastSpace = head.lastIndexOf(' ');
    final cut = lastSpace > 0 ? head.substring(0, lastSpace) : head;
    // Trailing punctuation before an ellipsis reads as a typo, not as a cut.
    return cut.replaceFirst(RegExp(r'[\s,;:.!?—-]+$'), '');
  }
}
