import 'package:flutter/foundation.dart';

import 'book.dart';

/// The four chips above the results, in the order golden 04 puts them.
///
/// `Boekenseries` rather than `Series`, because the tab bar underneath this
/// screen already says `Series` for television. Golden 01b renamed the rail
/// for the same reason; unlike the filter sheet, that bar is in view here.
enum BookSearchCategory { all, books, authors, series }

/// What a query found, already grouped by kind.
///
/// Grouped rather than one ranked list: golden 04's whole point is that a
/// book, an author and a series are three different things, and a flat list
/// would make the screen sort that out again at paint time.
@immutable
class BookSearchResults {
  final List<Book> books;

  /// Author names, not [Book]s. An author is a result in its own right here,
  /// and the fixture has no author record to point at yet.
  final List<String> authors;

  final List<BookSeries> series;

  const BookSearchResults({this.books = const [], this.authors = const [], this.series = const []});

  static const BookSearchResults none = BookSearchResults();

  bool get isEmpty => books.isEmpty && authors.isEmpty && series.isEmpty;

  int countFor(BookSearchCategory category) => switch (category) {
    BookSearchCategory.all => books.length + authors.length + series.length,
    BookSearchCategory.books => books.length,
    BookSearchCategory.authors => authors.length,
    BookSearchCategory.series => series.length,
  };

  /// Which chips to draw. `Alles` is there whenever anything was found, and a
  /// kind with no results gets no chip rather than a chip that leads to an
  /// empty screen. `search_screen.dart` already does this for films and
  /// episodes; this is the same rule.
  List<BookSearchCategory> get availableCategories => [
    if (!isEmpty) BookSearchCategory.all,
    for (final category in [BookSearchCategory.books, BookSearchCategory.authors, BookSearchCategory.series])
      if (countFor(category) > 0) category,
  ];

  /// The same results narrowed to one chip.
  BookSearchResults within(BookSearchCategory category) => switch (category) {
    BookSearchCategory.all => this,
    BookSearchCategory.books => BookSearchResults(books: books),
    BookSearchCategory.authors => BookSearchResults(authors: authors),
    BookSearchCategory.series => BookSearchResults(series: series),
  };
}

/// Which results belong to a query.
///
/// Deliberately its own seam, and deliberately not part of the widgets that
/// draw results. Approved golden 04 fixes what a result looks like; what
/// counts as a match is a separate contract that has to be free to move.
/// Ranking will change when books gain real metadata (PS-14), and again if
/// matching ever moves to the server. Neither should reach the screen.
abstract class BookSearchRanking {
  BookSearchResults search({required String query, required List<Book> books, required List<BookSeries> series});
}

/// The local, in-memory ranking: substring matching over what the shelf has.
///
/// Honest about being simple. It is not a relevance engine and does not
/// pretend to be one; it is the answer for a shelf that fits in memory, and
/// it is replaced rather than extended when a real one arrives.
class LocalBookSearchRanking implements BookSearchRanking {
  const LocalBookSearchRanking();

  /// Below this a query is treated as no query at all. One letter matches
  /// most of a shelf, which is a slower way of showing everything.
  static const int minQueryLength = 2;

  @override
  BookSearchResults search({required String query, required List<Book> books, required List<BookSeries> series}) {
    final needle = _fold(query);
    if (needle.length < minQueryLength) return BookSearchResults.none;

    // Closeness first, then alphabetical inside each band. Searching `dune`
    // and finding `Dune` third, under `Children of Dune`, is alphabetically
    // correct and useless.
    final matchedBooks = books.where((book) => _fold(book.title).contains(needle)).toList()
      ..sort((a, b) {
        final byCloseness = _closeness(a.title, needle).compareTo(_closeness(b.title, needle));
        return byCloseness != 0 ? byCloseness : _byTitle(a.title, b.title);
      });

    // An author is a result because they wrote something that matched, not
    // only because their own name looks like the query. Searching `dune` and
    // getting no author at all would be the strict reading, and it is the
    // less useful one: the reason Frank Herbert is on this screen is exactly
    // the three books above him. A name that matches directly still counts,
    // so searching an author finds them even with no matching title.
    final authors = <String>{
      for (final book in matchedBooks) book.author,
      for (final book in books)
        if (_fold(book.author).contains(needle)) book.author,
    }.toList()..sort(_byTitle);

    // Same shape for a series: it matches on its own title, or because a book
    // in it did.
    final matchedSeriesIds = <String>{
      for (final book in matchedBooks)
        if (book.seriesId != null) book.seriesId!,
    };
    final matchedSeries =
        series.where((s) => matchedSeriesIds.contains(s.id) || _fold(s.title).contains(needle)).toList()
          ..sort((a, b) => _byTitle(a.title, b.title));

    // Books found only through their author belong in the books section too,
    // and after the title matches: searching an author should list their
    // work, and a title match is still the closer answer.
    final byAuthor = books.where((book) => !matchedBooks.contains(book) && _fold(book.author).contains(needle)).toList()
      ..sort((a, b) => _byTitle(a.title, b.title));

    return BookSearchResults(books: [...matchedBooks, ...byAuthor], authors: authors, series: matchedSeries);
  }

  /// Case and diacritics folded, so `dune` finds `Düne` and `de alchemist`
  /// finds `De Alchemist`. The same treatment `allByTitle` gives its sort.
  static String _fold(String value) {
    final lower = value.toLowerCase().trim();
    const from = 'áàâäãåéèêëíìîïóòôöõúùûüýÿñçø';
    const to = 'aaaaaaeeeeiiiiooooouuuuyynco';
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final index = from.indexOf(char);
      buffer.write(index == -1 ? char : to[index]);
    }
    return buffer.toString();
  }

  static int _byTitle(String a, String b) => _fold(a).compareTo(_fold(b));

  /// 0 for the title that is the query, 1 for one that starts with it, 2 for
  /// one that merely contains it.
  static int _closeness(String title, String needle) {
    final folded = _fold(title);
    if (folded == needle) return 0;
    if (folded.startsWith(needle)) return 1;
    return 2;
  }
}
