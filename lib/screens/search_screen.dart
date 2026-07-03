import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:rate_limiter/rate_limiter.dart';

import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../mixins/controller_disposer_mixin.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../mixins/refreshable.dart';
import '../providers/multi_server_provider.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/pill_input_decoration.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_view.dart';
import '../utils/focus_utils.dart';
import 'main_screen.dart';

/// Client-side result type filter. Only kinds that [searchAcrossServers]
/// actually returns (movies, shows, episodes) — no "people" row, search
/// results carry no person items.
enum _SearchFilter { all, movies, shows, episodes }

const int _searchHistoryLimit = 15;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with
        Refreshable,
        FullRefreshable,
        SearchInputFocusable,
        FocusableTab,
        ControllerDisposerMixin,
        MountedSetStateMixin {
  late final _searchController = createTextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'SearchInput');
  final _firstResultFocusNode = FocusNode(debugLabel: 'SearchFirstResult');
  List<MediaItem> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  late final Debounce _searchDebounce;
  String _lastSearchedQuery = '';
  String? _focusResultsForQuery;
  _SearchFilter _activeFilter = _SearchFilter.all;
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _searchDebounce = debounce(_performSearch, const Duration(milliseconds: 500));
    _searchController.addListener(_onSearchChanged);
    _history = SettingsService.instance.read(SettingsService.searchHistory);
    FocusUtils.requestFocusAfterBuild(this, _searchFocusNode);
  }

  /// Filtered view of [_searchResults] for the active type chip.
  List<MediaItem> get _filteredResults {
    return switch (_activeFilter) {
      _SearchFilter.all => _searchResults,
      _SearchFilter.movies => _searchResults.where((i) => i.kind == MediaKind.movie).toList(),
      _SearchFilter.shows => _searchResults.where((i) => i.kind == MediaKind.show).toList(),
      _SearchFilter.episodes => _searchResults.where((i) => i.kind == MediaKind.episode).toList(),
    };
  }

  void _addToHistory(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final next = [trimmed, ..._history.where((q) => q.toLowerCase() != trimmed.toLowerCase())];
    if (next.length > _searchHistoryLimit) next.removeRange(_searchHistoryLimit, next.length);
    _history = next;
    SettingsService.instance.write(SettingsService.searchHistory, next);
  }

  void _clearHistory() {
    _history = const [];
    SettingsService.instance.write(SettingsService.searchHistory, const []);
    setStateIfMounted(() {});
  }

  void _runHistoryQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(offset: query.length);
    _searchDebounce.cancel();
    _performSearch(query);
  }

  @override
  void dispose() {
    _searchDebounce.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;

    final query = _searchController.text;

    if (query.trim().isEmpty) {
      _searchDebounce.cancel();
      _focusResultsForQuery = null;
      setStateIfMounted(() {
        _searchResults = [];
        _hasSearched = false;
        _isSearching = false;
        _lastSearchedQuery = '';
      });
      return;
    }

    // Only search if the query has actually changed
    if (query.trim() == _lastSearchedQuery.trim()) {
      return;
    }

    _searchDebounce([query]);
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    if (query.trim().isEmpty) {
      setStateIfMounted(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setStateIfMounted(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      if (!mounted) return;
      final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);

      if (!multiServerProvider.hasConnectedServers) {
        throw Exception('No servers available');
      }

      final neutral = await multiServerProvider.aggregationService.searchAcrossServers(query);
      if (mounted) {
        setStateIfMounted(() {
          _searchResults = neutral;
          _isSearching = false;
          _lastSearchedQuery = query.trim();
          _activeFilter = _SearchFilter.all;
        });
        if (neutral.isNotEmpty) _addToHistory(query);
        _maybeFocusResultsAfterSubmit(query, neutral);
      }
    } catch (e) {
      _focusResultsForQuery = null;
      if (mounted) {
        setStateIfMounted(() {
          _isSearching = false;
        });
        showErrorSnackBar(context, t.errors.searchFailed(error: e));
      }
    }
  }

  /// OSK "Search" / hardware Enter on TV: jump to results, or force the
  /// search to run now and focus results when it lands.
  void _handleSearchSubmit() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (_searchResults.isNotEmpty && !_isSearching && query == _lastSearchedQuery.trim()) {
      _firstResultFocusNode.requestFocus();
      return;
    }

    _focusResultsForQuery = query;
    if (_searchDebounce.isPending || !_isSearching) {
      _searchDebounce.cancel();
      _performSearch(query);
    }
    // else: the in-flight search already covers the current text; its
    // completion focuses the results.
  }

  void _maybeFocusResultsAfterSubmit(String query, List<MediaItem> results) {
    if (_focusResultsForQuery == null || _focusResultsForQuery != query.trim()) return;
    _focusResultsForQuery = null;
    if (results.isEmpty) return;
    if (_searchController.text.trim() != query.trim()) return; // user kept editing
    FocusUtils.requestFocusAfterBuild(this, _firstResultFocusNode);
  }

  @override
  void refresh() {
    if (!mounted) return;
    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  /// Focus the search input field
  @override
  void focusSearchInput() {
    if (!mounted) return;
    _searchFocusNode.requestFocus();
  }

  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    _searchFocusNode.requestFocus();
  }

  /// Set the search query externally (e.g. from companion remote)
  @override
  void setSearchQuery(String query) {
    if (!mounted) return;
    _searchController.text = query;
  }

  // Public method to fully reload all content (for profile switches)
  @override
  void fullRefresh() {
    if (!mounted) return;
    appLogger.d('SearchScreen.fullRefresh() called - clearing search and reloading');
    // Clear search results and search text for new profile
    _searchController.clear();
    _focusResultsForQuery = null;
    setStateIfMounted(() {
      _searchResults.clear();
      _isSearching = false;
      _hasSearched = false;
      _lastSearchedQuery = '';
    });
  }

  void updateItem(String _) {
    if (!mounted) return;
    // Trigger a refresh of the search to get updated metadata
    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  /// Navigate focus to the sidebar
  void _navigateToSidebar() {
    MainScreenFocusScope.of(context, listen: false)?.focusSidebar();
  }

  Widget _buildResultsList(BuildContext context) {
    final multiServer = context.watch<MultiServerProvider>();
    final showServerName = multiServer.totalServerCount > 1;
    final results = _filteredResults;
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = results[index];
          return FocusableMediaCard(
            key: Key(item.globalKey),
            item: item,
            forceListMode: true,
            disableScale: true,
            focusNode: index == 0 ? _firstResultFocusNode : null,
            onRefresh: updateItem,
            onListRefresh: () => updateItem(item.id),
            onNavigateLeft: _navigateToSidebar,
            onNavigateUp: index == 0 ? focusSearchInput : null,
            showServerName: showServerName,
          );
        }, childCount: results.length),
      ),
    );
  }

  /// Type filter chips shown above the results. A filter with no matches in the
  /// current result set is hidden so the row only offers useful narrowing.
  Widget _buildFilterChips(BuildContext context) {
    bool has(MediaKind k) => _searchResults.any((i) => i.kind == k);
    final chips = <Widget>[
      _filterChip(context, _SearchFilter.all, t.search.filters.all),
      if (has(MediaKind.movie)) _filterChip(context, _SearchFilter.movies, t.search.filters.movies),
      if (has(MediaKind.show)) _filterChip(context, _SearchFilter.shows, t.search.filters.shows),
      if (has(MediaKind.episode)) _filterChip(context, _SearchFilter.episodes, t.search.filters.episodes),
    ];
    // Only "All" available → nothing to filter, hide the row entirely.
    if (chips.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _filterChip(BuildContext context, _SearchFilter filter, String label) {
    return FilterChip(
      label: Text(label),
      selected: _activeFilter == filter,
      onSelected: (_) => setStateIfMounted(() => _activeFilter = filter),
    );
  }

  /// Recent-searches empty state: tappable chips that re-run a past query.
  /// Doubles as the TV recent-search row (chips are focusable for d-pad).
  Widget _buildRecentSearches(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.search.recentSearches,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(onPressed: _clearHistory, child: Text(t.search.clearHistory)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final query in _history)
                  ActionChip(
                    avatar: const AppIcon(Symbols.history_rounded, fill: 1, size: 18),
                    label: Text(query),
                    onPressed: () => _runHistoryQuery(query),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          primary: false,
          slivers: [
            DesktopSliverAppBar(title: Text(t.common.search), floating: true),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: FocusableTextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onNavigateLeft: _navigateToSidebar,
                  onNavigateDown: _searchResults.isNotEmpty && !_isSearching
                      ? _firstResultFocusNode.requestFocus
                      : null,
                  onEditingComplete: PlatformDetector.isTV() ? _handleSearchSubmit : null,
                  onBack: () {
                    if (_searchController.text.isNotEmpty) {
                      _searchController.clear();
                    } else {
                      _navigateToSidebar();
                    }
                  },
                  decoration: pillInputDecoration(
                    context,
                    hintText: t.search.hint,
                    prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const AppIcon(Symbols.clear_rounded, fill: 1),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            if (_isSearching)
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.builder(
                  itemCount: 6,
                  itemBuilder: (context, index) => const SkeletonListTile(),
                ),
              )
            else if (!_hasSearched)
              if (_history.isNotEmpty)
                _buildRecentSearches(context)
              else
                SliverFillRemaining(
                  child: StateView.empty(
                    title: t.search.searchYourMedia,
                    message: t.search.enterTitleActorOrKeyword,
                    icon: Symbols.search_rounded,
                  ),
                )
            else if (_searchResults.isEmpty)
              SliverFillRemaining(
                child: StateView.empty(
                  title: t.messages.noResultsFound,
                  message: t.search.tryDifferentTerm,
                  icon: Symbols.search_off_rounded,
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _buildFilterChips(context)),
              _buildResultsList(context),
            ],
          ],
        ),
      ),
    );
  }
}
