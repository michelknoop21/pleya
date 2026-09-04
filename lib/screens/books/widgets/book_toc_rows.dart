import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../books/book.dart';
import '../../../books/book_toc.dart';
import '../../../books/book_toc_layout.dart';
import '../../../books/book_toc_view.dart';
import '../../../theme/mono_theme.dart' show kAccent;
import '../../../widgets/app_icon.dart';
import 'book_cover.dart';

/// The four row shapes of approved golden 06
/// (`docs/assets/ebooks/northstar/06c-books-toc-rowtypes.png`).
///
/// Every row is exactly the height its kind says and draws its own hairline
/// inside its top edge, so the card's geometry is the table in
/// [BookTocLayout] and nothing else.
class BookTocRowWidget extends StatelessWidget {
  const BookTocRowWidget({super.key, required this.row, required this.book, this.onTap});

  final BookTocRow row;

  /// Only the book row needs it, for its cover.
  final Book book;

  /// Drawn and inert: what a row opens is the reader, and the reader does not
  /// exist. Passed anyway so the hit target is real the day it does.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = switch (row.kind) {
      BookTocRowKind.book => _BookRow(row: row, book: book),
      BookTocRowKind.entry => _EntryRow(row: row),
      BookTocRowKind.part => _PartRow(row: row),
      BookTocRowKind.chapter => _ChapterRow(row: row),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: BookTocLayout.heightOf(row.kind),
        child: Stack(
          children: [
            Positioned.fill(child: content),
            if (row.startsSection)
              const Positioned(
                left: BookTocLayout.hairlineInset,
                right: 0,
                top: 0,
                height: BookTocLayout.hairlineThickness,
                child: ColoredBox(color: BookTocLayout.hairline),
              ),
          ],
        ),
      ),
    );
  }
}

/// 38 % for what lies before the locator, the ordinary inactive presentation
/// for what comes after, white for where the reader is.
///
/// The dimming says "this comes earlier in the book" and not "you have read
/// this" — see [BookTocPosition].
Color _titleInk(BookTocRow row, double restingAlpha) => switch (row.position) {
  BookTocPosition.behind => Colors.white.withValues(alpha: 0.38),
  BookTocPosition.atLocator => Colors.white,
  BookTocPosition.ahead => Colors.white.withValues(alpha: restingAlpha),
};

Color _subtitleInk(BookTocRow row) =>
    Colors.white.withValues(alpha: row.position == BookTocPosition.behind ? 0.38 : 0.62);

/// The dot, in the accent. One per screen: it marks the deepest row that is
/// actually drawn for the locator.
class _Marker extends StatelessWidget {
  const _Marker();

  @override
  Widget build(BuildContext context) => Container(
    width: BookTocLayout.markerSize,
    height: BookTocLayout.markerSize,
    decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
  );
}

/// The book itself: cover, title, author — the silhouette golden 04 approved
/// for a book result, so no new shape is introduced to say the same thing.
class _BookRow extends StatelessWidget {
  const _BookRow({required this.row, required this.book});

  final BookTocRow row;
  final Book book;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookTocLayout.pageMargin),
      child: Row(
        children: [
          SizedBox(
            width: BookTocLayout.coverWidth,
            height: BookTocLayout.coverHeight,
            child: BookCover(
              artwork: book.artwork,
              title: book.title,
              author: book.author,
              borderRadius: BookTocLayout.coverRadius,
            ),
          ),
          const SizedBox(width: BookTocLayout.coverGap),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 20 / 16),
                ),
                if (row.subtitle != null)
                  Text(
                    row.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, height: 18 / 13.5, color: Colors.white.withValues(alpha: 0.62)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A loose entry of the top layer: one line, no chevron. An introduction and a
/// conclusion are not groups, and the tree does not pretend otherwise.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.row});

  final BookTocRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookTocLayout.pageMargin),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, height: 22 / 17, color: _titleInk(row, 1)),
            ),
          ),
          if (row.showsMarker) ...[const SizedBox(width: BookTocLayout.rowGap), const _Marker()],
        ],
      ),
    );
  }
}

/// A part: its name, the range it spans, and a chevron.
///
/// The chevron points at what opens and, when the part is open, back at the row
/// that closes it — the two glyphs the comp draws, rather than one that rotates.
class _PartRow extends StatelessWidget {
  const _PartRow({required this.row});

  final BookTocRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookTocLayout.pageMargin),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    height: 22 / 17,
                    color: _titleInk(row, 1),
                  ),
                ),
                if (row.subtitle != null)
                  Text(
                    row.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, height: 18 / 13.5, color: _subtitleInk(row)),
                  ),
              ],
            ),
          ),
          if (row.showsMarker) ...[const SizedBox(width: BookTocLayout.rowGap), const _Marker()],
          const SizedBox(width: BookTocLayout.rowGap),
          Opacity(
            opacity: 0.55,
            child: AppIcon(
              row.isExpanded ? Symbols.keyboard_arrow_up_rounded : Symbols.chevron_right_rounded,
              size: BookTocLayout.chevronSize,
            ),
          ),
        ],
      ),
    );
  }
}

/// A chapter: `12. The Law of Least Effort`, indented, with the marker in the
/// gutter when this is where the reader stands.
class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.row});

  final BookTocRow row;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(
              left: BookTocLayout.pageMargin + BookTocLayout.chapterIndent,
              right: BookTocLayout.pageMargin,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: row.position == BookTocPosition.atLocator ? FontWeight.w500 : FontWeight.w400,
                  height: 21 / 16,
                  color: _titleInk(row, 0.7),
                ),
              ),
            ),
          ),
        ),
        if (row.showsMarker)
          const Positioned(
            left: BookTocLayout.chapterMarkerLeft,
            top: 0,
            bottom: 0,
            width: BookTocLayout.markerSize,
            child: Center(child: _Marker()),
          ),
      ],
    );
  }
}
