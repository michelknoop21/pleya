import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../models/seerr/seerr_media.dart';
import '../../navigation/main_screen_scope.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/debouncer.dart';
import '../../utils/seerr_error_message.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/pill_input_decoration.dart';
import '../../widgets/seerr_poster_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/state_view.dart';
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
/// Discover/search type filter. `all` shows the mixed shelves; `movies` / `tv`
/// narrow the shelves (and enable genre chips in discover, client-side type
/// filtering in search).
enum _SeerrType { all, movies, tv }

class SeerrDiscoverScreen extends StatefulWidget {
  const SeerrDiscoverScreen({super.key});

  @override
  State<SeerrDiscoverScreen> createState() => _SeerrDiscoverScreenState();
}

class _SeerrDiscoverScreenState extends State<SeerrDiscoverScreen> with ControllerDisposerMixin {
  SeerrClient? _client;
  late final List<_SeerrRow> _rows;
  late final TextEditingController _searchController;
  final _searchFocusNode = FocusNode(debugLabel: 'SeerrSearchInput');
  final _firstResultFocusNode = FocusNode(debugLabel: 'SeerrSearchFirstResult');
  final _searchDebounce = Debouncer(const Duration(milliseconds: 400));

  String _query = '';
  List<SeerrMedia> _searchResults = const [];
  int _searchPage = 1;
  int _searchTotalPages = 1;
  bool _searchLoadingMore = false;
  bool _searching = false;
  bool _searchErrored = false;

  // Filters.
  _SeerrType _type = _SeerrType.all;
  List<SeerrGenre> _movieGenres = const [];
  List<SeerrGenre> _tvGenres = const [];
  int? _genreId;
  _SeerrRow? _genreRow; // single paginated grid when a genre is active

  // Streaming services for this region, plus the row that follows the pick.
  List<SeerrWatchProvider> _providers = const [];
  SeerrWatchProvider? _provider;
  _SeerrRow? _providerRow;

