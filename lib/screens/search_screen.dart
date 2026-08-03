import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:rate_limiter/rate_limiter.dart';

import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_media.dart';
import '../providers/seerr_provider.dart';
import '../widgets/focusable_filter_chip.dart';
import '../widgets/focusable_list_tile.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/seerr_poster_card.dart';
import 'seerr/seerr_media_detail_screen.dart';
import '../mixins/controller_disposer_mixin.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../mixins/refreshable.dart';
import '../providers/multi_server_provider.dart';
import '../services/settings_service.dart';
import '../services/speech_search_service.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/pill_input_decoration.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_view.dart';
import '../widgets/tv_virtual_keyboard.dart';
import '../utils/focus_utils.dart';
import 'main_screen.dart';

/// Client-side result type filter over whatever [searchAcrossServers] returns.
/// There is no "people" row — search results carry no person items. Note that
/// the episodes chip is effectively Jellyfin-only: the Plex client searches
/// with `searchTypes: 'movies,tv'` and never yields episode items.
enum _SearchFilter { all, movies, shows, episodes }

/// Why the last search produced nothing — so the UI can tell "we couldn't
/// reach anything" apart from "your library really has no match".
enum _SearchError { network, noServers }

/// Marker for the no-connected-servers case so [_performSearch] can classify
/// it without string-matching an exception message.
class _NoServersAvailable implements Exception {
  const _NoServersAvailable();
  @override
  String toString() => 'No servers available';
}

