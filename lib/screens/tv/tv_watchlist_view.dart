/// The kijklijst on TV, in the catalog language
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108), mockup 34 A–D).
///
/// Until 7 September 2026 this page was a strip of filter chips over a
/// `SliverGrid` of `WatchlistCard`s. It already used [TvCatalogGrid]'s
/// geometry — P6 fixed that — but it was the only TV surface left whose
/// controls sat *above* the content instead of in CAT5's rail, and whose card
/// changed shape depending on whether an availability lookup had landed.
///
/// ## What this view owns, and what it does not
///
/// It owns presentation and focus traversal, and nothing else: the entries
/// arrive already sorted and filtered, and every action is a callback.
/// `watchlist_screen.dart` keeps the provider, the sheets and the filter state,
/// because the phone shares all three.
///
/// ## Where the remote can go
///
/// ```
///            topnav
///              │ DOWN            UP │
///              ▼                    │
///   rail ◀── LEFT ── grid ──────────┘
///        ── RIGHT/Menu ──▶
/// ```
///
/// The same shape as the catalog's, and deliberately so — this is the fourth
/// page on that contract, and a viewer who has learnt it on Films should not
/// have to learn it again here. What is different is one layer down: a rail row
/// opens a [TvCatalogFilterRailSubview] in place rather than an overlay panel,
/// because Soort, Beschikbaarheid and Sortering are each one column of radio
/// options. The only opened state the approved set draws for these pages is
/// that subview (mockup 35 D); the overlay panel belongs to the catalog's
/// two-zone multi-select and was never drawn here.
///
/// ## Availability is resolved around the focus, not around the viewport
///
/// The kijklijst resolves lazily on purpose: a 300-title list must not fan out
/// 300 lookups on open. On the phone that is viewport-driven — a card asks for
/// its own row as it is built. That does not survive the move to
/// [TvCatalogCardGrid], which builds every row eagerly (see its library doc),
/// so a card asking on build would ask for all three hundred at once.
///
/// So on TV the cursor drives it, which on this platform means the focus. The
/// grid reports the focused cell and its geometry, and the row it is in plus
/// the rows either side get their lookups. It is the same substitution the
/// artwork prefetcher makes one file over, for the same reason.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/watchlist_entry.dart';
import '../../media/watchlist_filter.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_catalog_card_grid.dart';
import '../../widgets/tv/tv_catalog_empty_state.dart';
import '../../widgets/tv/tv_catalog_filter_rail.dart';
import '../../widgets/tv/tv_catalog_header_bar.dart';
import '../../widgets/tv/tv_catalog_rail_scaffold.dart';
import '../../widgets/tv/tv_catalog_selection_tags.dart';
import '../../widgets/tv/tv_catalog_skeleton_grid.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_watchlist_card.dart';
import '../../widgets/watchlist_sort_sheet.dart';

/// Which of the rail's three questions is open, if any.
enum TvWatchlistRailSubview { kind, availability, sort }

/// What this page is called in `tv.catalog.*` automation ids, so a Pleya Verify
/// scenario names `tv.catalog.grid[watchlist]` the way it names
/// `tv.catalog.grid[movies]` on Alle films (WL2).
const String tvWatchlistSurface = 'watchlist';

class TvWatchlistView extends StatefulWidget {
  const TvWatchlistView({
    super.key,
    required this.entries,
    required this.totalCount,
    required this.selection,
    required this.sort,
    required this.onSelectionChanged,
    required this.onSortChanged,
    required this.onActivate,
    required this.isLoading,
    required this.coverageComplete,
    required this.offerAvailability,
    required this.onReload,
    this.error,
    this.clientFor,
    this.onNeedsAvailability,
    this.onExitTop,
  });

  /// Already filtered and sorted, in display order.
  final List<WatchlistEntry> entries;

  /// How many titles the kijklijst holds before [selection] is applied.
  ///
  /// It is the whole difference between mockup 34 D and an empty kijklijst: one
  /// says "you have 34 titles and none of them are this", the other says "you
  /// have nothing yet", and they need different words and a different way out.
  final int totalCount;

  final WatchlistFilterSelection selection;
  final WatchlistSort sort;
  final ValueChanged<WatchlistFilterSelection> onSelectionChanged;
  final ValueChanged<WatchlistSort> onSortChanged;

