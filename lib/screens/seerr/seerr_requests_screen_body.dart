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
            outlined: false,
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

  /// The Regiekamer counts (mockup C1), for a manager looking at everyone's
  /// requests: what waits on them, what is on its way, and the open reports
  /// where that page exists (otherwise everything). The numbers come from the
  /// same count route as the chips, so a tile and its chip never disagree.
  Widget _tilesRow() {
    final counts = _counts;
    int? known(int? v) => counts == null ? null : v;
    return SeerrCockpitTiles(
      tiles: [
        SeerrCockpitTile(
          instance: 'pending',
          count: known(counts?.pending),
          label: t.seerr.cockpit.tilePending,
          tone: SeerrCockpitTone.waiting,
          selected: _filter == TvSeerrRequestFilter.pending,
          onTap: () => _onTile(TvSeerrRequestFilter.pending),
        ),
        SeerrCockpitTile(
          instance: 'approved',
          count: known(counts?.approved),
          label: t.seerr.cockpit.tileInProgress,
          selected: _filter == TvSeerrRequestFilter.approved,
          onTap: () => _onTile(TvSeerrRequestFilter.approved),
        ),
        if (_issuesReachable)
          SeerrCockpitTile(
            instance: 'issues',
            count: _issueCounts?.open,
            label: t.seerr.cockpit.tileIssues,
            onTap: _openIssues,
          )
        else
          SeerrCockpitTile(
            instance: 'all',
            count: known(counts?.total),
            label: t.seerr.allRequests,
            selected: _filter == TvSeerrRequestFilter.all,
            onTap: () => _onFilter(TvSeerrRequestFilter.all),
          ),
      ],
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
          outlined: false,
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

  /// The chip says which status; the number lives in the tile above it.
  /// Showing it twice, a hand-width apart, was noise.
  String _chipLabel(TvSeerrRequestFilter filter, bool ownOnly) => seerrRequestFilterLabel(filter);

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
    final provider = context.read<SeerrProvider>();
    final manages = provider.canManageRequests && !_ownOnly(provider);
    final slivers = <Widget>[];
    var index = 0;
    final groups = _groups(manages);
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      if (group.title != null) slivers.add(SliverToBoxAdapter(child: _sectionHeader(group)));
      final first = index;
      final rows = group.items;
      // The tile that starts the next page is the last item of the last list,
      // never a sliver of its own: a list always builds its first child, in
      // view or not, and a tile that is built asks for a page.
      final tail = showLoadMore && g == groups.length - 1;
      slivers.add(
        SliverList.builder(
          itemCount: rows.length + (tail ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == rows.length) {
              return SeerrAutoLoadMoreListTile(
                // A new tile for every page: it asks for the next page when it
                // is first built, so the same element would ask once and wait.
                key: ValueKey('seerr-load-more-$_page'),
                loading: _loadingMore,
                failed: _loadMoreFailed,
                onLoadMore: () => unawaited(_load()),
              );
            }
            return Padding(
              padding: EdgeInsets.only(top: i == 0 && group.title == null ? 8 : 0),
              child: _row(rows[i], first + i, first: i == 0, last: i == rows.length - 1),
            );
          },
        ),
      );
      if (group.hint != null) slivers.add(SliverToBoxAdapter(child: _hint(group.hint!)));
      index += rows.length;
    }
    return slivers;
  }

  /// The loaded rows in the Regiekamer order. Under Alle the list is split by
  /// what it asks of the viewer: decisions first, oldest first (the one that
  /// has waited longest is the one to take), then what is on its way, then
  /// what is done. A chosen filter is one group without a heading: the viewer
  /// already said what they are looking at.
  ///
  /// The request the page was opened for stays first, as before.
  List<_RequestGroup> _groups(bool manages) {
    if (_filter != TvSeerrRequestFilter.all) return [_RequestGroup(null, _items)];
    final chosen = [
      for (final r in _items)
        if (r.id == _chosenId) r,
    ];
    final rest = [
      for (final r in _items)
        if (r.id != _chosenId) r,
    ];
    final waiting = [
      for (final r in rest)
        if (r.statusKnown && r.isPending) r,
    ]..sort(_oldestFirst);
    final moving = [
      for (final r in rest)
        if (r.statusKnown && r.status == SeerrRequestStatus.approved && !r.isFulfilled) r,
    ];
    final done = [
      for (final r in rest)
        if (!waiting.contains(r) && !moving.contains(r)) r,
    ];
    final canDecide = manages && waiting.any((r) => _rightsFor(r).canApprove);
    return [
      if (chosen.isNotEmpty) _RequestGroup(null, chosen),
      if (waiting.isNotEmpty)
        _RequestGroup(
          manages ? t.seerr.cockpit.waitingOnYou : t.seerr.cockpit.waitingForApproval,
          waiting,
          note: t.seerr.cockpit.oldestFirst,
          bulk: canDecide,
          hint: canDecide ? t.seerr.cockpit.swipeHint : null,
        ),
      if (moving.isNotEmpty) _RequestGroup(t.seerr.cockpit.inProgress, moving),
      if (done.isNotEmpty) _RequestGroup(t.seerr.cockpit.handled, done),
    ];
  }

  static int _oldestFirst(SeerrRequest a, SeerrRequest b) {
    final x = a.createdAt == null ? null : DateTime.tryParse(a.createdAt!);
    final y = b.createdAt == null ? null : DateTime.tryParse(b.createdAt!);
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  Widget _sectionHeader(_RequestGroup group) {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final ticked = group.bulk ? _selectedApprovable.length : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_SeerrRequestsScreenState._hInset, 16, _SeerrRequestsScreenState._hInset, 8),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            // The heading keeps its words; the note beside it gives way first.
            Flexible(
              flex: 3,
              child: Text(
                group.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            if (group.note != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  group.note!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted),
                ),
              ),
            ],
            const Spacer(),
            if (ticked > 0)
              AutomationNode(
                id: AutomationIds.requestsListBulkApprove,
                role: 'button',
                state: () => {'count': ticked},
                child: FocusableButton(
                  onPressed: () => unawaited(_approveSelected()),
                  child: FilledButton.icon(
                    onPressed: () => unawaited(_approveSelected()),
                    icon: const Icon(Symbols.check_rounded, size: 16),
                    label: Text(t.seerr.cockpit.approveSelected(n: ticked)),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: tk.text,
                      foregroundColor: tk.bg,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) {
    final tk = tokens(context);
    final quiet = tk.textMuted.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_SeerrRequestsScreenState._hInset, 8, _SeerrRequestsScreenState._hInset, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Symbols.swipe_rounded, size: 14, color: quiet),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: quiet),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(SeerrRequest req, int index, {required bool first, required bool last}) {
    final rights = _rightsFor(req);
    final busy = _busy.contains(req.id);
    final unresolved = _unresolved.contains(req.id);
    final provider = context.read<SeerrProvider>();
    final selectable = provider.canManageRequests && !_ownOnly(provider) && rights.canApprove;
    return AutomationNode(
      id: AutomationIds.requestsListItem,
      instance: '$index',
      role: 'list.item',
      label: req.mediaTitle,
      state: () => {'request': req.id, 'status': req.status.name, 'busy': busy, 'unresolved': unresolved},
      child: SeerrRequestRow(
        // The same key and node for as long as this is the chosen request,
        // not only until it has been landed on: a row that swaps them on the
        // next rebuild is a new row, and the focus that was on the old one is
        // nowhere.
        key: req.id == _chosenId ? _focusTargetKey : null,
        focusNode: req.id == _chosenId ? _focusTargetNode : null,
        request: req,
        automationInstance: '$index',
        busy: busy,
        statusUnknown: unresolved,
        groupFirst: first,
        groupLast: last,
        selected: selectable ? _selected.contains(req.id) : null,
        onSelectedChanged: selectable ? (on) => _toggleSelected(req, on) : null,
        onOpen: () => _openDetail(req),
        onApprove: rights.canApprove ? () => _approve(req) : null,
        onDecline: rights.canDecline ? () => _decline(req) : null,
        onSwipeDecline: rights.canDecline ? () => unawaited(_swipeDecline(req)) : null,
        onEdit: rights.canEdit ? () => unawaited(_edit(req)) : null,
        onCancel: rights.canCancel ? () => unawaited(_cancel(req)) : null,
        onMore: () => unawaited(_openActions(req)),
      ),
    );
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

/// One section of the Regiekamer list.
class _RequestGroup {
  const _RequestGroup(this.title, this.items, {this.note, this.bulk = false, this.hint});

  final String? title;
  final List<SeerrRequest> items;
  final String? note;

  /// Whether the section offers one Goedkeuren for every ticked row.
  final bool bulk;
  final String? hint;
}
