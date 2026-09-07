/// The Films and Series page, in one widget (hoofdstuk 10 of
/// docs/tvos-unified-experience.md).
///
/// One screen for both catalogs, because they differ in exactly two things a
/// parameter can carry: which [MediaKind] they browse and what the heading
/// says. Everything else (the controls rail, the grid, paging, the four
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
/// ## Where the remote can go (hoofdstuk 7.4, rewritten by CAT5)
///
/// Until 4 September 2026 the traversal was topnav → three header actions →
/// grid, and back up. [DEC-093](../../../docs/DECISIONS.md#dec-093) moved those
/// actions into a rail left of the grid, and the shape is now:
///
/// ```
///            topnav
///              │ DOWN            UP │
///              ▼                    │
///   rail ◀── LEFT ── grid ──────────┘
///        ── RIGHT/Menu ──▶
/// ```
///
/// Two consequences worth stating, because both were load-bearing before:
///
/// * **DOWN out of the topnav lands on a card**, not on a control. That is what
///   CAT4 spent a whole finding forbidding, but CAT4 was about a *header* the
///   viewer could no longer reach; with the controls one LEFT away from column
///   0 there is nothing left to be cut off from, and landing on the content is
///   the honest answer. `_focusEntry` is where that happens, and it waits for
///   the grid rather than assuming it is there.
/// * **UP from the first grid row goes straight to the topnav.** There is no
///   header row in between any more, so 7.4's "Up vanaf de eerste gridrij gaat
///   naar de dichtstbijzijnde headeractie" has nothing to land on.
///
/// The rail is never a dead end: UP and LEFT out of it close it and reach for
/// the topnav, RIGHT and Menu close it and put the remote back on the card it
/// came from.
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
import '../../widgets/tv/tv_catalog_empty_state.dart';
import '../../widgets/tv/tv_catalog_filter_panel.dart';
import '../../widgets/tv/tv_catalog_filter_rail.dart';
import '../../widgets/tv/tv_catalog_header_bar.dart';
import '../../widgets/tv/tv_catalog_rail_scaffold.dart';
import '../../widgets/tv/tv_catalog_selection_tags.dart';
import '../../widgets/tv/tv_catalog_skeleton_grid.dart';
import '../../widgets/tv/tv_catalog_sort_panel.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_unified_media_grid.dart';
import 'tv_media_source_picker_route.dart';
import 'tv_unified_activation.dart';
import 'tv_unified_context_menu.dart';

/// How many frames [_TvUnifiedCatalogScreenState._scheduleRestore] waits for a
/// scrollable to exist before giving up.
const int _restoreAttempts = 8;

/// What [TvDestinationFocusMemory.focusedElementId] carries for this screen: a
/// rail that was open when the viewer left the destination is open when they
/// come back.
///
/// It used to carry the last used header action. That memory has no subject any
/// more (DEC-093 has the rail always open on Bronnen), and the field is the
/// only per-destination place this screen has to keep a fact that is neither a
/// card nor a scroll offset.
const String _railOpenToken = 'rail';

