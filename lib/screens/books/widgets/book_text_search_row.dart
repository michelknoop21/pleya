import 'package:flutter/material.dart';

import '../../../books/book_text_search.dart';
import '../../../books/book_text_search_layout.dart';
import '../../../i18n/strings.g.dart';

/// One result of Zoeken in boek, the shape approved golden 09b specifies
/// (`docs/assets/ebooks/northstar/09b-books-search-in-book-rowtypes.png`).
///
/// **The first line is the chapter, and the page label is a suffix in weaker
/// ink.** The comp writes only `Pagina 102` there, and that cannot be: golden 05
/// made the page count bibliographical metadata about an edition, golden 06 hung
/// `Ga naar pagina` on the `page-list`, and golden 07 gave the footer two forms
/// that carry no page label at all. A publication with no usable `page-list` has
/// no page label, and then this row keeps `Hoofdstuk 12` — the last specimen of
/// `09b`.
///
/// **The row grows and shrinks with its excerpt.** A window of one line makes a
/// row of 70, two lines make 91, and anything past the second line is clipped
/// with an ellipsis. A fixed two-line row would hand every short result an empty
/// line. The heights are content, not a box: nothing in `lib/` clamps
/// `textScaler`, so at iOS Larger Text this row is taller than 91 rather than
/// clipping its own text.
///
/// **The match is amber ink on medium, never a filled block.** It is the amber
/// the reader already owns — golden 07's dark-theme highlight is that colour at
/// 26 % as a fill. On a reading surface a filled marker means a passage the
/// reader marked themselves, and accent red would collide with "selected" and
/// "playing".
class BookTextSearchRow extends StatelessWidget {
  const BookTextSearchRow({super.key, required this.hit, this.showsHairline = false, this.onTap});

  final BookSearchHit hit;

  /// Whether this row carries the separator above it. Drawn **inside** its own
  /// top edge and adding nothing to its height, the rule golden 06's rows
  /// already follow: the card's geometry is the table in `BookTextSearchLayout`
  /// and nothing else. A `Divider` between the rows would push every row after
  /// the first one point down the card.
  final bool showsHairline;

  /// `null` while nothing is wired to it. What a tap does — how the reader
  /// travels to the locator, whether the match stays marked when it arrives,
  /// whether there is a way back to where the search started — is one of the
  /// things golden 09 leaves open.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        children: [
          _content(),
          if (showsHairline)
            const Positioned(
              left: BookTextSearchLayout.hairlineInset,
              right: 0,
              top: 0,
              height: BookTextSearchLayout.hairlineThickness,
              child: ColoredBox(color: BookTextSearchLayout.hairline),
            ),
        ],
      ),
    );
  }

  Widget _content() {
    final page = hit.pageLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BookTextSearchLayout.rowPaddingHorizontal,
        vertical: BookTextSearchLayout.rowPaddingVertical,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              text: hit.chapterLabel,
              children: [
                if (page != null)
                  TextSpan(
                    text: ' · ${t.books.readerPage(page: page)}',
                    style: TextStyle(fontWeight: FontWeight.w400, color: Colors.white.withValues(alpha: 0.45)),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: BookTextSearchLayout.locationSize,
              height: BookTextSearchLayout.locationHeight / BookTextSearchLayout.locationSize,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: BookTextSearchLayout.excerptGap),
          Text.rich(
            TextSpan(children: excerptSpans(hit)),
            maxLines: BookTextSearchLayout.excerptMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: BookTextSearchLayout.excerptSize,
              height: BookTextSearchLayout.excerptLineHeight / BookTextSearchLayout.excerptSize,
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }

  /// The excerpt cut into plain and matched runs.
  ///
  /// Defensive about what it is handed, because the ranges come from whatever
  /// search engine is behind the seam: they are sorted, clamped to the excerpt
  /// and skipped when they overlap one already taken. A bad range from a future
  /// source paints the wrong word amber; an unguarded `substring` throws while
  /// building the widget tree, and that is a blank screen.
  static List<InlineSpan> excerptSpans(BookSearchHit hit) {
    final text = hit.excerpt;
    final ranges = [...hit.matchRanges]..sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(start, text.length);
      if (start < cursor || start == end) continue;
      if (start > cursor) spans.add(TextSpan(text: text.substring(cursor, start)));
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: const TextStyle(color: BookTextSearchLayout.match, fontWeight: FontWeight.w500),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return spans;
  }
}
