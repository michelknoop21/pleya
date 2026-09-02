/// The Films and Series page, in one widget (hoofdstuk 10 of
/// docs/tvos-unified-experience.md).
///
/// One screen for both catalogs, because they differ in exactly two things a
/// parameter can carry: which [MediaKind] they browse and what the heading
/// says. Everything else — the header actions, the grid, paging, the four
/// content states, activation, persisted preferences — is identical by
/// contract, and two copies of it would drift within a phase.
///
/// ## What this screen decides, and what it deliberately does not
///
/// It owns presentation, focus traversal and the query it asks for. It owns
/// **no** source logic: pressing Select hands the whole [UnifiedMediaGroup] to
/// `activateUnifiedMediaGroup`, which is the one place hoofdstuk 4.4 allows a
/// concrete `serverId:itemId` to be chosen. There is no representative-source
/// shortcut here, no ranking, and no second picker.
///
/// It also owns no merge logic. `UnifiedCatalogProvider` is handed in already
/// built and profile-scoped (see `UnifiedCatalogs`), so switching between the
/// two pages returns to a live merge with its pages and its scroll position
/// intact rather than restarting one.
///
/// ## The three states the header can be in
///
/// Hoofdstuk 7.4 fixes the traversal: topnav → header actions → grid, and back
/// up. On the current root shell "topnav" is the sidebar, which fase 7 replaces
/// without changing anything here. UP from the first grid row returns to the
/// header action the user last used — not always the first one, which is the
/// fase-5A interaction fix this page and Bibliotheken share.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_route_context.dart';
import '../../mixins/refreshable.dart';
import '../../navigation/main_screen_scope.dart';
import '../../navigation/tv/tv_navigation_coordinator.dart';
import 'tv_root_shell.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/offline_mode_provider.dart';
import '../../providers/unified_catalog_provider.dart';
import '../../services/api_cache.dart';
import '../../services/unified_catalog/source_resolver.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_catalog_query_store.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/library_header_bar.dart';
import '../../widgets/tv/tv_catalog_filter_panel.dart';
import '../../widgets/tv/tv_catalog_header_bar.dart';
import '../../widgets/tv/tv_panel_primitives.dart';
import '../../widgets/tv/tv_catalog_sort_panel.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_unified_media_card.dart';
import '../../widgets/tv/tv_unified_media_grid.dart';
import 'tv_media_source_picker_route.dart';
import 'tv_unified_activation.dart';
import 'tv_unified_context_menu.dart';

/// Which header action UP from the grid returns to (hoofdstuk 7.4 read
/// together with 7.6's focus memory).
enum _HeaderSlot { sources, filters, sort }

/// How many frames [_TvUnifiedCatalogScreenState._scheduleRestore] waits for a
/// scrollable to exist before giving up.
const int _restoreAttempts = 8;

class TvUnifiedCatalogScreen extends StatefulWidget {
  const TvUnifiedCatalogScreen({
    super.key,
    required this.catalog,
    required this.title,
    this.onManageServers,
    this.restoreFrom = TvDestinationFocusMemory.empty,
    this.onRemember,
  });

  /// Built and owned by `UnifiedCatalogs` in the profile subtree, never here:
  /// a screen-local catalog would restart its merge on every tab switch.
  final UnifiedCatalogProvider catalog;

  final String title;

  /// Hoofdstuk 14.7's "Servers beheren", handed down from the root shell
  /// because only it can change tab.
  final VoidCallback? onManageServers;

  /// Where this page was left last time (hoofdstuk 7.6).
  ///
  /// This screen is the one TV surface that genuinely cannot keep its own
  /// place: on the fase-7 shell it is a `TvNestedRoute`, so switching to
  /// another destination and back builds it again from nothing while every
  /// destination *root* stays mounted in the `IndexedStack`. So the place lives
  /// one level up, in `TvNavigationCoordinator`, and is handed in here.
  ///
  /// Empty on a standalone mount (a golden, a focus test) and on the very first
  /// visit, which is simply "start at the top".
  final TvDestinationFocusMemory restoreFrom;

  /// Reports the place back, so the next mount can be handed it.
  ///
  /// Called on teardown rather than on every scroll notification: the value is
  /// only ever read by the next build of this screen, so writing it once per
  /// visit is enough and a per-frame write would be noise on the hot path.
  final ValueChanged<TvDestinationFocusMemory>? onRemember;