/// Servers were connected, but every single one failed or timed out.
class _AllServersFailed implements Exception {
  const _AllServersFailed();
  @override
  String toString() => 'All servers failed to answer the search';
}

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
  _SearchError? _searchError;
  // TV only: phones and desktops already have a dictation key on the system
  // keyboard, so a second mic affordance there would just be noise.
  bool _voiceSearchSupported = false;
  // Bumped per search; a completing request that isn't the latest is dropped.
  int _searchGeneration = 0;
  String? _focusResultsForQuery;
  _SearchFilter _activeFilter = _SearchFilter.all;
  List<String> _history = const [];

  // Jellyseerr/Overseerr fallback: an explicit, one-shot search the user
  // triggers when a title isn't in their library (never per-keystroke).
  List<SeerrMedia> _seerrResults = const [];
  bool _seerrSearching = false;
  bool _seerrSearched = false;

  @override
  void initState() {
    super.initState();
    _searchDebounce = debounce(_performSearch, const Duration(milliseconds: 500));
    _searchController.addListener(_onSearchChanged);
    _history = SettingsService.instance.read(SettingsService.searchHistory);
    FocusUtils.requestFocusAfterBuild(this, _searchFocusNode);
    if (PlatformDetector.isTV()) {
      unawaited(
        SpeechSearchService.instance.isSupported().then((supported) {
          setStateIfMounted(() => _voiceSearchSupported = supported);
        }),
      );
    }
  }

  /// Hand off to the platform's dictation surface, then run whatever came back
  /// as a full search — no letter-by-letter D-pad entry needed at all.
  Future<void> _startVoiceSearch() async {
    final spoken = await SpeechSearchService.instance.capture(prompt: t.search.hint);
    if (!mounted || spoken == null) return;
    submitSearchQuery(spoken);
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
      _searchGeneration++;
      setStateIfMounted(() {
        _searchResults = [];
        _hasSearched = false;
        _isSearching = false;
        _searchError = null;
        _lastSearchedQuery = '';
      });
      return;
    }

    // A single character fans a query out to every server for a result set
    // that's rarely useful; wait for at least two. Explicit submits and
    // history chips bypass this listener, so short queries stay possible.
    if (query.trim().length < 2) {
      _searchDebounce.cancel();
      // Backspacing "abc" down to "a" must not leave the "abc" results on
      // screen under a query that no longer produced them.
      _focusResultsForQuery = null;
      _searchGeneration++;
      setStateIfMounted(() {
        _searchResults = [];
        _hasSearched = false;
        _isSearching = false;
        _searchError = null;
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

  Future<void> _performSearch(String rawQuery) async {
    if (!mounted) return;
    // Always work with the trimmed form: `refresh()` and `updateItem()` used to
    // pass the raw controller text, which then never matched _lastSearchedQuery
    // and re-ran the same search on every metadata update.
    final query = rawQuery.trim();

    if (query.isEmpty) {
      setStateIfMounted(() {
        _searchResults = [];
        _hasSearched = false;
        _searchError = null;
      });
      return;
    }

    // Staleness guard. Without it a slow "bat" landing after a fast "batman"
    // overwrote both the results AND _lastSearchedQuery — and since
    // _onSearchChanged short-circuits on _lastSearchedQuery, that state never
    // corrected itself again.
    final generation = ++_searchGeneration;
    bool isStale() => generation != _searchGeneration;

    setStateIfMounted(() {
      _isSearching = true;
      _hasSearched = true;
      _searchError = null;
      _seerrResults = const [];
      _seerrSearched = false;
      _seerrSearching = false;
    });

    try {
      if (!mounted) return;
      final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);

      if (!multiServerProvider.hasConnectedServers) {
        throw const _NoServersAvailable();
      }

      final aggregated = await multiServerProvider.aggregationService.searchAcrossServers(query);
      if (!mounted || isStale()) return;
      // Not one server answered → this is a connection failure, not an empty
      // library. Reporting it as "no results" is what made a dead network look
      // like a search that simply found nothing.
      if (aggregated.succeededServerIds.isEmpty) {
        throw const _AllServersFailed();
      }
      final neutral = aggregated.items;
      setStateIfMounted(() {
        _searchResults = neutral;
        _isSearching = false;
        _lastSearchedQuery = query;
        _activeFilter = _SearchFilter.all;
      });
      if (neutral.isNotEmpty) _addToHistory(query);
      _maybeFocusResultsAfterSubmit(query, neutral);
    } catch (e) {
      if (!mounted || isStale()) return;
      _focusResultsForQuery = null;
      setStateIfMounted(() {
        _isSearching = false;
        // Show the failure as a failure. Previously the stale results (or the
        // "no results, try another term" empty state) stayed on screen, which
        // reads as "your library doesn't have this" for what is really a
        // connection problem.
        _searchError = e is _NoServersAvailable ? _SearchError.noServers : _SearchError.network;
        _searchResults = const [];
        // Reset the filter too: keeping it would leave an active chip whose
        // row is now hidden, i.e. an apparently empty list with no way back.
        _activeFilter = _SearchFilter.all;
        _lastSearchedQuery = '';
      });
      appLogger.d('Search failed for "$query"', error: e);
    }
  }

  /// Re-run the last query after an error-state retry.
  void _retrySearch() {
    _performSearch(_searchController.text);
  }

  /// One-shot Jellyseerr/Overseerr search for the current query. Explicit
  /// (user-triggered) so we never fire a request per keystroke.
  Future<void> _searchSeerr() async {
    final client = context.read<SeerrProvider?>()?.client;
    final query = _searchController.text.trim();
    if (client == null || query.isEmpty || _seerrSearching) return;
    setStateIfMounted(() {
      _seerrSearching = true;
      _seerrSearched = true;
    });
    try {
      final page = await client.search(query);
      // Drop the result if the query changed while the request was in flight,
      // so stale Seerr results can't repaint under a newer query.
      if (!mounted || _searchController.text.trim() != query) return;
      setStateIfMounted(() {
        _seerrResults = page.items;
        _seerrSearching = false;
      });
    } catch (e) {
      if (!mounted || _searchController.text.trim() != query) return;
      setStateIfMounted(() => _seerrSearching = false);
      showErrorSnackBar(context, t.seerr.errorNetwork);
    }
  }

  Widget _buildSeerrFallback(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FocusableListTile(
          leading: const AppIcon(Symbols.travel_explore_rounded, fill: 1),
          title: Text(t.seerr.searchOnSeerr),
          trailing: _seerrSearching
              ? const LoadingIndicatorBox(size: 18)
              : const AppIcon(Symbols.chevron_right_rounded, fill: 1),
          onTap: _seerrSearching ? null : _searchSeerr,
        ),
      ),
      if (_seerrSearched && !_seerrSearching && _seerrResults.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(t.seerr.noResults, style: theme.textTheme.bodyMedium),
        ),
      if (_seerrResults.isNotEmpty)
        LayoutBuilder(
          builder: (context, constraints) {
            final metrics = seerrRowMetricsOf(context, constraints.maxWidth);
            return SizedBox(
              height: metrics.rowHeight + 12,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.fromLTRB(16, 4 + metrics.focusReserve, 16, 8 + metrics.focusReserve),
                itemCount: _seerrResults.length,
                separatorBuilder: (_, _) => SizedBox(width: metrics.itemGap),
                itemBuilder: (context, index) {
                  final media = _seerrResults[index];
                  return SeerrPosterCard(media: media, onTap: () => _openSeerrDetail(media), width: metrics.cardWidth);
                },
              ),
            );
          },
        ),
    ];
    return SliverList(delegate: SliverChildListDelegate(children));
  }

  void _openSeerrDetail(SeerrMedia media) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeerrMediaDetailScreen(media: media)));
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

  @override
  void submitSearchQuery(String query) {
    if (!mounted) return;
    final trimmed = query.trim();
    _searchController.text = trimmed;
    _searchController.selection = TextSelection.collapsed(offset: trimmed.length);
    _searchDebounce.cancel();
    if (trimmed.isEmpty) return;
    _performSearch(trimmed);
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
      _searchError = null;
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

  /// Menu/back on the inline TV keyboard: mirror the text field's onBack —
  /// clear a non-empty query first, exit to the sidebar when already empty.
  void _handleTvKeyboardClose() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    } else {
      _navigateToSidebar();
    }
  }

  /// D-pad down past the keyboard's bottom row: land on whatever sits below —
  /// filter chips, first result, recent-search chips, or the Seerr tile.
  void _handleTvKeyboardNavigateDown() {
    // While searching, the results area is skeletons with nothing focusable —
    // moving down would silently drop focus and strand the user. Keep focus on
    // the keyboard until there is something real to land on.
    if (_isSearching) return;
    if (FocusScope.of(context).focusInDirection(TraversalDirection.down)) return;
    if (_searchResults.isNotEmpty) {
      _firstResultFocusNode.requestFocus();
    }
  }

  /// TV header: read-only query pill + always-visible inline keyboard. No
  /// FocusableTextField here — nothing that can trigger the modal machinery.
  List<Widget> _buildTvSearchHeader(BuildContext context) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: ListenableBuilder(
            listenable: _searchController,
            builder: (context, _) {
              final text = _searchController.text;
              return InputDecorator(
                decoration: pillInputDecoration(
                  context,
                  hintText: t.search.hint,
                  prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
                ),
                isEmpty: text.isEmpty,
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            },
          ),
        ),
      ),
      if (_voiceSearchSupported)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
            child: Center(
              child: FocusableButton(
                onPressed: _startVoiceSearch,
                child: TextButton.icon(
                  onPressed: _startVoiceSearch,
                  icon: const AppIcon(Symbols.mic_rounded, fill: 1),
                  label: Text(t.search.voiceSearch),
                ),
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          child: Center(
            child: TvVirtualKeyboardPanel(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: t.search.hint,
              textInputAction: TextInputAction.search,
              autofocus: false,
              showPreview: false,
              showCancelKey: false,
              dismissOnPhysicalKeyboardInput: false,
              onSubmitted: (_) => _handleSearchSubmit(),
              onClose: _handleTvKeyboardClose,
              onNavigateDown: _handleTvKeyboardNavigateDown,
            ),
          ),
        ),
      ),
    ];
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
    return FocusableFilterChip(
      label: label,
      selected: _activeFilter == filter,
      onPressed: () => setStateIfMounted(() => _activeFilter = filter),
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
            if (PlatformDetector.isTV())
              ..._buildTvSearchHeader(context)
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  child: FocusableTextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    // Don't auto-open the TV keyboard the instant the field
                    // autofocuses: the field losing/regaining focus around the
                    // keyboard route races the auto-reopen guard and traps the
                    // user in the keyboard. Open on explicit select instead —
                    // same fix already applied to the Seerr search field.
                    tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.afterFirstFocus,
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
                sliver: SliverList.builder(itemCount: 6, itemBuilder: (context, index) => const SkeletonListTile()),
              )
            else if (_searchError != null)
              SliverFillRemaining(
                child: _searchError == _SearchError.noServers
                    ? StateView.error(
                        title: t.search.noServersTitle,
                        message: t.search.noServersBody,
                        icon: Symbols.dns_rounded,
                      )
                    : StateView.error(
                        title: t.search.errorTitle,
                        message: t.search.errorNetwork,
                        icon: Symbols.wifi_off_rounded,
                        onRetry: _retrySearch,
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
              if (context.watch<SeerrProvider?>()?.isConfigured ?? false) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: Text(
                      t.messages.noResultsFound,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                _buildSeerrFallback(context),
              ] else
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
              if (context.watch<SeerrProvider?>()?.isConfigured ?? false) _buildSeerrFallback(context),
            ],
          ],
        ),
      ),
    );
  }
}
