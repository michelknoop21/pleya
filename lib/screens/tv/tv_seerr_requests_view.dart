/// Alle aanvragen on TV, as a wall of cards
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108) (3) and (4), mockup 35 C1
/// and 35 D).
///
/// ## Why a grid and not the list
///
/// 35 C1 and 35 C2 were two sides of one question, and C1 won on three grounds
/// the manifest records. At the 389 requests on the device C1 shows twelve per
/// screen and C2 five. The report this comes from (CAT11) was that this page
/// looks unlike the rest of the app, and a list on TV-scale keeps a second card
/// language alive while merely fixing the size. And the argument *for* a list —
/// that a row can carry its own approve and decline buttons — does not hold on
/// TV: actions there go through the unified context menu (PB-5), so a row with
/// buttons would be the exception rather than the rule.
///
/// What C1 costs is the date beside the requester. On a card 281 wide the two do
/// not both fit, and DEC-108 gives up the date deliberately.
///
/// ## The status choice, and TOK3
///
/// The filter used to be a `SegmentedTabGroup` — the one segmented accent on TV
/// that no other TV surface carries, which is what TOK3 was about. It is now a
/// subview of CAT5's rail, with the counts Seerr already reports beside each
/// answer. Menu or LEFT goes one layer back, the same as the player panel
/// ([DEC-101](../../../docs/DECISIONS.md#dec-101) punt 3).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_request.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_catalog_card_grid.dart';
import '../../widgets/tv/tv_catalog_empty_state.dart';
import '../../widgets/tv/tv_catalog_filter_rail.dart';
import '../../widgets/tv/tv_catalog_header_bar.dart';
import '../../widgets/tv/tv_catalog_rail_scaffold.dart';
import '../../widgets/tv/tv_catalog_selection_tags.dart';
import '../../widgets/tv/tv_catalog_skeleton_grid.dart';
import '../../widgets/tv/tv_seerr_card.dart';
import '../../widgets/tv/tv_unified_layout.dart';

/// What this page is called in `tv.catalog.*` automation ids (REQ1).
const String tvSeerrRequestsSurface = 'requests';

/// The four slices Seerr's `/request` endpoint filters by, plus the fifth this
/// page adds because the counts endpoint reports it.
///
/// The wire values are Overseerr's own filter strings and are not this file's to
/// rename: they go straight into the query.
enum TvSeerrRequestFilter {
  all('all'),
  pending('pending'),
  approved('approved'),
  available('available'),
  declined('declined');

  const TvSeerrRequestFilter(this.wire);

  final String wire;
}

/// How many requests are behind each answer, as Seerr reports them.
typedef TvSeerrRequestCounts = ({int total, int pending, int approved, int available, int processing});

class TvSeerrRequestsView extends StatefulWidget {
  const TvSeerrRequestsView({
    super.key,
    required this.title,
    required this.requests,
    required this.filter,
    required this.onFilterChanged,
    required this.onActivate,
    required this.isLoading,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onReload,
    this.counts,
    this.error,
    this.onExitTop,
  });

  /// "Alle aanvragen" for a manager, "Mijn aanvragen" for everyone else. The
  /// page is the same either way; only what the server returns differs.
  final String title;

  final List<SeerrRequest> requests;
  final TvSeerrRequestFilter filter;
  final ValueChanged<TvSeerrRequestFilter> onFilterChanged;

  /// Select on a card — the request's own detail page.
  final ValueChanged<SeerrRequest> onActivate;

  final bool isLoading;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final VoidCallback onReload;

  /// Null until the counts endpoint has answered. Null is drawn as no number
  /// rather than as a zero: mockup 35 D shows counts because Seerr reports them,
  /// and a zero would claim there is nothing behind a choice that has simply not
  /// been counted yet.
  final TvSeerrRequestCounts? counts;

  final String? error;

  /// UP out of the first grid row, and out of the rail.
  final VoidCallback? onExitTop;

  @override
  State<TvSeerrRequestsView> createState() => TvSeerrRequestsViewState();
}

class TvSeerrRequestsViewState extends State<TvSeerrRequestsView> {
  final _gridKey = GlobalKey<TvCatalogCardGridState>();
  final _statusFocus = FocusNode(debugLabel: 'TvSeerrRailStatus');
  final _clearFocus = FocusNode(debugLabel: 'TvSeerrRailClear');
  final _stateActionFocus = FocusNode(debugLabel: 'TvSeerrStateAction');

  bool _railExpanded = false;
  bool _statusSubview = false;
  bool _wantsEntryFocus = false;