class TvUnifiedCatalogScreen extends StatefulWidget {
  const TvUnifiedCatalogScreen({
    super.key,
    required this.catalog,
    required this.title,
    this.onManageServers,
    this.restoreFrom = TvDestinationFocusMemory.empty,
    this.onRemember,
    this.initialFilterOverride,
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

  /// A filter to open with instead of the stored per-profile one (ROW1c,
  /// DEC-100 (2)'s "Alle N" tile): the viewer's own custom row, opened for one
  /// visit only. Not persisted, and not written back even if the stored
  /// preferences needed pruning against known sources — leaving this screen
  /// restores whatever the viewer had set here before (Michel, 6 September
  /// 2026). A deliberate edit made *while* viewing the override still saves
  /// normally, the same as any other visit: only the initial seed is transient.
  final UnifiedCatalogPreferences? initialFilterOverride;

  @override
  State<TvUnifiedCatalogScreen> createState() => _TvUnifiedCatalogScreenState();
}

class _TvUnifiedCatalogScreenState extends State<TvUnifiedCatalogScreen> implements FocusableTab {
  final _gridKey = GlobalKey<TvUnifiedMediaGridState>();
  final _scrollController = ScrollController();
  final _sourcesFocus = FocusNode(debugLabel: 'TvCatalogRailSources');
  final _filtersFocus = FocusNode(debugLabel: 'TvCatalogRailFilters');
  final _sortFocus = FocusNode(debugLabel: 'TvCatalogRailSort');
  final _clearFocus = FocusNode(debugLabel: 'TvCatalogRailClear');

  /// The one action a state with no grid has (hoofdstuk 29). It is the only
  /// thing left to put the remote on when the rail closes over an empty page.
  final _stateActionFocus = FocusNode(debugLabel: 'TvCatalogStateAction');

  /// The user's stored setup. Kept whole: what is *applied* is this constrained
  /// to the live capabilities, which change with the source restriction.
  UnifiedCatalogPreferences _preferences = UnifiedCatalogPreferences.defaults;
  bool _preferencesLoaded = false;

  /// Whether the controls rail is open (CAT5). Closed is the resting state:
  /// Michel's condition on choosing the rail was "dan moet dit niet altijd in
  /// beeld blijven deze zijbalk".
  bool _railExpanded = false;

  /// Set while the screen still owes someone an entry focus: DOWN out of the
  /// topnav on a catalog whose grid has not been built yet. See [_tryEntryFocus].
  bool _wantsEntryFocus = false;

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
    _railExpanded = place.focusedElementId == _railOpenToken;
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
        focusedElementId: _railExpanded ? _railOpenToken : null,
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
    _clearFocus.dispose();
    _stateActionFocus.dispose();
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
    _scheduleRestore();
    if (_wantsEntryFocus) {
      // After the frame this rebuild produces: the grid's `State` only exists
      // once it has been built, and an entry focus asked for before the first
      // page landed has nothing to land on yet.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryEntryFocus());
    }
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
  ///
  /// [TvUnifiedCatalogScreen.initialFilterOverride], when set, replaces the
  /// stored read outright rather than being merged with it: an "Alle N" visit
  /// is a specific, complete filter, not an amendment to whatever the viewer
  /// had set here before. The pruning against known sources still runs, in
  /// memory only; nothing here is written back, so leaving the screen loses
  /// nothing the viewer had stored.
  Future<void> _restorePreferences() async {
    final override = widget.initialFilterOverride;
    final stored = override ?? await UnifiedCatalogQueryStore.read(widget.catalog.query.kind);
    if (!mounted) return;
    // Hoofdstuk 10.6: "Een bron/library die niet meer bestaat wordt bij openen
    // automatisch uit de opgeslagen selectie verwijderd." Written back, unlike
    // a capability-suppressed filter, because a key naming a removed server has
    // no row left in the panel to untick it with — except for an override,
    // which has no stored row to begin with.
    final pruned = stored.copyWith(
      filters: stored.filters.withKnownSources(knownServerIds: _knownServerIds, knownLibraryKeys: _knownLibraryKeys),
    );
    setState(() {
      _preferences = pruned;
      _preferencesLoaded = true;
    });
    if (_wantsEntryFocus) WidgetsBinding.instance.addPostFrameCallback((_) => _tryEntryFocus());
    if (override == null && pruned != stored) {
      unawaited(UnifiedCatalogQueryStore.write(widget.catalog.query.kind, pruned));
    }
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
    final result = await showTvCatalogSortPanel(context, selected: _preferences.sort);
    if (result == null || !mounted) return;
    await _updatePreferences(_preferences.copyWith(sort: result));
  }

  // ---------------------------------------------------------------------------
  // Focus traversal (hoofdstuk 7.4)
  // ---------------------------------------------------------------------------

  /// UP or LEFT out of the header, into the root navigation.
  ///
  /// Hoofdstuk 7.4 asks for UP; the shell resolves what is up there. On the
  /// fase-7 TV root that is the top navigation, on the desktop rail it is the
  /// rail — see [TvRootShell] on why one method serves both.
  void _focusSidebar() => MainScreenFocusScope.of(context, listen: false)?.focusSidebar();

  // ---------------------------------------------------------------------------
  // The rail (CAT5 / DEC-093)
  // ---------------------------------------------------------------------------

  /// LEFT off column 0, and LEFT off the one action an empty state has.
  ///
  /// The focus request is deferred a frame on purpose: the rail's nodes are
  /// only attached once the panel has been built, and `requestFocus` on a node
  /// that is not in the tree yet does nothing at all, and silently, which is the
  /// shape of bug this correctieronde keeps finding.
  void _openRail() {
    if (_railExpanded) return;
    setState(() => _railExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_railExpanded) return;
      // Always Bronnen, per DEC-093, not the row last used. The rail is a
      // short list the eye reads top to bottom, and opening it halfway down
      // costs more than the press it saves.
      if (_sourcesFocus.canRequestFocus) _sourcesFocus.requestFocus();
    });
  }

