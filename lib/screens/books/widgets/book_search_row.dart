import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../books/book.dart';
import '../../../i18n/strings.g.dart';
import '../../../widgets/app_icon.dart';
import 'book_cover.dart';

/// The three result shapes from approved golden 04
/// (`docs/assets/ebooks/northstar/04c-books-search-rowtypes.png`).
///
/// Three silhouettes rather than three labels: a book is a 2:3 cover, an
/// author is a circle, a series is a cover with the page blocks of two more
/// behind it. The kind of a result is legible before its text is read, which
/// is what makes one screen with three kinds of thing on it work at all.
class BookSearchRowMetrics {
  BookSearchRowMetrics._();

  /// Measured on `05-zoeken.png` from the iOS Unified set.
  static const double pageMargin = 16;
  static const double cardRadius = 12;
  static const double rowHeight = 82;

  /// An author row is shorter: one line of text and a 44 pt circle.
  static const double authorRowHeight = 64;

  static const double thumbWidth = 44;
  static const double thumbHeight = 66;
  static const double thumbRadius = 5;
  static const double avatarSize = 44;

  /// Between the thumbnail and the text, so titles line up down the column
  /// whatever the leading shape is.
  static const double gap = 15;

  /// Where a separator starts: past the leading shape, under the text.
  static const double separatorInset = pageMargin + thumbWidth + gap;

  static const Color surface = Color(0xFF1F1F1F);
  static const Color hairline = Color(0xFF2E2E2E);

  /// The page block of the books stacked behind a series cover. Cream, not
  /// grey: at eight pixels wide the cut edge is the only part of a book that
  /// still reads against a dark card.
  static const Color stackNear = Color(0xFFDCD5C7);
  static const Color stackFar = Color(0xFFB4ADA0);
}

/// One rounded card per section with hairlines between its rows, rather than
/// the comp's separate card per row. Fewer edges on a screen that already has
/// to show three kinds of thing at once.
class BookSearchSection extends StatelessWidget {
  const BookSearchSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(BookSearchRowMetrics.pageMargin, 0, BookSearchRowMetrics.pageMargin, 35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.6,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: BookSearchRowMetrics.surface,
              borderRadius: BorderRadius.circular(BookSearchRowMetrics.cardRadius),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.only(left: BookSearchRowMetrics.separatorInset),
                      child: Divider(height: 1, thickness: 1, color: BookSearchRowMetrics.hairline),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared row: a leading shape, one or two lines, a chevron.
class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.title, this.subtitle, required this.height, this.onTap});

  final Widget leading;
  final String title;
  final String? subtitle;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BookSearchRowMetrics.pageMargin),
          child: Row(
            children: [
              leading,
              const SizedBox(width: BookSearchRowMetrics.gap),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, height: 1.33, color: Colors.white.withValues(alpha: 0.62)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Opacity(opacity: 0.55, child: AppIcon(Symbols.chevron_right_rounded, size: 18)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cover, title, author. No third line: golden 02 kept year and genre out of
/// the shelf because this is a bookshelf and not a film catalogue, and a
/// search result is that same shelf in another shape.
class BookResultRow extends StatelessWidget {
  const BookResultRow({super.key, required this.book, this.onTap});

  final Book book;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Row(
      height: BookSearchRowMetrics.rowHeight,
      leading: SizedBox(
        width: BookSearchRowMetrics.thumbWidth,
        height: BookSearchRowMetrics.thumbHeight,
        child: BookCover(
          artwork: book.artwork,
          title: book.title,
          author: book.author,
          borderRadius: BookSearchRowMetrics.thumbRadius,
        ),
      ),
      title: book.title,
      subtitle: book.author,
      onTap: onTap,
    );
  }
}

/// A circle and a name, and nothing else. A second line would make this look
/// like a book row again, which is the one thing it must not do.
class AuthorResultRow extends StatelessWidget {
  const AuthorResultRow({super.key, required this.name, this.onTap});

  final String name;
  final VoidCallback? onTap;

  /// Initials, because an author portrait is not a golden asset this
  /// repository can carry and the fixture has none.
  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return _Row(
      height: BookSearchRowMetrics.authorRowHeight,
      leading: Container(
        width: BookSearchRowMetrics.avatarSize,
        height: BookSearchRowMetrics.avatarSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4A3A2A), Color(0xFF2A1D12), Color(0xFF1A1109)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          initials(name),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      title: name,
      onTap: onTap,
    );
  }
}

/// A cover with the page blocks of two more behind it, and the count under
/// the title. The box stays 44 wide like a plain cover so titles line up
/// across all three sections; the stacked edges overflow into the gap.
class SeriesResultRow extends StatelessWidget {
  const SeriesResultRow({super.key, required this.series, this.onTap});

  final BookSeries series;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Row(
      height: BookSearchRowMetrics.rowHeight,
      leading: SizedBox(
        width: BookSearchRowMetrics.thumbWidth,
        height: BookSearchRowMetrics.thumbHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 8, top: 8, child: _stackEdge(50, BookSearchRowMetrics.stackFar)),
            Positioned(left: 4, top: 4, child: _stackEdge(58, BookSearchRowMetrics.stackNear)),
            SizedBox(
              width: BookSearchRowMetrics.thumbWidth,
              height: BookSearchRowMetrics.thumbHeight,
              // No lettering on the front cover: the stacked edges are the
              // thing to read here, and a title drawn over 44 points competes
              // with them for the same few pixels.
              child: BookCover(artwork: series.artwork, title: '', borderRadius: BookSearchRowMetrics.thumbRadius),
            ),
          ],
        ),
      ),
      title: series.title,
      subtitle: series.bookCount == 1 ? t.books.oneBookLabel : t.books.bookCountLabel(count: series.bookCount),
      onTap: onTap,
    );
  }

  static Widget _stackEdge(double height, Color color) => Container(
    width: BookSearchRowMetrics.thumbWidth,
    height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
  );
}
