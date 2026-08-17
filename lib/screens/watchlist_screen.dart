import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_button.dart';
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
import '../widgets/media_grid_delegate.dart';
import '../widgets/settings_builder.dart';
import '../widgets/sliver_cross_axis_layout_builder.dart';
import '../widgets/state_view.dart';
import '../widgets/watchlist_card.dart';
import '../widgets/watchlist_item_sheet.dart';
import '../widgets/watchlist_sort_sheet.dart';

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

  Widget _buildGrid(WatchlistProvider provider, List<WatchlistEntry> entries) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
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
              final cellHeight = geometry.itemWidth * 3 / 2 + watchlistCardTextExtent;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: geometry.columnCount,
                  mainAxisSpacing: geometry.spacing,
                  crossAxisSpacing: geometry.spacing,
                  childAspectRatio: geometry.itemWidth / cellHeight,
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
                    // Both branches of the card render at exactly the cell
                    // size; a card wider than its tile gets its top clipped.
                    width: geometry.itemWidth,
                    height: cellHeight,
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

class _FilterBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final options = <(WatchlistFilter, String)>[
      (WatchlistFilter.all, t.watchlist.filterAll),
      (WatchlistFilter.movies, t.watchlist.filterMovies),
      (WatchlistFilter.shows, t.watchlist.filterShows),
      if (showAvailable) (WatchlistFilter.available, t.watchlist.filterAvailable),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // The chips scroll and the sort button does not. At 360dp the four
          // chips no longer fit beside it, and scrolling them is the only
          // answer that keeps the bar one row high; wrapping would push the
          // first row of posters down on exactly the screens with the least
          // room for that.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
              child: Row(
                children: [
                  for (final (value, label) in options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: filter == value,
                        onSelected: (_) => onChanged(value),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 4),
            // The current order rides along as the tooltip instead of in the
            // label. A button whose text changes with the state would shift
            // the chips beside it every time the user sorts, and the tooltip
            // is also what a screen reader announces.
            child: Tooltip(
              message: watchlistSortLabel(sort),
              // Wrapped the way the rest of the app wraps its buttons, so on TV
              // the control gets a focus ring instead of only the hairline a
              // bare TextButton draws.
              child: FocusableButton(
                onPressed: onSortPressed,
                child: TextButton.icon(
                  onPressed: onSortPressed,
                  icon: const Icon(Symbols.sort_rounded, size: 18),
                  label: Text(t.libraries.sort),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
