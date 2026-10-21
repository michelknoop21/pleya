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
import '../../widgets/tv/tv_view_all_action.dart';

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

/// What the counts beside the status answers can be about.
enum TvSeerrCountsScope {
  /// Every request, the same set the list shows: numbers where known.
  all,

  /// The viewer's own list. Seerr counts everyone's, so no numbers and a line
  /// that says why.
  own,

  /// Every request, but the count did not come: a dash, never a zero.
  failed,
}

String seerrRequestFilterLabel(TvSeerrRequestFilter filter) => switch (filter) {
  TvSeerrRequestFilter.all => t.seerr.filterAll,
  TvSeerrRequestFilter.pending => t.seerr.filterPending,
  TvSeerrRequestFilter.approved => t.seerr.filterApproved,
  TvSeerrRequestFilter.available => t.seerr.filterAvailable,
  TvSeerrRequestFilter.declined => t.seerr.filterDeclined,
};

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
    this.onContextMenu,
    this.onDiscover,
    this.busyIds = const {},
    this.unresolvedIds = const {},
    this.filterUnsupportedBody,
    this.loadMoreFailed = false,
    this.countFor,
    this.countsScope = TvSeerrCountsScope.all,
    this.filterUnsupported = false,
    this.ownScope = false,
    this.onScopeChanged,
    this.initialFocusedId,
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

  /// Long press on a card: the menu with what this request allows. Null
  /// leaves the card without one.
  final ValueChanged<SeerrRequest>? onContextMenu;

  /// The way out of an account with no requests at all: Ontdekken.
  final VoidCallback? onDiscover;

  /// Requests with an action on the wire. Their card says so and offers no
  /// second action until the first has an answer.
  final Set<int> busyIds;

  /// The subset of [busyIds] whose outcome is open. Their menu callback still
  /// fires: the owner answers it by reading the request again.
  final Set<int> unresolvedIds;

  /// Why the chosen status has no list. Null uses the "answered with other
  /// rows" wording.
  final String? filterUnsupportedBody;

  /// The last page request failed. The loaded cards stay, and a tile under
  /// them offers the retry instead of the grid asking again by itself.
  final bool loadMoreFailed;

  /// The number behind one status, or null when it is not known. Null is drawn
  /// as no number rather than as a zero: a zero would claim there is nothing
  /// behind a choice that has simply not been counted.
  final int? Function(TvSeerrRequestFilter filter)? countFor;

  final TvSeerrCountsScope countsScope;

  /// The server answered the chosen status with requests of another one.
  final bool filterUnsupported;

  /// The list is the viewer's own, which changes what an empty one says.
  final bool ownScope;

  /// A manager's choice between everyone's requests and their own (true is
  /// own). Null for a viewer who has no such choice: the rail then has no
  /// Bereik row at all, so there is nothing to select that the server would
  /// refuse.
  final ValueChanged<bool>? onScopeChanged;

  /// The request the page was opened for, as a card id. The grid opens with
  /// the focus on it instead of on the first card.
  final String? initialFocusedId;

  final String? error;

  /// UP out of the first grid row, and out of the rail.
  final VoidCallback? onExitTop;

  @override
  State<TvSeerrRequestsView> createState() => TvSeerrRequestsViewState();
}

class TvSeerrRequestsViewState extends State<TvSeerrRequestsView> {
  final _gridKey = GlobalKey<TvCatalogCardGridState>();
  final _statusFocus = FocusNode(debugLabel: 'TvSeerrRailStatus');
  final _scopeFocus = FocusNode(debugLabel: 'TvSeerrRailScope');
  final _clearFocus = FocusNode(debugLabel: 'TvSeerrRailClear');
  final _stateActionFocus = FocusNode(debugLabel: 'TvSeerrStateAction');
  final _loadMoreRetryFocus = FocusNode(debugLabel: 'TvSeerrLoadMoreRetry');

