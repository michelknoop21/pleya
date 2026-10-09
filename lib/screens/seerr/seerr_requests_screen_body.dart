part of 'seerr_requests_screen.dart';

/// The list as it is drawn off TV: the status chips, the rows, and what stands
/// in their place when there are none.
extension _SeerrRequestsBody on _SeerrRequestsScreenState {
  /// A manager's choice between everyone's requests and their own. Built only
  /// for a manager; nobody else has a second scope.
  Widget _scopeRow(bool ownOnly) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // Scrolls sideways like the status chips under it: the two labels do not
      // fit a phone in every language.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _SeerrRequestsScreenState._hInset),
        child: AutomationNode(
          id: AutomationIds.requestsListState,
          instance: 'scope',
          role: 'region',
          state: () => {'own': ownOnly},
          child: SegmentedTabGroup(
            children: [
              AutomationNode(
                id: AutomationIds.requestsListScope,
                instance: 'all',
                role: 'button',
                state: () => {'selected': !ownOnly},
                child: FocusableTabChip(
                  style: TabChipStyle.segmented,
                  label: t.seerr.allRequests,
                  isSelected: !ownOnly,
                  onSelect: () => _setScope(false),
                ),
              ),
              const SizedBox(width: 2),
              AutomationNode(
                id: AutomationIds.requestsListScope,
                instance: 'own',
                role: 'button',
                state: () => {'selected': ownOnly},
                child: FocusableTabChip(
                  style: TabChipStyle.segmented,
                  label: t.seerr.myRequests,
                  isSelected: ownOnly,
                  onSelect: () => _setScope(true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterRow(bool ownOnly) {
    const filters = [
      TvSeerrRequestFilter.all,
      TvSeerrRequestFilter.pending,
      TvSeerrRequestFilter.approved,
      TvSeerrRequestFilter.available,
      TvSeerrRequestFilter.declined,
    ];
    final chips = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: SingleChildScrollView(
        controller: _filterScrollController,
        scrollDirection: Axis.horizontal,
        // Inset lives on the scroll view, not around it: as padding around the
        // scrollport it is outside the scrollable area, so the first and last
        // chip ended up hard against the viewport edge the moment the strip was
        // dragged. Here it scrolls with the content and stays a real margin.
        padding: const EdgeInsets.symmetric(horizontal: _SeerrRequestsScreenState._hInset),
        child: SegmentedTabGroup(
          children: [
            for (var i = 0; i < filters.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              FocusableTabChip(
                key: _filterChipKeys[filters[i].wire],
                style: TabChipStyle.segmented,
                label: _chipLabel(filters[i], ownOnly),
                isSelected: _filter == filters[i],
                onSelect: () => _onFilter(filters[i]),
              ),
            ],
          ],
        ),
      ),
    );
    if (!ownOnly) return chips;
    // The chips carry no numbers on the viewer's own list, and this says why,
    // so missing counts do not read as counts that failed to load.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        chips,
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _SeerrRequestsScreenState._hInset,
            0,
            _SeerrRequestsScreenState._hInset,
            4,
          ),
          child: Text(
            t.seerr.countsOwnScopeNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
          ),
        ),
      ],
    );
  }

  /// A known count as a number (zero included: it was counted), a count that
  /// failed to load as a dash, and no suffix where none can be proven.
  String _chipLabel(TvSeerrRequestFilter filter, bool ownOnly) {
    final label = seerrRequestFilterLabel(filter);
    // No number where none can belong to the same set: the count route's
    // "available" is not the list's, and it has no declined figure the list
    // could ever show rows for.
    if (ownOnly || filter == TvSeerrRequestFilter.available || filter == TvSeerrRequestFilter.declined) return label;
    final count = _countFor(filter);
    if (count != null) return '$label  $count';
    return _countsFailed ? '$label  –' : label;
  }

  List<Widget> _contentSlivers() {
    if (_loading && _items.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_ownScopeUnknown) {
      return [_state('error', StateView.error(title: t.seerr.ownScopeUnknown, icon: Symbols.person_off_rounded))];
    }
    if (_filterUnsupported) {
      return [
        _state(
          'unsupported',
          StateView.empty(
            title: t.seerr.filterUnsupportedTitle(status: seerrRequestFilterLabel(_filter)),
            message: _unsupportedBody,
            icon: Symbols.filter_list_off_rounded,
            onRetry: () => _onFilter(TvSeerrRequestFilter.all),
            retryLabel: t.unifiedCatalog.states.clearFilters,
          ),
        ),
      ];
    }
    if (_error != null && _items.isEmpty) {
      return [
        _state(
          'error',
          StateView.error(title: _error, icon: Symbols.cloud_off_rounded, onRetry: _reload, retryLabel: t.common.retry),
        ),
      ];
    }
    if (_items.isEmpty) {
      // An empty list is not a failure, so neither way out is "try again": a
      // filter is cleared, and an account without requests goes to Ontdekken.
      final filtered = _filter != TvSeerrRequestFilter.all;
      return [
        _state(
          filtered ? 'filtered' : 'empty',
          filtered
              ? StateView.empty(
                  title: t.seerr.noRequestsInFilter(status: seerrRequestFilterLabel(_filter)),
                  icon: Symbols.filter_list_rounded,
                  onRetry: () => _onFilter(TvSeerrRequestFilter.all),
                  retryLabel: t.unifiedCatalog.states.clearFilters,
                )
              : StateView.empty(
                  title: _ownOnly(context.read<SeerrProvider>()) ? t.seerr.noOwnRequestsYet : t.seerr.noRequestsYet,
                  onRetry: _openDiscover,
                  retryLabel: t.seerr.discoverAction,
                ),
        ),
      ];
    }

    final showLoadMore = _hasMore && !_loading;
    return [
      SliverList.builder(
        itemCount: _items.length + (showLoadMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return SeerrAutoLoadMoreListTile(
              loading: _loadingMore,
              failed: _loadMoreFailed,
              onLoadMore: () => unawaited(_load()),
            );
          }
          final req = _items[index];
          final rights = _rightsFor(req);
          final busy = _busy.contains(req.id);
          final unresolved = _unresolved.contains(req.id);
          return AutomationNode(
            id: AutomationIds.requestsListItem,
            instance: '$index',
            role: 'list.item',
            label: req.mediaTitle,
            state: () => {'request': req.id, 'status': req.status.name, 'busy': busy, 'unresolved': unresolved},
            child: SeerrRequestRow(
              // The same key and node for as long as this is the chosen
              // request, not only until it has been landed on: a row that
              // swaps them on the next rebuild is a new row, and the focus
              // that was on the old one is nowhere.
              key: req.id == _chosenId ? _focusTargetKey : null,
              focusNode: req.id == _chosenId ? _focusTargetNode : null,
              request: req,
              automationInstance: '$index',
              busy: busy,
              statusUnknown: unresolved,
              onOpen: () => _openDetail(req),
              onApprove: rights.canApprove ? () => _approve(req) : null,
              onDecline: rights.canDecline ? () => _decline(req) : null,
              onEdit: rights.canEdit ? () => unawaited(_edit(req)) : null,
              onCancel: rights.canCancel ? () => unawaited(_cancel(req)) : null,
              onMore: () => unawaited(_openActions(req)),
            ),
          );
        },
      ),
    ];
  }

  Widget _state(String which, Widget child) => SliverToBoxAdapter(
    child: AutomationNode(
      id: AutomationIds.requestsListState,
      instance: which,
      role: 'region',
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: child),
    ),
  );
}
