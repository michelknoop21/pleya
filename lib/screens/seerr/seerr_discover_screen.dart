import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../models/seerr/seerr_media.dart';
import '../../widgets/desktop_app_bar.dart';
import 'mobile_seerr_discover_view.dart';
import '../../navigation/main_screen_scope.dart';
import '../../navigation/tv/tv_content_route_registry.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/debouncer.dart';
import '../../utils/seerr_error_message.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_header.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/overlay_sheet_geometry.dart';
import '../../widgets/pill_input_decoration.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/state_view.dart';
import '../tv/tv_seerr_discover_view.dart';
import 'seerr_discover_filter_bar.dart';
import 'seerr_grid_sliver.dart';
import 'seerr_media_detail_screen.dart';
import 'seerr_row_grid_screen.dart';
import 'seerr_requests_screen.dart';

/// Jellyseerr / Overseerr ("seerr") discover + search screen.
///
/// A search field sits above a stack of horizontal poster rows (Trending,
/// Popular movies, Popular TV, Upcoming). Typing runs a debounced search and
/// swaps the rows for a results grid. Each row owns its own pagination: reaching
/// the trailing "Load more" tile (via focus or tap) appends the next page.
/// Availability badges come straight from each [SeerrMedia.status]. Tapping a
/// poster opens the graphical [SeerrMediaDetailScreen].
///
/// Reuses the shared [SeerrPosterCard] / [SeerrLoadMoreTile] widgets plus the
/// lower-level focus + layout primitives (`FocusedScrollScaffold`,
/// `TvLayoutConstants`, `SkeletonHubRow`, `StateView`).
/// The discover app bar's trailing actions — empty on TV.
///
/// `FocusedScrollScaffold` wraps its app bar in `ExcludeFocus` on TV, so an
/// action put here cannot be reached with a remote. That is exactly why
/// `_buildSearchField` grows a focusable inbox button beside the search field
/// on TV, with a comment saying so. What never happened is removing this one,
/// so the page drew the same icon, with the same tooltip, calling the same
/// `_openRequests`, twice: one reachable, one decorative (P7).
///
/// A named function rather than an inline `if`, so the rule is assertable
/// without mounting a screen that needs a live Seerr session.
@visibleForTesting
List<Widget> seerrDiscoverAppBarActions({required VoidCallback onOpenRequests}) => [
  if (!PlatformDetector.isTV())
    IconButton(
      tooltip: t.seerr.myRequests,
      icon: const AppIcon(Symbols.inbox_rounded, fill: 1),
      onPressed: onOpenRequests,
    ),
];

class SeerrDiscoverScreen extends StatefulWidget {
  const SeerrDiscoverScreen({super.key, this.initialQuery, this.onBack});

  /// Back to Mijn Pleya on the phone, where this is a tab body that never pops (same
  /// reason as `MobileLibrariesScreen.onBack`). Null on a pushed route.
  final VoidCallback? onBack;

  /// A term to open on, already typed. Mockup 36 C's "Zoek op Aanvragen" hands
  /// the query Zoeken found nothing for straight over, so the viewer does not
  /// type it a second time on a remote.
  final String? initialQuery;

  /// REQ2: opens inside the TV shell when there is one — `openTvContentRoute`
  /// answers null off TV — so a caller never has to know whether it is pushing
  /// a bare route over the shell (the DEC-091 trap that stranded 36 C's own
  /// button in a modal only Menu-then-app-quit could leave) or an ordinary one.
  static Future<void> open(BuildContext context, {String? initialQuery}) async {
    final nested = openTvContentRoute(
      id: 'tvSeerrDiscover',
      builder: (_) => SeerrDiscoverScreen(initialQuery: initialQuery),
    );
    if (nested != null) {
      await nested;
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SeerrDiscoverScreen(initialQuery: initialQuery)));
  }

  @override
  State<SeerrDiscoverScreen> createState() => _SeerrDiscoverScreenState();
}

class _SeerrDiscoverScreenState extends State<SeerrDiscoverScreen> with ControllerDisposerMixin {
  SeerrClient? _client;

  late final List<_SeerrRow> _rows;
  late final TextEditingController _searchController;
  final _searchFocusNode = FocusNode(debugLabel: 'SeerrSearchInput');
  final _firstResultFocusNode = FocusNode(debugLabel: 'SeerrSearchFirstResult');

  /// The two rungs between the search field and the content. Without them the
  /// remote had to fall back on default directional traversal to reach the type
  /// tabs, and a horizontally scrolling row of chips inside a sliver is exactly
  /// where that gets unpredictable.
  final _filterFirstTabFocusNode = FocusNode(debugLabel: 'SeerrFilterFirstTab');
  final _firstDiscoverItemFocusNode = FocusNode(debugLabel: 'SeerrDiscoverFirstItem');
  final _searchDebounce = Debouncer(const Duration(milliseconds: 400));

  String _query = '';
  List<SeerrMedia> _searchResults = const [];
  int _searchPage = 1;
  int _searchTotalPages = 1;
  bool _searchLoadingMore = false;
  bool _searchLoadMoreFailed = false;
  bool _searching = false;
  bool _searchErrored = false;

  // Filters.
  SeerrDiscoverType _type = SeerrDiscoverType.all;
  List<SeerrGenre> _movieGenres = const [];
  List<SeerrGenre> _tvGenres = const [];
  int? _genreId;
  _SeerrRow? _genreRow; // single paginated grid when a genre is active

  /// The shelf "Alles tonen" expanded, on TV only.
  ///
  /// A mode of this page rather than a pushed `SeerrRowGridScreen`: mockup 35 B
  /// draws the expanded row *with the rail beside it*, and the rail's state is
  /// this screen's. Pushing a second screen would mean ferrying the type, the
  /// genre and the provider into it and every change back out again.
  _SeerrRow? _expandedRow;