  /// Select on a card — the kijklijst item sheet.
  final ValueChanged<WatchlistEntry> onActivate;

  final bool isLoading;

  /// Whether every source answered on the last fetch. False draws mockup 34 C's
  /// line under the heading.
  final bool coverageComplete;

  /// Whether Beschikbaarheid is a question worth asking.
  ///
  /// False offline, where availability needs live servers, so the filter would
  /// not be a slower answer but a wrong one. The row is dropped rather than
  /// disabled, exactly as the phone drops its chip: a rail row that cannot be
  /// answered is a focus stop that costs a press to discover.
  final bool offerAvailability;

  final VoidCallback onReload;

  /// Set when the last load failed and there is nothing on screen.
  final String? error;

  final MediaServerClient? Function(String serverId)? clientFor;

  /// Asks for the availability of the entries the remote is near. See the
  /// library doc for why this is focus-driven rather than viewport-driven.
  final ValueChanged<List<WatchlistEntry>>? onNeedsAvailability;

  /// UP out of the first grid row, and out of the rail: the top navigation.
  final VoidCallback? onExitTop;

  @override
  State<TvWatchlistView> createState() => TvWatchlistViewState();
}

class TvWatchlistViewState extends State<TvWatchlistView> {
  final _gridKey = GlobalKey<TvCatalogCardGridState>();
  final _kindFocus = FocusNode(debugLabel: 'TvWatchlistRailKind');
  final _availabilityFocus = FocusNode(debugLabel: 'TvWatchlistRailAvailability');
  final _sortFocus = FocusNode(debugLabel: 'TvWatchlistRailSort');
  final _clearFocus = FocusNode(debugLabel: 'TvWatchlistRailClear');

  /// The one action a state with no grid has. It is the only thing left to put
  /// the remote on when the rail closes over an empty page.
  final _stateActionFocus = FocusNode(debugLabel: 'TvWatchlistStateAction');

  /// Whether the controls rail is open (CAT5). Closed is the resting state.
  bool _railExpanded = false;

  /// Which question the rail is opened onto, if any.
  TvWatchlistRailSubview? _subview;

  /// Set while this view still owes someone an entry focus: DOWN out of the
  /// topnav before the first page has arrived.
  bool _wantsEntryFocus = false;

  /// The rows around the focus whose availability has already been asked for,
  /// so a walk along a row does not re-ask for the same twelve titles.
  final Set<String> _requested = {};

