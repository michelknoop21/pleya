import '../navigation/navigation_tab_id.dart';

/// Stable, agent-addressable automation IDs on a closed set of domains:
/// `screen`, `nav`, `sidebar`, `library`, `discover`, `detail`, `player`,
/// `search`, `settings`, `dialog`, `sheet`, `hub`, `profile`, `overlay`.
///
/// Every automation ID in the app is either a literal here, or the output of
/// [navTab] — never a raw string literal at the call site. Enforced by
/// test/architecture/automation_ids_test.dart.
class AutomationIds {
  AutomationIds._();

  /// `nav.<NavigationTabId.name>` — derived from the enum itself, not a
  /// second hand-written list that could drift out of sync with it.
  static String navTab(NavigationTabId id) => 'nav.${id.name}';

  static const String screenMain = 'screen.main';
  static const String screenDiscover = 'screen.discover';
  static const String screenLibraries = 'screen.libraries';

  /// Boeken-home (approved golden 01b). Ready once its source has answered,
  /// so a scenario waits for content rather than for a first frame.
  static const String screenBooks = 'screen.books';
  static const String screenMediaDetail = 'screen.media_detail';

  /// The nav rail as a whole — bounds for collapse/expand geometry checks.
  static const String sidebarRail = 'sidebar.rail';

  /// The mobile bottom bar as a whole — bounds and slot count. The per-tab
  /// nodes are [navTab], mounted on both the side rail and this bar.
  static const String navBar = 'nav.bar';

  /// One pinned library row on the nav rail. Instanceable: one per visible
  /// library, suffixed `[<globalKey>]`.
  static const String sidebarLibraryRow = 'sidebar.library_row';

  /// Alle boeken (approved golden 02), the grid behind Boeken-home's
  /// `Alle boeken ›`.
  static const String screenAllBooks = 'screen.all_books';

  /// One cell in that page's grid. Instanceable, suffixed `[<index>]`, and a
  /// cell rather than the grid because a sliver has no bounds to measure.
  static const String booksGridItem = 'books.grid.item';

  /// The filter sheet behind Alle boeken's Filters pill (approved golden 03).
  /// A route rather than a page, but a scenario still waits on it, so it
  /// carries a screen id like the other two.
  static const String screenBooksFilters = 'screen.books_filters';

  /// One group in that sheet's left rail. Instanceable, suffixed with the
  /// [BookFilterGroup] name (`[status]`, `[genre]`, …) rather than an index,
  /// because a group with no options on the shelf is left out and an index
  /// would then point at a different group.
  static const String booksFilterGroup = 'books.filter.group';

  /// One choice in the right pane. Instanceable, suffixed with the value it
  /// filters on.
  static const String booksFilterOption = 'books.filter.option';

  /// The sheet's Toepassen button: the only place a choice becomes a filter.
  static const String booksFilterApply = 'books.filter.apply';

  /// Boeken zoeken (approved golden 04), the books-scoped search behind the
  /// search glyph on the books screens.
  static const String screenBooksSearch = 'screen.books_search';

  /// One result row on that screen, whatever its kind. Instanceable, suffixed
  /// with the book id, the author name or the series id.
  static const String booksSearchResult = 'books.search.result';

  /// One category chip. Instanceable, suffixed with the
  /// [BookSearchCategory] name.
  static const String booksSearchCategory = 'books.search.category';

  /// Boekdetail (approved golden 05), the page behind a cover. Reached from a
  /// rail on Boeken-home, a cell in Alle boeken or a book row in Boeken zoeken.
  static const String screenBookDetail = 'screen.book_detail';

  /// The sharp cover on that page — the anchor every other block on it is
  /// measured from, because golden 05's column hangs off the cover's bottom.
  static const String booksDetailCover = 'books.detail.cover';

  /// One of the two full-width actions. Instanceable, `[primary]` for the
  /// reading button and `[secondary]` for Downloaden.
  static const String booksDetailAction = 'books.detail.action';

  /// The year/genre/pages row under the actions.
  static const String booksDetailStats = 'books.detail.stats';

  /// Inhoudsopgave (approved golden 06), the tree of one publication. It has
  /// no door yet — where it opens from is the reader's chrome — so a scenario
  /// reaches it through a route opener and nothing else.
  static const String screenBooksToc = 'screen.books_toc';

  /// The book's own row at the top of the card: cover, title, author.
  static const String booksTocBook = 'books.toc.book';

  /// One part row. Instanceable, suffixed with the part's id rather than an
  /// index, because a collapsed tree draws fewer rows and an index would then
  /// point at a different part.
  static const String booksTocPart = 'books.toc.part';

  /// One chapter row. Instanceable, suffixed with the chapter's id. On the row
  /// and not around the list: a node around a sliver has no bounds to measure.
  static const String booksTocChapter = 'books.toc.chapter';

  /// `Ga naar pagina` in the fixed action bar — drawn only when the
  /// publication ships page navigation.
  static const String booksTocGoto = 'books.toc.goto';

  /// Boeken-home's three rails, in the order golden 01b puts them.
  static const String booksRailContinue = 'books.rail.continue';
  static const String booksRailRecent = 'books.rail.recent';
  static const String booksRailSeries = 'books.rail.series';

  /// The library grid/list scrollable itself (either view mode).
  static const String libraryGrid = 'library.grid';