  @override
  State<TvUnifiedCatalogScreen> createState() => _TvUnifiedCatalogScreenState();
}

class _TvUnifiedCatalogScreenState extends State<TvUnifiedCatalogScreen> implements FocusableTab {
  final _gridKey = GlobalKey<TvUnifiedMediaGridState>();
  final _scrollController = ScrollController();
  final _sourcesFocus = FocusNode(debugLabel: 'TvCatalogSourcesAction');
  final _filtersFocus = FocusNode(debugLabel: 'TvCatalogFiltersAction');
  final _sortFocus = FocusNode(debugLabel: 'TvCatalogSortAction');

  /// The user's stored setup. Kept whole: what is *applied* is this constrained
  /// to the live capabilities, which change with the source restriction.
  UnifiedCatalogPreferences _preferences = UnifiedCatalogPreferences.defaults;
  bool _preferencesLoaded = false;

  /// Hoofdstuk 7.6: UP from the grid returns to the action the user last
  /// operated, so a second visit to Filters does not start at Sources again.
  _HeaderSlot _lastUsedSlot = _HeaderSlot.filters;

  /// The card the remote is on, by stable `groupId` — mirrored out of the grid
  /// so it can be handed on after the grid itself is gone.
  String? _focusedGroupId;

  /// The scroll offset, mirrored off the controller for the same reason: by the
  /// time [deactivate] runs the viewport may already be detached, and reading
  /// `offset` then throws.
  double _scrollOffset = 0;

  /// The place still to be applied to this mount, cleared once it has been.
  /// Non-null only between [initState] and the first frame that has both the
  /// grid and its viewport, which is at least one frame away: the stored
  /// preferences are read asynchronously and the skeleton stands in until they
  /// land.
  TvDestinationFocusMemory? _pendingRestore;

  SourceAllResolver? _resolver;
  String? _resolverProfileId;

  @override
  void initState() {
    super.initState();
    widget.catalog.addListener(_onCatalogChanged);
    _scrollController.addListener(_rememberScrollOffset);
    final place = widget.restoreFrom;
    _focusedGroupId = place.groupId;
    if (place.focusedElementId case final String slot) {
      _lastUsedSlot = _HeaderSlot.values.firstWhere((s) => s.name == slot, orElse: () => _lastUsedSlot);
    }
    if (!place.isEmpty) _pendingRestore = place;
    unawaited(_restorePreferences());
  }