  /// The TV presentation, when there is one.
  final GlobalKey<TvSeerrDiscoverViewState> _tvKey = GlobalKey<TvSeerrDiscoverViewState>();

  // Streaming services for this region, plus the row that follows the pick.
  List<SeerrWatchProvider> _providers = const [];
  SeerrWatchProvider? _provider;
  _SeerrRow? _providerRow;

  // The phone presents requests as one catalog, like Alle films. Desktop and
  // TV keep their existing shelves and expanded-row behavior.
  _SeerrRow? _phoneCatalogRow;
  MobileSeerrCatalogSort _phoneSort = MobileSeerrCatalogSort.popularity;
  MobileSeerrAvailability _phoneAvailability = MobileSeerrAvailability.all;
  bool _platformLoadsStarted = false;

  @override
  void initState() {
    super.initState();
    _client = context.read<SeerrProvider>().client;
    _searchController = createTextEditingController();
    _rows = [
      _SeerrRow(
        title: t.seerr.trending,
        showIn: const {SeerrDiscoverType.all},
        fetch: (c, p) => c.discoverTrending(page: p),
      ),
      _SeerrRow(
        title: t.seerr.popularMovies,
        showIn: const {SeerrDiscoverType.all, SeerrDiscoverType.movies},
        fetch: (c, p) => c.discoverMovies(page: p),
      ),
      _SeerrRow(
        title: t.seerr.popularTv,
        showIn: const {SeerrDiscoverType.all, SeerrDiscoverType.tv},
        fetch: (c, p) => c.discoverTv(page: p),
      ),
      _SeerrRow(
        title: t.seerr.upcoming,
        showIn: const {SeerrDiscoverType.all, SeerrDiscoverType.movies},
        fetch: (c, p) => c.discoverUpcomingMovies(page: p),
      ),
      _SeerrRow(
        title: t.seerr.upcoming,
        showIn: const {SeerrDiscoverType.tv},
        fetch: (c, p) => c.discoverUpcomingTv(page: p),
      ),
    ];
    final initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      // Through the controller rather than straight into `_runSearch`, so the
      // field shows the term as well as searching for it — the page must not
      // read as if it decided on its own what to look for.
      // Fields are set directly, not via `_onSearchChanged`: that method
      // calls `setState`, which is unnecessary this early — the first build
      // already reflects whatever these fields hold once `initState` returns.
      _searchController.text = initial;
      _query = initial;
      _searching = true;
      _searchDebounce.run(() => unawaited(_runSearch(initial)));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_platformLoadsStarted) return;
    _platformLoadsStarted = true;
    if (PlatformDetector.isPhone(context)) {
      _type = SeerrDiscoverType.movies;
      unawaited(_reloadPhoneCatalog());
      unawaited(_ensureGenres(_type));
      unawaited(_loadProviders());
    } else {
      unawaited(_loadAll());
      unawaited(_loadProviders());
    }
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    _filterFirstTabFocusNode.dispose();
    _firstDiscoverItemFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final client = _client;
    if (client == null) return;
    await Future.wait(_rows.map((row) => _loadFirst(row, client)));
  }

  /// Availability differs per country, so the region comes from the device
  /// locale. Falls back to US, which is what seerr itself defaults to.
  String get _watchRegion => WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase() ?? 'US';

  Future<void> _loadProviders() async {
    final client = _client;
    if (client == null) return;
    final movies = _type != SeerrDiscoverType.tv;
    final providers = await client.getWatchProviders(movies: movies, region: _watchRegion);
    if (!mounted || movies != (_type != SeerrDiscoverType.tv) || providers.isEmpty) return;
    setState(() => _providers = providers.take(10).toList(growable: false));
  }

  Future<void> _selectProvider(SeerrWatchProvider? provider) async {
    final client = _client;
    if (client == null) return;
    if (provider == null || provider.id == _provider?.id) {
      setState(() {
        _provider = null;
        _providerRow = null;
      });
      if (PlatformDetector.isPhone(context)) await _reloadPhoneCatalog();
      return;
    }
    if (PlatformDetector.isPhone(context)) {
      setState(() => _provider = provider);
      await _reloadPhoneCatalog();
      return;
    }
    final wantsTv = _type == SeerrDiscoverType.tv;
    final row = _SeerrRow(
      title: provider.name,
      showIn: const {SeerrDiscoverType.all, SeerrDiscoverType.movies, SeerrDiscoverType.tv},
      fetch: (c, p) => wantsTv
          ? c.discoverTv(page: p, watchProvider: provider.id, watchRegion: _watchRegion)
          : c.discoverMovies(page: p, watchProvider: provider.id, watchRegion: _watchRegion),
    );
    setState(() {
      _provider = provider;
      _providerRow = row;
    });
    await _loadFirst(row, client);
    if (mounted) setState(() {});
  }

  Future<void> _loadFirst(_SeerrRow row, SeerrClient client) async {
    try {
      final page = await row.fetch(client, 1);
      if (!mounted) return;
      setState(() {
        row.items = page.items;
        row.page = page.page;
        row.totalPages = page.totalPages;
        row.loadingFirst = false;
      });
    } catch (e, st) {
      // Broad catch so a non-Seerr parse error can't leave the row stuck on its
      // skeleton forever (which would also wedge the whole-screen empty state).
      // Logged because the row state only records *that* it failed: without
      // this line a 401, a 403 and a 500 are indistinguishable after the fact,
      // and the screen shows the same "try again" for all three.
      appLogger.w('Seerr discover row "${row.title}" failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        row.loadingFirst = false;
        row.errored = true;
        row.errorKind = seerrErrorKindOf(e);
      });
    }
  }

  Future<void> _loadMore(_SeerrRow row) async {
    final client = _client;
    if (client == null || row.loadingMore || row.page >= row.totalPages) return;
    setState(() {
      row.loadingMore = true;
      row.loadMoreFailed = false;
    });
    try {
      final page = await row.fetch(client, row.page + 1);
      if (!mounted) return;
      setState(() {
        row.items = [...row.items, ...page.items];
        row.page = page.page;
        row.totalPages = page.totalPages;
        row.loadingMore = false;
        row.loadMoreFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        row.loadingMore = false;
        row.loadMoreFailed = true;
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      for (final row in _rows) {
        row.reset();
      }
    });
    await _loadAll();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    if (query == _query) return;
    _query = query;
    if (query.isEmpty) {
      _searchDebounce.cancel();
      setState(() {
        _searchResults = const [];
        _searching = false;
        _searchErrored = false;
        _searchLoadMoreFailed = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce.run(() => unawaited(_runSearch(query)));
  }

  Future<void> _runSearch(String query) async {
    final client = _client;
    if (client == null) return;
    try {
      final page = await client.search(query);
      // Drop the result if the query moved on while the request was in flight.
      if (!mounted || _query != query) return;
      setState(() {
        _searchResults = page.items;
        _searchPage = page.page;
        _searchTotalPages = page.totalPages;
        _searching = false;
        _searchErrored = false;
        _searchLoadMoreFailed = false;
      });
    } catch (_) {
      if (!mounted || _query != query) return;
      setState(() {
        _searching = false;
        _searchErrored = true;
      });
    }
  }

  Future<void> _loadMoreSearch() async {
    final client = _client;
    final query = _query;
    if (client == null || _searchLoadingMore || _searchPage >= _searchTotalPages) return;
    setState(() {
      _searchLoadingMore = true;
      _searchLoadMoreFailed = false;
    });
    try {
      final page = await client.search(query, page: _searchPage + 1);
      if (!mounted || _query != query) return;
      setState(() {
        _searchResults = [..._searchResults, ...page.items];
        _searchPage = page.page;
        _searchTotalPages = page.totalPages;
        _searchLoadingMore = false;
        _searchLoadMoreFailed = false;
      });
    } catch (_) {
      if (!mounted || _query != query) return;
      setState(() {
        _searchLoadingMore = false;
        _searchLoadMoreFailed = true;
      });
    }
  }

  /// Only the rows the current filter shows. The whole-screen states have to
  /// be judged on these: with "Shows" selected, two failing TV rows plus a
  /// healthy (but hidden) movie row used to mean "not everything failed", so no
  /// error was shown — and the render loop then skipped both empty rows,
  /// leaving a blank page with nothing to retry.
  Iterable<_SeerrRow> get _visibleRows => _rows.where((r) => r.showIn.contains(_type));

  bool get _allLoaded => _visibleRows.every((r) => !r.loadingFirst);
  bool get _allErrored => _visibleRows.isNotEmpty && _visibleRows.every((r) => r.errored);
  bool get _allEmpty => _visibleRows.every((r) => r.items.isEmpty);

  /// The failure to name when every visible row failed.
  SeerrErrorKind get _dominantErrorKind =>
      dominantSeerrErrorKind(_visibleRows.where((r) => r.errored).map((r) => r.errorKind));

  Future<void> _openDetail(SeerrMedia media) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
  }

  /// [mineOnly]: the phone's "Mijn aanvragen" header, which opens the viewer's own list even
  /// for a manager. The app bar action keeps opening the full one.
  Future<void> _openRequests({bool mineOnly = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrRequestsScreen(mineOnly: mineOnly)));
  }

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  /// Search results narrowed to the active type chip (Overseerr `/search` has no
  /// type param, so we filter client-side).
  List<SeerrMedia> get _filteredSearchResults {
    final byType = switch (_type) {
      SeerrDiscoverType.all => _searchResults,
      SeerrDiscoverType.movies => _searchResults.where((m) => m.isMovie),
      SeerrDiscoverType.tv => _searchResults.where((m) => !m.isMovie),
    };
    if (!PlatformDetector.isPhone(context)) return byType.toList();
    return byType.where((m) => mobileSeerrMatchesAvailability(m.status, _phoneAvailability)).toList();
  }

  /// Picking a segment selects it outright. It used to toggle back to "All"
  /// when you tapped the active chip, which was the only way to get there while
  /// "All" had no chip of its own; the segment now says so on screen.
  void _onTypeSelected(SeerrDiscoverType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _genreId = null;
      _genreRow = null;
      _provider = null;
      _providerRow = null;
      if (PlatformDetector.isPhone(context)) _providers = const [];
    });
    if (_type != SeerrDiscoverType.all) unawaited(_ensureGenres(_type));
    if (PlatformDetector.isPhone(context)) {
      unawaited(_loadProviders());
      unawaited(_reloadPhoneCatalog());
    }
  }

  Future<void> _ensureGenres(SeerrDiscoverType type) async {
    final client = _client;
    if (client == null) return;
    if (type == SeerrDiscoverType.movies && _movieGenres.isNotEmpty) return;
    if (type == SeerrDiscoverType.tv && _tvGenres.isNotEmpty) return;
    try {
      final genres = type == SeerrDiscoverType.movies ? await client.getMovieGenres() : await client.getTvGenres();
      if (!mounted) return;
      setState(() {
        if (type == SeerrDiscoverType.movies) {
          _movieGenres = genres;
        } else {
          _tvGenres = genres;
        }
      });
    } catch (_) {
      // Genres are an optional refinement — a failure just hides the chip row.
    }
  }

  /// [id] is null for "all genres". It used to be a chip you tapped twice to
  /// clear; the picker spells that out as its first row instead.
  void _onGenreSelected(int? id) {
    if (id == _genreId) return;
    setState(() {
      _genreId = id;
      _genreRow = null;
    });
    if (PlatformDetector.isPhone(context)) {
      unawaited(_reloadPhoneCatalog());
    } else if (id != null) {
      unawaited(_loadGenreRow(id));
    }
  }

  Future<void> _loadGenreRow(int genreId) async {
    final client = _client;
    if (client == null) return;
    final type = _type;
    final row = _SeerrRow(
      title: '',
      fetch: (c, p) => type == SeerrDiscoverType.movies
          ? c.discoverMovies(page: p, genre: genreId)
          : c.discoverTv(page: p, genre: genreId),
    );
    setState(() => _genreRow = row);
    await _loadFirst(row, client);
  }

  List<SeerrGenre> get _activeGenres => switch (_type) {
    SeerrDiscoverType.movies => _movieGenres,
    SeerrDiscoverType.tv => _tvGenres,
    SeerrDiscoverType.all => const [],
  };

  Future<void> _reloadPhoneCatalog() async {
    final client = _client;
    if (client == null) return;
    final type = _type == SeerrDiscoverType.tv ? SeerrDiscoverType.tv : SeerrDiscoverType.movies;
    final genre = _genreId;
    final provider = _provider;
    final sort = _phoneSort;
    final row = _SeerrRow(
      title: '',
      fetch: (c, page) => type == SeerrDiscoverType.tv
          ? c.discoverTv(
              page: page,
              genre: genre,
              watchProvider: provider?.id,
              watchRegion: provider == null ? null : _watchRegion,
              sortBy: mobileSeerrSortWire(sort, type),
            )
          : c.discoverMovies(
              page: page,
              genre: genre,
              watchProvider: provider?.id,
              watchRegion: provider == null ? null : _watchRegion,
              sortBy: mobileSeerrSortWire(sort, type),
            ),
    );
    setState(() => _phoneCatalogRow = row);
    await _loadFirst(row, client);
  }

  List<SeerrMedia> get _phoneCatalogItems {
    final items = _phoneCatalogRow?.items ?? const <SeerrMedia>[];
    return items.where((item) => mobileSeerrMatchesAvailability(item.status, _phoneAvailability)).toList();
  }

  int get _phoneActiveFilterCount =>
      (_genreId == null ? 0 : 1) +
      (_provider == null ? 0 : 1) +
      (_phoneAvailability == MobileSeerrAvailability.all ? 0 : 1);

  Future<void> _pickPhoneType(BuildContext sheetContext) async {
    final selected = await showMobileSeerrChoiceSheet<SeerrDiscoverType>(
      sheetContext,
      title: t.seerr.title,
      selected: _type,
      choices: [
        (value: SeerrDiscoverType.movies, label: t.seerr.filterMovies),
        (value: SeerrDiscoverType.tv, label: t.seerr.filterShows),
      ],
    );
    if (selected != null && mounted) _onTypeSelected(selected);
  }

  Future<void> _pickPhoneSort(BuildContext sheetContext) async {
    final selected = await showMobileSeerrChoiceSheet<MobileSeerrCatalogSort>(
      sheetContext,
      title: t.unifiedCatalog.sort.title,
      selected: _phoneSort,
      choices: [
        for (final sort in MobileSeerrCatalogSort.values) (value: sort, label: mobileSeerrSortLabel(sort, _type)),
      ],
    );
    if (selected == null || selected == _phoneSort || !mounted) return;
    setState(() => _phoneSort = selected);
    await _reloadPhoneCatalog();
  }

  Future<void> _pickPhoneFilters(BuildContext sheetContext) async {
    await OverlaySheetController.showAdaptive<void>(
      sheetContext,
      presentation: OverlaySheetPresentation.panel,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refreshSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomSheetHeader(title: t.unifiedCatalog.filters.title),
            Flexible(
              child: ListView(
                primary: false,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _phoneFilterHeading(t.libraries.filterCategories.genre),
                  _phoneFilterChoice(
                    label: t.libraries.all,
                    selected: _genreId == null,
                    onTap: () {
                      _onGenreSelected(null);
                      refreshSheet(() {});
                    },
                  ),
                  for (final genre in _activeGenres)
                    _phoneFilterChoice(
                      label: genre.name,
                      selected: _genreId == genre.id,
                      onTap: () {
                        _onGenreSelected(genre.id);
                        refreshSheet(() {});
                      },
                    ),
                  if (_providers.isNotEmpty) ...[
                    _phoneFilterHeading(t.seerr.byStreamingService),
                    _phoneFilterChoice(
                      label: t.libraries.all,
                      selected: _provider == null,
                      onTap: () {
                        unawaited(_selectProvider(null));
                        refreshSheet(() {});
                      },
                    ),
                    for (final provider in _providers)
                      _phoneFilterChoice(
                        label: provider.name,
                        selected: _provider?.id == provider.id,
                        onTap: () {
                          unawaited(_selectProvider(provider));
                          refreshSheet(() {});
                        },
                      ),
                  ],
                  _phoneFilterHeading(t.seerr.filterAvailable),
                  for (final availability in MobileSeerrAvailability.values)
                    _phoneFilterChoice(
                      label: mobileSeerrAvailabilityLabel(availability),
                      selected: _phoneAvailability == availability,
                      onTap: () {
                        setState(() => _phoneAvailability = availability);
                        refreshSheet(() {});
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneFilterHeading(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _phoneFilterChoice({required String label, required bool selected, required VoidCallback onTap}) {
    return FocusableListTile(
      leading: AppIcon(
        selected ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
        fill: 1,
      ),
      title: Text(label),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // React to the session being torn down (disconnect / profile switch).
    final client = context.watch<SeerrProvider>().client;
    if (client == null) {
      return FocusedScrollScaffold(
        title: Text(t.seerr.discoverTitle),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: StateView.empty(title: t.seerr.noResults, icon: Symbols.movie_rounded),
          ),
        ],
      );
    }

    if (PlatformDetector.isTV()) return _buildTv();
    if (PlatformDetector.isPhone(context)) return _buildPhone();

    return FocusedScrollScaffold(
      title: Text(t.seerr.discoverTitle),
      actions: seerrDiscoverAppBarActions(onOpenRequests: _openRequests),
      slivers: [
        SliverToBoxAdapter(child: _buildSearchField()),
        SliverToBoxAdapter(child: _buildFilterBar()),
        ..._query.isEmpty ? _buildDiscoverSlivers() : _buildSearchSlivers(),
      ],
    );
  }

  /// Aanvragen on the iPhone (northstar 19): search, type pills, the viewer's own
  /// requests, then the same discover rows desktop shows.
  Widget _buildPhone() {
    final row = _phoneCatalogRow;
    return AutomationScreen(
      id: AutomationIds.screenRequests,
      readiness: () => _query.isEmpty && (row?.loadingFirst ?? true)
          ? const AutomationReadiness.loading('requests')
          : const AutomationReadiness.ready(),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            DesktopSliverAppBar(
              title: Text(t.seerr.title),
              leading: widget.onBack == null ? null : BackButton(onPressed: widget.onBack),
              actions: seerrDiscoverAppBarActions(onOpenRequests: _openRequests),
            ),
            SliverToBoxAdapter(child: _buildSearchField()),
            SliverToBoxAdapter(
              child: MobileSeerrCatalogControls(
                type: _type,
                activeFilterCount: _phoneActiveFilterCount,
                sortLabel: mobileSeerrSortLabel(_phoneSort, _type),
                automationInstance: 'requests',
                onTypePressed: () => unawaited(_pickPhoneType(context)),
                onFiltersPressed: () => unawaited(_pickPhoneFilters(context)),
                onSortPressed: () => unawaited(_pickPhoneSort(context)),
              ),
            ),
            if (_query.isEmpty) SliverToBoxAdapter(child: _buildMyRequestsEntry()),
            if (_query.isEmpty && row != null && !row.loadingFirst && !row.errored)
              SliverToBoxAdapter(
                child: AutomationNode(
                  id: AutomationIds.catalogCount,
                  instance: 'requests',
                  role: 'region',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      t.unifiedCatalog.titlesLoaded(count: _phoneCatalogItems.length),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ..._query.isEmpty ? _buildPhoneCatalogSlivers() : _buildSearchSlivers(),
          ],
        ),
      ),
    );
  }

  Widget _buildMyRequestsEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AutomationNode(
        id: AutomationIds.requestsMineItem,
        instance: 'entry',
        role: 'list.item',
        child: Card(
          margin: EdgeInsets.zero,
          child: FocusableListTile(
            leading: const AppIcon(Symbols.inbox_rounded, fill: 1),
            title: Text(t.seerr.myRequests),
            trailing: const AppIcon(Symbols.chevron_right_rounded),
            onTap: () => unawaited(_openRequests(mineOnly: true)),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPhoneCatalogSlivers() {
    final row = _phoneCatalogRow;
    if (row == null || row.loadingFirst) {
      return const [
        SliverPadding(
          padding: EdgeInsets.only(top: 48),
          sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (row.errored) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.error(
            title: seerrErrorMessage(row.errorKind),
            icon: Symbols.cloud_off_rounded,
            onRetry: _reloadPhoneCatalog,
            retryLabel: t.common.retry,
          ),
        ),
      ];
    }
    final items = _phoneCatalogItems;
    if (items.isEmpty && !row.hasMore) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.empty(title: t.seerr.noResults, icon: Symbols.movie_rounded),
        ),
      ];
    }
    return [
      _buildGridSliver(
        items,
        hasMore: row.hasMore,
        loadingMore: row.loadingMore,
        loadMoreFailed: row.loadMoreFailed,
        onLoadMore: () => _loadMore(row),
        automationInstance: 'requests',
      ),
    ];
  }

  /// Ontdekken on TV (DEC-108, mockup 35 A and 35 B).
  ///
  /// The type tabs and the genre picker move into the rail, and the streaming
  /// chips with them; what is left above the content is the search field, which
  /// this screen still builds itself. The three grid modes — a search, a genre,
  /// an expanded shelf — are one `grid` here, because to the viewer they are the
  /// same page showing one list instead of several.
  Widget _buildTv() {
    final grid = _tvGridPage();
    return TvSeerrDiscoverView(
      key: _tvKey,
      searchField: _buildSearchField(),
      shelves: grid != null ? const [] : _tvShelves(),
      grid: grid,
      type: _type,
      onTypeSelected: (type) {
        _collapseRowGrid();
        _onTypeSelected(type);
      },
      genres: [for (final genre in _activeGenres) (id: genre.id, name: genre.name)],
      genreId: _genreId,
      onGenreSelected: (id) {
        _collapseRowGrid();
        _onGenreSelected(id);
      },
      providers: [for (final provider in _providers) (id: provider.id, name: provider.name)],
      providerId: _provider?.id,
      onProviderSelected: (id) {
        _collapseRowGrid();
        unawaited(_selectProvider(id == null ? null : _providers.firstWhere((p) => p.id == id)));
      },
      isLoading: _query.isEmpty ? _visibleRows.any((row) => row.loadingFirst) && _allEmpty : _searching,
      error: _tvError(),
      onReload: () {
        if (_query.isNotEmpty) {
          unawaited(_runSearch(_query));
        } else {
          unawaited(_retry());
        }
      },
      onActivate: _openDetail,
      onLeaveGrid: _tvGridPage() == null ? null : _leaveTvGrid,
      onExitTop: _navigateToSidebar,
    );
  }

  /// Menu out of a grid mode: back to whatever the page was showing before.
  ///
  /// An expanded shelf collapses; a search clears; a genre or a provider is
  /// unset. In every case the page returns to its shelves rather than leaving
  /// the section, which is what a viewer means by Menu one level in.
  void _leaveTvGrid() {
    if (_collapseRowGrid()) return;
    if (_query.isNotEmpty) {
      _clearSearch();
      return;
    }
    if (_genreId != null) {
      _onGenreSelected(null);
      return;
    }
    if (_provider != null) unawaited(_selectProvider(null));
  }

  /// The one list the page shows instead of its shelves, or null while it shows
  /// them.
  TvSeerrGridPage? _tvGridPage() {
    if (_query.isNotEmpty) {
      return TvSeerrGridPage(
        title: t.seerr.title,
        items: _filteredSearchResults,
        hasMore: _searchPage < _searchTotalPages,
        isLoadingMore: _searchLoadingMore,
        onLoadMore: () => unawaited(_loadMoreSearch()),
      );
    }
    final expanded = _expandedRow;
    if (expanded != null) return _tvGridFor(expanded, expanded.title);
    final genreRow = _genreRow;
    if (_type != SeerrDiscoverType.all && _genreId != null && genreRow != null) {
      return _tvGridFor(genreRow, _tvGenreTitle());
    }
    final providerRow = _providerRow;
    if (providerRow != null && _provider != null) return _tvGridFor(providerRow, _provider!.name);
    return null;
  }

  String _tvGenreTitle() {
    for (final genre in _activeGenres) {
      if (genre.id == _genreId) return genre.name;
    }
    return t.seerr.title;
  }

  TvSeerrGridPage _tvGridFor(_SeerrRow row, String title) => TvSeerrGridPage(
    title: title,
    items: row.items,
    hasMore: row.hasMore,
    isLoadingMore: row.loadingMore,
    onLoadMore: () => unawaited(_loadMore(row)),
  );

  List<TvSeerrShelf> _tvShelves() => [
    for (final row in _visibleRows)
      if (!row.loadingFirst)
        TvSeerrShelf(
          // The title is the identity: the row objects are rebuilt on a type
          // change and two shelves never share a title within one type.
          id: row.title,
          title: row.title,
          items: row.items,
          hasMore: row.hasMore,
          isLoadingMore: row.loadingMore,
          onLoadMore: () => unawaited(_loadMore(row)),
          onShowAll: () => _openRowGrid(row),
        ),
  ];

  /// The message to show when the page has nothing at all, or null.
  String? _tvError() {
    if (_query.isNotEmpty) return _searchErrored ? t.seerr.errorNetwork : null;
    if (_expandedRow?.errored ?? false) return seerrErrorMessage(_expandedRow!.errorKind);
    if (_genreRow?.errored ?? false) return seerrErrorMessage(_genreRow!.errorKind);
    if (_providerRow?.errored ?? false) return seerrErrorMessage(_providerRow!.errorKind);
    // The shelves' own aggregate failure, and only while shelves are what the
    // page is actually showing. `_tvGridPage()` non-null means an expanded
    // row, a genre or a provider grid is active; that grid has already
    // answered for itself above (or has none of its own error and is simply
    // showing its items), and must not be overridden by a shelf failure the
    // viewer cannot even see any more — that was the bug: two failed
    // discover shelves kept the page on Retry after a picked genre loaded
    // fine, because this check ran unconditionally.
    if (_tvGridPage() != null) return null;
    if (_allLoaded && _allErrored) return seerrErrorMessage(_dominantErrorKind);
    return null;
  }

  /// Type segments plus, in discover mode with a type active, that type's
  /// genres. Presentation lives in [SeerrDiscoverFilterBar]; this only wires
  /// the state to it.
  Widget _buildFilterBar() {
    return SeerrDiscoverFilterBar(
      type: _type,
      // Genres refine the shelves, and there are no shelves while a search is
      // running: same rule the outlined chip row had.
      genres: _query.isEmpty ? _activeGenres : const [],
      genreId: _genreId,
      onTypeSelected: _onTypeSelected,
      onGenreSelected: _onGenreSelected,
      firstTabFocusNode: _filterFirstTabFocusNode,
      onExitLeft: _navigateToSidebar,
      onExitUp: _searchFocusNode.requestFocus,
      onExitDown: _navigateDownFromFilterBar,
    );
  }

  /// Down from the search field: the results while a search is running, the type
  /// tabs otherwise.
  void _navigateDownFromSearch() {
    if (_filteredSearchResults.isNotEmpty && !_searching) {
      _firstResultFocusNode.requestFocus();
    } else {
      _filterFirstTabFocusNode.requestFocus();
    }
  }

  /// Down from the filter line: the first card under it. Nothing there (loading,
  /// empty, an error panel) leaves focus where it is rather than sending it to a
  /// node that is not on screen.
  ///
  /// While a search is running the shelves are gone and the results carry their
  /// own first-item node, so the discover node is never attached. Without the
  /// switch Down would be a dead key: `handleChipKeyEvent` reports the press as
  /// handled the moment a callback exists, so default traversal never gets a
  /// turn either.
  void _navigateDownFromFilterBar() {
    final target = _query.isEmpty ? _firstDiscoverItemFocusNode : _firstResultFocusNode;
    if (target.context != null) target.requestFocus();
  }

  /// Grid view of [items], delegating to the shared seerr grid so discover and
  /// the expanded row view stay identical.
  Widget _buildGridSliver(
    List<SeerrMedia> items, {
    bool hasMore = false,
    bool loadingMore = false,
    bool loadMoreFailed = false,
    VoidCallback? onLoadMore,
    FocusNode? firstItemFocusNode,
    String? automationInstance,
  }) {
    return buildSeerrGridSliver(
      items: items,
      onTap: _openDetail,
      hasMore: hasMore,
      loadingMore: loadingMore,
      loadMoreFailed: loadMoreFailed,
      onLoadMore: onLoadMore,
      firstItemFocusNode: firstItemFocusNode,
      onExitLeft: _navigateToSidebar,
      onExitTop: _filterFirstTabFocusNode.requestFocus,
      automationInstance: automationInstance,
    );
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _navigateToSidebar() {
    final scope = MainScreenFocusScope.of(context, listen: false);
    if (scope != null) {
      scope.focusSidebar();
    } else {
      // No main-screen scope (modal/test/lifecycle edge): fall back to plain
      // reverse traversal rather than stranding focus in the search field.
      FocusScope.of(context).previousFocus();
    }
  }

  /// TV: hand focus to the first result if there is one, otherwise fall back to
  /// the sidebar. Never leaves focus in limbo (which traps the D-pad).
  void _focusFirstResultOrSidebar() {
    if (_filteredSearchResults.isNotEmpty && !_searching) {
      _firstResultFocusNode.requestFocus();
    } else {
      _navigateToSidebar();
    }
  }

  Widget _buildSearchField() {
    final isTv = PlatformDetector.isTV();
    final inset = isTv ? TvLayoutConstants.horizontalInset : 12.0;
    final field = FocusableTextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.afterFirstFocus,
      // Mirror the working search_screen field: always route focus to a
      // reachable target (first result or sidebar) — never a bare unfocus(),
      // which strands the D-pad with nothing focused and traps the user.
      onEditingComplete: isTv ? _focusFirstResultOrSidebar : null,
      onNavigateLeft: _navigateToSidebar,
      // Down goes to the first thing below that can actually take focus: the
      // result grid while searching, the type tabs otherwise. Leaving it to the
      // field's own down-traversal was the old behaviour and it did not reliably
      // land on the tabs, so the filter line was close to unreachable by remote.
      onNavigateDown: _navigateDownFromSearch,
      onBack: () {
        if (_searchController.text.isNotEmpty) {
          _clearSearch();
        } else {
          _navigateToSidebar();
        }
      },
      decoration: pillInputDecoration(
        context,
        hintText: t.seerr.searchOnSeerrShort,
        prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(icon: const AppIcon(Symbols.close_rounded, fill: 1), onPressed: _clearSearch),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
      // On TV the AppBar action is unreachable (the app bar is excluded from
      // focus), so surface a focusable inbox button beside the search field.
      child: isTv
          ? Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: t.seerr.myRequests,
                  icon: const AppIcon(Symbols.inbox_rounded, fill: 1),
                  onPressed: _openRequests,
                ),
              ],
            )
          : field,
    );
  }

  List<Widget> _buildSearchSlivers() {
    if (_searching) {
      return [
        const SliverPadding(
          padding: EdgeInsets.only(top: 48),
          sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (_searchErrored) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.error(
            title: t.seerr.errorNetwork,
            icon: Symbols.cloud_off_rounded,
            onRetry: () => _runSearch(_query),
          ),
        ),
      ];
    }
    final results = _filteredSearchResults;
    if (results.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.empty(title: t.seerr.noResults, icon: Symbols.search_off_rounded),
        ),
      ];
    }
    return [
      _buildGridSliver(
        results,
        hasMore: _searchPage < _searchTotalPages,
        loadingMore: _searchLoadingMore,
        loadMoreFailed: _searchLoadMoreFailed,
        onLoadMore: _loadMoreSearch,
        firstItemFocusNode: _firstResultFocusNode,
      ),
    ];
  }

  List<Widget> _buildDiscoverSlivers() {
    // A genre is active → one filtered grid instead of the mixed shelves.
    if (_type != SeerrDiscoverType.all && _genreId != null) {
      return _buildGenreGridSlivers();
    }

    // Fatal: every row failed to load its first page.
    if (_allLoaded && _allErrored) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.error(
            title: seerrErrorMessage(_dominantErrorKind),
            icon: Symbols.cloud_off_rounded,
            onRetry: _retry,
            retryLabel: t.common.retry,
          ),
        ),
      ];
    }

    // All rows loaded successfully but empty.
    if (_allLoaded && !_allErrored && _allEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.empty(title: t.seerr.noResults, icon: Symbols.movie_rounded),
        ),
      ];
    }

    final slivers = <Widget>[];
    // The first row that actually renders owns the node the filter line aims at.
    var firstItemNodeTaken = false;
    for (final row in _rows) {
      if (!row.showIn.contains(_type)) continue;
      if (row.loadingFirst) {
        slivers.add(SliverToBoxAdapter(child: _RowHeaderSkeleton(title: row.title)));
        continue;
      }
      // Skip a row that finished empty (errored or genuinely no results) while
      // other rows still have content.
      if (row.items.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(
          child: _SeerrRowView(
            row: row,
            onTapItem: _openDetail,
            onLoadMore: () => _loadMore(row),
            onShowAll: () => _openRowGrid(row),
            firstItemFocusNode: firstItemNodeTaken ? null : _firstDiscoverItemFocusNode,
          ),
        ),
      );
      firstItemNodeTaken = true;
    }
    if (_providers.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(child: _buildProviderPicker()));
      final row = _providerRow;
      if (row != null && !row.loadingFirst && row.items.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: _SeerrRowView(
              row: row,
              onTapItem: _openDetail,
              onLoadMore: () => _loadMore(row),
              onShowAll: () => _openRowGrid(row),
            ),
          ),
        );
      } else if (row != null && row.loadingFirst) {
        slivers.add(SliverToBoxAdapter(child: _RowHeaderSkeleton(title: row.title)));
      }
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }

  void _openRowGrid(_SeerrRow row) {
    if (PlatformDetector.isTV()) {
      setState(() => _expandedRow = row);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tvKey.currentState?.focusFirstContent();
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeerrRowGridScreen(title: row.title, fetch: row.fetch),
      ),
    );
  }

  /// Menu out of the expanded row, back to the shelves.
  bool _collapseRowGrid() {
    if (_expandedRow == null) return false;
    setState(() => _expandedRow = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvKey.currentState?.focusFirstContent();
    });
    return true;
  }

  /// Streaming services for this region. Picking one swaps the row underneath,
  /// the way seerr's own discover does it; picking it again clears the row.
  Widget _buildProviderPicker() {
    final inset = PlatformDetector.isTV() ? TvLayoutConstants.horizontalInset : _rowInset;
    return Padding(
      padding: EdgeInsets.only(left: inset, right: inset, top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.seerr.byStreamingService, style: seerrRowHeaderStyle(context)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in _providers)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FocusableFilterChip(
                      label: p.name,
                      selected: _provider?.id == p.id,
                      onPressed: () => unawaited(_selectProvider(p)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The single grid shown when a genre chip is active.
  List<Widget> _buildGenreGridSlivers() {
    final row = _genreRow;
    if (row == null || row.loadingFirst) {
      return const [
        SliverPadding(
          padding: EdgeInsets.only(top: 48),
          sliver: SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (row.errored) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.error(
            title: seerrErrorMessage(row.errorKind),
            icon: Symbols.cloud_off_rounded,
            onRetry: () {
              final gid = _genreId;
              if (gid != null) unawaited(_loadGenreRow(gid));
            },
            retryLabel: t.common.retry,
          ),
        ),
      ];
    }
    if (row.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.empty(title: t.seerr.noResults, icon: Symbols.movie_rounded),
        ),
      ];
    }
    return [
      _buildGridSliver(
        row.items,
        hasMore: row.hasMore,
        loadingMore: row.loadingMore,
        onLoadMore: () => _loadMore(row),
        firstItemFocusNode: _firstDiscoverItemFocusNode,
      ),
    ];
  }
}

/// Mutable per-row pagination state.
class _SeerrRow {
  _SeerrRow({required this.title, required this.fetch, this.showIn = const {SeerrDiscoverType.all}});

  final String title;
  final Future<SeerrMediaPage> Function(SeerrClient client, int page) fetch;

  /// Which type-filter selections this shelf appears under.
  final Set<SeerrDiscoverType> showIn;

  List<SeerrMedia> items = const [];
  int page = 0;
  int totalPages = 1;
  bool loadingFirst = true;
  bool loadingMore = false;
  bool loadMoreFailed = false;
  bool errored = false;
  SeerrErrorKind errorKind = SeerrErrorKind.generic;

  bool get hasMore => page < totalPages;

  void reset() {
    items = const [];
    page = 0;
    totalPages = 1;
    loadingFirst = true;
    loadingMore = false;
    loadMoreFailed = false;
    errored = false;
    errorKind = SeerrErrorKind.generic;
  }
}

// -----------------------------------------------------------------------------
// Row view
// -----------------------------------------------------------------------------

double get _rowInset => PlatformDetector.isTV() ? TvLayoutConstants.shelfHorizontalInset : 12;

/// Shelf/row header styled like the app's HubSection headers: `titleLarge`,
/// bumped to 26/w700 on TV for legibility across the room.
@visibleForTesting
TextStyle? seerrRowHeaderStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.titleLarge;
  if (PlatformDetector.isTV()) {
    // Through the scale clamp, like every other piece of TV type. A bare 26
    // was 26 logical pixels on every panel, which on the canonical 1038-wide
    // canvas is ~48 reference px — a size no token in
    // `TvDiscoveryLayout`/`TvCatalogLayout` uses, and one that made a shelf
    // heading compete with the page title above it (P7).
    return base?.copyWith(
      fontSize: TvDiscoveryLayout.sectionTitleFontSize * TvLayoutConstants.scaleOf(context),
      fontWeight: FontWeight.w700,
    );
  }
  return base?.copyWith(fontWeight: FontWeight.w700);
}

