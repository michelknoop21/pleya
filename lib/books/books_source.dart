import 'package:flutter/material.dart';

import 'book.dart';
import 'book_reader_page.dart';
import 'book_text_search.dart';
import 'book_toc.dart';
import 'demo_book_reader.dart';
import 'demo_book_text_search.dart';
import 'demo_book_tocs.dart';

/// Whether this build carries an e-book source at all.
///
/// The e-book data layer does not exist yet; this branch builds the screens it
/// will land in. A production build answers `false`, gets [EmptyBooksSource],
/// and behaves exactly as before: no Boeken destination, fourth navigation
/// slot to Live TV, Kijklijst or Downloads. A build with
/// `--dart-define=PLEYA_BOOKS=true` gets [DemoBooksSource], which is how
/// golden 01b is verified against the running app.
const bool kBooksEnabled = bool.fromEnvironment('PLEYA_BOOKS');

/// The source this build uses. One decision, one place.
BooksSource createBooksSource() => kBooksEnabled ? const DemoBooksSource() : const EmptyBooksSource();

/// Where books come from.
///
/// The seam between the Boeken screens and whatever ends up serving books.
/// Nothing behind this interface exists yet: e-books are a Pleya-native
/// content type, the server does not carry them, and the wire contract for
/// `/v1` is frozen. The screens are built against this, so the day a real
/// source lands it is one implementation and no screen changes.
abstract class BooksSource {
  /// Every book the acting profile may open.
  Future<List<Book>> books();

  /// The series those books belong to.
  Future<List<BookSeries>> series();

  /// The navigation of one publication, and where the reader stands in it.
  ///
  /// `null` for a book whose edition declares none — which is not an error and
  /// not an empty tree: there is simply nothing to draw a table of contents
  /// from. A real source reads this off the EPUB's own `toc` and `page-list`.
  Future<BookToc?> tableOfContents(String bookId);

  /// The page the reader is on, or `null` for a publication this source cannot
  /// open.
  ///
  /// A page and not a book: what a page *is* comes from the reader engine that
  /// lays a publication out at a given type size, and that engine is PS-15. Until
  /// then a source hands the reader a page it already has.
  Future<BookReaderPage?> readerPage(String bookId);

  /// How to search inside the publications this source serves, or `null` for a
  /// source that cannot.
  ///
  /// One object for the source rather than one per book: which publication is
  /// searched is an argument to [BookTextSearch.search], because an index that
  /// covers a shelf is as likely as one per file and this seam should not
  /// prejudge that. `null` is not an error — it is a source with no searchable
  /// text, and then the reader's magnifier stays drawn and inert the way it was
  /// before golden 09.
  BookTextSearch? get textSearch;
}

/// A source with nothing in it: the honest answer for a profile that has no
/// e-books, and the default in a normal build.
class EmptyBooksSource implements BooksSource {
  const EmptyBooksSource();

  @override
  Future<List<Book>> books() async => const [];

  @override
  Future<List<BookSeries>> series() async => const [];

  @override
  Future<BookToc?> tableOfContents(String bookId) async => null;

  @override
  Future<BookReaderPage?> readerPage(String bookId) async => null;

  @override
  BookTextSearch? get textSearch => null;
}

/// The fixed set behind `--dart-define=PLEYA_BOOKS=true`.
///
/// It is the same set golden 01b was drawn with, in the same order, so a
/// simulator screenshot and the approved golden can be put side by side and
/// any difference is a difference in the implementation rather than in the
/// data. It is not a demo mode and not a fallback: a build without that
/// define never constructs it.
class DemoBooksSource implements BooksSource {
  const DemoBooksSource();

  static final DateTime _epoch = DateTime.utc(2026, 9, 1);