  @override
  void initState() {
    super.initState();
    _client = context.read<SeerrProvider>().client;
    _searchController = createTextEditingController();
    _rows = [
      _SeerrRow(
        title: t.seerr.trending,
        showIn: const {_SeerrType.all},
        fetch: (c, p) => c.discoverTrending(page: p),
      ),
      _SeerrRow(
        title: t.seerr.popularMovies,
        showIn: const {_SeerrType.all, _SeerrType.movies},
        fetch: (c, p) => c.discoverMovies(page: p),
      ),
      _SeerrRow(
        title: t.seerr.popularTv,
        showIn: const {_SeerrType.all, _SeerrType.tv},
        fetch: (c, p) => c.discoverTv(page: p),
      ),
      _SeerrRow(
        title: t.seerr.upcoming,
        showIn: const {_SeerrType.all, _SeerrType.movies},
        fetch: (c, p) => c.discoverUpcomingMovies(page: p),
      ),
      _SeerrRow(
        title: t.seerr.upcoming,
        showIn: const {_SeerrType.tv},
        fetch: (c, p) => c.discoverUpcomingTv(page: p),
      ),
    ];
    unawaited(_loadAll());
    unawaited(_loadProviders());
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
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
    final providers = await client.getWatchProviders(movies: _type != _SeerrType.tv, region: _watchRegion);
    if (!mounted || providers.isEmpty) return;
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
      return;
    }
    final wantsTv = _type == _SeerrType.tv;
    final row = _SeerrRow(
      title: provider.name,
      showIn: const {_SeerrType.all, _SeerrType.movies, _SeerrType.tv},
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
    setState(() => row.loadingMore = true);
    try {
      final page = await row.fetch(client, row.page + 1);
      if (!mounted) return;
      setState(() {
        row.items = [...row.items, ...page.items];
        row.page = page.page;
        row.totalPages = page.totalPages;
        row.loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => row.loadingMore = false);
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
    setState(() => _searchLoadingMore = true);
    try {
      final page = await client.search(query, page: _searchPage + 1);
      if (!mounted || _query != query) return;
      setState(() {
        _searchResults = [..._searchResults, ...page.items];
        _searchPage = page.page;
        _searchTotalPages = page.totalPages;
        _searchLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || _query != query) return;
      setState(() => _searchLoadingMore = false);
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

  void _openDetail(SeerrMedia media) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
  }

  void _openRequests() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeerrRequestsScreen()));
  }

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  /// Search results narrowed to the active type chip (Overseerr `/search` has no
  /// type param, so we filter client-side).
  List<SeerrMedia> get _filteredSearchResults {
    switch (_type) {
      case _SeerrType.all:
        return _searchResults;
      case _SeerrType.movies:
        return _searchResults.where((m) => m.isMovie).toList();
      case _SeerrType.tv:
        return _searchResults.where((m) => !m.isMovie).toList();
    }
  }

  void _onTypeSelected(_SeerrType type) {
    setState(() {
      _type = (_type == type) ? _SeerrType.all : type;
      _genreId = null;
      _genreRow = null;
    });
    if (_type != _SeerrType.all) unawaited(_ensureGenres(_type));
  }

  Future<void> _ensureGenres(_SeerrType type) async {
    final client = _client;
    if (client == null) return;
    if (type == _SeerrType.movies && _movieGenres.isNotEmpty) return;
    if (type == _SeerrType.tv && _tvGenres.isNotEmpty) return;
    try {
      final genres = type == _SeerrType.movies ? await client.getMovieGenres() : await client.getTvGenres();
      if (!mounted) return;
      setState(() {
        if (type == _SeerrType.movies) {
          _movieGenres = genres;
        } else {
          _tvGenres = genres;
        }
      });
    } catch (_) {
      // Genres are an optional refinement — a failure just hides the chip row.
    }
  }

  void _onGenreSelected(int id) {
    setState(() {
      _genreId = (_genreId == id) ? null : id;
      _genreRow = null;
    });
    final gid = _genreId;
    if (gid != null) unawaited(_loadGenreRow(gid));
  }

  Future<void> _loadGenreRow(int genreId) async {
    final client = _client;
    if (client == null) return;
    final type = _type;
    final row = _SeerrRow(
      title: '',
      fetch: (c, p) =>
          type == _SeerrType.movies ? c.discoverMovies(page: p, genre: genreId) : c.discoverTv(page: p, genre: genreId),
    );
    setState(() => _genreRow = row);
    await _loadFirst(row, client);
  }

  List<SeerrGenre> get _activeGenres => switch (_type) {
    _SeerrType.movies => _movieGenres,
    _SeerrType.tv => _tvGenres,
    _SeerrType.all => const [],
  };

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

    return FocusedScrollScaffold(
      title: Text(t.seerr.discoverTitle),
      actions: [
        IconButton(
          tooltip: t.seerr.myRequests,
          icon: const AppIcon(Symbols.inbox_rounded, fill: 1),
          onPressed: _openRequests,
        ),
      ],
      slivers: [
        SliverToBoxAdapter(child: _buildSearchField()),
        SliverToBoxAdapter(child: _buildFilterBar()),
        ..._query.isEmpty ? _buildDiscoverSlivers() : _buildSearchSlivers(),
      ],
    );
  }