  /// One card in [libraryGrid]. Instanceable: suffixed `[<index>]`.
  static const String libraryGridItem = 'library.grid.item';

  static const String libraryFilterGrouping = 'library.filter.grouping';
  static const String libraryFilterFilters = 'library.filter.filters';
  static const String libraryFilterSort = 'library.filter.sort';

  /// The Discover hero billboard as a whole.
  static const String discoverHero = 'discover.hero';

  /// The hero's smart-play button.
  static const String discoverHeroPlay = 'discover.hero.play';

  /// The episode list on the media-detail screen (single-season-direct and
  /// per-season-pager paths both render through the same widget).
  static const String mediaDetailEpisodeList = 'media-detail.episode-list';

  /// One row in [mediaDetailEpisodeList]. Instanceable: suffixed `[<index>]`.
  static const String mediaDetailEpisodeListItem = 'media-detail.episode-list.item';

  /// The video player's rendering surface (`lib/mpv/video.dart`).
  static const String playerSurface = 'player.surface';

  /// Base ids a scenario may address as `id[instance]` — see
  /// `pleya_verify/automation_ids.yaml`'s `instanceable` field and the Pleya
  /// Verify plan's instance-ID semantics (Fase 5).
  static const Set<String> instanceableIds = {
    sidebarLibraryRow,
    libraryGridItem,
    mediaDetailEpisodeListItem,
    booksGridItem,
    booksFilterGroup,
    booksFilterOption,
    booksSearchResult,
    booksSearchCategory,
    booksDetailAction,
    booksTocPart,
    booksTocChapter,
  };

  /// The static, autoritative id catalogue `GET /v1/automation_ids` serves,
  /// and the source `pleya_verify/automation_ids.yaml` is generated from
  /// (`tool/generate_automation_ids_yaml.dart`). Deliberately not a dump of
  /// [AutomationRegistry]'s live-mounted nodes — that registry only ever
  /// holds whatever screen happens to be on screen, while a scenario needs
  /// the full, screen-independent set.
  static List<Map<String, Object?>> catalog() => [
    {'id': screenMain, 'role': 'screen', 'instanceable': false},
    {'id': screenDiscover, 'role': 'screen', 'instanceable': false},
    {'id': screenLibraries, 'role': 'screen', 'instanceable': false},
    {'id': screenBooks, 'role': 'screen', 'instanceable': false},
    {'id': screenAllBooks, 'role': 'screen', 'instanceable': false},
    {'id': booksGridItem, 'role': 'grid.item', 'instanceable': true},
    {'id': screenBooksFilters, 'role': 'screen', 'instanceable': false},
    {'id': booksFilterGroup, 'role': 'filter.group', 'instanceable': true},
    {'id': booksFilterOption, 'role': 'filter.option', 'instanceable': true},
    {'id': booksFilterApply, 'role': 'button', 'instanceable': false},
    {'id': screenBooksSearch, 'role': 'screen', 'instanceable': false},
    {'id': booksSearchResult, 'role': 'list.item', 'instanceable': true},
    {'id': booksSearchCategory, 'role': 'filter', 'instanceable': true},
    {'id': screenBookDetail, 'role': 'screen', 'instanceable': false},
    {'id': booksDetailCover, 'role': 'image', 'instanceable': false},
    {'id': booksDetailAction, 'role': 'button', 'instanceable': true},
    {'id': booksDetailStats, 'role': 'list', 'instanceable': false},
    {'id': screenBooksToc, 'role': 'screen', 'instanceable': false},
    {'id': booksTocBook, 'role': 'list.item', 'instanceable': false},
    {'id': booksTocPart, 'role': 'list.item', 'instanceable': true},
    {'id': booksTocChapter, 'role': 'list.item', 'instanceable': true},
    {'id': booksTocGoto, 'role': 'button', 'instanceable': false},
    {'id': booksRailContinue, 'role': 'rail', 'instanceable': false},
    {'id': booksRailRecent, 'role': 'rail', 'instanceable': false},
    {'id': booksRailSeries, 'role': 'rail', 'instanceable': false},
    {'id': screenMediaDetail, 'role': 'screen', 'instanceable': false},
    for (final tab in NavigationTabId.values) {'id': navTab(tab), 'role': 'nav', 'instanceable': false},
    {'id': navBar, 'role': 'nav', 'instanceable': false},
    {'id': sidebarRail, 'role': 'sidebar', 'instanceable': false},
    {'id': sidebarLibraryRow, 'role': 'nav.item', 'instanceable': true},
    {'id': libraryGrid, 'role': 'grid', 'instanceable': false},
    {'id': libraryGridItem, 'role': 'grid.item', 'instanceable': true},
    {'id': libraryFilterGrouping, 'role': 'filter', 'instanceable': false},
    {'id': libraryFilterFilters, 'role': 'filter', 'instanceable': false},
    {'id': libraryFilterSort, 'role': 'filter', 'instanceable': false},
    {'id': discoverHero, 'role': 'hero', 'instanceable': false},
    {'id': discoverHeroPlay, 'role': 'button', 'instanceable': false},
    {'id': mediaDetailEpisodeList, 'role': 'list', 'instanceable': false},
    {'id': mediaDetailEpisodeListItem, 'role': 'list.item', 'instanceable': true},
    {'id': playerSurface, 'role': 'surface', 'instanceable': false},
  ];
}