  /// Hands the place up before the element goes away.
  ///
  /// `deactivate` rather than `dispose`: it runs while this subtree is still
  /// attached, and it is the one callback guaranteed to run on the teardown a
  /// destination switch causes.
  @override
  void deactivate() {
    widget.onRemember?.call(
      TvDestinationFocusMemory(
        focusedElementId: _lastUsedSlot.name,
        groupId: _focusedGroupId,
        scrollOffset: _scrollOffset,
      ),
    );
    super.deactivate();
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_onCatalogChanged);
    _scrollController.removeListener(_rememberScrollOffset);
    _scrollController.dispose();
    _sourcesFocus.dispose();
    _filtersFocus.dispose();
    _sortFocus.dispose();
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
    _scheduleRestore();
  }

  void _rememberScrollOffset() {
    if (_scrollController.hasClients) _scrollOffset = _scrollController.offset;
  }

  /// Puts the viewer back where they were, once there is something to put them
  /// back on.
  ///
  /// The grid is only built after the stored preferences have loaded *and* the
  /// merge has yielded its first groups, so this cannot run in [initState]; it
  /// is retried on every catalog change until it succeeds, and then never
  /// again. The card itself needs no work here — the grid is handed the same
  /// `groupId` as [TvUnifiedMediaGrid.initialFocusedGroupId], so DOWN out of
  /// the header already lands on it.
  void _scheduleRestore({int attempt = 0}) {
    if (_pendingRestore == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final place = _pendingRestore;
      if (!mounted || place == null) return;
      if (!_scrollController.hasClients) {
        // The grid is not on screen yet — the skeleton is. A handful of frames
        // rather than an open-ended retry: after that the page has settled on
        // an empty or error state, and there is nothing to scroll.
        if (attempt < _restoreAttempts) _scheduleRestore(attempt: attempt + 1);
        return;
      }
      _pendingRestore = null;
      final offset = place.scrollOffset;
      if (offset == null || offset <= 0) return;
      // Clamped: the catalog can come back shorter than it was left.
      final position = _scrollController.position;
      _scrollController.jumpTo(offset.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
  }

  /// Loads the stored setup, prunes sources that no longer exist, and starts
  /// the merge — in that order, so the first fetch already carries the user's
  /// filters instead of loading the unfiltered catalog and replacing it.
  Future<void> _restorePreferences() async {
    final stored = await UnifiedCatalogQueryStore.read(widget.catalog.query.kind);
    if (!mounted) return;
    // Hoofdstuk 10.6: "Een bron/library die niet meer bestaat wordt bij openen
    // automatisch uit de opgeslagen selectie verwijderd." Written back, unlike
    // a capability-suppressed filter, because a key naming a removed server has
    // no row left in the panel to untick it with.
    final pruned = stored.copyWith(
      filters: stored.filters.withKnownSources(knownServerIds: _knownServerIds, knownLibraryKeys: _knownLibraryKeys),
    );
    setState(() {
      _preferences = pruned;
      _preferencesLoaded = true;
    });
    if (pruned != stored) unawaited(UnifiedCatalogQueryStore.write(widget.catalog.query.kind, pruned));
    _scheduleRestore();
    await _applyQuery(startIfNeeded: true);
  }

  Set<String> get _knownServerIds => {for (final library in widget.catalog.eligibleLibraries) library.serverId.value};

  Set<String> get _knownLibraryKeys => {
    for (final library in widget.catalog.eligibleLibraries) buildGlobalKey(library.serverId, library.libraryId),
  };

  /// What the participating backends can execute right now.
  ///
  /// Read off `participatingLibraries` — after the source restriction — so
  /// excluding the one backend that cannot filter is enough to get genre and
  /// year back, rather than its mere existence disabling them for good.
  UnifiedFilterCapabilities get _capabilities =>
      unifiedFilterCapabilitiesFor(widget.catalog.participatingLibraries.map((l) => l.backend));

  /// The capability-derived view of the stored selection: what is actually
  /// applied, what the panel shows as active, and what the badge counts.
  UnifiedCatalogFilterSelection get _effectiveFilters => _preferences.filters.constrainedTo(_capabilities);

  /// Pushes the current preferences into the merge.
  ///
  /// Capabilities are computed from a *hypothetical* participating set rather
  /// than the live one, because the source restriction and the item filters are
  /// applied in the same call: asking the provider what participates today
  /// would evaluate the new genre filter against yesterday's backends.
  Future<void> _applyQuery({bool startIfNeeded = false}) {
    final selection = _preferences.filters;
    final participating = widget.catalog.eligibleLibraries.where(selection.selects);
    final capabilities = unifiedFilterCapabilitiesFor(participating.map((l) => l.backend));
    final query = buildUnifiedCatalogQuery(
      kind: widget.catalog.query.kind,
      preferences: _preferences,
      capabilities: capabilities,
    );
    // `startIfNeeded` means "start it if it is not running", not "start it
    // again". On the fase-7 shell this screen is rebuilt from nothing every
    // time the viewer leaves the destination and comes back, and restarting a
    // merge that is already loaded would throw away every page it holds and
    // re-ask every server for them — the reload hoofdstuk 24 forbids and
    // [DEC-069] promises this nested route does not cost.
    final alreadyRunning = !startIfNeeded || widget.catalog.hasStarted;
    if (alreadyRunning && query == widget.catalog.query && !_restrictionChanged(selection)) {
      return Future<void>.value();
    }
    return widget.catalog.setQuery(query, librarySelector: selection.restrictsSources ? selection.selects : null);
  }

  /// Whether the participating library set would change, which a query
  /// comparison alone cannot see: server and library filters live outside
  /// [UnifiedCatalogQuery] by design (they are executed by leaving cursors out).
  bool _restrictionChanged(UnifiedCatalogFilterSelection selection) {
    final wouldParticipate = {
      for (final library in widget.catalog.eligibleLibraries.where(selection.selects))
        buildGlobalKey(library.serverId, library.libraryId),
    };
    final participating = {
      for (final library in widget.catalog.participatingLibraries) buildGlobalKey(library.serverId, library.libraryId),
    };
    return wouldParticipate.length != participating.length || !wouldParticipate.containsAll(participating);
  }

  Future<void> _updatePreferences(UnifiedCatalogPreferences next) async {
    if (next == _preferences) return;
    setState(() => _preferences = next);
    unawaited(UnifiedCatalogQueryStore.write(widget.catalog.query.kind, next));
    // Hoofdstuk 7.6: "filter- of sorteermutatie → grid naar boven, focus blijft
    // op de actie totdat nieuwe data gereed is." Focus is already on the action
    // the panel restored it to; the scroll reset is this line.
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _applyQuery();
  }

  // ---------------------------------------------------------------------------
  // Activation — fase 4, and nothing else
  // ---------------------------------------------------------------------------

  Future<void> _activate(UnifiedMediaGroup group) async {
    final multiServer = context.read<MultiServerProvider>();
    final manager = multiServer.serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );

    await activateUnifiedMediaGroup(
      context,
      group: group,
      intent: UnifiedActivationIntent.details,
      environment: buildUnifiedActivationEnvironment(
        group: group,
        health: health,
        catalogServerIds: {for (final library in widget.catalog.participatingLibraries) library.serverId.value},
        // The provider notifies on every server health change, which is what
        // hoofdstuk 14.4 needs to disable a row under the cursor.
        availabilityRevision: multiServer,
        resolver: _sourceResolver(multiServer),
        onManageServers: widget.onManageServers,
      ),
      // I19: player return re-reads the concrete item that played and folds
      // it back into its group in place — no re-page, no lost scroll
      // position, no card that jumps under the cursor. `refreshItem` is a
      // no-op when the merge never popped this item (the shape every existing
      // callback already tolerates).
      onPlaybackReturned: (item) => unawaited(
        widget.catalog.refreshItem(item.globalKey, () async {
          final serverId = item.serverId;
          if (serverId == null) return null;
          return context.read<MultiServerProvider>().getClientForServer(ServerId(serverId))?.fetchItem(item.id);
        }),
      ),
    );
  }

  /// Hoofdstuk 23's menu, on the same live health read [_activate] uses.
  ///
  /// `isInContinueWatching` stays false: the complete catalogus is a library
  /// wall, and "Verwijder uit Verder kijken" on a card that is not in Verder
  /// kijken is an action with nothing to act on.
  Future<void> _openContextMenu(UnifiedMediaGroup group) async {
    final manager = context.read<MultiServerProvider>().serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );
    await showTvUnifiedContextMenu(
      context,
      group: group,
      availabilityFor: (source) => unifiedSourceAvailability(source, health),
      isOffline: context.read<OfflineModeProvider?>()?.isOffline ?? false,
    );
  }

  /// The hoofdstuk 12.8 fan-out, built once per profile.
  ///
  /// Cached on the profile id rather than rebuilt per activation so its
  /// positive/negative cache actually survives between titles — a resolver
  /// recreated on every Select would re-ask every server for a title it
  /// resolved a minute ago. Null before a profile is bound, which degrades the
  /// picker to the sources this page merged rather than crashing.
  SourceAllResolver? _sourceResolver(MultiServerProvider multiServer) {
    final profileId = context.read<ActiveProfileProvider>().activeId;
    if (profileId == null) return null;
    if (_resolver != null && _resolverProfileId == profileId) return _resolver;
    _resolverProfileId = profileId;
    final manager = multiServer.serverManager;
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    return _resolver = SourceAllResolver(
      profileId: profileId,
      // A19: the denominator is the profile's topology, not the live client
      // map. `eligibleSourceServers` documents why an expected server without
      // a client has to stay in the list instead of quietly leaving coverage
      // complete.
      serversFor: () => eligibleSourceServers(
        expectedServerIds: multiServer.expectedServerIds,
        visibleServerIds: multiServer.serverIds,
        clientFor: manager.getClient,
        isOnline: manager.isServerOnline,
        authErrorServerIds: manager.authErrorServerIds,
      ),
      // Library visibility, read live: the resolver is cached per profile and
      // must see a hide that lands after it was built. Server visibility is
      // already closed by the `isServerVisible` guard above; this closes the
      // other half, so a hidden library on a visible server cannot come back
      // as a picker row.
      hiddenLibraryKeysFor: () => hiddenLibraries.hiddenLibraryKeys,
      cache: ApiCache.forBackend(MediaBackend.plex),
    );
  }

  // ---------------------------------------------------------------------------
  // Panels
  // ---------------------------------------------------------------------------

  Future<void> _openFilters({required TvCatalogFilterSection initialSection}) async {
    _lastUsedSlot =
        initialSection == TvCatalogFilterSection.servers || initialSection == TvCatalogFilterSection.libraries
        ? _HeaderSlot.sources
        : _HeaderSlot.filters;
    final result = await showTvCatalogFilterPanel(
      context,
      selection: _preferences.filters,
      capabilities: _capabilities,
      libraries: widget.catalog.eligibleLibraries,
      initialSection: initialSection,
      clientFor: (serverId) => context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId)),
    );
    if (result == null || !mounted) return;
    await _updatePreferences(_preferences.copyWith(filters: result));
  }

  Future<void> _openSort() async {
    _lastUsedSlot = _HeaderSlot.sort;
    final result = await showTvCatalogSortPanel(context, selected: _preferences.sort);
    if (result == null || !mounted) return;
    await _updatePreferences(_preferences.copyWith(sort: result));
  }

  // ---------------------------------------------------------------------------
  // Focus traversal (hoofdstuk 7.4)
  // ---------------------------------------------------------------------------

  void _focusGrid() => _gridKey.currentState?.focusGrid();

  /// UP from the grid: the last used action, or Filters as the standing
  /// default — it is the one that changes the page most and the one hoofdstuk
  /// 10.6 gives the count badge to.
  void _focusHeader() {
    final node = switch (_lastUsedSlot) {
      _HeaderSlot.sources => _sourcesFocus,
      _HeaderSlot.filters => _filtersFocus,
      _HeaderSlot.sort => _sortFocus,
    };
    if (node.canRequestFocus) node.requestFocus();
  }

  /// UP or LEFT out of the header, into the root navigation.
  ///
  /// Hoofdstuk 7.4 asks for UP; the shell resolves what is up there. On the
  /// fase-7 TV root that is the top navigation, on the desktop rail it is the
  /// rail — see [TvRootShell] on why one method serves both.
  void _focusSidebar() => MainScreenFocusScope.of(context, listen: false)?.focusSidebar();

  /// DOWN out of the top navigation, per hoofdstuk 7.4: "Down vanaf topnav
  /// focust de eerste headeractie."
  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    _focusHeader();
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    // Not a flat fill. A very slight lift towards the top of the frame gives the
    // page a horizon, so the grid stands in a room rather than floating on a
    // uniform slab — the same reason a cinema wall is never one value. It is
    // deliberately almost subliminal: two per cent over the whole height, well
    // under any banding threshold, and the posters still sit on `MonoTokens.bg`
    // wherever they actually are.
    //
    // Inside the fase-7 shell the shell paints it instead, across the whole
    // viewport. Painting it again here would start a second gradient at the
    // bottom edge of the top navigation and leave a hard step there; the lift
    // belongs to the page, and under a top bar the page starts above this box.
    final framedByShell = TvShellSurface.isPresent(context);
    return DecoratedBox(
      decoration: framedByShell
          ? const BoxDecoration()
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(tk.text.withValues(alpha: TvCatalogLayout.pageLift), tk.bg),
                  tk.bg,
                ],
                stops: const [0, 0.55],
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvCatalogHeaderBar(title: widget.title, actions: _headerActions()),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  List<TvCatalogHeaderAction> _headerActions() {
    final filters = _effectiveFilters;
    return [
      TvCatalogHeaderAction(
        icon: Symbols.dns_rounded,
        action: LibraryHeaderAction(
          label: t.unifiedCatalog.allSources,
          value: _sourcesLabel(filters),
          isActive: filters.restrictsSources,
          focusNode: _sourcesFocus,
          onPressed: () => _openFilters(initialSection: TvCatalogFilterSection.servers),
          onNavigateRight: () => _filtersFocus.requestFocus(),
          onNavigateLeft: _focusSidebar,
          onNavigateUp: _focusSidebar,
          onNavigateDown: _focusGrid,
        ),
      ),
      TvCatalogHeaderAction(
        icon: Symbols.filter_list_rounded,
        badgeCount: filters.activeCount,
        action: LibraryHeaderAction(
          label: t.unifiedCatalog.filters.title,
          isActive: !filters.isEmpty,
          focusNode: _filtersFocus,
          onPressed: () => _openFilters(initialSection: TvCatalogFilterSection.status),
          onNavigateLeft: () => _sourcesFocus.requestFocus(),
          onNavigateRight: () => _sortFocus.requestFocus(),
          onNavigateUp: _focusSidebar,
          onNavigateDown: _focusGrid,
        ),
      ),
      TvCatalogHeaderAction(
        icon: Symbols.swap_vert_rounded,
        action: LibraryHeaderAction(
          label: t.unifiedCatalog.sort.title,
          value: sortLabel(_preferences.sort),
          focusNode: _sortFocus,
          onPressed: _openSort,
          onNavigateLeft: () => _filtersFocus.requestFocus(),
          onNavigateUp: _focusSidebar,
          onNavigateDown: _focusGrid,
        ),
      ),
    ];
  }

  /// "All sources" until something is excluded, then how many are left.
  String? _sourcesLabel(UnifiedCatalogFilterSelection filters) {
    if (!filters.restrictsSources) return null;
    final count = widget.catalog.participatingLibraries.map((l) => l.serverId.value).toSet().length;
    return count == 1 ? t.unifiedCatalog.oneSource : t.unifiedCatalog.sources(count: count);
  }

  Widget _buildBody() {
    final catalog = widget.catalog;
    final snapshot = catalog.snapshot;

    if (!_preferencesLoaded || (catalog.isInitialLoading && snapshot.groups.isEmpty)) {
      return const TvCatalogSkeletonGrid(key: tvCatalogSkeletonKey);
    }

    // Hoofdstuk 29: a full-page error only when there is no usable catalog at
    // all. Anything that loaded stays on screen, however many libraries failed.
    if (snapshot.groups.isEmpty) {
      if (snapshot.initialLoadFailed || catalog.loadFailed) {
        return _EmptyState(
          title: t.unifiedCatalog.states.errorTitle,
          body: t.unifiedCatalog.states.errorBody,
          actionLabel: t.common.retry,
          onAction: catalog.refresh,
        );
      }
      // An empty *filtered* result is a different situation from an empty
      // catalog, and needs a different way out (hoofdstuk 29).
      if (!_effectiveFilters.isEmpty) {
        return _EmptyState(
          title: t.unifiedCatalog.states.filterEmptyTitle,
          body: t.unifiedCatalog.states.filterEmptyBody,
          actionLabel: t.unifiedCatalog.states.clearFilters,
          onAction: () => _updatePreferences(_preferences.copyWith(filters: UnifiedCatalogFilterSelection.empty)),
        );
      }
      return _EmptyState(title: t.unifiedCatalog.states.emptyTitle, body: t.unifiedCatalog.states.emptyBody);
    }

    return TvUnifiedMediaGrid(
      key: _gridKey,
      controller: _scrollController,
      initialFocusedGroupId: _focusedGroupId,
      onFocusedGroupChanged: (groupId) => _focusedGroupId = groupId,
      groups: snapshot.groups,
      hasMore: snapshot.hasMore,
      isLoadingMore: catalog.isLoadingMore,
      onLoadMore: catalog.loadMore,
      onActivate: _activate,
      onContextMenu: _openContextMenu,
      onExitTop: _focusHeader,
      onExitLeft: _focusSidebar,
      clientFor: (serverId) => context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId)),
      footer: TvUnifiedGridFooter(
        loadedCount: snapshot.groups.length,
        isComplete: snapshot.isComplete,
        isLoadingMore: catalog.isLoadingMore,
        failedLibraryCount: snapshot.failedLibraryIds.length,
      ),
    );
  }
}