  /// Type chips (Movies / Shows), plus a horizontal genre-chip row when a type
  /// is active in discover mode. Mirrors the search screen's filter-chip style.
  Widget _buildFilterBar() {
    final inset = PlatformDetector.isTV() ? TvLayoutConstants.horizontalInset : 12.0;
    final showGenres = _query.isEmpty && _type != _SeerrType.all && _activeGenres.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: inset, right: inset, bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FocusableFilterChip(
                label: t.seerr.filterMovies,
                selected: _type == _SeerrType.movies,
                onPressed: () => _onTypeSelected(_SeerrType.movies),
              ),
              FocusableFilterChip(
                label: t.seerr.filterShows,
                selected: _type == _SeerrType.tv,
                onPressed: () => _onTypeSelected(_SeerrType.tv),
              ),
            ],
          ),
        ),
        if (showGenres)
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: inset, right: inset, bottom: 8),
              itemCount: _activeGenres.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final g = _activeGenres[index];
                return Center(
                  child: FocusableFilterChip(
                    label: g.name,
                    selected: _genreId == g.id,
                    onPressed: () => _onGenreSelected(g.id),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Grid view of [items], delegating to the shared seerr grid so discover and
  /// the expanded row view stay identical.
  Widget _buildGridSliver(
    List<SeerrMedia> items, {
    bool hasMore = false,
    bool loadingMore = false,
    VoidCallback? onLoadMore,
    FocusNode? firstItemFocusNode,
  }) {
    return buildSeerrGridSliver(
      items: items,
      onTap: _openDetail,
      hasMore: hasMore,
      loadingMore: loadingMore,
      onLoadMore: onLoadMore,
      firstItemFocusNode: firstItemFocusNode,
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
      // Only intercept Down when there are results to jump to. In discover mode
      // (no query) leave it null so the field's built-in down-traversal reaches
      // the filter chips / discover rows below — matches search_screen.dart.
      onNavigateDown: (_filteredSearchResults.isNotEmpty && !_searching) ? _firstResultFocusNode.requestFocus : null,
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
        onLoadMore: _loadMoreSearch,
        firstItemFocusNode: _firstResultFocusNode,
      ),
    ];
  }

  List<Widget> _buildDiscoverSlivers() {
    // A genre is active → one filtered grid instead of the mixed shelves.
    if (_type != _SeerrType.all && _genreId != null) {
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
          ),
        ),
      );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeerrRowGridScreen(title: row.title, fetch: row.fetch),
      ),
    );
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
          Text(t.seerr.byStreamingService, style: _rowHeaderStyle(context)),
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
      _buildGridSliver(row.items, hasMore: row.hasMore, loadingMore: row.loadingMore, onLoadMore: () => _loadMore(row)),
    ];
  }
}

/// Mutable per-row pagination state.
class _SeerrRow {
  _SeerrRow({required this.title, required this.fetch, this.showIn = const {_SeerrType.all}});

  final String title;
  final Future<SeerrMediaPage> Function(SeerrClient client, int page) fetch;

  /// Which type-filter selections this shelf appears under.
  final Set<_SeerrType> showIn;

  List<SeerrMedia> items = const [];
  int page = 0;
  int totalPages = 1;
  bool loadingFirst = true;
  bool loadingMore = false;
  bool errored = false;
  SeerrErrorKind errorKind = SeerrErrorKind.generic;

  bool get hasMore => page < totalPages;

  void reset() {
    items = const [];
    page = 0;
    totalPages = 1;
    loadingFirst = true;
    loadingMore = false;
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
TextStyle? _rowHeaderStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.titleLarge;
  if (PlatformDetector.isTV()) {
    return base?.copyWith(fontSize: 26, fontWeight: FontWeight.w700);
  }
  return base?.copyWith(fontWeight: FontWeight.w700);
}

/// A single horizontal poster row with a header and an optional trailing
/// "Load more" tile.
class _SeerrRowView extends StatelessWidget {
  const _SeerrRowView({required this.row, required this.onTapItem, required this.onLoadMore, this.onShowAll});

  final _SeerrRow row;
  final ValueChanged<SeerrMedia> onTapItem;
  final VoidCallback onLoadMore;

  /// Opens this row as a full grid. Null hides the action (skeleton rows).
  final VoidCallback? onShowAll;

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
                Expanded(child: Text(row.title, style: _rowHeaderStyle(context))),
                if (onShowAll != null)
                  FocusableFilterChip(label: t.seerr.showAll, icon: Symbols.grid_view_rounded, onPressed: onShowAll!),
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
                    return SeerrPosterCard(media: media, onTap: () => onTapItem(media), width: metrics.cardWidth);
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
            child: Text(title, style: _rowHeaderStyle(context)),
          ),
          const SizedBox(height: 8),
          SkeletonHubRow(cardWidth: seerrPosterWidth, rowHeight: seerrPosterHeight + 16),
        ],
      ),
    );
  }
}
