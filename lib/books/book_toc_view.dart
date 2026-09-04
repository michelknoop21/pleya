import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import 'book.dart';
import 'book_toc.dart';

/// The four row shapes approved golden 06 puts in the card, in the order it
/// puts them.
enum BookTocRowKind {
  /// The book itself, as the first row: cover, title, author. Panel 6 names
  /// the book nowhere, and on a device this is the one screen of the series
  /// you cannot place without it.
  book,

  /// A loose entry of the top layer — an introduction, a conclusion. One line,
  /// no children, no chevron.
  entry,

  /// A group of chapters. Two lines: its name and the range it spans.
  part,

  /// One chapter, indented, with its number in front of its name.
  chapter,
}

/// One drawn row of the tree.
@immutable
class BookTocRow {
  final BookTocRowKind kind;

  /// The node's own id, or `book` for the book row.
  final String id;

  final String title;

  /// The author for the book row, the chapter range for a part, and nothing
  /// for the other two.
  final String? subtitle;

  final BookTocPosition position;

  /// Parts only, and the reason they carry a chevron at all.
  final bool isExpandable;
  final bool isExpanded;

  /// The dot: on the chapter the reader is in, and on the part that holds the
  /// locator once that part is closed. Never on both at once — a marker says
  /// "the reader is in here", and it belongs to the deepest row that is
  /// actually drawn.
  final bool showsMarker;

  /// Whether a hairline is drawn along this row's top edge.
  ///
  /// Only the boundaries of the top layer get one. Between the chapters of a
  /// part there is none: they are held together by their rhythm and their
  /// indent, and four rules inside one open part would chop the card into
  /// cards — the thing golden 04 already turned down.
  final bool startsSection;

  const BookTocRow({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.position = BookTocPosition.ahead,
    this.isExpandable = false,
    this.isExpanded = false,
    this.showsMarker = false,
    this.startsSection = false,
  });
}

/// What the Inhoudsopgave draws for one book: the rows of the tree, the footer
/// label, and whether the jump control exists.
///
/// Separate from the widget for the same reason `BookDetailView` and
/// `BookSearchRanking` are: golden 06 fixes what the screen looks like, not
/// where a publication's navigation comes from. The day a real source (PS-14)
/// answers with an EPUB's own `toc` and `page-list`, this layer moves and the
/// screen is not touched.
@immutable
class BookTocView {
  final Book book;
  final BookToc toc;

  /// Which parts stand open. Held by the screen, passed in here, so the tree
  /// is derived rather than mutated in place.
  final Set<String> expanded;

  const BookTocView({required this.book, required this.toc, this.expanded = const {}});

  /// `55% gelezen`, or `null` for a publication with no locator — in which
  /// case the bar carries the jump control alone rather than a percentage of
  /// nothing.
  String? get progressLabel {
    final locator = toc.locator;
    return locator == null ? null : t.books.percentReadLong(percent: locator.percent);
  }

  /// Whether `Ga naar pagina` is drawn. See [BookToc.hasPageList] for what
  /// does and does not count as page navigation.
  bool get showsGoToPage => toc.hasPageList;

  /// The rows, top to bottom, exactly as the card stacks them.
  List<BookTocRow> get rows {
    final rows = <BookTocRow>[
      BookTocRow(kind: BookTocRowKind.book, id: 'book', title: book.title, subtitle: book.author),
    ];
    for (final node in toc.nodes) {
      final position = toc.positionOfNode(node);
      switch (node) {
        case BookTocEntry():
          rows.add(
            BookTocRow(
              kind: BookTocRowKind.entry,
              id: node.id,
              title: node.label,
              position: toc.positionOf(node.id),
              startsSection: true,
            ),
          );
        case BookTocPart():
          final isExpanded = expanded.contains(node.id);
          final holdsLocator = position == BookTocPosition.atLocator;
          rows.add(
            BookTocRow(
              kind: BookTocRowKind.part,
              id: node.id,
              title: node.label,
              subtitle: _rangeLabel(node),
              position: position,
              isExpandable: true,
              isExpanded: isExpanded,
              // The marker moves up to the part the moment that part closes,
              // so a collapsed tree still says where the reader is — which is
              // what `06b` exists to show.
              showsMarker: holdsLocator && !isExpanded,
              startsSection: true,
            ),
          );
          if (!isExpanded) continue;
          for (final chapter in node.chapters) {
            final chapterPosition = toc.positionOf(chapter.id);
            rows.add(
              BookTocRow(
                kind: BookTocRowKind.chapter,
                id: chapter.id,
                title: '${chapter.number}. ${chapter.title}',
                position: chapterPosition,
                showsMarker: chapterPosition == BookTocPosition.atLocator,
              ),
            );
          }
      }
    }
    return rows;
  }

  /// `Hoofdstuk 11 tot 14`. Dutch chrome over an English publication, which is
  /// what the app shows for an English edition anyway.
  static String? _rangeLabel(BookTocPart part) {
    final range = part.range;
    if (range == null) return null;
    final (from, to) = range;
    return t.books.tocChapterRange(from: from, to: to);
  }
}
