import 'package:flutter/foundation.dart';

import 'book.dart';

/// The five groups in the filter sheet's left rail, in the order golden 03
/// puts them (`docs/assets/ebooks/northstar/03a-filters-status.png`).
///
/// The Unified set also carries `Servers` and `Bibliotheken`. Those are
/// deliberately absent: Alle boeken has no source pill, the e-books comp does
/// not show them, and inventing a sixth group here would decide something the
/// golden did not.
enum BookFilterGroup { status, genre, series, author, language }

/// The Status group: one choice, not several.
///
/// `unread` means *not finished*, so a book at 48 % is unread rather than
/// falling outside both `unread` and `read`. The alternative, unread meaning
/// never-opened, leaves every in-progress book unreachable through Status,
/// and content the filter cannot reach is worse than a label that reads a
/// little broad.
///
/// `downloaded` sits in the same single-choice group as two read states
/// because the comp puts it there and golden 03 approved that. It is a
/// different axis, and combining it with a read state is not expressible.
enum BookStatusFilter { all, unread, read, downloaded }

/// One selectable value in a group: what to match on, and what to show.
///
/// The two differ for series, where the filter matches a `seriesId` and the
/// reader sees the series title.
@immutable
class BookFilterOption {
  final String value;
  final String label;

  const BookFilterOption({required this.value, required this.label});

  @override
  bool operator ==(Object other) => other is BookFilterOption && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);
}

/// What the shelf actually offers, per group.
///
/// Derived from the books in hand rather than from a fixed vocabulary, so a
/// genre Pleya has never heard of still shows up, and a genre nothing on this
/// shelf carries does not sit there returning nothing.
@immutable
class BookFilterOptions {
  final List<BookFilterOption> genres;
  final List<BookFilterOption> series;
  final List<BookFilterOption> authors;
  final List<BookFilterOption> languages;

  const BookFilterOptions({
    this.genres = const [],
    this.series = const [],
    this.authors = const [],
    this.languages = const [],
  });

  static BookFilterOptions from({required List<Book> books, required List<BookSeries> series}) {
    final seriesTitles = {for (final s in series) s.id: s.title};
    final usedSeriesIds = <String>{
      for (final book in books)
        if (book.seriesId != null) book.seriesId!,
    };
    return BookFilterOptions(
      genres: _plain({for (final book in books) ...book.genres}),
      // A series with no book on this shelf is not a filter, it is a dead end.
      series:
          (usedSeriesIds
              .where(seriesTitles.containsKey)
              .map((id) => BookFilterOption(value: id, label: seriesTitles[id]!))
              .toList()
            ..sort((a, b) => _byLabel(a, b))),
      authors: _plain({for (final book in books) book.author}),
      languages: _plain({
        for (final book in books)
          if (book.language != null) book.language!,
      }),
    );
  }

  /// Values that are their own label, alphabetically.
  static List<BookFilterOption> _plain(Set<String> values) =>
      (values.map((v) => BookFilterOption(value: v, label: v)).toList()..sort(_byLabel));

  static int _byLabel(BookFilterOption a, BookFilterOption b) => a.label.toLowerCase().compareTo(b.label.toLowerCase());

  List<BookFilterOption> forGroup(BookFilterGroup group) => switch (group) {
    // Status is not derived from the shelf: its four choices are fixed by the
    // golden, and the sheet renders them from [BookStatusFilter].
    BookFilterGroup.status => const [],
    BookFilterGroup.genre => genres,
    BookFilterGroup.series => series,
    BookFilterGroup.author => authors,
    BookFilterGroup.language => languages,
  };
}

/// What the reader has chosen, and whether a book survives it.
///
/// Immutable, so the sheet can hold a staged copy next to the applied one.
/// That separation is golden 03's third decision: the sheet is a draft and
/// `Toepassen` is the only moment anything changes.
@immutable
class BookFilter {
  final BookStatusFilter status;
  final Set<String> genres;
  final Set<String> seriesIds;
  final Set<String> authors;
  final Set<String> languages;

  const BookFilter({
    this.status = BookStatusFilter.all,
    this.genres = const {},
    this.seriesIds = const {},
    this.authors = const {},
    this.languages = const {},
  });

  static const BookFilter none = BookFilter();

  bool get isEmpty => chosenCount == 0;