/// A single horizontal poster row with a header and an optional trailing
/// "Load more" tile.
class _SeerrRowView extends StatelessWidget {
  const _SeerrRowView({
    required this.row,
    required this.onTapItem,
    required this.onLoadMore,
    this.onShowAll,
    this.firstItemFocusNode,
  });

  final _SeerrRow row;
  final ValueChanged<SeerrMedia> onTapItem;
  final VoidCallback onLoadMore;

  /// Opens this row as a full grid. Null hides the action (skeleton rows).
  final VoidCallback? onShowAll;

  /// Set on the topmost row only, so the filter line above has something to aim
  /// DOWN at.
  final FocusNode? firstItemFocusNode;

  @override
  Widget build(BuildContext context) {
    final topGap = PlatformDetector.isTV() ? TvLayoutConstants.shelfVerticalGap / 2 : 8.0;

    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _rowInset),
            child: Row(
              children: [
                Expanded(child: Text(row.title, style: seerrRowHeaderStyle(context))),
                if (onShowAll != null)
                  PlatformDetector.isPhone(context)
                      ? MobileSeerrSeeAllLink(onPressed: onShowAll!)
                      : FocusableFilterChip(
                          label: t.seerr.showAll,
                          icon: Symbols.grid_view_rounded,
                          onPressed: onShowAll!,
                        ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = seerrRowMetricsOf(context, constraints.maxWidth);
              return SizedBox(
                height: metrics.rowHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(horizontal: _rowInset, vertical: metrics.focusReserve),
                  itemCount: row.items.length + (row.hasMore ? 1 : 0),
                  separatorBuilder: (_, _) => SizedBox(width: metrics.itemGap),
                  itemBuilder: (context, index) {
                    if (index >= row.items.length) {
                      return SeerrLoadMoreTile(
                        loading: row.loadingMore,
                        onActivate: onLoadMore,
                        width: metrics.cardWidth,
                      );
                    }
                    final media = row.items[index];
                    return SeerrPosterCard(
                      media: media,
                      onTap: () => onTapItem(media),
                      width: metrics.cardWidth,
                      focusNode: index == 0 ? firstItemFocusNode : null,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Header + skeleton posters shown while a row loads its first page.
class _RowHeaderSkeleton extends StatelessWidget {
  const _RowHeaderSkeleton({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _rowInset),
            child: Text(title, style: seerrRowHeaderStyle(context)),
          ),
          const SizedBox(height: 8),
          SkeletonHubRow(cardWidth: seerrPosterWidth, rowHeight: seerrPosterHeight + 16),
        ],
      ),
    );
  }
}