  /// RIGHT or Menu out of the rail: back to the card it was opened from.
  ///
  /// [_focusGrid] prefers the remembered `groupId`, and the grid keys its nodes
  /// on that rather than on position, so the card survives the re-column from
  /// five back to six.
  void _closeRail() {
    if (!_railExpanded) return;
    setState(() => _railExpanded = false);
    final grid = _gridKey.currentState;
    if (grid != null && grid.hasFocusableCard) {
      grid.focusGrid();
      return;
    }
    // No grid to go back to: an error or a filtered-empty catalog. Its one
    // action autofocused when it was mounted, but that was before the rail took
    // the focus off it, and a page focused with nothing focused on it is one
    // the remote can neither move within nor leave.
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
  /// DOWN off the bottom of the rail: nothing at all.
  ///
  /// Explicit rather than left null. `FocusableWrapper` treats a missing
  /// handler as "not mine" and falls through to Flutter's own directional
  /// traversal, which from the last rail row walks sideways into the grid, and
  /// leaves the rail standing open with the focus somewhere else, which is the
  /// one state [_leaveRailUpwards] exists to prevent.
  void _railEdge() {}

  void _leaveRailUpwards() {
    if (_railExpanded) setState(() => _railExpanded = false);
    _focusSidebar();
  }

  /// DOWN out of the top navigation.
  ///
  /// Hoofdstuk 7.4 said "focust de eerste headeractie"; since CAT5 there is no
  /// header action, so this lands on the content: the rail if it is open,
  /// otherwise the card the viewer was last on.
  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    _wantsEntryFocus = true;
    _tryEntryFocus();
  }

