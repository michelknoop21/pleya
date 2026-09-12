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

  /// The TV shell's profile chip, at the far left of the top bar. Not a
  /// [NavigationTabId]: the chip opens the profile picker on the root
  /// navigator and never becomes an active destination. It carries a `nav` id
  /// anyway because it is a focus stop in the bar, and a walk over that bar
  /// has to be able to name where the leftmost hop lands.
  static const String navProfile = 'nav.profile';

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

  /// The tvOS Menu passthrough as `TvosSystemNavigationService` sees it: no
  /// widget, no bounds, only `state`. Published so a scenario can prove that
  /// no enable went to the engine while a remote key was down (NAV1, DEC-099);
  /// the engine's own half of that defect is out of the simulator's reach.
  static const String tvosMenuPassthrough = 'tvos.menu_passthrough';

  /// The Discover hero billboard as a whole.
  static const String discoverHero = 'discover.hero';

  /// The hero's smart-play button.
  static const String discoverHeroPlay = 'discover.hero.play';

  /// The Continue Watching section on the phone, tablet and desktop Home
  /// (`DiscoverScreen`, not the TV feed). Present whenever the row has items.
  ///
  /// Its `state` publishes `hero_visible`, mirroring the screen's own
  /// `_isHeroSectionVisible`: DEC-097 point 3 makes "no recently released
  /// film" mean "no hero, Continue Watching first", and a scenario that wants
  /// to prove that fallback needs a node that exists in the fallback state.
  /// The hero node cannot carry it, because in that state it is not built.
  static const String discoverContinueWatching = 'discover.continue_watching';

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

  /// The horizontal seizoenchips row on TV series detail (PB-4, DEC-109), the
  /// only focus row that changes which season [mediaDetailEpisodeList] shows.
  static const String mediaDetailSeasonChips = 'media-detail.season-chips';

  /// One chip in [mediaDetailSeasonChips]. Instanceable: suffixed `[<index>]`.
  static const String mediaDetailSeasonChip = 'media-detail.season-chip';

  /// The phone series-detail tab strip button (I6, mockup 07): Afleveringen/
  /// Vergelijkbaar/Extra's/Details. Instanceable: suffixed `[<index>]`,
  /// same 4 tabs in the same order every time (not conditional like
  /// [sheetContextMenuItem]), so an index is stable here.
  static const String mediaDetailPhoneTab = 'media-detail.phone-tab';

  /// The phone series-detail season dropdown button that opens
  /// [sheetSeasonPicker] (I6, mockup 07). Only rendered when a show has more
  /// than one season.
  static const String mediaDetailPhoneSeasonDropdown = 'media-detail.phone-season-dropdown';

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

  /// The player overlay's title block (title line plus the episode line) — the
  /// text a set that overscans cuts first, which is what PLR1 was.
  static const String playerTitle = 'player.title';

  /// The timeline row of the player overlay: elapsed, bar, remaining/ends-at.
  static const String playerTimeline = 'player.timeline';

  /// The inner title-safe rect of the player overlay, the same shape and the
  /// same reasoning as [discoverSafeArea]: registered *inside* the inset the
  /// overlay pays, so `notClipped` against it means something.
  static const String playerSafeArea = 'player.safe_area';

  /// The TV player panel (`TvInfoPanel`) as a whole; `state` carries the active
  /// tab and sub-view, so a scenario can prove which layer is open.
  static const String playerPanel = 'player.panel';

  /// One pill of the panel. Instanceable: `[information|video|audio|subtitles]`;
  /// `state.active` says whether it is the open tab.
  static const String playerPanelTab = 'player.panel.tab';

  /// One row of the panel. Instanceable: suffixed with the row's key
  /// (`speed`, `volume_boost`, `audio.track.0`, …); `state` carries the row
  /// kind and its value, selection or on/off, whichever applies.
  static const String playerPanelRow = 'player.panel.row';

  /// The tune button in the player bar. On TV it opens [playerPanel] on the
  /// Video tab; RIGHT from play/pause lands on it, which is how a scenario
  /// reaches the panel on a simulator that cannot swipe.
  static const String playerSettingsButton = 'player.settings_button';

  /// The mobile bottom navigation bar as a whole (bounds, not per-tab). The
  /// per-tab nodes are [navTab], mounted on both the side rail and this bar.
  static const String navBar = 'nav.bar';

  /// The mobile Home header (lockup, and on Home the conditional actions,
  /// search and avatar) — iOS Unified 2026 fase 1,
  /// `docs/ios-unified-2026-fase1-plan.md` stap 3.
  static const String homeHeader = 'home.header';

  /// The header's search action.
  static const String homeHeaderSearch = 'home.header.search';

  /// The header's profile avatar. Not tappable: profile switching's own
  /// entry point is elsewhere (fase 6, DEC-102), so this node exists for
  /// scenarios to find the avatar, not to activate it.
  static const String homeHeaderAvatar = 'home.header.avatar';

  /// The Series/Films chip bar under the header.
  static const String homeChips = 'home.chips';

  /// One mobile media rail. Instanceable: suffixed `[<railIndex>]`.
  static const String homeRail = 'home.rail';

  /// One card in [homeRail]. Instanceable: suffixed
  /// `[<railIndex>.<itemIndex>]`.
  static const String homeRailItem = 'home.rail.item';

  /// The Series and Films landing screens (iOS Unified 2026 fase 2, DEC-104).
  static const String screenSeries = 'screen.series';
  static const String screenMovies = 'screen.movies';

  /// A landing's header, title line, "Alle series"/"Alle films" action and one
  /// of its rails. All four are instanceable and all four carry the landing's
  /// kind, because Home, Series and Films are children of the same
  /// `IndexedStack` and therefore all mounted at once: an id without the kind
  /// would name two rows at the same moment, which is the collision
  /// [myPleyaSectionTile] documents.
  ///
  /// `landing.header[series]`, `landing.title[movies]`,
  /// `landing.view_all[series]`, `landing.rail[series.0]`.
  static const String landingHeader = 'landing.header';
  static const String landingHeaderSearch = 'landing.header.search';
  static const String landingHeaderAvatar = 'landing.header.avatar';
  static const String landingTitle = 'landing.title';
  static const String landingViewAll = 'landing.view_all';
  static const String landingRail = 'landing.rail';
  static const String landingRailItem = 'landing.rail.item';

  /// One phone result-group section on Zoeken (I4, `05-zoeken.png`):
  /// movies/shows/episodes/collections/playlists/people/other. Instanceable
  /// by section id (`search.results.section[people]`) — hoofdstuk 16.1's
  /// section names, the same ids the TV rails already use in
  /// `SearchScreenState._tvSections`.
  static const String searchResultsSection = 'search.results.section';

  /// One row inside [searchResultsSection]. Instanceable
  /// `<sectionId>.<index>` (`search.results.item[people.0]`), the same
  /// `<family>.<index>` shape [landingRailItem]/[discoverRailItem] use.
  static const String searchResultsItem = 'search.results.item';

  /// The mobile source-picker sheet as a whole.
  static const String sheetSourcePicker = 'sheet.source_picker';

  /// One row in [sheetSourcePicker]. Instanceable: suffixed `[<index>]`.
  static const String sheetSourcePickerRow = 'sheet.source_picker.row';

  /// The phone series-detail season picker (I6, mockup 07) as a whole.
  static const String sheetSeasonPicker = 'sheet.season_picker';

  /// One row in [sheetSeasonPicker]. Instanceable: suffixed `[<index>]`,
  /// same shape as [sheetSourcePickerRow].
  static const String sheetSeasonPickerRow = 'sheet.season_picker.row';

  /// The mobile unified context menu (mockup 09,
  /// `docs/assets/ios-unified/northstar/09-contextmenu-sheet.png`) as a whole.
  static const String sheetContextMenu = 'sheet.context_menu';

  /// One action row in [sheetContextMenu]. Instanceable: suffixed with the
  /// `UnifiedGroupAction.name` it dispatches (`sheet.context_menu.item[markWatched]`),
  /// a name rather than an index because the action set is conditional on
  /// group state and an index would silently address a different action on a
  /// different fixture — the same reasoning [myPleyaTile] documents.
  static const String sheetContextMenuItem = 'sheet.context_menu.item';

  /// The Alle films/Alle series catalogue screens (iOS Unified 2026 fase 3,
  /// `docs/ios-unified-2026-fase3-plan.md`). Two separate consts rather than
  /// one instanceable id, the same choice [screenSeries]/[screenMovies] made:
  /// each screen is pushed on its own, kind is the whole identity.
  static const String screenCatalogMovies = 'screen.catalog_movies';
  static const String screenCatalogSeries = 'screen.catalog_series';

  /// A catalogue screen's header, its three chips, its count line, its grid
  /// and one grid cell. All instanceable and all carry the kind
  /// (`catalog.chip.filters[movies]`, `catalog.grid.item[series.4]`) for the
  /// same reason [landingHeader] does: a screen the viewer left on the
  /// Navigator stack can still be mounted underneath the one they are
  /// looking at.
  static const String catalogHeader = 'catalog.header';
  static const String catalogHeaderSearch = 'catalog.header.search';
  static const String catalogChipSources = 'catalog.chip.sources';
  static const String catalogChipFilters = 'catalog.chip.filters';
  static const String catalogChipSort = 'catalog.chip.sort';
  static const String catalogCount = 'catalog.count';
  static const String catalogGrid = 'catalog.grid';
  static const String catalogGridItem = 'catalog.grid.item';

  /// The catalogue filter sheet (fase 3) as a whole, one category row, one
  /// option row, and its two footer actions. Not suffixed with a kind: a
  /// modal sheet is exclusive, so only one of these is ever mounted at once.
  static const String sheetCatalogFilters = 'sheet.catalog_filters';
  static const String sheetCatalogFiltersCategory = 'sheet.catalog_filters.category';
  static const String sheetCatalogFiltersOption = 'sheet.catalog_filters.option';
  static const String sheetCatalogFiltersClear = 'sheet.catalog_filters.clear';
  static const String sheetCatalogFiltersApply = 'sheet.catalog_filters.apply';

  /// The catalogue sort sheet (fase 3) and one of its options. Same exclusive
  /// reasoning as [sheetCatalogFilters].
  static const String sheetCatalogSort = 'sheet.catalog_sort';
  static const String sheetCatalogSortOption = 'sheet.catalog_sort.option';

  /// The TV surfaces that share CAT5's rail and the catalog grid: Films,
  /// Series, Kijklijst, Alle aanvragen and Zoeken
  /// ([DEC-108](../../docs/DECISIONS.md#dec-108)).
  ///
  /// One instanceable family rather than one set per screen, because the widgets
  /// really are one: a scenario that walks the kijklijst's grid and one that
  /// walks Alle films are the same walk over `tv.catalog.grid[watchlist]` and
  /// `tv.catalog.grid[movies]`. The instance is the surface, and for an item or
  /// a rail row it is `<surface>.<index>` / `<surface>.<row>`, so the surfaces
  /// never have to share a counter.
  static const String tvCatalogGrid = 'tv.catalog.grid';
  static const String tvCatalogGridItem = 'tv.catalog.grid.item';
  static const String tvCatalogRail = 'tv.catalog.rail';
  static const String tvCatalogRailRow = 'tv.catalog.rail.row';

  /// The one non-content state a catalog-language page can be in: empty,
  /// filtered-empty or failed. Instanceable by surface, like the rest.
  static const String tvCatalogState = 'tv.catalog.state';

  /// Base ids a scenario may address as `id[instance]` — see
  /// `pleya_verify/automation_ids.yaml`'s `instanceable` field and the Pleya
  /// Verify plan's instance-ID semantics (Fase 5).
  static const Set<String> instanceableIds = {
    sidebarLibraryRow,
    libraryGridItem,
    mediaDetailEpisodeListItem,
    mediaDetailSeasonChip,
    mediaDetailPhoneTab,
    discoverRail,
    discoverRailItem,
    myPleyaTile,
    myPleyaSection,
    myPleyaSectionContent,
    myPleyaSectionTile,
    myPleyaChip,
    myPleyaLogRow,
    playerPanelTab,
    playerPanelRow,
    homeRail,
    homeRailItem,
    landingHeader,
    landingHeaderSearch,
    landingHeaderAvatar,
    landingTitle,
    landingViewAll,
    landingRail,
    landingRailItem,
    searchResultsSection,
    searchResultsItem,
    sheetSourcePickerRow,
    sheetContextMenuItem,
    sheetSeasonPickerRow,
    catalogHeader,
    catalogHeaderSearch,
    catalogChipSources,
    catalogChipFilters,
    catalogChipSort,
    catalogCount,
    catalogGrid,
    catalogGridItem,
    sheetCatalogFiltersCategory,
    sheetCatalogFiltersOption,
    sheetCatalogSortOption,
    tvCatalogGrid,
    tvCatalogGridItem,
    tvCatalogRail,
    tvCatalogRailRow,
    tvCatalogState,
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
    {'id': navProfile, 'role': 'nav', 'instanceable': false},
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
    {'id': discoverContinueWatching, 'role': 'rail', 'instanceable': false},
    {'id': discoverRail, 'role': 'rail', 'instanceable': true},
    {'id': discoverRailItem, 'role': 'grid.item', 'instanceable': true},
    {'id': discoverSafeArea, 'role': 'region', 'instanceable': false},
    {'id': mediaDetailEpisodeList, 'role': 'list', 'instanceable': false},
    {'id': mediaDetailEpisodeListItem, 'role': 'list.item', 'instanceable': true},
    {'id': mediaDetailSeasonChips, 'role': 'list', 'instanceable': false},
    {'id': mediaDetailSeasonChip, 'role': 'chip', 'instanceable': true},
    {'id': mediaDetailPhoneTab, 'role': 'tab', 'instanceable': true},
    {'id': mediaDetailPhoneSeasonDropdown, 'role': 'button', 'instanceable': false},
    {'id': screenMyPleya, 'role': 'screen', 'instanceable': false},
    {'id': myPleyaTile, 'role': 'grid.item', 'instanceable': true},
    {'id': myPleyaSection, 'role': 'region', 'instanceable': true},
    {'id': myPleyaSectionContent, 'role': 'region', 'instanceable': true},
    {'id': myPleyaSectionTile, 'role': 'grid.item', 'instanceable': true},
    {'id': myPleyaChip, 'role': 'button', 'instanceable': true},
    {'id': myPleyaLogRow, 'role': 'list.item', 'instanceable': true},
    {'id': playerSurface, 'role': 'surface', 'instanceable': false},
    {'id': playerTitle, 'role': 'region', 'instanceable': false},
    {'id': playerTimeline, 'role': 'region', 'instanceable': false},
    {'id': playerSafeArea, 'role': 'region', 'instanceable': false},
    {'id': playerPanel, 'role': 'region', 'instanceable': false},
    {'id': playerPanelTab, 'role': 'tab', 'instanceable': true},
    {'id': playerPanelRow, 'role': 'list.item', 'instanceable': true},
    {'id': playerSettingsButton, 'role': 'button', 'instanceable': false},
    {'id': tvosMenuPassthrough, 'role': 'service', 'instanceable': false},
    {'id': homeHeader, 'role': 'region', 'instanceable': false},
    {'id': homeHeaderSearch, 'role': 'button', 'instanceable': false},
    {'id': homeHeaderAvatar, 'role': 'image', 'instanceable': false},
    {'id': homeChips, 'role': 'filter', 'instanceable': false},
    {'id': homeRail, 'role': 'rail', 'instanceable': true},
    {'id': homeRailItem, 'role': 'grid.item', 'instanceable': true},
    {'id': screenSeries, 'role': 'screen', 'instanceable': false},
    {'id': screenMovies, 'role': 'screen', 'instanceable': false},
    {'id': landingHeader, 'role': 'region', 'instanceable': true},
    {'id': landingHeaderSearch, 'role': 'button', 'instanceable': true},
    {'id': landingHeaderAvatar, 'role': 'image', 'instanceable': true},
    {'id': landingTitle, 'role': 'region', 'instanceable': true},
    {'id': landingViewAll, 'role': 'button', 'instanceable': true},
    {'id': landingRail, 'role': 'rail', 'instanceable': true},
    {'id': landingRailItem, 'role': 'grid.item', 'instanceable': true},
    {'id': searchResultsSection, 'role': 'region', 'instanceable': true},
    {'id': searchResultsItem, 'role': 'list.item', 'instanceable': true},
    {'id': sheetSourcePicker, 'role': 'sheet', 'instanceable': false},
    {'id': sheetSourcePickerRow, 'role': 'list.item', 'instanceable': true},
    {'id': sheetContextMenu, 'role': 'sheet', 'instanceable': false},
    {'id': sheetContextMenuItem, 'role': 'list.item', 'instanceable': true},
    {'id': sheetSeasonPicker, 'role': 'sheet', 'instanceable': false},
    {'id': sheetSeasonPickerRow, 'role': 'list.item', 'instanceable': true},
    {'id': screenCatalogMovies, 'role': 'screen', 'instanceable': false},
    {'id': screenCatalogSeries, 'role': 'screen', 'instanceable': false},
    {'id': catalogHeader, 'role': 'region', 'instanceable': true},
    {'id': catalogHeaderSearch, 'role': 'button', 'instanceable': true},
    {'id': catalogChipSources, 'role': 'button', 'instanceable': true},
    {'id': catalogChipFilters, 'role': 'button', 'instanceable': true},
    {'id': catalogChipSort, 'role': 'button', 'instanceable': true},
    {'id': catalogCount, 'role': 'region', 'instanceable': true},
    {'id': catalogGrid, 'role': 'grid', 'instanceable': true},
    {'id': catalogGridItem, 'role': 'grid.item', 'instanceable': true},
    {'id': sheetCatalogFilters, 'role': 'sheet', 'instanceable': false},
    {'id': sheetCatalogFiltersCategory, 'role': 'list.item', 'instanceable': true},
    {'id': sheetCatalogFiltersOption, 'role': 'list.item', 'instanceable': true},
    {'id': sheetCatalogFiltersClear, 'role': 'button', 'instanceable': false},
    {'id': sheetCatalogFiltersApply, 'role': 'button', 'instanceable': false},
    {'id': sheetCatalogSort, 'role': 'sheet', 'instanceable': false},
    {'id': sheetCatalogSortOption, 'role': 'list.item', 'instanceable': true},
    {'id': tvCatalogGrid, 'role': 'grid', 'instanceable': true},
    {'id': tvCatalogGridItem, 'role': 'grid.item', 'instanceable': true},
    {'id': tvCatalogRail, 'role': 'region', 'instanceable': true},
    {'id': tvCatalogRailRow, 'role': 'list.item', 'instanceable': true},
    {'id': tvCatalogState, 'role': 'region', 'instanceable': true},
  ];
}