/// Centred title, body and one optional action — the shape all four of
/// hoofdstuk 29's non-content states share, so they cannot drift apart.
/// Finds the loading placeholder. Public so a test can assert *which* waiting
/// state is on screen rather than merely that the grid is absent.
const Key tvCatalogSkeletonKey = ValueKey('tvCatalogSkeleton');

/// What the page looks like before the first round of results lands.
///
/// A centred spinner on an otherwise empty page was the first build, and it is
/// the one frame that undoes the rest: the user presses Films and gets a black
/// screen with a small red circle in it, then the catalogue appears all at
/// once. Nothing about it says a wall of posters is coming.
///
/// So the placeholder is the page, on the page's own geometry —
/// [TvCatalogGrid.forWidth] is the same call the real grid makes, so the
/// columns, the card width, the gutter and the outer inset are not
/// approximated here, they are identical. The posters resolve in place instead
/// of replacing something shaped differently, and the first thing the eye is
/// given is the layout it is about to read.
///
/// Deliberately still. A shimmer is the reflex, and it would cost the goldens
/// their determinism — `pumpAndSettle` never returns under a repeating
/// animation — for motion that a 10-foot surface reads as flicker rather than
/// as progress.
class TvCatalogSkeletonGrid extends StatelessWidget {
  const TvCatalogSkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final grid = TvCatalogGrid.forWidth(MediaQuery.sizeOf(context).width, scale: scale);

    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = TvCatalogLayout.cardContentInset(scale);
        final cardHeight = (grid.cardWidth - inset * 2) / TvCatalogLayout.posterAspectRatio;
        // Enough rows to reach the bottom edge, so the placeholder fills the
        // surface it is standing in for rather than floating in the top half of
        // it. Partly-visible rows count: the real grid has them too.
        final rows = constraints.maxHeight.isFinite
            ? ((constraints.maxHeight + grid.gutter) / (cardHeight + grid.gutter)).ceil().clamp(1, 6)
            : 2;

