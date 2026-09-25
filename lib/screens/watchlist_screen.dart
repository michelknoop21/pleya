import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../widgets/focusable_filter_chip.dart';
import '../i18n/strings.g.dart';
import '../media/media_kind.dart';
import '../media/watchlist_entry.dart';
import '../media/watchlist_filter.dart';
import '../models/seerr/seerr_media.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/settings_service.dart';
import '../services/watchlist_ui_actions.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/seerr_request_sheet.dart';
import '../widgets/media_card_grid_layout.dart';
import '../widgets/media_grid_delegate.dart';
import '../widgets/settings_builder.dart';
import '../widgets/sliver_cross_axis_layout_builder.dart';
import '../widgets/state_view.dart';
import '../widgets/watchlist_card.dart';
import '../widgets/watchlist_item_sheet.dart';
import '../widgets/watchlist_filter_sheet.dart';
import '../widgets/watchlist_sort_sheet.dart';
import '../mixins/refreshable.dart';
import '../navigation/main_screen_scope.dart';
import '../providers/multi_server_provider.dart';
import '../media/ids.dart';
import '../utils/grid_size_calculator.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import '../utils/media_navigation_helper.dart';
import 'tv/tv_watchlist_view.dart';

/// The full kijklijst.
///
/// A flat grid in the order titles were added, available and unavailable mixed
/// together. Grouping by availability was considered and dropped: it needs the
/// whole list resolved before the screen can settle, so at 300 titles across
/// several servers the grid would keep reflowing while answers trickle in, and
/// that fights the lazy resolver instead of using it. Ordering by availability
/// is still possible, but only when the user asks for it through the filter,
/// and asking for it is what pays for the full sweep.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> implements FocusableTab {
  bool _requestedLoad = false;
  WatchlistFilterSelection _selection = WatchlistFilterSelection.none;
  WatchlistSort _sort = WatchlistSort.recentlyAdded;

  /// The first filter chip, which is this screen's header off TV: UP out of the
  /// first grid row lands here, and so does a DOWN out of the bar on an empty
  /// list.
  final FocusNode _filterBarFocus = FocusNode(debugLabel: 'watchlistFilterBar');

  /// The TV presentation, when there is one. It owns the rail, the grid and the
  /// focus traversal; this state owns the data and the sheets, which the phone
  /// shares.
  final GlobalKey<TvWatchlistViewState> _tvKey = GlobalKey<TvWatchlistViewState>();

  @override
  void dispose() {
    _filterBarFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedLoad) return;
    _requestedLoad = true;
    final provider = context.read<WatchlistProvider?>();
    // Already loaded for this profile: returning to the tab should not put a
    // spinner over a list that is already right.
    if (provider?.hasLoaded ?? false) return;
    final isOffline = _isOffline;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider?.load(offline: isOffline);
    });
  }

  bool get _isOffline => context.read<OfflineModeProvider?>()?.isOffline ?? false;

  Future<void> _reload() async {
    await context.read<WatchlistProvider?>()?.load(offline: _isOffline);
  }

  /// Turning on "Available" pays for a full sweep of everything still
  /// unresolved. Lazy resolving and filtering on availability contradict each
  /// other: entries the cursor has not reached are still unknown, so without the
  /// sweep the filter would hide titles that are in fact there.
  ///
  /// It is the one thing the rail may promise, and the reason it offers
  /// Beschikbaarheid as two answers rather than three: "Niet beschikbaar" would
  /// need the same sweep and would then be answering with a snapshot of what
  /// happened to have resolved.
  Future<void> _setSelection(WatchlistFilterSelection selection) async {
    if (selection == _selection) return;
    final needsSweep = selection.availableOnly && !_selection.availableOnly;
    setState(() => _selection = selection);
    if (needsSweep) await context.read<WatchlistProvider?>()?.resolveAllUnknown();
  }

  /// Pick an order. Nothing else happens: no fetch, no availability sweep.
  ///
  /// The contrast with [_setSelection] is the point. Availability is a question
  /// for the servers, so asking for it costs a round of lookups; order is a
  /// property of what is already loaded, so it costs a rebuild.
  Future<void> _pickSort() async {
    final picked = await showWatchlistSortSheet(context, current: _sort);
    if (picked == null || !mounted) return;
    setState(() => _sort = picked);
  }

  Future<void> _pickFilters() async {
    final picked = await showWatchlistFilterSheet(context, current: _selection, showAvailable: !_isOffline);
    if (picked == null || !mounted) return;
    await _setSelection(picked);
  }

  Future<void> _activateEntry(WatchlistProvider provider, WatchlistEntry entry) async {
    final match = entry.lastKnownMatch;
    if (provider.isPlayable(entry) && match != null) {
      await navigateToMediaItem(context, match);
      return;
    }
    await _openSheet(provider, entry);
  }

  List<WatchlistEntry> _sorted(WatchlistProvider provider) =>
      List<WatchlistEntry>.of(provider.entries)..sort(_sort.comparator(provider.sourcePriority));

  Future<void> _openSheet(WatchlistProvider provider, WatchlistEntry entry) async {
    final action = await showWatchlistItemSheet(context, entry: entry, requestability: provider.requestability(entry));
    if (action == null || !mounted) return;
    switch (action) {
      case WatchlistSheetAction.request:
        await _request(entry);
      case WatchlistSheetAction.remove:
        // No snackbar on success: the card leaves the grid, and that is the
        // confirmation. A failure still speaks, because there nothing moves.
        //
        // TvCatalogCardGrid's reconcile rescues the ring, walking outward from
        // the old position so a neighbour takes it. But the rescue only moves
        // focus when the disappearing card is actually holding it at that
        // moment (WL3), and by the time Verwijderen is pressed here it is
        // not: Select opened this sheet first, the sheet has held the ring
        // since, and the card only disappears once Verwijderen is pressed
        // inside it. The grid cannot tell "a sheet borrowed my focus" from
        // "focus left for good" from inside its own reconcile, so a shared
        // fix there would have to trust every caller's modal to give the
        // ring back, which the grid has no way to verify. The sheet is the
        // one that borrowed it, so the sheet is the one that returns it:
        // hand the ring back to the grid before the card disappears.
        _tvKey.currentState?.focusContent();
        await WatchlistUiActions.remove(context, entry);
      case WatchlistSheetAction.cancel:
        break;
    }
  }

  /// Open the Seerr request sheet for [entry].
  ///
  /// The TMDB id comes off the entry rather than out of a lookup: the sources
  /// already parsed it from Plex' `Guid` array or Jellyfin's `ProviderIds`, and
  /// a catalogue item has no server to ask a second time.
  Future<void> _request(WatchlistEntry entry) async {
    final tmdb = entry.externalIds.tmdb;
    if (tmdb == null) {
      showErrorSnackBar(context, t.seerr.errorGeneric);
      return;
    }
    final requested = await SeerrRequestSheet.show(
      context,
      media: SeerrMedia(
        tmdbId: tmdb,
        mediaType: entry.kind == MediaKind.show ? 'tv' : 'movie',
        title: entry.item.displayTitle,
      ),
    );
    if (requested == true && mounted) showSuccessSnackBar(context, t.seerr.requestSuccess);
  }

  // ------------------------------------------------------------------ focus

  /// DOWN out of the top navigation (hoofdstuk 7.1).
  ///
  /// On TV the view answers it — the rail if it is open, otherwise the card the
  /// viewer was last on. Off TV the filter bar is the only thing on this page
  /// that is programmatically focusable, and it is also this page's header.
  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    final tv = _tvKey.currentState;
    if (tv != null) {
      tv.focusContent();
      return;
    }
    if (_filterBarFocus.canRequestFocus) _filterBarFocus.requestFocus();
  }

  /// LEFT off the first column, and UP out of the rail. On the TV shell that is
  /// the top navigation — see `TvRootShell` on why the coordinator's "sidebar"
  /// vocabulary is reused.
  void _exitLeft() => MainScreenFocusScope.of(context, listen: false)?.focusSidebar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WatchlistProvider?>();
    final isOffline = context.watch<OfflineModeProvider?>()?.isOffline ?? false;
    final all = provider == null ? const <WatchlistEntry>[] : _sorted(provider);
    final entries = _selection.apply(all);

    if (PlatformDetector.isTV()) return _buildTv(provider, all, entries, isOffline: isOffline);

    return Scaffold(
      body: CustomScrollView(
        // Not the default Clip.hardEdge: a focused card grows past its cell and
        // the ring would be sheared off at the viewport edge on TV.
        clipBehavior: Clip.none,
        slivers: [
          CustomAppBar(title: Text(t.watchlist.title), automaticallyImplyLeading: false),
          SliverToBoxAdapter(
            child: _FilterBar(
              firstChipFocusNode: _filterBarFocus,
              selection: _selection,
              onFiltersPressed: _pickFilters,
              sort: _sort,
              onSortPressed: _pickSort,
            ),
          ),
          if (provider == null || (provider.isLoading && all.isEmpty))
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: StateView.empty(
                icon: Symbols.bookmark_add_rounded,
                // An empty watchlist and a filter that hides everything are
                // different problems and get different words.
                title: all.isEmpty ? t.watchlist.empty : t.watchlist.emptyFiltered,
                message: all.isEmpty ? t.watchlist.emptyBody : null,
                // Without a retry there is no focusable element left here, and
                // a TV remote would have nowhere to go.
                onRetry: all.isEmpty ? _reload : () => _setSelection(WatchlistFilterSelection.none),
                retryLabel: all.isEmpty ? t.watchlist.retry : t.watchlist.filterAll,
              ),
            )
          else
            _buildGrid(provider, entries),
        ],
      ),
    );
  }

  /// The kijklijst on TV: the same data, in the catalog language (DEC-108).
  ///
  /// The view is handed finished lists and callbacks and owns no provider of
  /// its own — that split is what lets it be pumped in a test without a
  /// `WatchlistProvider`, and it is why the sheets, the sweep and the load stay
  /// here where the phone can share them.
  Widget _buildTv(
    WatchlistProvider? provider,
    List<WatchlistEntry> all,
    List<WatchlistEntry> entries, {
    required bool isOffline,
  }) {
    return TvWatchlistView(
      key: _tvKey,
      entries: entries,
      totalCount: all.length,
      selection: _selection,
      sort: _sort,
      onSelectionChanged: _setSelection,
      onSortChanged: (sort) => setState(() => _sort = sort),
      onActivate: provider == null ? (_) {} : (entry) => unawaited(_activateEntry(provider, entry)),
      onContextMenu: provider == null ? (_) {} : (entry) => unawaited(_openSheet(provider, entry)),
      isLoading: provider == null || (provider.isLoading && all.isEmpty),
      coverageComplete: provider?.isComplete ?? true,
      offerAvailability: !isOffline,
      onReload: _reload,
      error: all.isEmpty ? provider?.error : null,
      clientFor: (serverId) => context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId)),
      onNeedsAvailability: provider == null
          ? null
          : (wanted) {
              for (final entry in wanted) {
                provider.resolveAvailability(entry);
              }
            },
      onExitTop: _exitLeft,
    );
  }

  /// Smallest a watchlist card may get before its own content stops fitting:
  /// a title on two lines, a year under it, and an availability badge across
  /// the poster. Handheld and tablet widths size their columns against this
  /// instead of against the library's target extent, which rounds up and put a
  /// fourth 85pt poster on a phone.
  static const double _minCardWidthHandheld = 108;
  static const double _minCardWidthTablet = 150;

  /// Two lines of title on the layouts where a card is wide enough to make the
  /// second line worth reserving.
  static int _titleLinesFor(double width) => ScreenBreakpoints.isDesktopOrLarger(width) ? 1 : 2;

  Widget _buildGrid(WatchlistProvider provider, List<WatchlistEntry> entries) {
    // The bottom bar is the shell's, not this screen's, so the room it takes
    // comes from the padding the shell leaves behind rather than from a number
    // typed in here.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 24 + safeBottom),
      sliver: SettingsBuilder(
        prefs: const [SettingsService.libraryDensity],
        builder: (context) {
          final density = SettingsService.instance.read(SettingsService.libraryDensity);
          return SliverCrossAxisLayoutBuilder(
            builder: (context, crossAxisExtent) {
              final geometry = MediaGridGeometry.resolve(
                context: context,
                crossAxisExtent: crossAxisExtent,
                density: density,
                usePaddingAware: true,
                horizontalPadding: 16,
              );
              final screenWidth = MediaQuery.sizeOf(context).width;
              final titleLines = _titleLinesFor(screenWidth);

              // Desktop and TV keep the library's geometry; a phone or tablet
              // gets its columns from how wide a card has to be to stay
              // readable, so the row never packs one more poster than fits.
              final int columnCount;
              if (ScreenBreakpoints.isDesktopOrLarger(screenWidth) || PlatformDetector.isTV()) {
                columnCount = geometry.columnCount;
              } else {
                columnCount = GridSizeCalculator.getColumnCountForMinWidth(
                  crossAxisExtent,
                  ScreenBreakpoints.isTablet(screenWidth) ? _minCardWidthTablet : _minCardWidthHandheld,
                  spacing: geometry.spacing,
                );
              }
              final itemWidth = GridSizeCalculator.getCellWidthForColumnCount(
                crossAxisExtent,
                columnCount,
                crossAxisSpacing: geometry.spacing,
              );
              // One contract for the cell and both card branches: a 2:3
              // poster plus the caption block MediaCard draws under it.
              final cellHeight = MediaCardGridLayout.cardHeightFor(context, itemWidth, titleLines: titleLines);
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  mainAxisSpacing: geometry.spacing,
                  crossAxisSpacing: geometry.spacing,
                  childAspectRatio: itemWidth / cellHeight,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = entries[index];
                  // Viewport-driven: a card asks for its own row as it is
                  // built, so a 300-title list never fans out 300 lookups on
                  // open.
                  if (entry.availability == WatchlistAvailability.unknown) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) provider.resolveAvailability(entry);
                    });
                  }
                  return WatchlistCard(
                    entry: entry,
                    isPlayable: provider.isPlayable(entry),
                    onTap: () => _openSheet(provider, entry),
                    // Both branches lay out inside the cell through
                    // MediaCardGridLayout, so nothing spills into the row
                    // below.
                    width: itemWidth,
                    titleLines: titleLines,
                  );
                }, childCount: entries.length),
              );
            },
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatefulWidget {
  const _FilterBar({
    required this.firstChipFocusNode,
    required this.selection,
    required this.onFiltersPressed,
    required this.sort,
    required this.onSortPressed,
  });

  /// Owned by the screen: it is this page's header, and UP out of the first
  /// grid row has to be able to reach it from outside this widget.
  final FocusNode firstChipFocusNode;

  final WatchlistFilterSelection selection;
  final VoidCallback onFiltersPressed;
  final WatchlistSort sort;
  final VoidCallback onSortPressed;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  /// Matches the grid's own inset, so the first chip lines up with the first
  /// poster instead of starting somewhere of its own.
  static const double _inset = 8;

  @override
  Widget build(BuildContext context) {
    final activeCount =
        (widget.selection.kind == WatchlistKindFilter.all ? 0 : 1) + (widget.selection.availableOnly ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            AutomationNode(
              id: AutomationIds.catalogChipFilters,
              instance: 'watchlist',
              role: 'button',
              child: FocusableFilterChip(
                variant: FilterChipVariant.filled,
                focusNode: widget.firstChipFocusNode,
                icon: Symbols.filter_list_rounded,
                label: t.unifiedCatalog.filters.title,
                badgeCount: activeCount,
                onPressed: widget.onFiltersPressed,
              ),
            ),
            const SizedBox(width: 8),
            AutomationNode(
              id: AutomationIds.catalogChipSort,
              instance: 'watchlist',
              role: 'button',
              child: FocusableFilterChip(
                icon: Symbols.swap_vert_rounded,
                label: watchlistSortLabel(widget.sort),
                variant: FilterChipVariant.filled,
                onPressed: widget.onSortPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