  bool _railExpanded = false;
  bool _statusSubview = false;
  bool _scopeSubview = false;
  bool _wantsEntryFocus = false;

  @override
  void didUpdateWidget(TvSeerrRequestsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The manage right went away under an open Bereik subview (a profile
    // switch). The rail falls back to its rows, without the Bereik row, and the
    // option that held the focus is gone with the subview. Left set, the flag
    // would send the next close to that unmounted row and the remote nowhere.
    if (_scopeSubview && widget.onScopeChanged == null) {
      _scopeSubview = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_railExpanded || _statusSubview || _scopeSubview) return;
        if (_statusFocus.canRequestFocus) _statusFocus.requestFocus();
      });
    }
    if (_wantsEntryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryEntryFocus());
    }
  }

  @override
  void dispose() {
    _statusFocus.dispose();
    _scopeFocus.dispose();
    _clearFocus.dispose();
    _stateActionFocus.dispose();
    _loadMoreRetryFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Focus traversal — the same shape as every other catalog-language page
  // ---------------------------------------------------------------------------

  /// Puts the focus on one request's card, when it is on the page.
  void focusRequest(int id) {
    if (!mounted || _railExpanded) return;
    _wantsEntryFocus = false;
    _gridKey.currentState?.focusItem('$id');
  }

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

  /// CAT17: an already open rail takes the focus instead of returning. A rail
  /// standing open with the ring on a card is a page the remote cannot leave,
  /// because this is the only LEFT a card offers.
  ///
  /// A rail showing a subview is the case that has to go through
  /// [_closeSubview] rather than straight at the row: the parent rows are not
  /// mounted while the subview stands in for them, and `requestFocus` on an
  /// unattached node reports `canRequestFocus` true and then does nothing at
  /// all, which would leave the remote exactly as stuck as before. With no
  /// subview the nodes are attached, and the request has to be synchronous
  /// because without a `setState` nothing schedules the frame a post-frame
  /// callback would wait for.
  void _openRail() {
    if (_railExpanded) {
      if (_statusSubview || _scopeSubview) {
        _closeSubview();
      } else if (_statusFocus.canRequestFocus) {
        _statusFocus.requestFocus();
      }
      return;
    }
    setState(() {
      _railExpanded = true;
      _statusSubview = false;
      _scopeSubview = false;
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
      _scopeSubview = false;
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

  /// UP out of the rail: the topnav, with the rail closed behind it.
  ///
  /// LEFT used to fall through here too, until CAT19 (Michel, 13 September):
  /// the rail is the leftmost content on the page, so a second LEFT reached the
  /// topnav and a third one walked sideways along the bar to a different
  /// destination. LEFT out of a rail row is [_railEdge] now.
  void _leaveRailUpwards() {
    if (_railExpanded) {
      setState(() {
        _railExpanded = false;
        _statusSubview = false;
        _scopeSubview = false;
      });
    }
    widget.onExitTop?.call();
  }

  /// LEFT and DOWN off an edge of the rail: nothing at all. Explicit, because a
  /// null handler walks sideways into the grid and leaves the rail standing
  /// open.
  void _railEdge() {}

  void _closeSubview() {
    if (!_statusSubview && !_scopeSubview) return;
    // Back to the row the subview was opened from, so choosing a scope does
    // not leave the remote on Status or the other way round.
    final row = _scopeSubview ? _scopeFocus : _statusFocus;
    setState(() {
      _statusSubview = false;
      _scopeSubview = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _statusSubview || _scopeSubview) return;
      if (row.canRequestFocus) row.requestFocus();
    });
  }

  void _pickScope(bool own) {
    if (own != widget.ownScope) widget.onScopeChanged?.call(own);
    _closeSubview();
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
    final total = _countFor(TvSeerrRequestFilter.all);
    if (total == null) return const [];
    return [TvCatalogSelectionTag(total == 1 ? t.seerr.oneRequest : t.seerr.requestCount(count: total))];
  }

  String _filterLabel(TvSeerrRequestFilter filter) => seerrRequestFilterLabel(filter);

  /// The number behind one answer, or null when it is not known. Never one
  /// beside the viewer's own list: the count route counts everyone's.
  int? _countFor(TvSeerrRequestFilter filter) =>
      widget.countsScope == TvSeerrCountsScope.all ? widget.countFor?.call(filter) : null;

  Widget _buildRail(double scale) {
    final onScopeChanged = widget.onScopeChanged;
    if (_scopeSubview && onScopeChanged != null) {
      return AutomationNode(
        id: AutomationIds.tvCatalogRail,
        instance: '$tvSeerrRequestsSurface.scope',
        role: 'region',
        child: TvCatalogFilterRailSubview(
          key: tvCatalogFilterRailSubviewKey,
          scale: scale,
          title: t.seerr.railScope,
          options: [
            TvCatalogRailOption(
              label: t.seerr.allRequests,
              isSelected: !widget.ownScope,
              automationInstance: '$tvSeerrRequestsSurface.scope.all',
              onPressed: () => _pickScope(false),
            ),
            TvCatalogRailOption(
              label: t.seerr.myRequests,
              isSelected: widget.ownScope,
              automationInstance: '$tvSeerrRequestsSurface.scope.own',
              onPressed: () => _pickScope(true),
            ),
          ],
          onBack: _closeSubview,
          onExitUp: _leaveRailUpwards,
          onExitDown: _railEdge,
          onExitRight: _closeRail,
        ),
      );
    }
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
                countUnavailable: widget.countsScope == TvSeerrCountsScope.failed,
                automationInstance: '$tvSeerrRequestsSurface.status.${filter.name}',
                onPressed: () => _pick(filter),
              ),
          ],
          onBack: _closeSubview,
          onExitUp: _leaveRailUpwards,
          onExitDown: _railEdge,
          onExitRight: _closeRail,
          note: switch (widget.countsScope) {
            TvSeerrCountsScope.own => t.seerr.countsOwnScopeNote,
            TvSeerrCountsScope.failed => t.seerr.countsNotLoaded,
            TvSeerrCountsScope.all => null,
          },
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
          if (onScopeChanged != null)
            TvCatalogFilterRailRow(
              icon: Symbols.group_rounded,
              label: t.seerr.railScope,
              value: widget.ownScope ? t.seerr.myRequests : t.seerr.allRequests,
              automationInstance: '$tvSeerrRequestsSurface.scope',
              focusNode: _scopeFocus,
              onPressed: () => setState(() => _scopeSubview = true),
              onNavigateUp: _leaveRailUpwards,
              onNavigateDown: () => _statusFocus.requestFocus(),
              onNavigateLeft: _railEdge,
              onNavigateRight: _closeRail,
              onBack: _closeRail,
            ),
          TvCatalogFilterRailRow(
            icon: Symbols.check_rounded,
            label: t.seerr.railStatus,
            value: _filterLabel(widget.filter),
            automationInstance: '$tvSeerrRequestsSurface.status',
            focusNode: _statusFocus,
            onPressed: () => setState(() => _statusSubview = true),
            onNavigateUp: onScopeChanged == null ? _leaveRailUpwards : () => _scopeFocus.requestFocus(),
            onNavigateDown: widget.filter == TvSeerrRequestFilter.all ? _railEdge : () => _clearFocus.requestFocus(),
            onNavigateLeft: _railEdge,
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
        onClearNavigateLeft: _railEdge,
        onClearNavigateRight: _closeRail,
        onClearBack: _closeRail,
      ),
    );
  }

  Widget _buildBody(double scale) {
    if (widget.isLoading && widget.requests.isEmpty) {
      return TvCatalogSkeletonGrid(key: tvCatalogSkeletonKey, reservedLeading: _railLeading());
    }

    if (widget.filterUnsupported) {
      return _state(
        'unsupported',
        TvCatalogEmptyState(
          icon: Symbols.filter_list_off_rounded,
          title: t.seerr.filterUnsupportedTitle(status: _filterLabel(widget.filter)),
          body: widget.filterUnsupportedBody ?? t.seerr.filterUnsupportedBody,
          actionLabel: t.unifiedCatalog.states.clearFilters,
          onAction: () => widget.onFilterChanged(TvSeerrRequestFilter.all),
          onActionFocusNode: _stateActionFocus,
          onActionNavigateLeft: _openRail,
        ),
      );
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
      // TVUX-36: an empty list loaded fine, so asking again is not a way out.
      // Ontdekken is where a first request starts.
      final onDiscover = widget.onDiscover;
      return _state(
        'empty',
        TvCatalogEmptyState(
          icon: Symbols.inbox_rounded,
          title: t.seerr.noResults,
          body: widget.ownScope ? t.seerr.noOwnRequestsYet : t.seerr.noRequestsYet,
          actionLabel: onDiscover == null ? t.common.retry : t.seerr.discoverAction,
          onAction: onDiscover ?? widget.onReload,
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
        initialFocusedId: widget.initialFocusedId,
        cardHeight: _cardHeight(scale),
        // A failed page stops the grid asking by itself. The tile under the
        // last row is the retry, so the failure cannot loop.
        hasMore: widget.hasMore && !widget.loadMoreFailed,
        isLoadingMore: widget.isLoadingMore,
        onLoadMore: widget.onLoadMore,
        onExitTop: widget.onExitTop,
        onExitLeft: _openRail,
        reservedLeading: _railLeading(),
        footer: widget.loadMoreFailed ? _loadMoreFailedTile() : null,
        nodeDebugLabel: 'TvSeerrRequestCard',
        itemBuilder: (context, cell) {
          final request = widget.requests[cell.index];
          final busy = widget.busyIds.contains(request.id);
          final unresolved = widget.unresolvedIds.contains(request.id);
          final onContextMenu = widget.onContextMenu;
          return AutomationNode(
            id: AutomationIds.tvCatalogGridItem,
            instance: '$tvSeerrRequestsSurface.${cell.index}',
            role: 'grid.item',
            label: request.mediaTitle,
            focusNode: cell.focusNode,
            state: () => {'request': request.id, 'status': request.status.name, 'busy': busy, 'unresolved': unresolved},
            child: TvSeerrRequestCard(
              key: ValueKey(request.id),
              request: request,
              width: cell.width,
              focusNode: cell.focusNode,
              busy: busy,
              statusUnknown: unresolved,
              onSelect: () => widget.onActivate(request),
              onContextMenu: onContextMenu == null || (busy && !unresolved) ? null : () => onContextMenu(request),
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

  /// The page that did not come, as one action under the loaded cards.
  Widget _loadMoreFailedTile() => AutomationNode(
    id: AutomationIds.tvCatalogState,
    instance: '$tvSeerrRequestsSurface.load_more_failed',
    role: 'region',
    focusNode: _loadMoreRetryFocus,
    child: Align(
      alignment: Alignment.centerLeft,
      child: TvViewAllAction(
        label: '${t.seerr.loadMoreFailed} · ${t.common.retry}',
        semanticLabel: '${t.seerr.loadMoreFailed}, ${t.common.retry}',
        focusNode: _loadMoreRetryFocus,
        onSelect: widget.onLoadMore,
        onNavigateUp: () => _gridKey.currentState?.focusGrid(),
      ),
    ),
  );

  Widget _state(String which, Widget child) => AutomationNode(
    id: AutomationIds.tvCatalogState,
    instance: '$tvSeerrRequestsSurface.$which',
    role: 'region',
    focusNode: _stateActionFocus,
    child: child,
  );
}