  /// Puts the remote on the content, once there is content to put it on.
  ///
  /// The header used to make this trivial: it exists from the first frame, so
  /// `focusActiveTabIfReady` could always land somewhere. A grid cannot promise
  /// that, because the stored preferences are read asynchronously and the skeleton
  /// stands in until the first page arrives, so the request is remembered and
  /// retried from the two places that produce a new frame with a grid in it:
  /// [_onCatalogChanged] and the end of [_restorePreferences].
  ///
  /// It gives up once the page has settled on a state that has no grid at all.
  /// Those states focus their own action ([TvCatalogEmptyState] autofocuses
  /// it), and a request left standing would steal the focus back off it the
  /// moment a late page arrived.
  void _tryEntryFocus() {
    if (!mounted || !_wantsEntryFocus) return;
    if (_railExpanded) {
      if (_sourcesFocus.canRequestFocus) {
        _wantsEntryFocus = false;
        _sourcesFocus.requestFocus();
      }
      return;
    }
    final grid = _gridKey.currentState;
    if (grid != null && grid.hasFocusableCard) {
      _wantsEntryFocus = false;
      grid.focusGrid();
      return;
    }
    if (_preferencesLoaded && !widget.catalog.isInitialLoading) _wantsEntryFocus = false;
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
          // The tags are capped here and uncapped in the rail: the heading has
          // one line and no way to scroll, the panel wraps.
          TvCatalogHeaderBar(title: widget.title, tags: _railExpanded ? const [] : _selectionTags()),
          Expanded(child: _buildContentArea()),
        ],
      ),
    );
  }

  /// The grid, with the rail standing beside it — the shared placement of
  /// [TvCatalogRailScaffold], which this screen used to own outright.
  Widget _buildContentArea() {
    final scale = TvLayoutConstants.scaleOf(context);
    return TvCatalogRailScaffold(
      cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
      rail: _railExpanded
          ? TvCatalogFilterRailPanel(
              key: tvCatalogFilterRailKey,
              scale: scale,
              rows: _railRows(),
              tags: _selectionTags(capped: false),
              onClear: _preferences.filters.isEmpty ? null : _clearFilters,
              clearFocusNode: _clearFocus,
              onClearNavigateUp: () => _sortFocus.requestFocus(),
              onClearNavigateDown: _railEdge,
              onClearNavigateLeft: _leaveRailUpwards,
              onClearNavigateRight: _closeRail,
              onClearBack: _closeRail,
            )
          : null,
      body: _buildBody(),
    );
  }

  double _railLeading(double width) => TvCatalogRailScaffold.leadingFor(width, expanded: _railExpanded);

  List<TvCatalogSelectionTag> _selectionTags({bool capped = true}) => tvCatalogSelectionTags(
    filters: _effectiveFilters,
    sort: _preferences.sort,
    sourcesLabel: _sourcesLabel(_effectiveFilters),
    overflowAfter: capped ? TvCatalogLayout.tagOverflowThreshold : null,
  );

  /// Clears every filter, from the rail's Wissen row or from the
  /// filtered-empty state's own button.
  ///
  /// The focus move is not optional. Wissen is only drawn while something is
  /// filtered, so pressing it removes the row the remote is standing on.
  /// Without this line the ring does not vanish, which is what makes the bug
  /// easy to miss: Flutter hands it to whatever sibling survives, and measured
  /// here that is Sortering, one row further from where the viewer was. Naming
  /// the destination is the difference between a move the viewer can follow and
  /// one the framework picked. From the empty state the guard is false and
  /// nothing moves, because there the button survives its own press.
  Future<void> _clearFilters() {
    if (_clearFocus.hasFocus) _filtersFocus.requestFocus();
    return _updatePreferences(_preferences.copyWith(filters: UnifiedCatalogFilterSelection.empty));
  }

  List<TvCatalogFilterRailRow> _railRows() {
    final filters = _effectiveFilters;
    final itemFilters = filters.itemFilterCount;
    return [
      TvCatalogFilterRailRow(
        icon: Symbols.dns_rounded,
        label: t.unifiedCatalog.rail.sources,
        value: _sourcesLabel(filters) ?? t.unifiedCatalog.allSources,
        focusNode: _sourcesFocus,
        onPressed: () => _openFilters(initialSection: TvCatalogFilterSection.servers),
        onNavigateUp: _leaveRailUpwards,
        onNavigateDown: () => _filtersFocus.requestFocus(),
        onNavigateLeft: _leaveRailUpwards,
        onNavigateRight: _closeRail,
        onBack: _closeRail,
      ),
      TvCatalogFilterRailRow(
        icon: Symbols.filter_list_rounded,
        label: t.unifiedCatalog.filters.title,
        value: itemFilters == 0
            ? t.unifiedCatalog.rail.noFilters
            : t.unifiedCatalog.rail.filtersActive(count: itemFilters),
        focusNode: _filtersFocus,
        onPressed: () => _openFilters(initialSection: TvCatalogFilterSection.status),
        onNavigateUp: () => _sourcesFocus.requestFocus(),
        onNavigateDown: () => _sortFocus.requestFocus(),
        onNavigateLeft: _leaveRailUpwards,
        onNavigateRight: _closeRail,
        onBack: _closeRail,
      ),
      TvCatalogFilterRailRow(
        icon: Symbols.swap_vert_rounded,
        label: t.unifiedCatalog.sort.title,
        value: sortLabel(_preferences.sort),
        focusNode: _sortFocus,
        onPressed: _openSort,
        onNavigateUp: () => _filtersFocus.requestFocus(),
        onNavigateDown: _preferences.filters.isEmpty ? _railEdge : () => _clearFocus.requestFocus(),
        onNavigateLeft: _leaveRailUpwards,
        onNavigateRight: _closeRail,
        onBack: _closeRail,
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
      return TvCatalogSkeletonGrid(
        key: tvCatalogSkeletonKey,
        reservedLeading: _railLeading(MediaQuery.sizeOf(context).width),
      );
    }

    // Hoofdstuk 29: a full-page error only when there is no usable catalog at
    // all. Anything that loaded stays on screen, however many libraries failed.
    if (snapshot.groups.isEmpty) {
      if (snapshot.initialLoadFailed || catalog.loadFailed) {
        return TvCatalogEmptyState(
          title: t.unifiedCatalog.states.errorTitle,
          body: t.unifiedCatalog.states.errorBody,
          actionLabel: t.common.retry,
          onActionFocusNode: _stateActionFocus,
          onAction: catalog.refresh,
          onActionNavigateLeft: _openRail,
        );
      }
      // An empty *filtered* result is a different situation from an empty
      // catalog, and needs a different way out (hoofdstuk 29).
      if (!_effectiveFilters.isEmpty) {
        return TvCatalogEmptyState(
          title: t.unifiedCatalog.states.filterEmptyTitle,
          body: t.unifiedCatalog.states.filterEmptyBody,
          actionLabel: t.unifiedCatalog.states.clearFilters,
          onActionFocusNode: _stateActionFocus,
          onAction: _clearFilters,
          onActionNavigateLeft: _openRail,
        );
      }
      return TvCatalogEmptyState(title: t.unifiedCatalog.states.emptyTitle, body: t.unifiedCatalog.states.emptyBody);
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
      onExitTop: _focusSidebar,
      onExitLeft: _openRail,
      reservedLeading: _railLeading(MediaQuery.sizeOf(context).width),
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
