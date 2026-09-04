import 'package:flutter/foundation.dart';

/// Where an entry sits relative to the reader's current locator.
///
/// **Position, never completion.** A locator says where the reader stands now,
/// and therefore only that an entry comes earlier or later in publication
/// order; it says nothing about whether that entry was opened. Jumping to
/// chapter 12 from this very screen would put eleven chapters [behind] the
/// locator without a page of them having been seen, which is exactly why
/// approved golden 06 rejected the reading-state reading of the dimmed row and
/// why nothing here is called `isRead` or `completed`.
///
/// The one global statement about reading is `totalProgression`, in the footer,
/// and it is one number over the whole publication rather than a claim about
/// any single entry.
enum BookTocPosition {
  /// Earlier in publication order than the locator. Drawn dimmed.
  behind,

  /// The entry the locator is in, or — for a group — the group that holds it.
  atLocator,

  /// Later in publication order. Drawn in the ordinary inactive presentation.
  ahead,
}

/// One chapter of a publication.
@immutable
class BookTocChapter {
  /// A stable id for this entry in the publication's navigation.
  final String id;

  /// The chapter's own number, written in front of its name — `12. The Law of
  /// Least Effort`, the way the episode list writes `3. Who Is Alive?`.
  final int number;

  final String title;

  const BookTocChapter({required this.id, required this.number, required this.title});
}

/// One entry of the top layer of the tree.
///
/// Two shapes, because that is what a real table of contents has: groups that
/// hold chapters, and loose entries — an introduction, a conclusion — that hold
/// nothing and carry no chevron.
@immutable
sealed class BookTocNode {
  final String id;
  final String label;

  const BookTocNode({required this.id, required this.label});

  /// The entries this node contributes to publication order, in that order.
  /// A loose entry is its own; a part is its chapters.
  List<String> get readingOrderIds;
}

/// A loose entry of the top layer: one line, no children, no chevron.
@immutable
class BookTocEntry extends BookTocNode {
  const BookTocEntry({required super.id, required super.label});

  @override
  List<String> get readingOrderIds => [id];
}

/// A group of chapters: its name, and the range it spans underneath, so a
/// closed part still says what is in it.
@immutable
class BookTocPart extends BookTocNode {
  final List<BookTocChapter> chapters;

  const BookTocPart({required super.id, required super.label, required this.chapters});

  /// The first and last chapter numbers, for the `Hoofdstuk 11 tot 14` line.
  /// `null` for a part with no chapters, which then says nothing rather than
  /// inventing a range.
  (int, int)? get range => chapters.isEmpty ? null : (chapters.first.number, chapters.last.number);

  @override
  List<String> get readingOrderIds => [for (final chapter in chapters) chapter.id];
}

/// Where the reader stands in a publication, and how far in.
@immutable
class BookTocLocator {
  /// The id of the entry the reader is in — a chapter, or a loose entry.
  final String entryId;

  /// How far through the whole publication, 0.0 to 1.0.
  ///
  /// This is the reader's `totalProgression` and the only number on this
  /// screen: `55% gelezen` in the footer is this value and no row repeats it.
  /// It is one figure over the publication, not a claim that each earlier
  /// entry was finished.
  final double totalProgression;

  const BookTocLocator({required this.entryId, required this.totalProgression});

  /// `55`, rounded down, so the footer never claims a percentage the reader
  /// has not reached. Same rule as `Book.progressPercent`.
  int get percent => (totalProgression * 100).floor();
}

/// A publication's navigation, plus where the reader stands in it.
///
/// The navigation is the publication's; the locator is reader state. They
/// arrive together here because this branch has no reader to own the second
/// one yet — the moment one exists, the locator moves to it and this class
/// keeps only the tree.
@immutable
class BookToc {
  /// The top layer, in publication order. Loose entries and parts mixed, which
  /// is what a real table of contents does.
  final List<BookTocNode> nodes;

  /// Whether the publication ships the `page-list` navigation that maps the
  /// printed edition's pages onto positions in the text.
  ///
  /// The precondition for `Ga naar pagina`, and nothing else is a substitute.
  /// Not screen pages — a reflowable EPUB has no fixed number of them, they
  /// move with type size, typeface and margins. And not the bibliographical
  /// page count from golden 05's stats row either: that is a figure about the
  /// edition, not a map to places in the text. Without it the button stays
  /// away and the bar keeps only the progress label.
  final bool hasPageList;

  final BookTocLocator? locator;

  const BookToc({required this.nodes, this.hasPageList = false, this.locator});

  /// Every entry that occupies a place in publication order — loose entries
  /// and chapters, in reading order. Parts are not in it: a part is a grouping
  /// and the reader is never "in" one except through one of its chapters.
  List<String> get readingOrder => [for (final node in nodes) ...node.readingOrderIds];

  /// Where [entryId] sits relative to the locator.
  ///
  /// [BookTocPosition.ahead] when there is no locator: nothing is behind a
  /// reader who has not started, and the whole tree draws in its ordinary
  /// inactive presentation.
  BookTocPosition positionOf(String entryId) {
    final here = locator?.entryId;
    if (here == null) return BookTocPosition.ahead;
    if (entryId == here) return BookTocPosition.atLocator;
    final order = readingOrder;
    final self = order.indexOf(entryId);
    final current = order.indexOf(here);
    if (self < 0 || current < 0) return BookTocPosition.ahead;
    return self < current ? BookTocPosition.behind : BookTocPosition.ahead;
  }

  /// Where a top-layer node sits: a part that holds the locator is
  /// [BookTocPosition.atLocator], one whose every chapter ends before it is
  /// [BookTocPosition.behind].
  BookTocPosition positionOfNode(BookTocNode node) {
    final ids = node.readingOrderIds;
    if (ids.isEmpty) return BookTocPosition.ahead;
    if (ids.any((id) => positionOf(id) == BookTocPosition.atLocator)) return BookTocPosition.atLocator;
    return ids.every((id) => positionOf(id) == BookTocPosition.behind) ? BookTocPosition.behind : BookTocPosition.ahead;
  }

  /// The parts the tree arrives open: the one the reader is in, and no other.
  ///
  /// Collapsing everything is a state you can reach, not the state you arrive
  /// in — that is what `06b` shows.
  Set<String> get initiallyExpanded => {
    for (final node in nodes)
      if (node is BookTocPart && positionOfNode(node) == BookTocPosition.atLocator) node.id,
  };
}