  @override
  void didUpdateWidget(TvWatchlistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) _seedAvailability();
    if (_wantsEntryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryEntryFocus());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedAvailability());
  }

  @override
  void dispose() {
    _kindFocus.dispose();
    _availabilityFocus.dispose();
    _sortFocus.dispose();
    _clearFocus.dispose();
    _stateActionFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Availability, around the cursor
  // ---------------------------------------------------------------------------

  /// The first screenful, before anything has been focused.
  ///
  /// Without this an untouched page would resolve nothing at all: the focus
  /// hook only fires once the remote has moved, and a viewer who opens the
  /// kijklijst and reads it without pressing anything would see no badge on a
  /// title none of their servers has.
  void _seedAvailability() {
    if (!mounted || widget.entries.isEmpty) return;
    _requestWindow(0, _seedRows * _columnsGuess);
  }

  /// How many rows either side of the focused one are resolved with it.
  static const int _windowRows = 1;

  /// How many rows are resolved before the remote has moved at all.
  static const int _seedRows = 2;

  /// Only used by [_seedAvailability], which runs before a grid exists to ask.
  /// Six is the contract's own column count on the reference surface.
  static const int _columnsGuess = 6;

  void _onFocusedCell(int index, TvCatalogGrid grid) {
    final row = index ~/ grid.columns;
    final first = (row - _windowRows) * grid.columns;
    _requestWindow(first, grid.columns * (_windowRows * 2 + 1));
  }

  void _requestWindow(int start, int count) {
    final callback = widget.onNeedsAvailability;
    if (callback == null) return;
    final from = start.clamp(0, widget.entries.length);
    final to = (start + count).clamp(0, widget.entries.length);
    final wanted = <WatchlistEntry>[];
    for (var i = from; i < to; i++) {
      final entry = widget.entries[i];
      if (entry.availability != WatchlistAvailability.unknown) continue;
      if (!_requested.add(entry.key)) continue;
      wanted.add(entry);
    }
    if (wanted.isNotEmpty) callback(wanted);
  }

  // ---------------------------------------------------------------------------
  // Focus traversal
  // ---------------------------------------------------------------------------

  /// DOWN out of the top navigation: the rail if it is open, otherwise the card
  /// the viewer was last on.
  void focusContent() {
    if (!mounted) return;
    _wantsEntryFocus = true;
    _tryEntryFocus();
  }

  void _tryEntryFocus() {
    if (!mounted || !_wantsEntryFocus) return;
    if (_railExpanded) {
      if (_firstRailFocus.canRequestFocus) {
        _wantsEntryFocus = false;
        _firstRailFocus.requestFocus();
      }
      return;
    }
    final grid = _gridKey.currentState;
    if (grid != null && grid.hasFocusableCard) {
      _wantsEntryFocus = false;
      grid.focusGrid();
      return;
    }
    // The page has settled on a state with no grid at all. Those focus their own
    // action ([TvCatalogEmptyState] autofocuses it), and a request left standing
    // would steal the focus back off it the moment a late load arrived.
    if (!widget.isLoading) _wantsEntryFocus = false;
  }

  FocusNode get _firstRailFocus => _kindFocus;

  /// LEFT off column 0, and LEFT off the one action an empty state has.
  ///
  /// The focus request is deferred a frame on purpose: the rail's nodes are
  /// only attached once the panel has been built, and `requestFocus` on a node
  /// that is not in the tree yet does nothing at all, and silently.
  void _openRail() {
    if (_railExpanded) return;
    setState(() {
      _railExpanded = true;
      _subview = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_railExpanded) return;
      if (_firstRailFocus.canRequestFocus) _firstRailFocus.requestFocus();
    });
  }

  /// RIGHT or Menu out of the rail: back to the card it was opened from.
  void _closeRail() {
    if (!_railExpanded) return;
    setState(() {
      _railExpanded = false;
      _subview = null;
    });
    _focusContentAfterRail();
  }

  /// The card the rail was opened from, or — on a page with no grid — the one
  /// action the state has. Without the second half, closing the rail over a
  /// filtered-empty kijklijst leaves the page focused with nothing focused on
  /// it, which on tvOS is a page you can neither move within nor leave.
  void _focusContentAfterRail() {
    final grid = _gridKey.currentState;
    if (grid != null && grid.hasFocusableCard) {
      grid.focusGrid();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _railExpanded) return;
      if (_stateActionFocus.canRequestFocus) _stateActionFocus.requestFocus();
    });
  }

  /// UP or LEFT out of the rail: the topnav, with the rail closed behind it.
  ///
  /// Closing is not cosmetic. A rail left open with the focus somewhere else
  /// keeps a column off the grid for no reason the viewer can see, and DOWN out
  /// of the topnav would then land back in it rather than on the content.
  void _leaveRailUpwards() {
    if (_railExpanded) {
      setState(() {
        _railExpanded = false;
        _subview = null;
      });
    }
    widget.onExitTop?.call();
  }

  /// DOWN off the bottom of the rail: nothing at all.
  ///
  /// Explicit rather than left null. `FocusableWrapper` treats a missing handler
  /// as "not mine" and falls through to Flutter's own directional traversal,
  /// which from the last rail row walks sideways into the grid and leaves the
  /// rail standing open with the focus somewhere else.
  void _railEdge() {}

  void _openSubview(TvWatchlistRailSubview subview) => setState(() => _subview = subview);

  /// One layer back out of a subview, with the remote on the row it came from.
  void _closeSubview() {
    final was = _subview;
    if (was == null) return;
    setState(() => _subview = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _subview != null) return;
      final node = switch (was) {
        TvWatchlistRailSubview.kind => _kindFocus,
        TvWatchlistRailSubview.availability => _availabilityFocus,
        TvWatchlistRailSubview.sort => _sortFocus,
      };
      if (node.canRequestFocus) node.requestFocus();
    });
  }

  // ---------------------------------------------------------------------------
  // Choices
  // ---------------------------------------------------------------------------

  void _apply(WatchlistFilterSelection next) {
    if (next == widget.selection) {
      _closeSubview();
      return;
    }
    // A changed filter changes which entries are on screen, so what has already
    // been asked for is no longer what is near the cursor.
    _requested.clear();
    widget.onSelectionChanged(next);
    _closeSubview();
  }

  void _clearFilters() {
    // Wissen is only drawn while something is filtered, so pressing it removes
    // the row the remote is standing on. Naming the destination is the
    // difference between a move the viewer can follow and one the framework
    // picked. From the empty state the guard is false and nothing moves,
    // because there the button survives its own press.
    if (_clearFocus.hasFocus) _sortFocus.requestFocus();
    _requested.clear();
    widget.onSelectionChanged(WatchlistFilterSelection.none);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The tags are capped here and uncapped in the rail: the heading has one
        // line and no way to scroll, the panel wraps.
        TvCatalogHeaderBar(title: t.watchlist.title, tags: _railExpanded ? const [] : _tags()),
        if (!widget.coverageComplete && widget.entries.isNotEmpty) _CoverageNotice(scale: scale),
        Expanded(
          child: TvCatalogRailScaffold(
            cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
            rail: _railExpanded ? _buildRail(scale) : null,
            body: _buildBody(scale),
          ),
        ),
      ],
    );
  }

  double _railLeading() => TvCatalogRailScaffold.leadingFor(MediaQuery.sizeOf(context).width, expanded: _railExpanded);

  List<TvCatalogSelectionTag> _tags() => [
    if (widget.selection.availableOnly) TvCatalogSelectionTag(t.watchlist.filterAvailable),
    if (widget.selection.kind != WatchlistKindFilter.all) TvCatalogSelectionTag(_kindLabel(widget.selection.kind)),
    TvCatalogSelectionTag(watchlistSortLabel(widget.sort), muted: true),
  ];

  String _kindLabel(WatchlistKindFilter kind) => switch (kind) {
    WatchlistKindFilter.all => t.watchlist.filterAll,
    WatchlistKindFilter.movies => t.watchlist.filterMovies,
    WatchlistKindFilter.shows => t.watchlist.filterShows,
  };

  Widget _buildRail(double scale) {
    final subview = _subview;
    if (subview != null) {
      return AutomationNode(
        id: AutomationIds.tvCatalogRail,
        instance: '$tvWatchlistSurface.${subview.name}',
        role: 'region',
        child: TvCatalogFilterRailSubview(
          key: tvCatalogFilterRailSubviewKey,
          scale: scale,
          title: switch (subview) {
            TvWatchlistRailSubview.kind => t.watchlist.rail.kind,
            TvWatchlistRailSubview.availability => t.watchlist.rail.availability,
            TvWatchlistRailSubview.sort => t.libraries.sort,
          },
          options: _subviewOptions(subview),
          onBack: _closeSubview,
          onExitUp: _leaveRailUpwards,
          onExitDown: _railEdge,
          onExitRight: _closeRail,
        ),
      );
    }

    return AutomationNode(
      id: AutomationIds.tvCatalogRail,
      instance: tvWatchlistSurface,
      role: 'region',
      child: TvCatalogFilterRailPanel(
        key: tvCatalogFilterRailKey,
        scale: scale,
        rows: _railRows(),
        tags: _tags(),
        onClear: widget.selection.isEmpty ? null : _clearFilters,
        clearFocusNode: _clearFocus,
        onClearNavigateUp: () => _sortFocus.requestFocus(),
        onClearNavigateDown: _railEdge,
        onClearNavigateLeft: _leaveRailUpwards,
        onClearNavigateRight: _closeRail,
        onClearBack: _closeRail,
      ),
    );
  }

  List<TvCatalogFilterRailRow> _railRows() {
    final selection = widget.selection;
    // Beschikbaarheid drops out offline, so the row above it has to know what
    // is actually below it rather than assuming three rows.
    final availability = widget.offerAvailability;
    return [
      TvCatalogFilterRailRow(
        icon: Symbols.filter_list_rounded,
        label: t.watchlist.rail.kind,
        value: _kindLabel(selection.kind),
        automationInstance: '$tvWatchlistSurface.kind',
        focusNode: _kindFocus,
        onPressed: () => _openSubview(TvWatchlistRailSubview.kind),
        onNavigateUp: _leaveRailUpwards,
        onNavigateDown: () => (availability ? _availabilityFocus : _sortFocus).requestFocus(),
        onNavigateLeft: _leaveRailUpwards,
        onNavigateRight: _closeRail,
        onBack: _closeRail,
      ),
      if (availability)
        TvCatalogFilterRailRow(
          icon: Symbols.check_rounded,
          label: t.watchlist.rail.availability,
          value: selection.availableOnly ? t.watchlist.filterAvailable : t.watchlist.filterAll,
          automationInstance: '$tvWatchlistSurface.availability',
          focusNode: _availabilityFocus,
          onPressed: () => _openSubview(TvWatchlistRailSubview.availability),
          onNavigateUp: () => _kindFocus.requestFocus(),
          onNavigateDown: () => _sortFocus.requestFocus(),
          onNavigateLeft: _leaveRailUpwards,
          onNavigateRight: _closeRail,
          onBack: _closeRail,
        ),
      TvCatalogFilterRailRow(
        icon: Symbols.swap_vert_rounded,
        label: t.libraries.sort,
        value: watchlistSortLabel(widget.sort),
        automationInstance: '$tvWatchlistSurface.sort',
        focusNode: _sortFocus,
        onPressed: () => _openSubview(TvWatchlistRailSubview.sort),
        onNavigateUp: () => (availability ? _availabilityFocus : _kindFocus).requestFocus(),
        onNavigateDown: widget.selection.isEmpty ? _railEdge : () => _clearFocus.requestFocus(),
        onNavigateLeft: _leaveRailUpwards,
        onNavigateRight: _closeRail,
        onBack: _closeRail,
      ),
    ];
  }

  List<TvCatalogRailOption> _subviewOptions(TvWatchlistRailSubview subview) {
    final selection = widget.selection;
    return switch (subview) {
      TvWatchlistRailSubview.kind => [
        for (final kind in WatchlistKindFilter.values)
          TvCatalogRailOption(
            label: _kindLabel(kind),
            isSelected: selection.kind == kind,
            automationInstance: '$tvWatchlistSurface.kind.${kind.name}',
            onPressed: () => _apply(selection.copyWith(kind: kind)),
          ),
      ],
      TvWatchlistRailSubview.availability => [
        TvCatalogRailOption(
          label: t.watchlist.filterAll,
          isSelected: !selection.availableOnly,
          automationInstance: '$tvWatchlistSurface.availability.all',
          onPressed: () => _apply(selection.copyWith(availableOnly: false)),
        ),
        TvCatalogRailOption(
          label: t.watchlist.filterAvailable,
          isSelected: selection.availableOnly,
          automationInstance: '$tvWatchlistSurface.availability.available',
          onPressed: () => _apply(selection.copyWith(availableOnly: true)),
        ),
      ],
      TvWatchlistRailSubview.sort => [
        for (final sort in WatchlistSort.values)
          TvCatalogRailOption(
            label: watchlistSortLabel(sort),
            isSelected: widget.sort == sort,
            automationInstance: '$tvWatchlistSurface.sort.${sort.name}',
            onPressed: () {
              if (sort != widget.sort) widget.onSortChanged(sort);
              _closeSubview();
            },
          ),
      ],
    };
  }

  Widget _buildBody(double scale) {
    if (widget.isLoading && widget.entries.isEmpty) {
      return TvCatalogSkeletonGrid(key: tvCatalogSkeletonKey, reservedLeading: _railLeading());
    }

    if (widget.entries.isEmpty) {
      final error = widget.error;
      if (error != null) {
        return _state(
          'error',
          TvCatalogEmptyState(
            icon: Symbols.cloud_off_rounded,
            title: t.unifiedCatalog.states.errorTitle,
            body: error,
            actionLabel: t.common.retry,
            onActionFocusNode: _stateActionFocus,
            onAction: widget.onReload,
            onActionNavigateLeft: _openRail,
          ),
        );
      }
      // An empty kijklijst and a filter that hides everything are different
      // problems and get different words, and different ways out.
      if (widget.totalCount > 0) {
        return _state(
          'filtered',
          TvCatalogEmptyState(
            icon: Symbols.filter_list_rounded,
            title: t.watchlist.emptyFiltered,
            body: t.watchlist.emptyFilteredBody(count: widget.totalCount),
            actionLabel: t.unifiedCatalog.states.clearFilters,
            onActionFocusNode: _stateActionFocus,
            onAction: _clearFilters,
            onActionNavigateLeft: _openRail,
          ),
        );
      }
      return _state(
        'empty',
        TvCatalogEmptyState(
          icon: Symbols.bookmark_add_rounded,
          title: t.watchlist.empty,
          body: t.watchlist.emptyBody,
          actionLabel: t.watchlist.retry,
          onActionFocusNode: _stateActionFocus,
          onAction: widget.onReload,
          onActionNavigateLeft: _openRail,
        ),
      );
    }

    return AutomationNode(
      id: AutomationIds.tvCatalogGrid,
      instance: tvWatchlistSurface,
      role: 'grid',
      child: TvCatalogCardGrid(
        key: _gridKey,
        itemIds: [for (final entry in widget.entries) entry.key],
        cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
        // The kijklijst is merged and sorted in memory: it has no pages, so there
        // is nothing to load more of.
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: _railEdge,
        onExitTop: widget.onExitTop,
        onExitLeft: _openRail,
        onFocusedCell: _onFocusedCell,
        reservedLeading: _railLeading(),
        nodeDebugLabel: 'TvWatchlistCard',
        itemBuilder: (context, cell) {
          final entry = widget.entries[cell.index];
          return AutomationNode(
            id: AutomationIds.tvCatalogGridItem,
            instance: '$tvWatchlistSurface.${cell.index}',
            role: 'grid.item',
            label: entry.item.displayTitle,
            focusNode: cell.focusNode,
            child: TvWatchlistCard(
              key: ValueKey(entry.key),
              entry: entry,
              width: cell.width,
              clientFor: widget.clientFor,
              focusNode: cell.focusNode,
              onSelect: () => widget.onActivate(entry),
              onFocusChange: cell.onFocusChange,
              onNavigateUp: cell.onNavigateUp,
              onNavigateDown: cell.onNavigateDown,
              onNavigateLeft: cell.onNavigateLeft,
              onNavigateRight: cell.onNavigateRight,
            ),
          );
        },
      ),
    );
  }

  /// Names a non-content state so a scenario can tell "nothing matches this
  /// filter" apart from "your kijklijst is empty" without reading the words.
  Widget _state(String which, Widget child) => AutomationNode(
    id: AutomationIds.tvCatalogState,
    instance: '$tvWatchlistSurface.$which',
    role: 'region',
    focusNode: _stateActionFocus,
    child: child,
  );
}

