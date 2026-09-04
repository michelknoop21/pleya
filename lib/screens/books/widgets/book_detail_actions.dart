import 'package:flutter/material.dart';

import '../../../books/book_detail_layout.dart';
import '../../../books/book_detail_view.dart';
import '../../../navigation/navigation_tabs.dart' show NavGlyphs;
import '../../../widgets/app_icon.dart' show NavGlyph;
import 'package:material_symbols_icons/symbols.dart';

/// The action block of approved golden 05, drawn in `05c` on its own so both
/// states can be read side by side: the progress lines, the two pills and the
/// stats row.
///
/// `05c` is a shape specification, not a runtime state. It exists so the
/// difference between a book with progress and one without can be judged
/// without the rest of the page around it.
class BookDetailActionColours {
  const BookDetailActionColours._();

  /// The colours are set here rather than read from the theme, the same choice
  /// golden 01b and 02 made: these screens are held against a golden, and
  /// `monoTheme` collapses half its container roles onto `surface`.
  static const Color primaryFill = Color(0xFFFFFFFF);
  static const Color primaryInk = Color(0xFF111111);
  static const Color secondaryFill = Color(0xFF2F2F2F);
  static const Color hairline = Color(0x24FFFFFF);
}

/// `48% gelezen` over `Hoofdstuk 12`. Two lines of text, no bar.
class BookDetailProgress extends StatelessWidget {
  const BookDetailProgress({super.key, required this.progress});

  final BookProgressLines progress;

  @override
  Widget build(BuildContext context) {
    final chapter = progress.chapter;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 20,
          child: Text(
            progress.percent,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 20 / 15),
          ),
        ),
        if (chapter != null)
          SizedBox(
            height: 18,
            child: Text(
              chapter,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, height: 18 / 13.5, color: Colors.white.withValues(alpha: 0.62)),
            ),
          ),
      ],
    );
  }
}

/// One full-width pill, 48 tall.
///
/// Both pills are drawn and neither opens anything, exactly as the Filters pill
/// stood between golden 02 and golden 03. What the primary opens is the reader,
/// panel 7 of the comp, which has its own golden and its own approval; what
/// `Downloaden` means in each of its states is PS-16. Golden 05 fixes the slot,
/// not what fills it.
class BookDetailAction extends StatelessWidget {
  const BookDetailAction({super.key, required this.label, required this.isPrimary, this.onTap});

  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isPrimary ? BookDetailActionColours.primaryInk : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: BookDetailLayout.actionHeight,
        decoration: BoxDecoration(
          color: isPrimary ? BookDetailActionColours.primaryFill : BookDetailActionColours.secondaryFill,
          borderRadius: BorderRadius.circular(BookDetailLayout.actionRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The primary carries the open book, not the comp's play triangle:
            // a triangle is the glyph for starting a stream, and this is the
            // one screen in the set with no video on it. Same silhouette as the
            // Boeken tab, because it is the same object.
            NavGlyph(
              svgAsset: isPrimary ? NavGlyphs.libBook : NavGlyphs.downloads,
              icon: isPrimary ? Symbols.menu_book_rounded : Symbols.download_rounded,
              size: 19,
              color: ink,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16.5, fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w600, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Year, genre and pages, with a hairline between the columns.
///
/// Golden 02 kept this metadata out of the grid because a shelf is not a film
/// catalogue. That was a decision about the grid, not about the product: the
/// detail page is exactly where a book's metadata belongs.
class BookDetailStats extends StatelessWidget {
  const BookDetailStats({super.key, required this.stats});

  final List<BookStat> stats;

  /// The key a test or a scenario addresses a column by, without going through
  /// a translated label.
  static String columnKey(String stat) => 'books.detail.stat.$stat';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: BookDetailLayout.statsHeight,
      child: Row(
        children: [
          for (final stat in stats)
            Expanded(
              flex: stat.flex,
              child: Stack(
                // Without this the column's children get loose constraints and
                // a 40 pt row draws its two lines against its own top edge —
                // the same trap the filter sheet's group labels fell into.
                fit: StackFit.expand,
                children: [
                  if (stat != stats.first)
                    const Positioned(
                      left: 0,
                      top: 5,
                      width: 1,
                      height: 30,
                      child: ColoredBox(color: BookDetailActionColours.hairline),
                    ),
                  Column(
                    key: Key(columnKey(stat.key)),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 22,
                        child: Text(
                          stat.value,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 22 / 16),
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 16,
                        child: Text(
                          stat.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, height: 16 / 12, color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