  /// What the pill's badge and the sheet's header count.
  ///
  /// `Alles` is the neutral status and counts for nothing, which is why the
  /// opening state in golden 03a shows a tick next to Alles and no `1` beside
  /// Status.
  int get chosenCount =>
      (status == BookStatusFilter.all ? 0 : 1) + genres.length + seriesIds.length + authors.length + languages.length;

  int countFor(BookFilterGroup group) => switch (group) {
    BookFilterGroup.status => status == BookStatusFilter.all ? 0 : 1,
    BookFilterGroup.genre => genres.length,
    BookFilterGroup.series => seriesIds.length,
    BookFilterGroup.author => authors.length,
    BookFilterGroup.language => languages.length,
  };

  Set<String> valuesFor(BookFilterGroup group) => switch (group) {
    BookFilterGroup.status => {status.name},
    BookFilterGroup.genre => genres,
    BookFilterGroup.series => seriesIds,
    BookFilterGroup.author => authors,
    BookFilterGroup.language => languages,
  };

  /// Within a group the chosen values are OR'd, between groups they are AND'd.
  ///
  /// Two genres means either genre, a genre plus an author means both. The
  /// other way round, picking a second genre would narrow to books carrying
  /// both, and on a shelf this size that returns nothing almost every time.
  bool matches(Book book) {
    final statusOk = switch (status) {
      BookStatusFilter.all => true,
      BookStatusFilter.unread => !book.isFinished,
      BookStatusFilter.read => book.isFinished,
      BookStatusFilter.downloaded => book.isDownloaded,
    };
    if (!statusOk) return false;
    if (genres.isNotEmpty && !book.genres.any(genres.contains)) return false;
    if (seriesIds.isNotEmpty && !seriesIds.contains(book.seriesId)) return false;
    if (authors.isNotEmpty && !authors.contains(book.author)) return false;
    if (languages.isNotEmpty && !languages.contains(book.language)) return false;
    return true;
  }

  List<Book> apply(List<Book> books) => books.where(matches).toList();

  BookFilter withStatus(BookStatusFilter value) => _copy(status: value);

  /// Add the value if it is not there, remove it if it is.
  BookFilter toggle(BookFilterGroup group, String value) {
    if (group == BookFilterGroup.status) {
      return withStatus(BookStatusFilter.values.firstWhere((s) => s.name == value));
    }
    final current = valuesFor(group);
    final next = current.contains(value) ? (Set<String>.from(current)..remove(value)) : {...current, value};
    return switch (group) {
      BookFilterGroup.status => this,
      BookFilterGroup.genre => _copy(genres: next),
      BookFilterGroup.series => _copy(seriesIds: next),
      BookFilterGroup.author => _copy(authors: next),
      BookFilterGroup.language => _copy(languages: next),
    };
  }

  /// The labels behind the choices, in rail order, for the summary on Alle
  /// boeken's result line. Status comes first because it is the coarsest cut.
  List<String> summaryLabels({
    required String Function(BookStatusFilter) statusLabel,
    required BookFilterOptions options,
  }) => [
    if (status != BookStatusFilter.all) statusLabel(status),
    for (final group in [
      BookFilterGroup.genre,
      BookFilterGroup.series,
      BookFilterGroup.author,
      BookFilterGroup.language,
    ])
      for (final option in options.forGroup(group))
        if (valuesFor(group).contains(option.value)) option.label,
  ];

  BookFilter _copy({
    BookStatusFilter? status,
    Set<String>? genres,
    Set<String>? seriesIds,
    Set<String>? authors,
    Set<String>? languages,
  }) => BookFilter(
    status: status ?? this.status,
    genres: genres ?? this.genres,
    seriesIds: seriesIds ?? this.seriesIds,
    authors: authors ?? this.authors,
    languages: languages ?? this.languages,
  );

  @override
  bool operator ==(Object other) =>
      other is BookFilter &&
      other.status == status &&
      setEquals(other.genres, genres) &&
      setEquals(other.seriesIds, seriesIds) &&
      setEquals(other.authors, authors) &&
      setEquals(other.languages, languages);

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAllUnordered(genres),
    Object.hashAllUnordered(seriesIds),
    Object.hashAllUnordered(authors),
    Object.hashAllUnordered(languages),
  );
}
