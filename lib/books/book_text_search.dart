import 'package:flutter/foundation.dart';

/// An opaque handle to a place in a publication.
///
/// **The identity of a result, and the only thing that is ever navigated on.**
/// What is inside it belongs to the reader engine (PS-15) and to nothing on the
/// screen: a row draws its chapter label and its excerpt, and carries this
/// along untouched.
///
/// Two things are deliberately *not* a locator, and approved golden 09 names
/// both. A character index into a string is not one, and a screen page is not
/// one either: both are gone the moment the reader changes the type size, and a
/// result that moves when you make the letters bigger is not a place in a book.
/// `Pagina 248` is optional navigation metadata from the publication's
/// `page-list`, never an identity — golden 09a draws two different results that
/// both sit on `Hoofdstuk 12 · Pagina 248`, and a screen that addressed them by
/// that label could not tell them apart.
@immutable
class BookLocator {
  /// The publication's own handle for this place, as its source writes it.
  /// Compared, never parsed.
  final String value;

  const BookLocator(this.value);

  @override
  bool operator ==(Object other) => other is BookLocator && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BookLocator($value)';
}

/// Where one match sits inside an excerpt, as a half-open range of code units.
///
/// A drawing instruction and nothing more. It is an offset into [BookSearchHit.excerpt],
/// the string this result carries, so it stays valid however the type is set;
/// it is not an offset into the publication, which is what the locator is for.
@immutable
class BookMatchRange {
  final int start;
  final int end;

  const BookMatchRange(this.start, this.end);

  @override
  bool operator ==(Object other) => other is BookMatchRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'BookMatchRange($start, $end)';
}

/// One place in a publication where a query matched.
///
/// The shape approved golden 09 fixes:
///
/// ```
/// result -> locator + chapterLabel + excerpt + matchRanges
/// ```
///
/// [chapterLabel] comes from the publication's navigation document, [excerpt] is
/// a window around the match rather than a whole sentence, and there are more
/// match ranges than one per excerpt — golden 09b's fourth specimen has two.
@immutable
class BookSearchHit {
  final BookLocator locator;

  /// The first line of the row: where in the publication this is.
  final String chapterLabel;

  /// The printed edition's page label from the `page-list`, or `null` for a
  /// publication that ships none. A suffix in weaker ink, and the row keeps its
  /// chapter alone without it — golden 09b's last specimen.
  final String? pageLabel;

  /// The window of text around the match, with whatever the source uses to say
  /// the sentence runs on outside it. How wide that window is is a parameter of
  /// the source; golden 09 fixes only that it is a window and that the row shows
  /// two lines of it.
  final String excerpt;

  /// Where the matches sit in [excerpt], in order.
  final List<BookMatchRange> matchRanges;

  const BookSearchHit({
    required this.locator,
    required this.chapterLabel,
    required this.excerpt,
    required this.matchRanges,
    this.pageLabel,
  });
}

/// Which places in a publication belong to a query.
///
/// Deliberately its own seam, for the reason [BookSearchRanking] in
/// `book_search.dart` is one: approved golden 09 fixes what a result looks like
/// and what it must be able to say about itself, and leaves everything about the
/// engine open. Whether this runs over the Readium search API or an index of our
/// own, whether that index lives on the device or on the server, whether there
/// is stemming or fuzzy matching, and how results are ordered are all questions
/// this interface is free to answer differently without the screen changing.
///
/// The one thing it is not free to do is rank: golden 09 puts the list in
/// publication order, because a place in a book is not a score.
abstract class BookTextSearch {
  /// The shortest query this source will answer.
  ///
  /// Asked rather than assumed, because it is a property of the engine: a
  /// substring matcher over a shelf in memory needs two characters before the
  /// answer stops being "most of the book", and an engine with a real index may
  /// well need fewer or more. The screen uses it for one thing — to know whether
  /// a search ran at all, so `Geen resultaten gevonden` is never printed under a
  /// query that was never put to anyone.
  int get minQueryLength;

  /// The places in [bookId] that match [query], in publication order.
  ///
  /// Empty for a query too short to mean anything, for a publication this
  /// source cannot read, and for a query that simply finds nothing. The screen
  /// tells those apart by the query it holds, not by three kinds of empty list.
  List<BookSearchHit> search({required String bookId, required String query});
}

const String _foldFrom = 'áàâäãåéèêëíìîïóòôöõúùûüýÿñçø';
const String _foldTo = 'aaaaaaeeeeiiiiooooouuuuyynco';

/// Case- and diacritics-folded text, the same treatment `LocalBookSearchRanking`
/// gives the shelf, so `cafe` finds `café` on both screens rather than on one of
/// them.
///
/// **Folded one code unit at a time, so an offset in the result is the same
/// offset in the input.** That is the property [BookMatchRange] rests on: a
/// match is found in the folded text and drawn in the text the reader sees, and
/// a fold that grew or shrank anywhere would misplace every highlight after it.
/// The handful of characters whose lower case is not a single code unit are
/// therefore left alone rather than expanded.
///
/// It does not trim, for the same reason. Trimming belongs to the query, and the
/// query is trimmed by whoever holds it.
String foldForSearch(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    final lower = char.toLowerCase();
    final folded = lower.length == 1 ? lower : char;
    final index = _foldFrom.indexOf(folded);
    buffer.write(index == -1 ? folded : _foldTo[index]);
  }
  return buffer.toString();
}
