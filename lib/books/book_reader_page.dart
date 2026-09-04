import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';

/// One paragraph of the page the reader is on.
@immutable
class BookReaderParagraph {
  final String text;

  /// Whether the reader has marked this passage.
  ///
  /// A flag on the paragraph and not a geometry: where the highlight lands
  /// follows from how the text lays out, which is the rule approved golden 07
  /// attaches to it. See `BookReaderMarkedText`.
  final bool isHighlighted;

  const BookReaderParagraph(this.text, {this.isHighlighted = false});
}

/// Where the reader stands in the publication, in the two units the footer of
/// approved golden 07 is allowed to speak.
///
/// **They are two sources and neither is derived from the other.**
/// [totalProgression] is the reader's own progress through the publication and
/// is always available. A page label comes from the EPUB's `page-list`
/// navigation, the map from a printed edition's pages onto positions in the
/// text, and from nothing else. Golden 05 fixed that the bibliographical page
/// count of an edition is metadata about the edition, golden 06 fixed that
/// screen pages are not a substitute, and this class is where those two rules
/// stop being prose.
///
/// The constructors are the enforcement. There is no way to build a position
/// whose total was counted off the number of `page-list` entries, and no way to
/// hand it the `Pagina's` figure from golden 05's stats row.
@immutable
class BookReaderPosition {
  /// 0.0 to 1.0 through the whole publication.
  final double totalProgression;

  /// The label of the `page-list` entry the locator maps onto, or `null` when
  /// the publication ships no such navigation or the locator does not map onto
  /// it. The label as the publication writes it: a `page-list` may carry `xiv`
  /// or `A-3` as easily as `248`.
  final String? pageLabel;

  /// The publication's last `page-list` label, and only when it is a reliable
  /// number. `null` otherwise, and then the footer says which page without
  /// claiming how many there are.
  final String? totalPageLabel;

  const BookReaderPosition._({required this.totalProgression, this.pageLabel, this.totalPageLabel});

  /// A publication with no usable `page-list`. The footer is the percentage and
  /// nothing else.
  const BookReaderPosition.withoutPageList({required double totalProgression})
    : this._(totalProgression: totalProgression);

  /// A publication whose `page-list` the locator maps onto.
  ///
  /// [terminalLabel] is the last entry's own label and is accepted only when it
  /// reads as a number: a list running `xiv, xv, 1, 2, …` has no `N` to speak
  /// of, and then the footer names the current page and stops. It is never the
  /// number of entries in the list, because a `page-list` is allowed to be
  /// sparse, and never the bibliographical page count from golden 05.
  factory BookReaderPosition.fromPageList({
    required double totalProgression,
    required String currentLabel,
    String? terminalLabel,
  }) {
    final total = terminalLabel != null && int.tryParse(terminalLabel) != null ? terminalLabel : null;
    return BookReaderPosition._(totalProgression: totalProgression, pageLabel: currentLabel, totalPageLabel: total);
  }

  /// Rounded down, so the footer never claims a percentage the reader has not
  /// reached. The same rule as `Book.progressPercent` and `BookTocLocator`.
  int get percent => (totalProgression * 100).floor();

  /// The line under the scrubber, in the three forms golden 07 approves:
  ///
  /// | state | footer |
  /// | --- | --- |
  /// | page-list with a reliable terminal label | `48% · Pagina 248 van 616` |
  /// | page-list, current label only | `48% · Pagina 248` |
  /// | no usable page-list | `48%` |
  String get footerLabel {
    final percentText = t.books.percentRead(percent: percent);
    final page = pageLabel;
    if (page == null) return percentText;
    final total = totalPageLabel;
    final pageText = total == null ? t.books.readerPage(page: page) : t.books.readerPageOf(page: page, total: total);
    return '$percentText · $pageText';
  }
}

/// The page the reader is on, and the running head above it.
@immutable
class BookReaderPage {
  /// The publication's title, for the running head.
  final String bookTitle;

  /// The chapter the page belongs to, or `null` for a page that belongs to no
  /// numbered chapter. The running head then carries the title alone rather
  /// than inventing a chapter for it.
  final int? chapterNumber;

  final List<BookReaderParagraph> paragraphs;

  final BookReaderPosition position;

  const BookReaderPage({required this.bookTitle, required this.paragraphs, required this.position, this.chapterNumber});

  /// `DUNE · HOOFDSTUK 12`.
  ///
  /// Composed by the app rather than taken from the file: the title is the
  /// publication's and stays in its own language, the chapter word is the app's
  /// and follows the interface language. That is the same split golden 06 made
  /// when it put `Hoofdstuk 11 tot 14` under an English part title.
  ///
  /// The uppercase is presentation, not content, and applied here so the running
  /// head has one source.
  String get runningHead {
    final chapter = chapterNumber;
    final head = chapter == null ? bookTitle : '$bookTitle · ${t.books.readerChapter(number: chapter)}';
    return head.toUpperCase();
  }
}
