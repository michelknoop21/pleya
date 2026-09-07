import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

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
import '../widgets/watchlist_sort_sheet.dart';
import '../mixins/refreshable.dart';
import '../navigation/main_screen_scope.dart';
import '../providers/multi_server_provider.dart';
import '../media/ids.dart';
import '../utils/grid_size_calculator.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
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
        // Nothing is done about the focus here any more. The card the remote
        // was on is about to be disposed, and `TvCatalogCardGrid` already
        // rescues that: it walks outward from the old position, forward first,
        // so the card that slides up into the empty cell takes the ring, and an
        // emptied grid falls back to whatever `onExitTop` points at.
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
              // Availability needs live servers, so offline the filter is not
              // a slower answer but a wrong one. Sorting has no such problem
              // and stays where it is.
              showAvailable: !isOffline,
              onChanged: (chip) => _setSelection(WatchlistFilterSelection.chip(chip)),
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
      onActivate: provider == null ? (_) {} : (entry) => _openSheet(provider, entry),
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
    required this.showAvailable,
    required this.onChanged,
    required this.sort,
    required this.onSortPressed,
  });

  /// Owned by the screen: it is this page's header, and UP out of the first
  /// grid row has to be able to reach it from outside this widget.
  final FocusNode firstChipFocusNode;

  final WatchlistFilterSelection selection;
  final bool showAvailable;
  final ValueChanged<WatchlistFilterChip> onChanged;
  final WatchlistSort sort;
  final VoidCallback onSortPressed;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final ScrollController _controller = ScrollController();
  final Map<WatchlistFilterChip, GlobalKey> _chipKeys = {for (final f in WatchlistFilterChip.values) f: GlobalKey()};

  /// Matches the grid's own inset, so the first chip lines up with the first
  /// poster instead of starting somewhere of its own.
  static const double _inset = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void didUpdateWidget(_FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) _revealSelected();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Which chip stands for the selection on screen, or null when the rail set
  /// something no single chip can express — which cannot happen from this bar,
  /// but can from the TV rail on a build that shares the state.
  WatchlistFilterChip? get _selectedChip {
    for (final chip in WatchlistFilterChip.values) {
      if (WatchlistFilterSelection.chip(chip) == widget.selection) return chip;
    }
    return null;
  }

  /// Scrolls the active filter fully into view. Without this the selected chip
  /// could sit off-screen on a phone, and coming back to the tab showed a strip
  /// that started halfway through a word.
  void _revealSelected() {
    if (!mounted || !_controller.hasClients) return;
    final context = _chipKeys[_selectedChip]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      alignment: 0.5,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = <(WatchlistFilterChip, String)>[
      (WatchlistFilterChip.all, t.watchlist.filterAll),
      (WatchlistFilterChip.movies, t.watchlist.filterMovies),
      (WatchlistFilterChip.shows, t.watchlist.filterShows),
      if (widget.showAvailable) (WatchlistFilterChip.available, t.watchlist.filterAvailable),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        // Chips and sort read as one toolbar: both sit on the same centre line
        // instead of each carrying its own top padding.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The chips scroll and the sort button does not. At 360dp the four
          // chips no longer fit beside it, and scrolling them is the only
          // answer that keeps the bar one row high; wrapping would push the
          // first row of posters down on exactly the screens with the least
          // room for that.
          Expanded(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              // Inset on the scroll view, not around it. Around the scrollport
              // it sits outside the scrollable area, so the first chip ended up
              // hard against the edge the moment the strip was dragged. There
              // used to be a fade over the last 12% here as well, which erased
              // the tail of the final chip and read as a clipped word rather
              // than as "there is more".
              padding: const EdgeInsets.symmetric(horizontal: _inset),
              child: Row(
                children: [
                  for (final (value, label) in options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FocusableFilterChip(
                        key: _chipKeys[value],
                        focusNode: value == options.first.$1 ? widget.firstChipFocusNode : null,
                        label: label,
                        selected: WatchlistFilterSelection.chip(value) == widget.selection,
                        onPressed: () => widget.onChanged(value),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: _inset),
            // The order is in the label, the way the libraries header shows it.
            // It used to ride along as a tooltip, and tooltips never open on an
            // iOS touch, so on a phone there was no way to see what the list
            // was sorted by.
            child: FocusableFilterChip(
              icon: Symbols.sort_rounded,
              label: t.libraries.sort,
              value: watchlistSortLabel(widget.sort),
              variant: FilterChipVariant.text,
              onPressed: widget.onSortPressed,
            ),
          ),
        ],
      ),
    );
  }
}