/// Mockup 34 C's line: the list on screen may be missing titles, because a
/// source did not answer.
///
/// A quiet line under the heading rather than a banner over the grid, the same
/// judgement `TvUnifiedGridFooter` makes about a library that failed: the
/// titles that *did* arrive are healthy and are what the viewer came for. Amber,
/// which hoofdstuk 8.2 allows for exactly this — a status worth noticing that is
/// not an error. Red here would say the page failed, and it did not.
class _CoverageNotice extends StatelessWidget {
  const _CoverageNotice({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final width = MediaQuery.sizeOf(context).width;
    final grid = TvCatalogGrid.forWidth(width, scale: scale);
    // The heading's inset, not the grid's: this line reads as part of the page
    // header, and the header already lines its own text up with the posters.
    final inset = grid.inset + TvCatalogLayout.cardContentInset(scale);

    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, TvCatalogLayout.headerContentGap * scale),
      child: Row(
        children: [
          Container(
            width: TvCatalogLayout.badgeDotSize * scale,
            height: TvCatalogLayout.badgeDotSize * scale,
            decoration: BoxDecoration(color: tk.accentAlt, shape: BoxShape.circle),
          ),
          SizedBox(width: TvCatalogLayout.railIconGap * scale),
          Expanded(
            child: Text(
              t.watchlist.coverageIncompleteList,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogLayout.cardMetaFontSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
