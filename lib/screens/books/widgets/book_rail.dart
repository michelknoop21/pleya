import 'package:flutter/material.dart';

import '../../../books/book.dart';
import '../../../i18n/strings.g.dart';
import 'book_cover.dart';

/// Golden 01b's rail geometry, measured on the iOS Unified set's
/// `01-series-landing.png`: 16 pt page margin, 110 pt covers, 12 pt between
/// them. One place, because a rail that disagrees with the rail above it is
/// the thing a reader notices first.
class BookRailMetrics {
  const BookRailMetrics._();

  static const double pageMargin = 16;
  static const double coverWidth = 110;
  static const double coverHeight = 165;
  static const double seriesCoverHeight = 150;
  static const double gap = 12;

  /// The caption under a cover: a title line over a subtitle line, and the air
  /// between them and the artwork. One place, because the tile draws them and
  /// the rail has to reserve room for exactly what the tile draws.
  static const double coverCaptionGap = 8;
  static const double titleFontSize = 14;
  static const double subtitleFontSize = 12.5;
  static const double captionLineHeight = 1.28;

  /// What a tile needs on top of its cover, at the reader's own text size.
  ///
  /// Resolved against [MediaQuery.textScalerOf] rather than frozen as a
  /// constant. It used to be a literal 42 against a column measuring
  /// 8 + 14 x 1.28 + 12.5 x 1.28 = 41.92: exact at scale 1.0, and five points
  /// short at iOS Larger Text or Android "Groot" (about 1.15), where every
  /// tile on every rail of Boeken-home overflowed its `Column` — striped in
  /// debug, silently clipped in release. Nothing in `lib/` clamps
  /// `textScaler`, so that setting arrives here at full strength. Same rule
  /// and the same reason as `MediaCardGridLayout.captionExtentFor`.
  ///
  /// Rounded up, so scale 1.0 still gives the 42 golden 01b was measured with.
  static double captionExtentFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = scaler.scale(titleFontSize) * captionLineHeight;
    final subtitle = scaler.scale(subtitleFontSize) * captionLineHeight;
    return (coverCaptionGap + title + subtitle).ceilToDouble();
  }
}

/// A row heading with its "Alles bekijken" link.
class BookRailHeader extends StatelessWidget {
  const BookRailHeader({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(BookRailMetrics.pageMargin, 0, BookRailMetrics.pageMargin, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2),
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Text(
                '${t.books.seeAll} ›',
                style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.62)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A horizontally scrolling row of covers with a caption and a subtitle.
class BookRail extends StatelessWidget {
  const BookRail({super.key, required this.items, this.coverHeight = BookRailMetrics.coverHeight});

  final List<BookRailItem> items;
  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: coverHeight + BookRailMetrics.captionExtentFor(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: BookRailMetrics.pageMargin),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: BookRailMetrics.gap),
        itemBuilder: (context, index) => _BookRailTile(item: items[index], coverHeight: coverHeight),
      ),
    );
  }
}

/// One cover plus its two lines of text.
@immutable
class BookRailItem {
  final String id;
  final BookArtwork artwork;
  final String title;
  final String subtitle;

  /// Passed to the cover so a shelf cover carries its author line the way
  /// golden 01b draws it. `null` on a series, which is a stack and has none.
  final String? coverAuthor;

  final VoidCallback? onTap;

  const BookRailItem({
    required this.id,
    required this.artwork,
    required this.title,
    required this.subtitle,
    this.coverAuthor,
    this.onTap,
  });

  factory BookRailItem.fromBook(Book book, {VoidCallback? onTap}) => BookRailItem(
    id: book.id,
    artwork: book.artwork,
    title: book.title,
    subtitle: book.author,
    coverAuthor: book.author,
    onTap: onTap,
  );

  factory BookRailItem.fromSeries(BookSeries series, {VoidCallback? onTap}) => BookRailItem(
    id: series.id,
    artwork: series.artwork,
    title: series.title,
    subtitle: t.books.bookCount(count: series.bookCount),
    onTap: onTap,
  );
}

class _BookRailTile extends StatelessWidget {
  const _BookRailTile({required this.item, required this.coverHeight});

  final BookRailItem item;
  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: BookRailMetrics.coverWidth,
      child: GestureDetector(
        onTap: item.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: coverHeight,
              child: BookCover(artwork: item.artwork, title: item.title, author: item.coverAuthor),
            ),
            const SizedBox(height: BookRailMetrics.coverCaptionGap),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: BookRailMetrics.titleFontSize,
                fontWeight: FontWeight.w500,
                height: BookRailMetrics.captionLineHeight,
              ),
            ),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: BookRailMetrics.subtitleFontSize,
                height: BookRailMetrics.captionLineHeight,
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