  static const _dune = BookArtwork(
    base: Color(0xFF3A1A0B),
    accent: Color(0xFFE08A3C),
    ink: Color(0xFFF7E2C6),
    shape: BookArtworkShape.orb,
  );
  static const _hailMary = BookArtwork(
    base: Color(0xFF101010),
    accent: Color(0xFFF6C62D),
    ink: Color(0xFF111111),
    shape: BookArtworkShape.diagonal,
  );
  static const _sapiens = BookArtwork(
    base: Color(0xFFEFE7D8),
    accent: Color(0xFF3A2F22),
    ink: Color(0xFFB3261E),
    shape: BookArtworkShape.rings,
  );
  static const _nineteen = BookArtwork(
    base: Color(0xFF0C0C0C),
    accent: Color(0xFFCFD6DE),
    ink: Color(0xFFE5140F),
    shape: BookArtworkShape.eye,
  );
  static const _alchemist = BookArtwork(
    base: Color(0xFFC8401A),
    accent: Color(0xFFF7B545),
    ink: Color(0xFFFFF3DF),
    shape: BookArtworkShape.orb,
  );
  static const _atomic = BookArtwork(
    base: Color(0xFFF4F2EC),
    accent: Color(0xFFE5140F),
    ink: Color(0xFF111111),
    shape: BookArtworkShape.plain,
  );
  static const _messiah = BookArtwork(
    base: Color(0xFF0D3742),
    accent: Color(0xFFEF9A3A),
    ink: Color(0xFFF1E6D0),
    shape: BookArtworkShape.orb,
  );
  static const _children = BookArtwork(
    base: Color(0xFF5C1A12),
    accent: Color(0xFFA33A1F),
    ink: Color(0xFFF6D9C4),
    shape: BookArtworkShape.orb,
  );
  static const _sevenSisters = BookArtwork(
    base: Color(0xFF163B4A),
    accent: Color(0xFFE8E4EA),
    ink: Color(0xFFEAF2F6),
    shape: BookArtworkShape.orb,
  );
  static const _hobbit = BookArtwork(
    base: Color(0xFF15522F),
    accent: Color(0xFFCFE7C6),
    ink: Color(0xFFEAF5D8),
    shape: BookArtworkShape.orb,
  );
  static const _braveNewWorld = BookArtwork(
    base: Color(0xFF4A140E),
    accent: Color(0xFFCFD6DE),
    ink: Color(0xFFF6D9C4),
    shape: BookArtworkShape.eye,
  );
  static const _discovery = BookArtwork(
    base: Color(0xFFD2521A),
    accent: Color(0xFFFFD9A0),
    ink: Color(0xFFFFF3DF),
    shape: BookArtworkShape.orb,
  );

