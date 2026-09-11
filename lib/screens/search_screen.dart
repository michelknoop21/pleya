import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:rate_limiter/rate_limiter.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_media.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/seerr_provider.dart';
import '../widgets/focusable_filter_chip.dart';
import '../widgets/focusable_list_tile.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/seerr_poster_card.dart';
import 'seerr/seerr_media_detail_screen.dart';
import '../mixins/controller_disposer_mixin.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../mixins/refreshable.dart';
import '../media/unified/unified_media_group.dart';
import '../media/ids.dart';
import '../providers/multi_server_provider.dart';
import '../services/unified_catalog/search_projection.dart';
import '../utils/external_ids_fetcher.dart';
import '../utils/provider_extensions.dart';

import '../services/apple_tv_native_text_entry.dart';
import '../services/settings_service.dart';
import '../services/speech_search_service.dart';
import '../utils/app_logger.dart';
import '../utils/native_input_session.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/pill_input_decoration.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_view.dart';
import '../widgets/tv/tv_catalog_item_card.dart';
import '../widgets/tv/tv_unified_layout.dart';
import '../widgets/tv/tv_unified_media_card.dart';
import '../widgets/tv_virtual_keyboard.dart';
import 'tv/tv_discovery_activation_mixin.dart';
import 'tv/tv_search_view.dart';
import 'seerr/seerr_discover_screen.dart';
import '../media/media_server_client.dart';
import '../navigation/tv/tv_content_route_registry.dart';
import '../services/search_recents.dart';
import '../utils/media_navigation_helper.dart';
import 'actor_media_screen.dart';

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
  const SearchScreen({super.key, this.onManageServers, this.onBack});

  /// Hoofdstuk 14.7's escape hatch from the unified source picker's
  /// `NoUsableSource` state — the same affordance the discovery landings
  /// and the Home hero offer for the same situation. Used by TV search's
  /// `activateDiscoveryGroup` calls.
  final VoidCallback? onManageServers;

  /// I4/`05-zoeken.png`: the phone build's own back chevron, wired by
  /// `MainScreen` to the tab Zoeken was opened from. Null on every other
  /// platform — TV has no such header, and desktop's app bar predates it.
  final VoidCallback? onBack;

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
        MountedSetStateMixin,
        TvDiscoveryActivationMixin {
  late final _searchController = createTextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'SearchInput');
  final _firstResultFocusNode = FocusNode(debugLabel: 'SearchFirstResult');
  List<MediaItem> _searchResults = [];
  // TV and phone (hoofdstuk 16.1/16.2, I4): the unified projection of the
  // same `_searchResults` this screen already fetched. Built alongside
  // `_searchResults` rather than derived from it in `build()`, because the
  // projection is async (identity resolution needs a network round trip per
  // ambiguous title) and `build()` cannot await. Desktop never reads this —
  // it stays exactly the source-concrete list it always was; desktop search
  // unification is not part of I4's scope.
  UnifiedSearchProjection? _projection;
  // TV only: the group rails of the result page, in the order hoofdstuk 16.1
  // draws them. It owns two things — reaching the first rail, so the existing
  // "focus the first result" call sites (OSK Done, keyboard navigate-down,
  // submit-while-results-loaded) land on it the same way they landed on
  // `_firstResultFocusNode`'s card in the non-TV list, and UP/DOWN between the
  // rails at one column (LAND4). Keyed on the section name rather than on a
  // position: which sections are non-empty changes with every query.
  // TV only: the DEC-108 presentation. It owns the bands and their focus
  // traversal; this state owns the fetches and the query.
  final _tvSearchKey = GlobalKey<TvSearchViewState>();

  // TV only (mockup 36 A): the titles opened from an earlier search, which is
  // what "Recent gezocht" draws. `_history` is the other recency — the query
  // strings — and stays what desktop and mobile show.
  List<MediaItem> _recentItems = const [];
  final _clearRecentsFocus = FocusNode(debugLabel: 'TvSearchClearRecents');
  bool _isSearching = false;
  bool _hasSearched = false;
  late final Debounce _searchDebounce;
  String _lastSearchedQuery = '';
  _SearchError? _searchError;
  // TV only: phones and desktops already have a dictation key on the system
  // keyboard, so a second mic affordance there would just be noise.
  bool _voiceSearchSupported = false;
  // Apple TV: the native system keyboard is the primary input (and the
  // dictation surface). Only when that path is broken does the inline D-pad
  // keyboard take over — latched, so a device where it fails never sees it again.
  bool _nativeEntryUnavailable = false;
  // Bumped per search; a completing request that isn't the latest is dropped.
  int _searchGeneration = 0;
  String? _focusResultsForQuery;
  _SearchFilter _activeFilter = _SearchFilter.all;
  List<String> _history = const [];
  // TV only (B17): set in initState so dispose can remove the same listener
  // without touching context after the tree may have started tearing down.
  HiddenLibrariesProvider? _hiddenLibrariesForTvRefresh;
  // The hidden set the last dispatched fan-out actually used — compared
  // against on every provider change so a notification that left the
  // effective set unchanged (the provider's own init, or a hide/unhide of a
  // library no result here belongs to) does not cost a second fan-out.
  Set<String> _lastSearchedHiddenLibraryKeys = const {};

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
    _recentItems = readSearchRecents();
    FocusUtils.requestFocusAfterBuild(this, _searchFocusNode);
    _nativeEntryUnavailable = PlatformDetector.isAppleTV() && AppleTvNativeTextEntry.instance.isUnavailable;
    // Warm the visibility set so the first query already filters against the
    // persisted value rather than an empty placeholder.
    unawaited(context.hiddenLibraries.ensureInitialized());
    if (PlatformDetector.isTV()) {
      // B17: a library hidden or unhidden after this screen already has
      // results must not leave a stale membership on screen — re-run the same
      // query through the same fan-out, so the filter is applied exactly
      // where every other search result is, before grouping. This also
      // catches the provider's own first-load notification (`_initialize()`
      // ends with one `notifyListeners()` regardless of whether the set
      // changed): if a query was submitted before the persisted visibility
      // loaded — the cold-start race this row is about — it dispatched
      // against whatever was in memory at that instant, and this rerun
      // corrects it against the real set the moment it lands.
      // Vals alarm: hij wordt verwijderd via _hiddenLibrariesForTvRefresh in dispose.
      // ignore: always-remove-listener
      _hiddenLibrariesForTvRefresh = context.hiddenLibraries..addListener(_onHiddenLibrariesChanged);
      unawaited(
        SpeechSearchService.instance.isSupported().then((supported) {
          setStateIfMounted(() => _voiceSearchSupported = supported);
        }),
      );
    }
  }

  /// Hand off to the platform's dictation surface — no letter-by-letter D-pad
  /// entry needed at all. On Apple TV that surface is the system keyboard
  /// itself (the Siri Remote mic dictates into it) and partial text streams
  /// back live, so results are already on screen when it closes.
  Future<void> _openNativeSearchEntry() async {
    try {
      final result = await SpeechSearchService.instance.capture(
        prompt: t.search.hint,
        initialText: _searchController.text,
        onPartial: (text) {
          if (!mounted) return;
          _searchController.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        },
      );
      if (!mounted) return;
      if (result == null) {
        // Cancelled or BUSY — but a missing plugin flips isSupported() to
        // false; reveal the inline keyboard when the surface is gone entirely.
        if (PlatformDetector.isAppleTV() && !await SpeechSearchService.instance.isSupported()) {
          _revealFallbackKeyboard();
        }
        return;
      }
      _searchController.text = result.text;
      _searchController.selection = TextSelection.collapsed(offset: result.text.length);
      if (result.submitted) _handleSearchSubmit();
    } on PlatformException {
      // Broken native surface — including the watchdog's verdict that it never
      // became usable (BUSY returns null instead). Switch this screen to the
      // inline D-pad keyboard so the user is never stuck.
      if (mounted) _revealFallbackKeyboard();
    }
  }

  /// Swap the Apple TV pill-plus-system-keyboard input for the inline D-pad
  /// keyboard, and keep focus alive across the swap.
  void _revealFallbackKeyboard() {
    if (_nativeEntryUnavailable) return;
    setStateIfMounted(() {
      _nativeEntryUnavailable = true;
      // The mic button opens the same broken surface — hide it too.
      _voiceSearchSupported = false;
    });
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
    // Explicitly typed: an untyped `const []` infers List<dynamic> here, which
    // StringListPref rejects at runtime — the button silently did nothing.
    SettingsService.instance.write(SettingsService.searchHistory, const <String>[]);
    setStateIfMounted(() {});
    // The chips and this button unmount with the row — without a new home,
    // primary focus dies with them and the D-pad goes dead.
    FocusUtils.requestFocusAfterBuild(this, _searchFocusNode);
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
    _hiddenLibrariesForTvRefresh?.removeListener(_onHiddenLibrariesChanged);
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    _clearRecentsFocus.dispose();
    super.dispose();
  }

  /// B17: re-runs the last search when the hidden-library set changes under
  /// it, so a title from a library that was just hidden does not linger as an
  /// activation candidate, and one that was just unhidden can come back. Also
  /// the correction path for the cold-start race (see `_performSearch`):
  /// `_initialize()` fires this same notification once, on the same
  /// condition, and a set that turns out unchanged is a no-op below rather
  /// than a second fan-out for nothing.
  void _onHiddenLibrariesChanged() {
    if (!mounted) return;
    final query = _lastSearchedQuery;
    if (query.isEmpty) return;
    final current = context.hiddenLibraries.hiddenLibraryKeys;
    if (setEquals(current, _lastSearchedHiddenLibraryKeys)) return;
    unawaited(_performSearch(query));
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
        _projection = null;
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
    // TV: the results/history area just became skeletons with zero focusables.
    // If primary focus lived there (result card, history chip), it unmounts and
    // the D-pad goes dead — park focus on the input until results land.
    // _maybeFocusResultsAfterSubmit still moves it onward for submit flows.
    // Scoped to focus inside this screen, so a background refresh() while
    // another tab is active can't steal focus across tabs.
    // Not while the native keyboard is up: each keystroke streams a new search
    // in, and parking focus would scroll this screen around underneath a
    // surface the user cannot see past. Results keep updating; the park waits
    // until the session ends, and a submit routes through
    // _maybeFocusResultsAfterSubmit anyway (that one runs after `edit`
    // completes, so after the session is over).
    if (PlatformDetector.isTV() && !_searchFocusNode.hasFocus && !NativeInputSession.isActive) {
      final primary = FocusManager.instance.primaryFocus;
      final inThisScreen = primary?.context?.findAncestorStateOfType<_SearchScreenState>() == this;
      if (inThisScreen) {
        FocusUtils.requestFocusAfterBuild(this, _searchFocusNode);
      }
    }

    try {
      if (!mounted) return;
      final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);

      if (!multiServerProvider.hasConnectedServers) {
        throw const _NoServersAvailable();
      }

      // Hidden libraries are a hard visibility boundary (hoofdstuk 22), and
      // search is a fan-out like any other — a title in a hidden library must
      // not surface here, nor become a source under a unified TV group.
      //
      // Read synchronously rather than awaiting `ensureInitialized()`. The
      // provider starts loading when the profile session mounts and initState
      // warms it again here, both long before a query can be typed and
      // submitted. Awaiting on this path instead would put an async gap
      // between the keystroke and the fan-out, and it broke the screen's own
      // tests by moving the client call a microtask later than the harness
      // expects — confirmed again while closing B17: the widget-test harness
      // does not guarantee the provider is done loading by the time a search
      // dispatches even after a settled pump, so gating the dispatch on
      // readiness is not a fix, it is the same bug wearing a condition.
      //
      // B17's actual fix is the read-and-correct pair below plus the
      // `_onHiddenLibrariesChanged` listener registered in `initState` (TV
      // only): a query submitted before storage finishes loading still
      // dispatches immediately against whatever is in memory (unchanged
      // behaviour, so no new async gap), but `_initialize()` ends with its own
      // `notifyListeners()` regardless of whether the set changed — the same
      // signal a later hide/unhide fires — so the already-armed listener
      // reruns this same query the instant the real set lands, before a user
      // can plausibly have acted on the uncorrected screen. The filter is
      // still applied before grouping; it is just applied twice when the
      // first pass ran on a stale set, not applied late.
      final hiddenLibraries = context.hiddenLibraries;
      _lastSearchedHiddenLibraryKeys = hiddenLibraries.hiddenLibraryKeys;
      final aggregated = await multiServerProvider.aggregationService.searchAcrossServers(
        query,
        hiddenLibraryKeys: _lastSearchedHiddenLibraryKeys,
      );
      if (!mounted || isStale()) return;
      // Not one server answered → this is a connection failure, not an empty
      // library. Reporting it as "no results" is what made a dead network look
      // like a search that simply found nothing.
      if (aggregated.succeededServerIds.isEmpty) {
        throw const _AllServersFailed();
      }
      final neutral = aggregated.items;
      // TV (hoofdstuk 16.1/16.2, fase 6) and phone (I4): project onto the
      // unified model — "Dune (2021) — 3 bronnen", not one row per server.
      // Runs after the staleness check above and rechecks it again below,
      // since this await (identity resolution) is exactly the kind of
      // network round trip `isStale()` exists to guard against — a slower
      // "bat" landing after a faster "batman" must not overwrite the newer
      // query's projection either. Desktop never takes this branch, so its
      // search stays the source-concrete list it always was.
      UnifiedSearchProjection? projection;
      if (PlatformDetector.isTV() || PlatformDetector.isPhone(context)) {
        projection = await searchProjection(
          neutral,
          fetchExternalIds: externalIdsFetcherFor(multiServerProvider),
          people: aggregated.people,
        );
        if (!mounted || isStale()) return;
      }
      setStateIfMounted(() {
        _searchResults = neutral;
        _projection = projection;
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
        _projection = null;
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
      _focusFirstResult();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFirstResult();
    });
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
      _focusFirstResult();
    }
  }

  /// Zoeken on TV (DEC-108, mockup 36 A, B and C).
  ///
  /// The page is `TvSearchView` whole rather than a branch inside the sliver
  /// tree below: every part of the TV presentation — field, bands, states — is
  /// laid out by that view, and a TV that shared the desktop `CustomScrollView`
  /// was how the phone list ended up on a ten-foot panel in the first place
  /// (CAT11).
  Widget _buildTv(BuildContext context) {
    final multiServer = context.watch<MultiServerProvider>();
    final seerrConfigured = context.watch<SeerrProvider?>()?.isConfigured ?? false;
    final sections = _tvSections(context, multiServer);
    final total = _hasSearched ? _tvResultCount() : null;
    return Scaffold(
      body: SafeArea(
        child: TvSearchView(
          key: _tvSearchKey,
          searchField: _buildTvSearchField(context, total),
          sections: sections,
          hasQuery: _hasSearched,
          isSearching: _isSearching,
          totalResultCount: total,
          error: switch (_searchError) {
            null => null,
            _SearchError.noServers => t.search.noServersBody,
            _ => t.search.errorNetwork,
          },
          onRetry: _retrySearch,
          // 36 C's way out, and only where it leads somewhere. It hands the
          // query to Ontdekken rather than running the old inline Seerr row:
          // that row is `seerrRowMetricsOf`'s phone-sized tile, which is the
          // very thing CAT11 reported, and Ontdekken is now a TV page of its
          // own that can hold the answer properly.
          onSearchOnRequests: seerrConfigured && _searchController.text.trim().isNotEmpty
              ? () => SeerrDiscoverScreen.open(context, initialQuery: _searchController.text.trim())
              : null,
          serverCount: multiServer.totalServerCount,
          onExitLeft: _navigateToSidebar,
          onExitTop: focusSearchInput,
        ),
      ),
    );
  }

  /// Every result the projection holds, across all seven sections.
  ///
  /// Counted off the projection rather than off `_searchResults`, because the
  /// two are different numbers: the flat list has one entry per *source*, and
  /// what 36 B states beside the pill is what the page draws — one per title.
  int _tvResultCount() {
    final projection = _projection;
    if (projection == null) return 0;
    return projection.movies.length +
        projection.shows.length +
        projection.episodes.length +
        projection.collections.length +
        projection.playlists.length +
        projection.people.length +
        projection.other.length;
  }

  /// The bands, in hoofdstuk 16.1's order — or, before anything has been
  /// searched for, the one row of titles opened from an earlier search
  /// (mockup 36 A).
  List<TvSearchSection> _tvSections(BuildContext context, MultiServerProvider multiServer) {
    MediaServerClient? clientFor(String serverId) => multiServer.serverManager.getClient(ServerId(serverId));

    if (!_hasSearched) {
      if (_recentItems.isEmpty) return const [];
      return [
        TvSearchSection(
          id: 'recent',
          title: t.search.recentSearches,
          actionLabel: t.search.clearHistory,
          onAction: _clearRecents,
          actionFocusNode: _clearRecentsFocus,
          itemIds: [for (final item in _recentItems) item.globalKey],
          cardBuilder: (context, cell) => TvCatalogItemCard(
            item: _recentItems[cell.index],
            width: cell.width,
            clientFor: clientFor,
            focusNode: cell.focusNode,
            onSelect: () => _openConcrete(_recentItems[cell.index]),
            onFocusChange: cell.onFocusChange,
            onNavigateUp: cell.onNavigateUp,
            onNavigateDown: cell.onNavigateDown,
            onNavigateLeft: cell.onNavigateLeft,
            onNavigateRight: cell.onNavigateRight,
          ),
        ),
      ];
    }

    final projection = _projection;
    if (projection == null) return const [];

    TvSearchSection groups(String id, String title, List<UnifiedMediaGroup> groups) => TvSearchSection(
      id: id,
      title: title,
      itemIds: [for (final group in groups) group.groupId],
      cardBuilder: (context, cell) => TvUnifiedMediaCard(
        group: groups[cell.index],
        width: cell.width,
        clientFor: clientFor,
        focusNode: cell.focusNode,
        // Activation goes through the fase-4 coordinator, never a
        // representative-source shortcut (hoofdstuk 4.4). Unchanged from the
        // rail this replaces; only the tile it hangs on is different.
        onSelect: () => _activateSearchGroup(groups[cell.index]),
        onContextMenu: () => openDiscoveryContextMenu(groups[cell.index]),
        onFocusChange: cell.onFocusChange,
        onNavigateUp: cell.onNavigateUp,
        onNavigateDown: cell.onNavigateDown,
        onNavigateLeft: cell.onNavigateLeft,
        onNavigateRight: cell.onNavigateRight,
      ),
    );

    // [onSelect] defaults to the source-concrete open every row here used
    // before SRCH-2; only `people` overrides it, since a person is not a
    // playable `MediaItem` `_openConcrete` can route (see [_openPerson]).
    TvSearchSection items(String id, String title, List<MediaItem> items, {void Function(MediaItem item)? onSelect}) =>
        TvSearchSection(
          id: id,
          title: title,
          itemIds: [for (final item in items) item.globalKey],
          cardBuilder: (context, cell) => TvCatalogItemCard(
            item: items[cell.index],
            width: cell.width,
            clientFor: clientFor,
            focusNode: cell.focusNode,
            onSelect: () => (onSelect ?? _openConcrete)(items[cell.index]),
            onFocusChange: cell.onFocusChange,
            onNavigateUp: cell.onNavigateUp,
            onNavigateDown: cell.onNavigateDown,
            onNavigateLeft: cell.onNavigateLeft,
            onNavigateRight: cell.onNavigateRight,
          ),
        );

    return [
      if (projection.movies.isNotEmpty) groups('movies', t.unifiedCatalog.moviesTitle, projection.movies),
      if (projection.shows.isNotEmpty) groups('shows', t.unifiedCatalog.seriesTitle, projection.shows),
      if (projection.episodes.isNotEmpty) groups('episodes', t.search.filters.episodes, projection.episodes),
      if (projection.collections.isNotEmpty) items('collections', t.collections.title, projection.collections),
      if (projection.playlists.isNotEmpty) items('playlists', t.playlists.title, projection.playlists),
      if (projection.people.isNotEmpty)
        items('people', t.search.filters.people, projection.people, onSelect: _openPerson),
      if (projection.other.isNotEmpty) items('other', t.search.filters.other, projection.other),
    ];
  }

  /// Select on a unified result. Remembers the title it opened, so the row at
  /// rest (36 A) is a row of things this viewer actually went to.
  void _activateSearchGroup(UnifiedMediaGroup group) {
    _rememberRecent(group.representativeSource.item);
    activateDiscoveryGroup(group, onManageServers: widget.onManageServers);
  }

  /// Select on a source-concrete result — a collection or a playlist — and on
  /// a card in the row at rest. Both go through the same helper every other
  /// list in the app opens an item with; the row at rest deliberately takes
  /// the same path a fresh result does, so a title that has since been
  /// removed fails where any other stale reference does rather than being
  /// quietly dropped from the row. A person result is never routed here —
  /// see [_openPerson].
  void _openConcrete(MediaItem item) {
    _rememberRecent(item);
    unawaited(navigateToMediaItem(context, item, onRefresh: updateItem));
  }

  /// Select on a `people` result (SRCH-2). The item is a stand-in
  /// (`search_projection.dart`'s own documented shape — id/title/thumbPath/
  /// serverId/backend, `MediaKind.unknown`), not a real playable [MediaItem],
  /// so it cannot go through [_openConcrete]/`navigateToMediaItem`: nothing
  /// there has ever had a branch for a person, and one built to accept the
  /// same generic `MediaItem` shape a movie or show arrives as would be a
  /// second, silent way to reach `ActorMediaScreen` next to
  /// `_navigateToActorMedia` in `media_detail_screen.dart`, which already
  /// carries the real contract (a cast credit's id/tag/thumb). This calls the
  /// same `ActorMediaScreen` directly instead.
  ///
  /// Not remembered in "recent gezocht" (36 A): that row's own reopen path
  /// goes exclusively through [_openConcrete], and giving it a person here
  /// without teaching it the same branch this method needed would silently
  /// break on return, not just leave a person out of the row.
  void _openPerson(MediaItem person) {
    final serverId = person.serverId;
    if (serverId == null) return;
    ActorMediaScreen buildPerson(BuildContext _) => ActorMediaScreen(
      actorName: person.displayTitle,
      personId: person.id,
      actorThumb: person.thumbPath,
      serverId: serverId,
      serverName: person.serverName,
      backend: person.backend,
    );
    if (openTvContentRoute(id: 'tvPerson_${serverId}_${person.id}', builder: buildPerson) != null) return;
    Navigator.push(context, MaterialPageRoute(builder: buildPerson));
  }

  /// Empties the row at rest. It also clears the query chips, because on this
  /// page the two are one idea with two presentations, and a Wissen that left
  /// half of "recent" standing would be a lie about what it did.
  void _clearRecents() {
    clearSearchRecents();
    _clearHistory();
    setStateIfMounted(() => _recentItems = const []);
  }

  void _rememberRecent(MediaItem item) {
    final next = rememberSearchRecent(item);
    setStateIfMounted(() => _recentItems = next);
  }

  /// TV header: the query pill, and the count beside it.
  ///
  /// On Apple TV the pill itself is the input: select opens the native system
  /// keyboard, which is also the Siri-Remote dictation surface, so the inline
  /// D-pad keyboard only renders as fallback when the native path is broken.
  /// Everywhere else the pill stays read-only and the inline keyboard is the
  /// input.
  Widget _buildTvSearchField(BuildContext context, int? total) {
    final nativePill = PlatformDetector.isAppleTV() && !_nativeEntryUnavailable;
    final countLabel = TvSearchViewState.resultCountLabel(
      hasQuery: _hasSearched,
      isSearching: _isSearching,
      total: total,
    );
    final pill = ListenableBuilder(
      listenable: _searchController,
      builder: (context, _) {
        final text = _searchController.text;
        return InputDecorator(
          decoration: pillInputDecoration(
            context,
            hintText: t.search.hint,
            prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
            // 36 B puts "14 resultaten" inside the pill, at tertiary ink. It is
            // a statement about the query, so it belongs to the field that
            // holds the query rather than to a line above the first band.
            suffixIcon: countLabel == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      countLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: TvCatalogLayout.inkTertiary),
                      ),
                    ),
                  ),
          ),
          isEmpty: text.isEmpty,
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nativePill)
            FocusableButton(
              focusNode: _searchFocusNode,
              onPressed: _openNativeSearchEntry,
              onNavigateLeft: _navigateToSidebar,
              onNavigateDown: _handleTvKeyboardNavigateDown,
              onBack: _handleTvKeyboardClose,
              child: pill,
            )
          else
            pill,
          // Apple TV gets no mic button: the mic is on the remote and dictates
          // the moment the system keyboard is up, which selecting the pill
          // already does. Android TV needs one — there the mic opens
          // RecognizerIntent.
          if (_voiceSearchSupported && !PlatformDetector.isAppleTV())
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: FocusableButton(
                  onPressed: _openNativeSearchEntry,
                  child: TextButton.icon(
                    onPressed: _openNativeSearchEntry,
                    icon: const AppIcon(Symbols.mic_rounded, fill: 1),
                    label: Text(t.search.voiceSearch),
                  ),
                ),
              ),
            ),
          if (!nativePill)
            Padding(
              padding: const EdgeInsets.only(top: 12),
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
        ],
      ),
    );
  }

  /// The one "focus the first result" target every submit/keyboard-navigate
  /// call site already used. On TV the view answers it — the first card of the
  /// first band, or the one action an empty state has; off TV it is the first
  /// card of the list, unchanged.
  void _focusFirstResult() {
    if (_tvSearchKey.currentState?.focusFirstResult() ?? false) return;
    _firstResultFocusNode.requestFocus();
  }

  /// The phone result sections (I4, `05-zoeken.png`): the same `_projection`
  /// TV renders as rails, presented as one rounded row-list card per
  /// section — the phone's own list shape (`mobile_media_rail.dart`'s cards
  /// are a horizontal-rail grid, the wrong shape for a results *list*).
  ///
  /// A specific type chip (movies/shows/episodes) narrows to just that
  /// section; collections/playlists/people/other only ever show under "all",
  /// matching how `_filteredResults` narrowed the desktop list before I4 —
  /// picking a kind chip there dropped everything outside movie/show/episode
  /// too.
  Widget _buildMobileResults(BuildContext context) {
    final projection = _projection;
    if (projection == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final showMovies = _activeFilter == _SearchFilter.all || _activeFilter == _SearchFilter.movies;
    final showShows = _activeFilter == _SearchFilter.all || _activeFilter == _SearchFilter.shows;
    final showEpisodes = _activeFilter == _SearchFilter.all || _activeFilter == _SearchFilter.episodes;
    final showRest = _activeFilter == _SearchFilter.all;

    final sections = <Widget>[
      if (showMovies && projection.movies.isNotEmpty)
        _MobileSearchSection(
          sectionId: 'movies',
          title: t.unifiedCatalog.moviesTitle,
          children: [for (final group in projection.movies) _mobileGroupRow(context, group)],
        ),
      if (showShows && projection.shows.isNotEmpty)
        _MobileSearchSection(
          sectionId: 'shows',
          title: t.unifiedCatalog.seriesTitle,
          children: [for (final group in projection.shows) _mobileGroupRow(context, group)],
        ),
      if (showEpisodes && projection.episodes.isNotEmpty)
        _MobileSearchSection(
          sectionId: 'episodes',
          title: t.search.filters.episodes,
          children: [for (final group in projection.episodes) _mobileGroupRow(context, group)],
        ),
      if (showRest && projection.collections.isNotEmpty)
        _MobileSearchSection(
          sectionId: 'collections',
          title: t.collections.title,
          children: [
            for (final item in projection.collections) _mobileItemRow(context, item, onTap: () => _openConcrete(item)),
          ],
        ),
      if (showRest && projection.playlists.isNotEmpty)
        _MobileSearchSection(
          sectionId: 'playlists',
          title: t.playlists.title,
          children: [
            for (final item in projection.playlists) _mobileItemRow(context, item, onTap: () => _openConcrete(item)),
          ],
        ),
      if (showRest && projection.people.isNotEmpty)
        _MobileSearchSection(
          sectionId: 'people',
          title: t.search.filters.people,
          children: [
            for (final item in projection.people) _mobileItemRow(context, item, onTap: () => _openPerson(item)),
          ],
        ),
      if (showRest && projection.other.isNotEmpty)
        _MobileSearchSection(
          sectionId: 'other',
          title: t.search.filters.other,
          children: [
            for (final item in projection.other) _mobileItemRow(context, item, onTap: () => _openConcrete(item)),
          ],
        ),
    ];

    if (sections.isEmpty) {
      return SliverFillRemaining(
        child: StateView.empty(
          title: t.messages.noResultsFound,
          message: t.search.tryDifferentTerm,
          icon: Symbols.search_off_rounded,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverList(delegate: SliverChildListDelegate(sections)),
    );
  }

  /// A unified group's row: representative source's artwork/title, every
  /// group always carrying its source count (hoofdstuk 16.1's "Dune (2021) —
  /// 3 bronnen", true from one source up — `05-zoeken.png` shows "1 bron" on
  /// a single-source title, not a hidden label).
  ///
  /// Select opens detail on the representative source, the same read
  /// `mobile_home_screen.dart`'s own rail cards already use — full
  /// source-aware activation is I6 (film/series detail unified), not this
  /// workitem, and TV's own group activation
  /// (`TvDiscoveryActivationMixin.activateDiscoveryGroup`) opens a TV-only
  /// picker route this platform cannot show.
  Widget _mobileGroupRow(BuildContext context, UnifiedMediaGroup group) {
    final item = group.representativeSource.item;
    return _mobileResultTile(
      context,
      item: item,
      trailingLabel: group.sources.length == 1
          ? t.unifiedCatalog.oneSource
          : t.unifiedCatalog.sources(count: group.sources.length),
      onTap: () => _openMobileGroupDetails(group),
    );
  }

  Widget _mobileItemRow(BuildContext context, MediaItem item, {required VoidCallback onTap}) {
    return _mobileResultTile(context, item: item, trailingLabel: null, onTap: onTap);
  }

  Widget _mobileResultTile(
    BuildContext context, {
    required MediaItem item,
    required String? trailingLabel,
    required VoidCallback onTap,
  }) {
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    final muted = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7);
    final subtitle = _mobileResultSubtitle(item);
    final fallbackIcon = item.isShow || item.isSeason || item.isEpisode ? Symbols.tv_rounded : Symbols.movie_rounded;
    return FocusableListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: OptimizedMediaImage.poster(
          client: client,
          imagePath: item.posterThumb(),
          width: 46,
          height: 69,
          fallbackIcon: fallbackIcon,
          blurHash: item.posterBlurHash,
        ),
      ),
      title: Text(item.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingLabel != null) ...[Text(trailingLabel, style: TextStyle(color: muted)), const SizedBox(width: 4)],
          AppIcon(Symbols.chevron_right_rounded, color: muted),
        ],
      ),
      onTap: onTap,
    );
  }

  String? _mobileResultSubtitle(MediaItem item) {
    switch (item.kind) {
      case MediaKind.episode:
        final season = item.parentIndex;
        final episode = item.index;
        return season != null && episode != null
            ? t.unifiedCatalog.discovery.episodeLabel(season: season, episode: episode)
            : null;
      case MediaKind.show:
        final seasons = item.childCount;
        final seasonLabel = seasons != null && seasons > 0
            ? (seasons == 1 ? t.unifiedCatalog.oneSeason : t.unifiedCatalog.seasons(count: seasons))
            : null;
        final parts = [?item.year?.toString(), ?seasonLabel];
        return parts.isEmpty ? null : parts.join(' · ');
      case MediaKind.movie:
        final parts = [?item.year?.toString(), ?item.genres?.firstOrNull];
        return parts.isEmpty ? null : parts.join(' · ');
      default:
        return null;
    }
  }

  /// A group's representative source, opened as a read — see [_mobileGroupRow].
  void _openMobileGroupDetails(UnifiedMediaGroup group) {
    unawaited(navigateToMediaItemDetails(context, group.representativeSource.item, onRefresh: updateItem));
  }

  /// The desktop result list. TV never reaches this: `build` returns
  /// [_buildTv] before the sliver tree is assembled, and phone uses
  /// [_buildMobileResults] instead.
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
                // FocusableButton, not a bare TextButton: this row is the
                // default TV landing state, so everything on it must carry the
                // 10ft focus highlight and be select-activatable.
                FocusableButton(
                  onPressed: _clearHistory,
                  child: TextButton(onPressed: _clearHistory, child: Text(t.search.clearHistory)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final query in _history)
                  FocusableFilterChip(
                    icon: Symbols.history_rounded,
                    label: query,
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
    if (PlatformDetector.isTV()) return _buildTv(context);
    final isPhone = PlatformDetector.isPhone(context);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          primary: false,
          slivers: [
            DesktopSliverAppBar(
              title: Text(t.common.search),
              floating: true,
              // I4/`05-zoeken.png`: only the phone build reaches Zoeken by tab
              // selection rather than a pushed route (see `MainScreen._openSearch`),
              // so it is the only one that needs an explicit way back.
              leading: isPhone && widget.onBack != null ? BackButton(onPressed: widget.onBack) : null,
            ),
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
                  onNavigateDown: _searchResults.isNotEmpty && !_isSearching ? _focusFirstResult : null,
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
            // On phone, "no results" has to look at the projection, not just
            // `_searchResults`: SRCH-2 means a query can match a person with
            // no matching title at all, and `_searchResults` alone would
            // then read as empty even though `_buildMobileResults` has a
            // people section to draw.
            else if (isPhone ? (_projection?.isEmpty ?? _searchResults.isEmpty) : _searchResults.isEmpty)
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
            else if (isPhone) ...[
              SliverToBoxAdapter(child: _buildFilterChips(context)),
              _buildMobileResults(context),
              if (context.watch<SeerrProvider?>()?.isConfigured ?? false) _buildSeerrFallback(context),
            ] else ...[
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

/// One phone result section (I4): a small-caps label above a rounded card
/// of rows, `05-zoeken.png`'s FILMS/SERIES/… groups. `Card` rather than a
/// hand-rolled `Container`/`BoxDecoration`: it already reads the app's
/// `CardTheme` surface color, so this needs no new token.
class _MobileSearchSection extends StatelessWidget {
  final String sectionId;
  final String title;
  final List<Widget> children;

  const _MobileSearchSection({required this.sectionId, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AutomationNode(
      id: AutomationIds.searchResultsSection,
      instance: sectionId,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    AutomationNode(
                      id: AutomationIds.searchResultsItem,
                      instance: '$sectionId.$i',
                      role: 'list.item',
                      child: children[i],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
