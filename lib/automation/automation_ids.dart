import '../navigation/navigation_tabs.dart';

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
  static const String screenMediaDetail = 'screen.media_detail';

  /// The nav rail as a whole — bounds for collapse/expand geometry checks.
  static const String sidebarRail = 'sidebar.rail';

  /// One pinned library row on the nav rail. Instanceable: one per visible
  /// library, suffixed `[<globalKey>]`.
  static const String sidebarLibraryRow = 'sidebar.library_row';

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

  /// One discovery rail's tile band, on a Films/Series landing or the TV Home
  /// feed. Instanceable: suffixed `[<railIndex>]`, top to bottom.
  ///
  /// The band alone, not the whole section: the heading above it and the
  /// metadata block below it are not what a tile is measured against.
  static const String discoverRail = 'discover.rail';

  /// One tile in [discoverRail]. Instanceable: suffixed
  /// `[<railIndex>.<tileIndex>]`, so a scenario can name a tile without the
  /// rails having to share a global counter.
  ///
  /// Its bounds are the tile's artwork *plus* its focus-ring gap on every side
  /// — see `TvExpandableMediaTile.automationId` for why that distinction is the
  /// whole point for an overscan assertion.
  static const String discoverRailItem = 'discover.rail.item';

  /// The inner title-safe rect of a discovery landing: the box that is left
  /// once the page has paid its own insets.
  ///
  /// Registered *inside* the padding, deliberately. Wrapping the page's outer
  /// `Padding` instead would give this node the whole viewport as its rect,
  /// which makes `notClipped` against it true for anything on screen and the
  /// overscan assertion worthless.
  static const String discoverSafeArea = 'discover.safe_area';

  /// The episode list on the media-detail screen (single-season-direct and
  /// per-season-pager paths both render through the same widget).
  static const String mediaDetailEpisodeList = 'media-detail.episode-list';

  /// One row in [mediaDetailEpisodeList]. Instanceable: suffixed `[<index>]`.
  static const String mediaDetailEpisodeListItem = 'media-detail.episode-list.item';

  /// The Mijn Pleya hub as a screen. Its own `AutomationScreen`, because
  /// `screen.main` is mounted for the whole session and says nothing about
  /// which destination is on show.
  static const String screenMyPleya = 'screen.my_pleya';

  /// One tile on the Mijn Pleya hub. Instanceable, suffixed with the
  /// `TvMyPleyaSection.name` it opens (`my_pleya.tile[watchlist]`) — a name
  /// rather than an index, because the tile order changes with what the
  /// profile actually has (Requests only with a Seerr server, Live TV only
  /// with a tuner) and an index would silently address a different section
  /// on a different fixture.
  static const String myPleyaTile = 'my_pleya.tile';

  /// The root of the section a tile opened, suffixed the same way
  /// (`my_pleya.section[watchlist]`). Presence of this node is what makes
  /// "SELECT opened the right thing" assertable; its bounds are what make
  /// the page insets and the seam under the top bar measurable.
  static const String myPleyaSection = 'my_pleya.section';

  /// The content column inside a section, suffixed the same way
  /// (`my_pleya.section.content[settings]`).
  ///
  /// Distinct from [myPleyaSection], which is the whole route and therefore
  /// full-bleed. Alignment is a property of the *column*, not of the route, so
  /// without a node on the column a left-inset assertion would measure the
  /// page background and pass on every page including the misaligned ones.
  /// This is the node `TvPageSurface` puts around its own padded column, which
  /// is what makes the canonical edge a check instead of an opinion.
  static const String myPleyaSectionContent = 'my_pleya.section.content';

  /// One tile *inside* a section page, suffixed with the page and the tile
  /// (`my_pleya.section.tile[settings.about]`).
  ///
  /// Deliberately not [myPleyaTile]. The registry holds every mounted node,
  /// including the screens the shell keeps alive offstage, and `SettingsScreen`
  /// is one of those — it is a main destination as well as a Mijn Pleya
  /// section. Its tile keyed `about` therefore registered as
  /// `my_pleya.tile[about]` alongside the hub's own About tile, and the
  /// resolver handed a scenario the offstage one: `tvos.my-pleya.alignment`
  /// failed with "`my_pleya.tile[about]`.focused is false" while the hub tile
  /// it meant sat there focused as `my_pleya.tile[about]#2`. A hub tile opens
  /// a section and a menu tile lives inside one; they are different things and
  /// now say so.
  ///
  /// The page prefix does the same job one level down, so two sections cannot
  /// collide with each other either.
  static const String myPleyaSectionTile = 'my_pleya.section.tile';

  /// A capsule on a nested section page, suffixed with the page and the chip
  /// (`my_pleya.chip[logs.level_warning]`).
  ///
  /// A page action and a page's picker are the same control here, which is
  /// deliberate: a scenario asserting "the level filter is on warnings" and
  /// one asserting "Copy is disabled because the buffer is empty" both read
  /// `selected` and `enabled` off the same node rather than off two ids that
  /// happen to draw the same capsule.
  static const String myPleyaChip = 'my_pleya.chip';

  /// One row in the Logs reader (`my_pleya.log_row[3]`), indexed within the
  /// filtered list. Carries its level, so "the error filter shows only errors"
  /// is a state assertion instead of a screenshot.
  static const String myPleyaLogRow = 'my_pleya.log_row';

  /// The library page's heading, carrying which library is actually open.
  ///
  /// Hoofdstuk 16's contract is that concrete libraries are visible and
  /// choosable, and the way to prove it is `Movies → Shows → Movies` — which
  /// needs a node that answers "which one am I looking at". Before this the
  /// only thing a scenario could read was a chip's own `selected` flag, and a
  /// chip that marks itself is not evidence that the page behind it changed.
  static const String libraryHeader = 'library.header';

  /// The video player's rendering surface (`lib/mpv/video.dart`).
  static const String playerSurface = 'player.surface';

  /// The mobile bottom navigation bar as a whole (bounds, not per-tab). The
  /// per-tab nodes are [navTab], mounted on both the side rail and this bar.
  static const String navBar = 'nav.bar';

  /// The mobile Home header (lockup, and on Home the conditional actions,
  /// search and avatar) — iOS Unified 2026 fase 1,
  /// `docs/ios-unified-2026-fase1-plan.md` stap 3.
  static const String homeHeader = 'home.header';

  /// The header's search action.
  static const String homeHeaderSearch = 'home.header.search';

  /// The header's profile avatar action.
  static const String homeHeaderAvatar = 'home.header.avatar';

  /// The Series/Films chip bar under the header.
  static const String homeChips = 'home.chips';

  /// One mobile media rail. Instanceable: suffixed `[<railIndex>]`.
  static const String homeRail = 'home.rail';

  /// One card in [homeRail]. Instanceable: suffixed
  /// `[<railIndex>.<itemIndex>]`.
  static const String homeRailItem = 'home.rail.item';

  /// The header of a mobile Series/Films landing — iOS Unified 2026 fase 2.
  ///
  /// Its own id rather than [homeHeader], because the shell keeps every root
  /// destination alive in one `IndexedStack`: Home and both landings mount at
  /// the same time, and two surfaces answering to `home.header` would make
  /// every assertion on it ambiguous. Same reason for [landingRail] next to
  /// [homeRail].
  static const String landingHeader = 'landing.header';

  /// A landing's title row: the page title and, once fase 3 gives it a
  /// destination, the "Alle series"/"Alle films" entry.
  static const String landingTitle = 'landing.title';

  /// One rail on a landing. Instanceable: suffixed `[<railIndex>]`.
  static const String landingRail = 'landing.rail';

  /// One card in [landingRail]. Instanceable: suffixed
  /// `[<railIndex>.<itemIndex>]`.
  static const String landingRailItem = 'landing.rail.item';

  /// The complete-catalogue surface: "Alle films" / "Alle series" — iOS
  /// Unified 2026 fase 3, mockup `03-alle-films.png`.
  ///
  /// Its own family rather than a reuse of the landing ids, for a different
  /// reason than the one that split landing from home. This screen is pushed
  /// above the shell rather than mounted in its `IndexedStack` (DEC-094), so
  /// it never coexists with a landing; the ids are separate because the
  /// surfaces are separate, and a scenario asserting on `catalog.grid` should
  /// fail rather than silently match a rail.
  static const String screenCatalog = 'screen.catalog';

  /// The catalogue's header: back, title, search.
  static const String catalogHeader = 'catalog.header';

  /// The row of three controls: sources, filters, sort.
  static const String catalogControls = 'catalog.controls';

  /// The sources control, which opens the filter sheet on its source section.
  static const String catalogControlSources = 'catalog.controls.sources';

  /// The filters control, carrying the active-filter count.
  static const String catalogControlFilters = 'catalog.controls.filters';

  /// The sort control, labelled with the current sort.
  static const String catalogControlSort = 'catalog.controls.sort';

  /// The "N titles loaded" line plus the active-filter summary.
  static const String catalogStatus = 'catalog.status';

  /// The three-column poster grid, carrying `child_count`.
  ///
  /// A state node, not a geometry one. It wraps a sliver, so it has no
  /// `RenderBox` and a `insideViewport`-style assertion on it fails with "no
  /// bounds" — the same shape [libraryGrid] has. Geometry questions go to
  /// [catalogGridItem].
  static const String catalogGrid = 'catalog.grid';

  /// One card in [catalogGrid]. Instanceable: suffixed `[<index>]`.
  static const String catalogGridItem = 'catalog.grid.item';

  /// The Search destination — iOS Unified 2026 fase 4, mockup
  /// `05-zoeken.png`.
  ///
  /// A screen id like [screenDiscover] and [screenLibraries], and for the same
  /// reason: Search is a root destination in the shell's `IndexedStack`, so
  /// `POST /v1/open` can reach it through the shell's own tab selection. That
  /// is what gives fase 4 a device-independent scenario entry where fase 2 and
  /// fase 3 had none — those surfaces are a tab switch and a push that the
  /// scenario DSL cannot express without coordinates.
  static const String screenSearch = 'screen.search';

  /// The search header: back and the page title.
  static const String searchHeader = 'search.header';

  /// The query field.
  static const String searchField = 'search.field';

  /// The type chips: all, movies, shows, episodes.
  static const String searchChips = 'search.chips';

  /// One result section — Films, Series, Afleveringen, Collecties, Playlists,
  /// Overig, "Niet op je servers". Instanceable: suffixed `[<section key>]`
  /// rather than an index, because which sections exist depends on the query
  /// and an index would move under the caller.
  static const String searchSection = 'search.section';

  /// One row inside [searchSection]. Instanceable: suffixed
  /// `[<section key>/<index>]`.
  static const String searchResult = 'search.result';

  /// The two-column filter sheet — mockup `04-filters-sheet.png`.
  static const String sheetCatalogFilters = 'sheet.catalog_filters';

  /// The sort sheet the sort control opens.
  static const String sheetCatalogSort = 'sheet.catalog_sort';

  /// The mobile source-picker sheet as a whole.
  static const String sheetSourcePicker = 'sheet.source_picker';

  /// One row in [sheetSourcePicker]. Instanceable: suffixed `[<index>]`.
  static const String sheetSourcePickerRow = 'sheet.source_picker.row';

  /// Base ids a scenario may address as `id[instance]` — see
  /// `pleya_verify/automation_ids.yaml`'s `instanceable` field and the Pleya
  /// Verify plan's instance-ID semantics (Fase 5).
  static const Set<String> instanceableIds = {
    sidebarLibraryRow,
    libraryGridItem,
    mediaDetailEpisodeListItem,
    discoverRail,
    discoverRailItem,
    myPleyaTile,
    myPleyaSection,
    myPleyaSectionContent,
    myPleyaSectionTile,
    myPleyaChip,
    myPleyaLogRow,
    homeRail,
    homeRailItem,
    landingRail,
    landingRailItem,
    catalogGridItem,
    searchSection,
    searchResult,
    sheetSourcePickerRow,
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
    {'id': screenMediaDetail, 'role': 'screen', 'instanceable': false},
    for (final tab in NavigationTabId.values) {'id': navTab(tab), 'role': 'nav', 'instanceable': false},
    {'id': navBar, 'role': 'nav', 'instanceable': false},
    {'id': sidebarRail, 'role': 'sidebar', 'instanceable': false},
    {'id': sidebarLibraryRow, 'role': 'nav.item', 'instanceable': true},
    {'id': libraryGrid, 'role': 'grid', 'instanceable': false},
    {'id': libraryGridItem, 'role': 'grid.item', 'instanceable': true},
    {'id': libraryHeader, 'role': 'region', 'instanceable': false},
    {'id': libraryFilterGrouping, 'role': 'filter', 'instanceable': false},
    {'id': libraryFilterFilters, 'role': 'filter', 'instanceable': false},
    {'id': libraryFilterSort, 'role': 'filter', 'instanceable': false},
    {'id': discoverHero, 'role': 'hero', 'instanceable': false},
    {'id': discoverHeroPlay, 'role': 'button', 'instanceable': false},
    {'id': discoverRail, 'role': 'rail', 'instanceable': true},
    {'id': discoverRailItem, 'role': 'grid.item', 'instanceable': true},
    {'id': discoverSafeArea, 'role': 'region', 'instanceable': false},
    {'id': mediaDetailEpisodeList, 'role': 'list', 'instanceable': false},
    {'id': mediaDetailEpisodeListItem, 'role': 'list.item', 'instanceable': true},
    {'id': screenMyPleya, 'role': 'screen', 'instanceable': false},
    {'id': myPleyaTile, 'role': 'grid.item', 'instanceable': true},
    {'id': myPleyaSection, 'role': 'region', 'instanceable': true},
    {'id': myPleyaSectionContent, 'role': 'region', 'instanceable': true},
    {'id': myPleyaSectionTile, 'role': 'grid.item', 'instanceable': true},
    {'id': myPleyaChip, 'role': 'button', 'instanceable': true},
    {'id': myPleyaLogRow, 'role': 'list.item', 'instanceable': true},
    {'id': playerSurface, 'role': 'surface', 'instanceable': false},
    {'id': homeHeader, 'role': 'region', 'instanceable': false},
    {'id': homeHeaderSearch, 'role': 'button', 'instanceable': false},
    {'id': homeHeaderAvatar, 'role': 'button', 'instanceable': false},
    {'id': homeChips, 'role': 'filter', 'instanceable': false},
    {'id': homeRail, 'role': 'rail', 'instanceable': true},
    {'id': homeRailItem, 'role': 'grid.item', 'instanceable': true},
    {'id': landingHeader, 'role': 'region', 'instanceable': false},
    {'id': landingTitle, 'role': 'region', 'instanceable': false},
    {'id': landingRail, 'role': 'rail', 'instanceable': true},
    {'id': landingRailItem, 'role': 'grid.item', 'instanceable': true},
    {'id': screenCatalog, 'role': 'screen', 'instanceable': false},
    {'id': catalogHeader, 'role': 'region', 'instanceable': false},
    {'id': catalogControls, 'role': 'filter', 'instanceable': false},
    {'id': catalogControlSources, 'role': 'button', 'instanceable': false},
    {'id': catalogControlFilters, 'role': 'button', 'instanceable': false},
    {'id': catalogControlSort, 'role': 'button', 'instanceable': false},
    {'id': catalogStatus, 'role': 'region', 'instanceable': false},
    {'id': catalogGrid, 'role': 'grid', 'instanceable': false},
    {'id': catalogGridItem, 'role': 'grid.item', 'instanceable': true},
    {'id': screenSearch, 'role': 'screen', 'instanceable': false},
    {'id': searchHeader, 'role': 'region', 'instanceable': false},
    {'id': searchField, 'role': 'region', 'instanceable': false},
    {'id': searchChips, 'role': 'filter', 'instanceable': false},
    {'id': searchSection, 'role': 'region', 'instanceable': true},
    {'id': searchResult, 'role': 'list.item', 'instanceable': true},
    {'id': sheetCatalogFilters, 'role': 'sheet', 'instanceable': false},
    {'id': sheetCatalogSort, 'role': 'sheet', 'instanceable': false},
    {'id': sheetSourcePicker, 'role': 'sheet', 'instanceable': false},
    {'id': sheetSourcePickerRow, 'role': 'list.item', 'instanceable': true},
  ];
}