  @override
  Future<List<Book>> books() async => [
    Book(
      id: 'dune',
      title: 'Dune',
      author: 'Frank Herbert',
      artwork: _dune,
      seriesId: 'dune',
      progress: 0.48,
      chapterLabel: 'Hoofdstuk 12',
      addedAt: _epoch.subtract(const Duration(days: 30)),
      genres: const ['Sciencefiction'],
      language: 'Engels',
      isDownloaded: true,
      seriesIndex: 1,
      year: 1965,
      pages: 616,
      description:
          'Ver weg in de toekomst krijgt Paul Atreides, een briljante en begaafde jongeman, een lot dat groter is dan hij ooit '
          'had kunnen bevroeden. Hij moet afreizen naar de gevaarlijkste planeet van het universum om de toekomst van zijn '
          'familie en zijn volk veilig te stellen.',
    ),
    Book(
      id: 'hail-mary',
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      artwork: _hailMary,
      progress: 0.21,
      chapterLabel: 'Hoofdstuk 5',
      addedAt: _epoch.subtract(const Duration(days: 1)),
      genres: const ['Sciencefiction'],
      language: 'Engels',
      isDownloaded: true,
      year: 2021,
      pages: 496,
      description:
          'Ryland Grace wordt wakker aan boord van een schip dat hij zich niet herinnert, met twee dode bemanningsleden naast '
          'zich en geen idee wie hij is. Langzaam dringt tot hem door dat de aarde afhangt van wat hij hier alleen voor '
          'elkaar krijgt.',
    ),
    Book(
      id: 'sapiens',
      title: 'Sapiens',
      author: 'Yuval Noah Harari',
      artwork: _sapiens,
      progress: 0.03,
      chapterLabel: 'Hoofdstuk 1',
      addedAt: _epoch.subtract(const Duration(days: 2)),
      genres: const ['Non-fictie', 'Geschiedenis'],
      language: 'Engels',
      isDownloaded: true,
      year: 2011,
      pages: 464,
      description:
          'Honderdduizend jaar geleden deelden minstens zes menssoorten de aarde. Vandaag is er nog één over. Harari volgt hoe '
          'die ene soort van een onopvallend dier in de savanne de heerser van de planeet werd.',
    ),
    Book(
      id: '1984',
      title: '1984',
      author: 'George Orwell',
      artwork: _nineteen,
      addedAt: _epoch.subtract(const Duration(days: 3)),
      // Finished, so Status ▸ Gelezen has something to return. Above
      // isInProgress's 0.995 bound, so it stays out of Verder lezen.
      progress: 1,
      genres: const ['Sciencefiction', 'Literatuur'],
      language: 'Engels',
      year: 1949,
      pages: 328,
      description:
          'Winston Smith herschrijft voor zijn werk het verleden, dag na dag, tot het klopt met wat de Partij vandaag beweert. '
          'Dan begint hij aan een dagboek, en dat is het eerste wat hij ooit voor zichzelf houdt.',
    ),
    Book(
      id: 'alchemist',
      title: 'De Alchemist',
      author: 'Paulo Coelho',
      artwork: _alchemist,
      addedAt: _epoch.subtract(const Duration(days: 4)),
      genres: const ['Literatuur', 'Filosofie'],
      language: 'Nederlands',
      year: 1988,
      pages: 208,
      description:
          'De herdersjongen Santiago droomt twee keer dezelfde droom over een schat bij de piramides, en vertrekt. Wat hij '
          'onderweg leert gaat over alles behalve goud.',
    ),
    Book(
      id: 'atomic-habits',
      title: 'Atomic Habits',
      author: 'James Clear',
      artwork: _atomic,
      addedAt: _epoch.subtract(const Duration(days: 5)),
      genres: const ['Non-fictie', 'Psychologie'],
      language: 'Engels',
      year: 2018,
      pages: 320,
      description:
          'Grote veranderingen komen zelden van grote besluiten. Clear laat zien hoe gewoontes van één procent per dag zich '
          'opstapelen, en waarom het systeem eromheen belangrijker is dan het doel.',
    ),
    // The rest of golden 02's shelf. They are all older than the six above, so
    // Recent toegevoegd on Boeken-home still opens on the three golden 01b
    // shows; a grid needs more than six to judge density on.
    Book(
      id: 'dune-messiah',
      title: 'Dune Messiah',
      author: 'Frank Herbert',
      artwork: _messiah,
      seriesId: 'dune',
      addedAt: _epoch.subtract(const Duration(days: 40)),
      genres: const ['Sciencefiction'],
      language: 'Engels',
      seriesIndex: 2,
      year: 1969,
      pages: 336,
      description:
          'Twaalf jaar na zijn overwinning is Paul Atreides keizer, en gevangene van de heilige oorlog die in zijn naam wordt '
          'gevoerd. Wie hem het naast staat smeedt het complot.',
    ),
    Book(
      id: 'children-of-dune',
      title: 'Children of Dune',
      author: 'Frank Herbert',
      artwork: _children,
      seriesId: 'dune',
      addedAt: _epoch.subtract(const Duration(days: 41)),
      genres: const ['Sciencefiction'],
      language: 'Engels',
      seriesIndex: 3,
      year: 1976,
      pages: 444,
      description:
          'De tweeling Leto en Ghanima erft meer dan een troon: ze dragen de herinneringen van al hun voorouders met zich mee. '
          'Op Arrakis begint het zand te wijken voor gras.',
    ),
    Book(
      id: 'zeven-zussen-1',
      title: 'De Zeven Zussen',
      author: 'Lucinda Riley',
      artwork: _sevenSisters,
      seriesId: 'zeven-zussen',
      addedAt: _epoch.subtract(const Duration(days: 42)),
      genres: const ['Literatuur'],
      language: 'Nederlands',
      isDownloaded: true,
      seriesIndex: 1,
      year: 2014,
      pages: 640,
      description:
          'Na de dood van hun vader krijgen zes geadopteerde zussen elk een aanwijzing naar hun afkomst. Maia is de eerste die '
          'haar spoor volgt, tot in Rio de Janeiro.',
    ),
    Book(
      id: 'hobbit',
      title: 'De Hobbit',
      author: 'J.R.R. Tolkien',
      artwork: _hobbit,
      seriesId: 'midden-aarde',
      addedAt: _epoch.subtract(const Duration(days: 43)),
      // Finished, so Status ▸ Gelezen has something to return. Above
      // isInProgress's 0.995 bound, so it stays out of Verder lezen.
      progress: 1,
      genres: const ['Fantasy'],
      language: 'Nederlands',
      seriesIndex: 1,
      year: 1937,
      pages: 310,
      description:
          'Bilbo Balings wil vooral met rust gelaten worden, en gaat de volgende ochtend toch op pad met dertien dwergen en '
          'een tovenaar. Onderweg vindt hij een ring die niemand mist.',
    ),
    Book(
      id: 'brave-new-world',
      title: 'Brave New World',
      author: 'Aldous Huxley',
      artwork: _braveNewWorld,
      addedAt: _epoch.subtract(const Duration(days: 44)),
      genres: const ['Sciencefiction', 'Literatuur'],
      language: 'Engels',
      year: 1932,
      // No page count, deliberately. Golden 05 makes Pagina's the one optional
      // stat, and an edition that ships none is what makes the two-column
      // fallback real rather than theoretical.
      description:
          'Iedereen is gelukkig, want iedereen is gemaakt voor het leven dat hij krijgt. Tot er iemand binnenkomt die buiten '
          'het systeem geboren is.',
    ),
    // The long one, so the grid's two-line title and its truncation are real
    // rather than theoretical.
    Book(
      id: 'ontdekking-van-de-hemel',
      title: 'De ontdekking van de hemel',
      author: 'Harry Mulisch',
      artwork: _discovery,
      addedAt: _epoch.subtract(const Duration(days: 45)),
      genres: const ['Literatuur', 'Filosofie'],
      language: 'Nederlands',
      year: 1992,
      pages: 936,
      description:
          'Twee vrienden en een vrouw, en een opdracht die van veel hogerhand komt dan zij kunnen zien. Mulisch schrijft de '
          'twintigste eeuw als één samenzwering.',
    ),
  ];

  @override
  Future<BookToc?> tableOfContents(String bookId) async => demoBookToc(bookId);

  @override
  Future<BookReaderPage?> readerPage(String bookId) async => demoBookReaderPage(bookId);

  @override
  BookTextSearch? get textSearch => const DemoBookTextSearch();

  @override
  Future<List<BookSeries>> series() async => const [
    BookSeries(id: 'dune', title: 'Dune', bookCount: 6, artwork: _dune),
    BookSeries(
      id: 'zeven-zussen',
      title: 'De Zeven Zussen',
      bookCount: 7,
      artwork: BookArtwork(
        base: Color(0xFF5C1A12),
        accent: Color(0xFFE8E4EA),
        ink: Color(0xFFF6D9C4),
        shape: BookArtworkShape.orb,
      ),
    ),
    BookSeries(
      id: 'midden-aarde',
      title: 'Midden-aarde',
      bookCount: 4,
      artwork: BookArtwork(
        base: Color(0xFF15522F),
        accent: Color(0xFFCFE7C6),
        ink: Color(0xFFEAF5D8),
        shape: BookArtworkShape.orb,
      ),
    ),
    BookSeries(id: 'james-clear', title: 'James Clear', bookCount: 2, artwork: _atomic),
  ];
}
