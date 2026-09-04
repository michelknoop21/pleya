import 'package:flutter/foundation.dart';

import '../books/book.dart';
import '../books/book_reader_page.dart';
import '../books/book_toc.dart';
import '../books/books_source.dart';
import '../utils/app_logger.dart';

/// The three rails of Boeken-home, derived once so the screen does not sort
/// and filter the same list three times per build.
///
/// The rows and their order are golden 01b: Verder lezen, Recent toegevoegd,
/// Boekenseries. `Boekenseries` rather than `Series`, because `Series` is
/// already the primary destination for television in the same viewport.
@immutable
class BooksHomeRows {
  /// Books with progress, the furthest along first.
  final List<Book> continueReading;

  /// Newest first.
  final List<Book> recentlyAdded;

  final List<BookSeries> series;

  /// Everything the profile has, unordered by any row's rule. Alle boeken
  /// reads this and applies its own sort, rather than borrowing a row whose
  /// order means something else.
  final List<Book> all;

  const BooksHomeRows({
    this.continueReading = const [],
    this.recentlyAdded = const [],
    this.series = const [],
    this.all = const [],
  });

  bool get isEmpty => continueReading.isEmpty && recentlyAdded.isEmpty && series.isEmpty;

  /// [all] sorted the way Alle boeken shows it by default: title A–Z, case
  /// and diacritics ignored, so `De Alchemist` and `de alchemist` land in the
  /// same place.
  List<Book> get allByTitle => [...all]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}

/// Loads Boeken-home's content from a [BooksSource].
///
/// Separate from `BooksLibraryProvider`, which answers only whether the tab
/// exists at all. That one runs on every profile bind to decide a navigation
/// slot; this one runs when the screen is on screen. Merging them would make
/// the navigation bar wait for content it never shows.
class BooksHomeProvider extends ChangeNotifier {
  BooksHomeProvider({required BooksSource source}) : _source = source;

  final BooksSource _source;

  BooksHomeRows _rows = const BooksHomeRows();
  BooksHomeRows get rows => _rows;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// True once a load has completed, successfully or not. Separates "nothing
  /// yet" from "nothing at all", which is the difference between a skeleton
  /// and an empty state.
  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    notifyListeners();
    try {
      final books = await _source.books();
      final series = await _source.series();
      if (generation != _generation) return;
      _rows = buildRows(books: books, series: series);
    } catch (error) {
      if (generation != _generation) return;
      appLogger.w('BooksHomeProvider: load failed: $error');
      _rows = const BooksHomeRows();
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        _hasLoaded = true;
        notifyListeners();
      }
    }
  }

  /// The navigation of one publication, fetched on demand rather than loaded
  /// with the shelf: a table of contents belongs to the book you opened, and
  /// pulling every publication's tree in to draw three rails would be work
  /// nothing on this screen uses.
  Future<BookToc?> tableOfContents(String bookId) => _source.tableOfContents(bookId);

  /// The page the reader opens on, fetched on demand for the same reason.
  Future<BookReaderPage?> readerPage(String bookId) => _source.readerPage(bookId);

  /// Pure, so the row rules are testable without a provider or a source.
  @visibleForTesting
  static BooksHomeRows buildRows({required List<Book> books, required List<BookSeries> series}) {
    final continueReading = books.where((book) => book.isInProgress).toList()
      ..sort((a, b) => (b.progress ?? 0).compareTo(a.progress ?? 0));
    final recentlyAdded = [...books]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return BooksHomeRows(
      all: books,
      continueReading: continueReading,
      recentlyAdded: recentlyAdded,
      // A series row of one is not a series row; it is a book with extra
      // chrome, and it sends the reader to a list holding what they can
      // already see.
      series: series.where((s) => s.bookCount > 1).toList(),
    );
  }
}