  @override
  void didUpdateWidget(TvSeerrRequestsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_wantsEntryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryEntryFocus());
    }
  }

  @override
  void dispose() {
    _statusFocus.dispose();
    _clearFocus.dispose();
    _stateActionFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Focus traversal — the same shape as every other catalog-language page
  // ---------------------------------------------------------------------------

  void focusContent() {
    if (!mounted) return;
    _wantsEntryFocus = true;
    _tryEntryFocus();
  }

  void _tryEntryFocus() {
    if (!mounted || !_wantsEntryFocus) return;
    if (_railExpanded) {
      if (_statusFocus.canRequestFocus) {
        _wantsEntryFocus = false;
        _statusFocus.requestFocus();
      }
      return;
    }
    final grid = _gridKey.currentState;
    if (grid != null && grid.hasFocusableCard) {
      _wantsEntryFocus = false;
      grid.focusGrid();
      return;
    }
    if (!widget.isLoading) _wantsEntryFocus = false;
  }

  void _openRail() {
    if (_railExpanded) return;
    setState(() {
      _railExpanded = true;
      _statusSubview = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_railExpanded) return;
      if (_statusFocus.canRequestFocus) _statusFocus.requestFocus();
    });
  }

  void _closeRail() {
    if (!_railExpanded) return;
    setState(() {
      _railExpanded = false;
      _statusSubview = false;
    });
    final grid = _gridKey.currentState;
    if (grid != null && grid.hasFocusableCard) {
      grid.focusGrid();
      return;
    }
    // No grid to go back to. Its one action autofocused when the state was
    // mounted, but that was before the rail took the focus off it, and a page
    // focused with nothing focused on it is one the remote cannot leave.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _railExpanded) return;
      if (_stateActionFocus.canRequestFocus) _stateActionFocus.requestFocus();
    });
  }

  void _leaveRailUpwards() {
    if (_railExpanded) {
      setState(() {
        _railExpanded = false;
        _statusSubview = false;
      });
    }
    widget.onExitTop?.call();
  }

  /// DOWN off the bottom of the rail: nothing at all. Explicit, because a null
  /// handler walks sideways into the grid and leaves the rail standing open.
  void _railEdge() {}

  void _closeSubview() {
    if (!_statusSubview) return;
    setState(() => _statusSubview = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _statusSubview) return;
      if (_statusFocus.canRequestFocus) _statusFocus.requestFocus();
    });
  }

  void _pick(TvSeerrRequestFilter filter) {
    if (filter != widget.filter) widget.onFilterChanged(filter);
    _closeSubview();
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvCatalogHeaderBar(title: widget.title, tags: _railExpanded ? const [] : _tags()),
        Expanded(
          child: TvCatalogRailScaffold(
            cardHeight: _cardHeight(scale),
            rail: _railExpanded ? _buildRail(scale) : null,
            body: _buildBody(scale),
          ),
        ),
      ],
    );
  }

  /// A request card is one line taller than every other catalog card: it says
  /// who asked for it. The grid it sits in has to reserve that, or the last row
  /// loses its footer to the overscan band.
  double Function(double) _cardHeight(double scale) =>
      (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale, extraMetaLines: 1);

  double _railLeading() => TvCatalogRailScaffold.leadingFor(MediaQuery.sizeOf(context).width, expanded: _railExpanded);

  /// What the heading says the page is narrowed to.
  ///
  /// The total when nothing is filtered — mockup 35 C1's "389 aanvragen", which
  /// is the one number that says how big this list actually is — and the chosen
  /// status when something is.
  List<TvCatalogSelectionTag> _tags() {
    if (widget.filter != TvSeerrRequestFilter.all) return [TvCatalogSelectionTag(_filterLabel(widget.filter))];
    final total = widget.counts?.total;
    if (total == null) return const [];
    return [TvCatalogSelectionTag(total == 1 ? t.seerr.oneRequest : t.seerr.requestCount(count: total))];
  }

  String _filterLabel(TvSeerrRequestFilter filter) => switch (filter) {
    TvSeerrRequestFilter.all => t.seerr.filterAll,
    TvSeerrRequestFilter.pending => t.seerr.filterPending,
    TvSeerrRequestFilter.approved => t.seerr.filterApproved,
    TvSeerrRequestFilter.available => t.seerr.filterAvailable,
    TvSeerrRequestFilter.declined => t.seerr.filterDeclined,
  };

  /// The number behind one answer, or null when it is not known.
  ///
  /// Declined has no count of its own in Seerr's `/request/count` payload, so it
  /// gets none rather than a zero — the same rule the null counts follow.
  int? _countFor(TvSeerrRequestFilter filter) {
    final counts = widget.counts;
    if (counts == null) return null;
    return switch (filter) {
      TvSeerrRequestFilter.all => counts.total,
      TvSeerrRequestFilter.pending => counts.pending,
      TvSeerrRequestFilter.approved => counts.approved,
      TvSeerrRequestFilter.available => counts.available,
      TvSeerrRequestFilter.declined => null,
    };
  }

  Widget _buildRail(double scale) {
    if (_statusSubview) {
      return AutomationNode(
        id: AutomationIds.tvCatalogRail,
        instance: '$tvSeerrRequestsSurface.status',
        role: 'region',
        child: TvCatalogFilterRailSubview(
          key: tvCatalogFilterRailSubviewKey,
          scale: scale,
          title: t.seerr.railStatus,
          options: [
            for (final filter in TvSeerrRequestFilter.values)
              TvCatalogRailOption(
                label: _filterLabel(filter),
                isSelected: widget.filter == filter,
                count: _countFor(filter),
                automationInstance: '$tvSeerrRequestsSurface.status.${filter.name}',
                onPressed: () => _pick(filter),
              ),
          ],
          onBack: _closeSubview,
          onExitUp: _leaveRailUpwards,
          onExitDown: _railEdge,
          onExitRight: _closeRail,
        ),
      );
    }

    return AutomationNode(
      id: AutomationIds.tvCatalogRail,
      instance: tvSeerrRequestsSurface,
      role: 'region',
      child: TvCatalogFilterRailPanel(
        key: tvCatalogFilterRailKey,
        scale: scale,
        rows: [
          TvCatalogFilterRailRow(
            icon: Symbols.check_rounded,
            label: t.seerr.railStatus,
            value: _filterLabel(widget.filter),
            automationInstance: '$tvSeerrRequestsSurface.status',
            focusNode: _statusFocus,
            onPressed: () => setState(() => _statusSubview = true),
            onNavigateUp: _leaveRailUpwards,
            onNavigateDown: widget.filter == TvSeerrRequestFilter.all ? _railEdge : () => _clearFocus.requestFocus(),
            onNavigateLeft: _leaveRailUpwards,
            onNavigateRight: _closeRail,
            onBack: _closeRail,
          ),
        ],
        tags: _tags(),
        onClear: widget.filter == TvSeerrRequestFilter.all
            ? null
            : () {
                // Wissen is only drawn while something is filtered, so pressing
                // it removes the row the remote is standing on.
                if (_clearFocus.hasFocus) _statusFocus.requestFocus();
                widget.onFilterChanged(TvSeerrRequestFilter.all);
              },
        clearFocusNode: _clearFocus,
        onClearNavigateUp: () => _statusFocus.requestFocus(),
        onClearNavigateDown: _railEdge,
        onClearNavigateLeft: _leaveRailUpwards,
        onClearNavigateRight: _closeRail,
        onClearBack: _closeRail,
      ),
    );
  }

  Widget _buildBody(double scale) {
    if (widget.isLoading && widget.requests.isEmpty) {
      return TvCatalogSkeletonGrid(key: tvCatalogSkeletonKey, reservedLeading: _railLeading());
    }

    if (widget.requests.isEmpty) {
      final error = widget.error;
      if (error != null) {
        return _state(
          'error',
          TvCatalogEmptyState(
            icon: Symbols.cloud_off_rounded,
            title: t.seerr.errorGeneric,
            body: error,
            actionLabel: t.common.retry,
            onAction: widget.onReload,
            onActionFocusNode: _stateActionFocus,
            onActionNavigateLeft: _openRail,
          ),
        );
      }
      // A status with nothing in it is a different situation from an account
      // with no requests at all, and it needs a different way out.
      if (widget.filter != TvSeerrRequestFilter.all) {
        return _state(
          'filtered',
          TvCatalogEmptyState(
            icon: Symbols.filter_list_rounded,
            title: t.seerr.noResults,
            body: t.seerr.noRequestsInFilter(status: _filterLabel(widget.filter)),
            actionLabel: t.unifiedCatalog.states.clearFilters,
            onAction: () => widget.onFilterChanged(TvSeerrRequestFilter.all),
            onActionFocusNode: _stateActionFocus,
            onActionNavigateLeft: _openRail,
          ),
        );
      }
      return _state(
        'empty',
        TvCatalogEmptyState(
          icon: Symbols.inbox_rounded,
          title: t.seerr.noResults,
          body: t.seerr.noRequestsYet,
          actionLabel: t.common.retry,
          onAction: widget.onReload,
          onActionFocusNode: _stateActionFocus,
          onActionNavigateLeft: _openRail,
        ),
      );
    }

    return AutomationNode(
      id: AutomationIds.tvCatalogGrid,
      instance: tvSeerrRequestsSurface,
      role: 'grid',
      child: TvCatalogCardGrid(
        key: _gridKey,
        itemIds: [for (final request in widget.requests) '${request.id}'],
        cardHeight: _cardHeight(scale),
        hasMore: widget.hasMore,
        isLoadingMore: widget.isLoadingMore,
        onLoadMore: widget.onLoadMore,
        onExitTop: widget.onExitTop,
        onExitLeft: _openRail,
        reservedLeading: _railLeading(),
        nodeDebugLabel: 'TvSeerrRequestCard',
        itemBuilder: (context, cell) {
          final request = widget.requests[cell.index];
          return AutomationNode(
            id: AutomationIds.tvCatalogGridItem,
            instance: '$tvSeerrRequestsSurface.${cell.index}',
            role: 'grid.item',
            label: request.mediaTitle,
            focusNode: cell.focusNode,
            child: TvSeerrRequestCard(
              key: ValueKey(request.id),
              request: request,
              width: cell.width,
              focusNode: cell.focusNode,
              onSelect: () => widget.onActivate(request),
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

  Widget _state(String which, Widget child) => AutomationNode(
    id: AutomationIds.tvCatalogState,
    instance: '$tvSeerrRequestsSurface.$which',
    role: 'region',
    focusNode: _stateActionFocus,
    child: child,
  );
}
