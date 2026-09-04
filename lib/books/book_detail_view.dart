import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import 'book.dart';
import 'book_detail_layout.dart';

/// One column of the stats row: a value with its label underneath.
@immutable
class BookStat {
  /// A stable name for the column, so a test and a scenario can address it
  /// without going through a translated label.
  final String key;

  final String value;
  final String label;

  /// Genre carries the only word of the three, and an equal third is not wide
  /// enough to keep it off the hairlines. Golden 05 gives it 1.45 times the
  /// width of the others.
  final bool isWide;

  const BookStat({required this.key, required this.value, required this.label, this.isWide = false});

  /// Flex units, so a row of two and a row of three both keep the genre column
  /// at 1.45 times its neighbours.
  int get flex => isWide ? 145 : 100;
}

/// What a book looks like on its detail page: which blocks it has, and what
/// each of them says.
///
/// Separate from the widget for the same reason `BookSearchRanking` is separate
/// from Boeken zoeken: golden 05 fixes what the page looks like, not where the
/// metadata comes from. The moment a real source (PS-14) starts answering with
/// years, page counts and blurbs, this is the layer that moves and the screen
/// is not touched.
@immutable
class BookDetailView {
  final Book book;

  /// `Dune #1`, or the series title alone when the source does not say where
  /// in the series this book stands. `null` when the book is in no series, or
  /// in one this profile cannot name — inventing a label for a series we
  /// cannot identify would be worse than leaving the line out.
  final String? seriesLabel;

  /// The percentage line and the chapter line, or `null` for a book that has
  /// never been opened. Both or neither: golden 05's progress block is one
  /// block.
  final BookProgressLines? progress;

  /// Year, genre and pages, in that order, minus the ones this edition has no
  /// value for.
  final List<BookStat> stats;

  const BookDetailView({required this.book, this.seriesLabel, this.progress, this.stats = const []});

  /// Derives the page from a book and the series the profile knows about.
  factory BookDetailView.of(Book book, {List<BookSeries> series = const []}) {
    return BookDetailView(
      book: book,
      seriesLabel: _seriesLabel(book, series),
      progress: book.isInProgress ? BookProgressLines.of(book) : null,
      stats: _stats(book),
    );
  }

  /// The label under the primary action's own state: `Lees verder` for a book
  /// with progress, `Lezen` for one without.
  ///
  /// Its own string rather than the Verder-lezen rail heading golden 01b
  /// approved: a heading names a row, a button names an action, and golden 05
  /// words them differently.
  String get primaryActionLabel => progress == null ? t.books.read : t.books.readContinue;

  /// Which of golden 05's blocks this book carries. The rest of the column
  /// closes over the ones it does not.
  Set<BookDetailBlock> get blocks => {
    BookDetailBlock.title,
    BookDetailBlock.author,
    if (seriesLabel != null) BookDetailBlock.series,
    if (progress != null) BookDetailBlock.progress,
    BookDetailBlock.primary,
    BookDetailBlock.secondary,
    if (stats.isNotEmpty) BookDetailBlock.stats,
    if (book.description != null && book.description!.trim().isNotEmpty) BookDetailBlock.description,
  };

  static String? _seriesLabel(Book book, List<BookSeries> series) {
    final id = book.seriesId;
    if (id == null) return null;
    final match = series.where((s) => s.id == id).firstOrNull;
    if (match == null) return null;
    final index = book.seriesIndex;
    return index == null ? match.title : '${match.title} #$index';
  }

  static List<BookStat> _stats(Book book) {
    final year = book.year;
    // The first genre, not all of them: the column is one word wide by design,
    // and a book that is filed under three of them still has a main one.
    final genre = book.genres.isEmpty ? null : book.genres.first;
    final pages = book.pages;
    return [
      if (year != null) BookStat(key: 'year', value: '$year', label: t.books.statYear),
      if (genre != null) BookStat(key: 'genre', value: genre, label: t.books.statGenre, isWide: true),
      // Never `0 Pagina's`: an edition with no page count gets no column, and
      // the row falls back to two.
      if (pages != null && pages > 0) BookStat(key: 'pages', value: '$pages', label: t.books.statPages),
    ];
  }
}

/// `48% gelezen` over `Hoofdstuk 12`: exact, and it names the place.
///
/// Two lines of text and no bar, deliberately. A rule across a centred column
/// would be a third horizontal line right above two full-width pills, and the
/// percentage is more precise than a stripe. This is the one place it differs
/// from the Verder-lezen card on Boeken-home, which does carry a bar: there the
/// card is small and the text expensive, here it is the other way round.
@immutable
class BookProgressLines {
  final String percent;

  /// Where the reader left off. `null` when the source has no chapter, and the
  /// percentage then stands alone rather than over an empty line.
  final String? chapter;

  const BookProgressLines({required this.percent, this.chapter});

  factory BookProgressLines.of(Book book) => BookProgressLines(
    percent: t.books.percentReadLong(percent: book.progressPercent),
    chapter: book.chapterLabel,
  );
}