        // Not a bare ClipRect: the bottom row is meant to run off the edge the
        // way the real grid's does, and a Column that overtops its constraints
        // asserts before anything gets clipped. A scroll view the user cannot
        // scroll gives the Column the unbounded height it needs and clips the
        // result — which is also, structurally, what the real grid is.
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: grid.inset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var row = 0; row < rows; row++) ...[
                  if (row > 0) SizedBox(height: grid.gutter),
                  Row(
                    children: [
                      for (var column = 0; column < grid.columns; column++) ...[
                        if (column > 0) SizedBox(width: grid.gutter),
                        _SkeletonCard(width: grid.cardWidth, scale: scale, mono: mono),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One placeholder card: the poster block and the two text bars under it, on
/// the metrics [TvUnifiedMediaCard] uses for the real thing.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.width, required this.scale, required this.mono});

  final double width;
  final double scale;
  final MonoTokens mono;

  @override
  Widget build(BuildContext context) {
    final barHeight = TvCatalogLayout.cardTitleFontSize * scale;
    final metaHeight = TvCatalogLayout.cardMetaFontSize * scale;

    // The same inset the real card carries, and it is made of two things.
    // `TvUnifiedMediaCard` sizes the *wrapper* to the grid's card width, and
    // inside that wrapper `FocusableWrapper` draws its ring as a border — which
    // costs [FocusTheme.focusBorderWidth] a side whether or not the card has the
    // focus — before the card's own focus-ring gap pads it again. Sizing the
    // placeholder poster to the full column made every poster on screen shrink
    // and shift at the moment the data landed, which is the one frame this
    // placeholder exists to make uneventful. Counting only the gap and not the
    // border left two thirds of that jump in place.
    final inset = TvCatalogLayout.cardContentInset(scale);
    final posterWidth = width - inset * 2;

    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: tvCatalogPosterKey,
              width: posterWidth,
              height: posterWidth / TvCatalogLayout.posterAspectRatio,
              decoration: BoxDecoration(
                color: mono.text.withValues(alpha: TvCatalogLayout.skeletonArtworkFill),
                borderRadius: BorderRadius.circular(TvCatalogLayout.cardRadius * scale),
              ),
            ),
            SizedBox(height: TvCatalogLayout.cardFooterPaddingVertical * scale),
            _SkeletonBar(
              width: posterWidth * TvCatalogLayout.skeletonTitleWidthFraction,
              height: barHeight,
              scale: scale,
              mono: mono,
            ),
            SizedBox(height: TvCatalogLayout.cardFooterLineGap * scale * 2),
            _SkeletonBar(
              width: posterWidth * TvCatalogLayout.skeletonMetaWidthFraction,
              height: metaHeight,
              scale: scale,
              mono: mono,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height, required this.scale, required this.mono});

  final double width;
  final double height;
  final double scale;
  final MonoTokens mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: mono.text.withValues(alpha: TvCatalogLayout.skeletonTextFill),
        borderRadius: BorderRadius.circular(TvCatalogLayout.skeletonBarRadius * scale),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.body, this.actionLabel, this.onAction});

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w600,
                color: tk.text,
              ),
            ),
            SizedBox(height: TvCatalogLayout.cardFooterLineGap * scale * 2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
              TvPanelButton(scale: scale, label: actionLabel!, onPressed: onAction!, primary: true, autofocus: true),
            ],
          ],
        ),
      ),
    );
  }
}
