import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../widgets/focusable_filter_chip.dart';
import '../i18n/strings.g.dart';
import '../media/media_kind.dart';
import '../media/watchlist_entry.dart';
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
import '../utils/grid_size_calculator.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';

/// Which slice of the kijklijst is on screen.
enum WatchlistFilter { all, movies, shows, available }

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

class _WatchlistScreenState extends State<WatchlistScreen> {
  bool _requestedLoad = false;
  WatchlistFilter _filter = WatchlistFilter.all;
  WatchlistSort _sort = WatchlistSort.recentlyAdded;

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
  /// other: entries outside the viewport are still unknown, so without the
  /// sweep the filter would hide titles that are in fact there.
  Future<void> _setFilter(WatchlistFilter filter) async {
    setState(() => _filter = filter);
    if (filter == WatchlistFilter.available) {
      await context.read<WatchlistProvider?>()?.resolveAllUnknown();
    }
  }

  /// Pick an order. Nothing else happens: no fetch, no availability sweep.
  ///
  /// The contrast with [_setFilter] is the point. Availability is a question
  /// for the servers, so asking for it costs a round of lookups; order is a
  /// property of what is already loaded, so it costs a rebuild.
  Future<void> _pickSort() async {
    final picked = await showWatchlistSortSheet(context, current: _sort);
    if (picked == null || !mounted) return;
    setState(() => _sort = picked);
  }

  List<WatchlistEntry> _sorted(WatchlistProvider provider) =>
      List<WatchlistEntry>.of(provider.entries)..sort(_sort.comparator(provider.sourcePriority));

  List<WatchlistEntry> _applyFilter(List<WatchlistEntry> entries) {
    return switch (_filter) {
      WatchlistFilter.all => entries,
      WatchlistFilter.movies => entries.where((e) => e.kind == MediaKind.movie).toList(),
      WatchlistFilter.shows => entries.where((e) => e.kind == MediaKind.show).toList(),
      WatchlistFilter.available => entries.where((e) => e.availability == WatchlistAvailability.available).toList(),
    };
  }

  Future<void> _openSheet(WatchlistProvider provider, WatchlistEntry entry) async {
    final action = await showWatchlistItemSheet(context, entry: entry, requestability: provider.requestability(entry));
    if (action == null || !mounted) return;
    switch (action) {
      case WatchlistSheetAction.request:
        await _request(entry);
      case WatchlistSheetAction.remove:
        // No snackbar on success: the card leaves the grid, and that is the
        // confirmation. A failure still speaks, because there nothing moves.
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WatchlistProvider?>();
    final isOffline = context.watch<OfflineModeProvider?>()?.isOffline ?? false;
    final all = provider == null ? const <WatchlistEntry>[] : _sorted(provider);
    final entries = _applyFilter(all);

    return Scaffold(
      body: CustomScrollView(
        // Not the default Clip.hardEdge: a focused card grows past its cell and
        // the ring would be sheared off at the viewport edge on TV.
        clipBehavior: Clip.none,
        slivers: [
          CustomAppBar(title: Text(t.watchlist.title), automaticallyImplyLeading: false),
          SliverToBoxAdapter(
            child: _FilterBar(
              filter: _filter,
              // Availability needs live servers, so offline the filter is not
              // a slower answer but a wrong one. Sorting has no such problem
              // and stays where it is.
              showAvailable: !isOffline,
              onChanged: _setFilter,
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
                onRetry: all.isEmpty ? _reload : () => _setFilter(WatchlistFilter.all),
                retryLabel: all.isEmpty ? t.watchlist.retry : t.watchlist.filterAll,
              ),
            )
          else
            _buildGrid(provider, entries),
        ],
      ),
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
    required this.filter,
    required this.showAvailable,
    required this.onChanged,
    required this.sort,
    required this.onSortPressed,
  });

  final WatchlistFilter filter;
  final bool showAvailable;
  final ValueChanged<WatchlistFilter> onChanged;
  final WatchlistSort sort;
  final VoidCallback onSortPressed;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final ScrollController _controller = ScrollController();
  final Map<WatchlistFilter, GlobalKey> _chipKeys = {for (final f in WatchlistFilter.values) f: GlobalKey()};

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
    if (oldWidget.filter != widget.filter) _revealSelected();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scrolls the active filter fully into view. Without this the selected chip
  /// could sit off-screen on a phone, and coming back to the tab showed a strip
  /// that started halfway through a word.
  void _revealSelected() {
    if (!mounted || !_controller.hasClients) return;
    final context = _chipKeys[widget.filter]?.currentContext;
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
    final options = <(WatchlistFilter, String)>[
      (WatchlistFilter.all, t.watchlist.filterAll),
      (WatchlistFilter.movies, t.watchlist.filterMovies),
      (WatchlistFilter.shows, t.watchlist.filterShows),
      if (widget.showAvailable) (WatchlistFilter.available, t.watchlist.filterAvailable),
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
                        label: label,
                        selected: widget.filter == value,
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
