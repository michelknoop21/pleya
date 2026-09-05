import 'book_text_search.dart';

/// The searchable text behind `--dart-define=PLEYA_BOOKS=true`, so a simulator
/// screenshot and approved golden 09 can be put side by side.
///
/// One publication carries it, and it is the one golden 01b, 05 and 07 all read:
/// Dune. The twelve passages are the twelve golden 09a draws for `desert`, in
/// publication order, and two of them are not new — the fifth and the sixth are
/// the sentences that stand on the page golden 07 draws, so this list and the
/// approved reader are demonstrably the same book. They also share a page, which
/// is exactly why a result is a locator and not a page label.
///
/// **The prose is written for this repository and not quoted from the novel**,
/// the same rule `demoBookReaderPage` follows, and it is in English for the same
/// reason: the fixed set carries Dune as an English edition. The search term is
/// therefore `desert` and not `woestijn`. The interface language still makes the
/// header and the count; the chapter labels come from the publication, and this
/// publication writes them the way `Book.chapterLabel` already does.
///
/// **This is a real search over a small corpus, and honest about being that.**
/// Substring matching, folded for case and diacritics, in publication order,
/// with the passage as the window. It is not a relevance engine, it does not
/// pretend to be one, and it is replaced rather than extended when a real index
/// arrives — the same position `LocalBookSearchRanking` takes on the shelf.
class DemoBookTextSearch implements BookTextSearch {
  const DemoBookTextSearch();

  /// Below this a query is treated as no query at all, the bound
  /// `LocalBookSearchRanking` already uses: one letter matches most of a book,
  /// which is a slower way of showing everything.
  @override
  int get minQueryLength => 2;

  /// What the source puts around a window to say the sentence runs on outside
  /// it. It is the source's statement about the excerpt, and a different
  /// statement from the clip the row applies when a window overruns two lines.
  static const String ellipsis = '… ';
  static const String trailingEllipsis = ' …';

  @override
  List<BookSearchHit> search({required String bookId, required String query}) {
    final needle = foldForSearch(query.trim());
    if (needle.length < minQueryLength) return const [];
    final passages = _corpus[bookId];
    if (passages == null) return const [];

    final hits = <BookSearchHit>[];
    for (final passage in passages) {
      final ranges = _rangesIn(passage.text, needle);
      if (ranges.isEmpty) continue;
      hits.add(
        BookSearchHit(
          locator: BookLocator(passage.locator),
          chapterLabel: passage.chapterLabel,
          pageLabel: passage.pageLabel,
          excerpt: '$ellipsis${passage.text}$trailingEllipsis',
          // Shifted past the opening ellipsis, because the ranges are offsets
          // into the excerpt the row draws and not into the passage.
          matchRanges: [
            for (final range in ranges) BookMatchRange(range.start + ellipsis.length, range.end + ellipsis.length),
          ],
        ),
      );
    }
    return hits;
  }

  /// Every occurrence of [needle] in [text], in order. More than one per
  /// passage is the normal case, not the edge case: golden 09b's fourth
  /// specimen has two matches in one excerpt.
  static List<BookMatchRange> _rangesIn(String text, String needle) {
    final haystack = foldForSearch(text);
    final ranges = <BookMatchRange>[];
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) break;
      ranges.add(BookMatchRange(at, at + needle.length));
      from = at + needle.length;
    }
    return ranges;
  }

  static const Map<String, List<_Passage>> _corpus = {'dune': _dune};

  static const List<_Passage> _dune = [
    _Passage(
      locator: 'dune/ch03#p12',
      chapterLabel: 'Hoofdstuk 3',
      pageLabel: '41',
      text: 'the caravan moved after dark, when the desert gave back the day’s heat',
    ),
    _Passage(
      locator: 'dune/ch05#p04',
      chapterLabel: 'Hoofdstuk 5',
      pageLabel: '88',
      text: 'no map of the desert stays true',
    ),
    // Deliberately longer than the two lines the row gives it, because clipping
    // is what the row does with a window that overruns.
    _Passage(
      locator: 'dune/ch07#p21',
      chapterLabel: 'Hoofdstuk 7',
      pageLabel: '132',
      text:
          'she had been taught to read the desert the way other children were taught to read a face, and she was never '
          'once wrong about either of them',
    ),
    _Passage(
      locator: 'dune/ch09#p07',
      chapterLabel: 'Hoofdstuk 9',
      pageLabel: '176',
      text: 'water is the only currency the desert accepts, and it takes payment in advance',
    ),
    // The two sentences of golden 07's page, on the page golden 07 is drawn on.
    _Passage(
      locator: 'dune/ch12#p01',
      chapterLabel: 'Hoofdstuk 12',
      pageLabel: '248',
      text: 'felt the tremor of the desert under his feet, a rhythm he had come to know',
    ),
    _Passage(
      locator: 'dune/ch12#p04',
      chapterLabel: 'Hoofdstuk 12',
      pageLabel: '248',
      text: 'In the silence he heard the voice of the desert, old and patient',
    ),
    _Passage(
      locator: 'dune/ch15#p09',
      chapterLabel: 'Hoofdstuk 15',
      pageLabel: '302',
      text: 'the desert does not forgive a second mistake, and rarely waits for the first',
    ),
    _Passage(
      locator: 'dune/ch18#p16',
      chapterLabel: 'Hoofdstuk 18',
      pageLabel: '359',
      text: 'every crossing of the desert is two crossings, the planned and the survived',
    ),
    _Passage(
      locator: 'dune/ch21#p03',
      chapterLabel: 'Hoofdstuk 21',
      pageLabel: '415',
      text: 'by noon the sun stood over the desert like a judgment, and nothing moved',
    ),
    _Passage(
      locator: 'dune/ch24#p11',
      chapterLabel: 'Hoofdstuk 24',
      pageLabel: '468',
      text: 'he had stopped calling it the desert. It had a name now, and a name changes',
    ),
    // Two matches in one window.
    _Passage(
      locator: 'dune/ch27#p05',
      chapterLabel: 'Hoofdstuk 27',
      pageLabel: '502',
      text: 'many were lost in the desert, and the desert kept no record of them',
    ),
    _Passage(
      locator: 'dune/ch30#p08',
      chapterLabel: 'Hoofdstuk 30',
      pageLabel: '548',
      text: 'the desert had been a wall, then a road, and at the end of it a house',
    ),
  ];
}

/// One window of the publication's text, and where it sits.
///
/// The passage is the window: this fixture carries what golden 09 draws and not
/// the whole novel, so a source that widens or narrows the window is a change in
/// the source and not in the screen.
class _Passage {
  final String locator;
  final String chapterLabel;
  final String? pageLabel;
  final String text;

  const _Passage({required this.locator, required this.chapterLabel, required this.text, this.pageLabel});
}
