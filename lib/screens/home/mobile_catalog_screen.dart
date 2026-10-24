/// Alle films / Alle series: the complete, cross-source catalogue behind the
/// landing's "Alle films ›"/"Alle series ›" action (iOS Unified 2026 fase 3,
/// `docs/ios-unified-2026-fase3-plan.md`), against the frozen
/// `03-alle-films.png`.
///
/// One screen for both kinds, the same choice `MobileLandingScreen` and the
/// TV catalogue screen it is modelled on (`tv_unified_catalog_screen.dart`,
/// read via `git show origin/main:...`, it does not exist on this branch)
/// both make: the difference is which [MediaKind] the catalog reads and what
/// the header says, nothing else. It owns presentation and the query it
/// asks for; it owns no source logic: activation goes through
/// `openMobileMediaGroup` (I5, workitem 4), the same coordinator-backed path
/// the rails above it use.
///
/// A push, not a tab state: `06-film-detail.png` shows the northstar's own
/// pushed detail screen still carrying the bottom bar with Films lit, which
/// today's `media_detail_screen.dart` push does not do either. The bar in
/// every northstar mockup is generic device chrome for the reviewer, not a
/// functional requirement, so this is a plain `Navigator.push` like a detail
/// page, not a new IndexedStack state.
library;

import '../../providers/offline_mode_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_kind.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/unified_catalog_provider.dart';
import '../../providers/unified_catalogs.dart';
import '../../screens/tv/tv_unified_activation.dart';
import '../../services/unified_catalog/mobile_media_source_picker_route.dart';
import '../../services/unified_catalog/unified_artwork_prefetcher.dart';
import '../../services/unified_catalog/unified_catalog_snapshot.dart';
import 'mobile_catalog_widgets.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_catalog_query_store.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/formatters.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/home_custom_row_labels.dart' show unifiedWatchFilterLabel;
import '../../utils/language_codes.dart';
import '../../widgets/app_icon.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/media_card_grid_layout.dart';
import '../../widgets/mobile/mobile_catalog_filters_sheet.dart';
import '../../widgets/mobile/mobile_catalog_sort_sheet.dart';
import '../../widgets/mobile/mobile_media_card.dart';
import '../../widgets/mobile/mobile_media_rail.dart' show mobileRailGutter, mobileRailInset;
import '../../widgets/mobile/mobile_refresh_scope.dart';
import '../../widgets/mobile/mobile_unified_context_menu.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/skeleton_media_card.dart';
import '../../widgets/scroll_crown/scroll_crown.dart';

/// Which catalogue this is. Deliberately its own enum, not [MediaKind]
/// directly: [MobileLandingKind] made the same choice, and this screen needs
/// the same small per-kind vocabulary (title, automation id) that enum
/// already carries.
enum MobileCatalogKind {
  movies,
  series;

  MediaKind get mediaKind => switch (this) {
    MobileCatalogKind.movies => MediaKind.movie,
    MobileCatalogKind.series => MediaKind.show,
  };

  String get screenAutomationId => switch (this) {
    MobileCatalogKind.movies => AutomationIds.screenCatalogMovies,
    MobileCatalogKind.series => AutomationIds.screenCatalogSeries,
  };

  String get automationInstance => name;

  String get title => switch (this) {
    MobileCatalogKind.movies => t.unifiedCatalog.moviesTitle,
    MobileCatalogKind.series => t.unifiedCatalog.seriesTitle,
  };
}

class MobileCatalogScreen extends StatefulWidget {
  const MobileCatalogScreen({
    super.key,
    required this.kind,
    this.onSearchTap,
    this.isTabRoot = false,
    this.debugPrefetcher,
    this.initialFilterOverride,
  });

  final MobileCatalogKind kind;

  /// A filter to open with instead of the stored per-profile one: the viewer's
  /// own Home row, opened for this visit only (HOME-R1, the same as the tvOS
  /// "Alle N" tile). Not written back; a deliberate edit made while viewing it
  /// saves like any other.
  final UnifiedCatalogPreferences? initialFilterOverride;

  /// Closes this screen and opens search, the same target the landing's own
  /// header search action reaches. Threaded in from `_TitleRow` rather than
  /// reached directly: Search is a tab on `MainScreen`, which this push
  /// covers (see this file's own doc comment on why a push covers the bar),
  /// so search can only become visible again once this screen is gone.
  final VoidCallback? onSearchTap;

  /// Offline catalogs can be embedded in the root tab instead of pushed.
  final bool isTabRoot;

  /// Test-only seam. When set, this prefetcher is used instead of
  /// constructing the real one, and this widget never disposes it; the
  /// caller that built it owns it. Without this seam a widget test that
  /// scrolls a populated grid triggers the real `precacheImage`, which
  /// dispatches an actual network fetch no test mocks, hanging the test
  /// rather than failing it.
  @visibleForTesting
  final UnifiedArtworkPrefetcher? debugPrefetcher;

  @override
  State<MobileCatalogScreen> createState() => _MobileCatalogScreenState();
}

class _MobileCatalogScreenState extends State<MobileCatalogScreen> {
  late final UnifiedCatalogProvider _catalog;
  final _scrollController = ScrollController();
  bool _headerHidden = false;
  double _headerScrollTravel = 0;
  final _panelKey = GlobalKey();

  /// Height of the translucent top panel (status bar inset, title row, chips
  /// and count line), measured after layout. The grid scrolls under the panel
  /// and carries this much padding on top, so at offset 0 the first row starts
  /// below it.
  double _panelHeight = 0;
  bool _panelMeasured = false;
  UnifiedArtworkPrefetcher? _prefetcher;

  UnifiedCatalogPreferences _preferences = UnifiedCatalogPreferences.defaults;
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _catalog = context.read<UnifiedCatalogs>().forKind(widget.kind.mediaKind);
    _catalog.addListener(_onCatalogChanged);
    _scrollController.addListener(_onScroll);
    unawaited(_restorePreferences());
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalogChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // A `debugPrefetcher` is owned by whoever built it, not by this widget.
    if (widget.debugPrefetcher == null) _prefetcher?.dispose();
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  Set<String> get _knownServerIds => {for (final library in _catalog.eligibleLibraries) library.serverId.value};

  Set<String> get _knownLibraryKeys => {
    for (final library in _catalog.eligibleLibraries) buildGlobalKey(library.serverId, library.libraryId),
  };

  /// Loads the stored setup, prunes sources that no longer exist, then starts
  /// the merge, same order and same reasoning as
  /// `TvUnifiedCatalogScreen._restorePreferences`: the first fetch should
  /// already carry the user's filters instead of loading unfiltered and
  /// replacing it a frame later.
  Future<void> _restorePreferences() async {
    final override = widget.initialFilterOverride;
    final stored = override ?? await UnifiedCatalogQueryStore.read(widget.kind.mediaKind);
    if (!mounted) return;
    // CAT20: pruned against the server registry, not just the libraries bound
    // right now, so a server that has merely not finished connecting is not
    // mistaken for one that is gone (see [pruneStoredSourceFilter]).
    final pruning = pruneStoredSourceFilter(
      stored: stored,
      boundServerIds: _knownServerIds,
      boundLibraryKeys: _knownLibraryKeys,
      registeredServerIds: context.read<MultiServerProvider>().expectedServerIds.toSet(),
    );
    final pruned = pruning.preferences;
    setState(() {
      _preferences = pruned;
      _preferencesLoaded = true;
    });
    if (override == null && pruning.shouldPersist) {
      unawaited(UnifiedCatalogQueryStore.write(widget.kind.mediaKind, pruned));
    }
    await _applyQuery(startIfNeeded: true);
  }

  UnifiedFilterCapabilities get _capabilities =>
      unifiedFilterCapabilitiesFor(_catalog.participatingLibraries.map((l) => l.backend));

  UnifiedCatalogFilterSelection get _effectiveFilters => _preferences.filters.constrainedTo(_capabilities);

  Future<void> _applyQuery({bool startIfNeeded = false}) {
    final selection = _preferences.filters;
    final participating = _catalog.eligibleLibraries.where(selection.selects);
    final capabilities = unifiedFilterCapabilitiesFor(participating.map((l) => l.backend));
    final query = buildUnifiedCatalogQuery(
      kind: widget.kind.mediaKind,
      preferences: _preferences,
      capabilities: capabilities,
    );
    final alreadyRunning = !startIfNeeded || _catalog.hasStarted;
    if (alreadyRunning && query == _catalog.query && !_restrictionChanged(selection)) {
      return Future<void>.value();
    }
    return _catalog.setQuery(query, librarySelector: selection.restrictsSources ? selection.selects : null);
  }

  bool _restrictionChanged(UnifiedCatalogFilterSelection selection) {
    final wouldParticipate = {
      for (final library in _catalog.eligibleLibraries.where(selection.selects))
        buildGlobalKey(library.serverId, library.libraryId),
    };
    final participating = {
      for (final library in _catalog.participatingLibraries) buildGlobalKey(library.serverId, library.libraryId),
    };
    return wouldParticipate.length != participating.length || !wouldParticipate.containsAll(participating);
  }

  Future<void> _updatePreferences(UnifiedCatalogPreferences next) async {
    if (next == _preferences) return;
    setState(() => _preferences = next);
    unawaited(UnifiedCatalogQueryStore.write(widget.kind.mediaKind, next));
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _applyQuery();
  }

  /// [sheetContext] must sit *below* this screen's [OverlaySheetHost], so it
  /// cannot be the state's own `context`: the host is built inside [build],
  /// which makes it a descendant of that context and invisible to
  /// `OverlaySheetController.of`, which only looks upward. See the note on the
  /// host in [build] (CAT9).
  Future<void> _openSort(BuildContext sheetContext) async {
    final result = await showMobileCatalogSortSheet(sheetContext, current: _preferences.sort);
    if (result == null || !mounted) return;
    await _updatePreferences(_preferences.copyWith(sort: result));
  }

  Future<void> _openFilters(BuildContext sheetContext, {required MobileCatalogFilterSection initialSection}) async {
    final result = await showMobileCatalogFiltersSheet(
      sheetContext,
      selection: _preferences.filters,
      capabilities: _capabilities,
      libraries: _catalog.eligibleLibraries,
      clientFor: (serverId) => context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId)),
      initialSection: initialSection,
    );
    if (result == null || !mounted) return;
    await _updatePreferences(_preferences.copyWith(filters: result));
  }

  /// Live, not the stamped [UnifiedMediaSource.availability]: a freshly
  /// projected group's sources default to [SourceAvailability.unknown], and
  /// reading that would send every activation through the picker's
  /// no-usable-source path regardless of whether the server is actually up.
  SourceAvailability Function(UnifiedMediaSource source) get _availabilityFor {
    final manager = context.read<MultiServerProvider>().serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );
    return (source) => unifiedSourceAvailability(source, health);
  }

  Future<void> _openDetails(UnifiedMediaGroup group) => openMobileMediaGroup(
    context,
    group: group,
    intent: UnifiedActivationIntent.details,
    availabilityFor: _availabilityFor,
    coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
  );

  Future<void> _openQuickMenu(BuildContext cardContext, UnifiedMediaGroup group) async {
    final box = cardContext.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox) return;
    unawaited(HapticFeedback.mediumImpact());
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    await showMobileUnifiedQuickMenu(
      context,
      anchor: origin & box.size,
      group: group,
      availabilityFor: _availabilityFor,
      isOffline: context.read<OfflineModeProvider?>()?.isOffline ?? false,
      onPlay: () => unawaited(
        openMobileMediaGroup(
          context,
          group: group,
          intent: UnifiedActivationIntent.play,
          availabilityFor: _availabilityFor,
          coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
        ),
      ),
    );
  }

  /// "All sources" until something is excluded, then how many are left:
  /// same rule `TvUnifiedCatalogScreen._sourcesLabel` uses.
  String _sourcesLabel(UnifiedCatalogFilterSelection filters) {
    if (!filters.restrictsSources) return t.unifiedCatalog.allSources;
    final count = _catalog.participatingLibraries.map((l) => l.serverId.value).toSet().length;
    return formatSourceCount(count);
  }

  /// The right-hand half of the count row: what is actively narrowing the
  /// result, or nothing at all. Every item filter, not the sources:
  /// server/library restriction already shows on the sources chip, and
  /// repeating it here would say the same thing twice.
  String? _filterSummary(UnifiedCatalogFilterSelection filters) {
    final parts = <String>[];
    if (filters.watchState != UnifiedWatchFilter.all) parts.add(unifiedWatchFilterLabel(filters.watchState));
    if (filters.genres.isNotEmpty) parts.add((filters.genres.toList()..sort()).join(', '));
    if (filters.audioLanguages.isNotEmpty) {
      final languages = filters.audioLanguages.map((code) => languageDisplayName(code) ?? code).toList()..sort();
      parts.add(languages.join(', '));
    }
    if (filters.years.isNotEmpty) {
      final years = filters.years.toList()..sort();
      parts.add(years.length == 1 ? '${years.first}' : '${years.first}-${years.last}');
    }
    if (filters.officialRatings.isNotEmpty) parts.add(contentRatingLabels(filters.officialRatings).join(', '));
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Distance the finger has to travel in one direction before the top menu
  /// follows. Keeps a jittery thumb from flickering the header.
  static const double _headerScrollSlop = 12;

  /// Hide the top menu (title row and chips) on scroll down, bring it back on
  /// any scroll up, even mid-list, and always at the very top (A-06, decision
  /// Michel 20 Oct 2026). Overscroll at either end is ignored so a rubber-band
  /// bounce cannot flip it.
  bool _onHeaderScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) return false;
    final metrics = notification.metrics;
    if (metrics.pixels <= 0) {
      _headerScrollTravel = 0;
      _setHeaderHidden(false);
      return false;
    }
    if (notification is! ScrollUpdateNotification) return false;
    if (metrics.pixels > metrics.maxScrollExtent) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    // The last step of a bottom bounce travels back up without a finger on
    // the screen; it must not reveal the panel.
    if (delta < 0 && notification.dragDetails == null && metrics.pixels >= metrics.maxScrollExtent - 1) return false;
    // A reversal restarts the count, so only a sustained run changes the state.
    if (delta.sign != _headerScrollTravel.sign) _headerScrollTravel = 0;
    _headerScrollTravel += delta;
    if (_headerScrollTravel >= _headerScrollSlop) {
      _setHeaderHidden(true);
    } else if (_headerScrollTravel <= -_headerScrollSlop) {
      _setHeaderHidden(false);
    }
    return false;
  }

  /// Content that stops overflowing (source change, refresh, rotation to a
  /// larger viewport) leaves nothing to scroll back with, so the panel returns.
  void _onHeaderMetrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return;
    if (metrics.pixels <= 0 || metrics.maxScrollExtent <= 0) {
      _headerScrollTravel = 0;
      _setHeaderHidden(false);
    }
  }

  void _setHeaderHidden(bool hidden) {
    if (_headerHidden == hidden || !mounted) return;
    setState(() => _headerHidden = hidden);
  }

  void _onScroll() {
    final prefetcher = _prefetcher;
    if (prefetcher == null || !_scrollController.hasClients) return;
    final groups = _catalog.snapshot.groups;
    if (groups.isEmpty) return;
    final metrics = _scrollController.position;
    final columns = 3;
    final cardWidth = _cardWidth(metrics.viewportDimension);
    final cardHeight = cardWidth / (2 / 3) + MediaCardGridLayout.textExtentFor(context);
    final rowExtent = cardHeight + mobileRailGutter;
    final firstRow = (metrics.pixels / rowExtent).floor().clamp(0, 1 << 30);
    final visibleRows = (metrics.viewportDimension / rowExtent).ceil() + 1;
    final firstIndex = firstRow * columns;
    final lastIndex = ((firstRow + visibleRows) * columns - 1).clamp(0, groups.length - 1);
    prefetcher.prefetchAround(
      groups: groups,
      firstVisibleIndex: firstIndex,
      lastVisibleIndex: lastIndex,
      posterSize: Size(cardWidth, cardWidth / (2 / 3)),
      context: context,
    );
  }

  double _cardWidth(double viewportWidth) => (viewportWidth - mobileRailInset * 2 - mobileRailGutter * 2) / 3;

  @override
  Widget build(BuildContext context) {
    _prefetcher ??=
        widget.debugPrefetcher ??
        UnifiedArtworkPrefetcher(
          clientFor: (serverId) => context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId)),
        );
    final filters = _effectiveFilters;
    return AutomationScreen(
      id: widget.kind.screenAutomationId,
      readiness: () => !_preferencesLoaded || (_catalog.isInitialLoading && _catalog.snapshot.groups.isEmpty)
          ? const AutomationReadiness.loading('catalog')
          : const AutomationReadiness.ready(),
      // This screen carries its own host, the way every other pushed screen
      // does (hub detail, media detail, the Seerr detail). It is pushed by
      // `MobileLandingScreen._TitleRow` with `Navigator.of(context).push`,
      // which resolves to the profile navigator *above* `MainScreen` — and
      // `MainScreen.build` is what installs the host. The pushed route is
      // therefore a sibling of the host's owner, never a descendant, so
      // `OverlaySheetController.of` found nothing and all three chips were
      // dead: an assert in debug, a swallowed `scope!` in release (CAT9).
      child: OverlaySheetHost(
        // Mirrors the Seerr detail screen: keeps the iOS interactive
        // swipe-back, and a system back with a sheet open closes the sheet.
        canPop: PlatformDetector.isHandheldIOS(context),
        // `pop`, never `maybePop`: this callback *is* what the host's PopScope
        // runs when it refused the pop, so asking to pop again lands straight
        // back here. That loop hangs the route (it hung
        // `mobile_landing_screen_test`'s search-pops-back test outright).
        onSystemBack: () {
          final navigator = Navigator.of(context);
          if (mounted && navigator.canPop()) navigator.pop();
        },
        child: Builder(
          // Below the host, so the chips can reach it.
          builder: (sheetContext) {
            _schedulePanelMeasure();
            final safe = MediaQuery.paddingOf(context);
            final background = Theme.of(context).scaffoldBackgroundColor;
            return Scaffold(
              // The grid scrolls under the status bar, the top panel and the
              // home indicator; only the panel and two fades sit above it.
              body: Stack(
                children: [
                  // Hidden until the panel is measured, so the grid does not
                  // jump down one frame after it first appears.
                  // Left and right stay clear of a landscape cutout and the
                  // rounded corners, as the SafeArea before the panel did.
                  Positioned.fill(
                    left: safe.left,
                    right: safe.right,
                    child: Opacity(
                      key: const ValueKey('catalog.body'),
                      opacity: _panelMeasured ? 1 : 0,
                      child: _buildBody(filters),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    // Only while a grid is scrolling: an empty or loading body
                    // has nothing to scroll back with, so the panel stays put.
                    child: CatalogTopPanel(
                      collapsed: _headerHidden && _catalog.snapshot.groups.isNotEmpty,
                      background: background,
                      measureKey: _panelKey,
                      child: Padding(
                        padding: EdgeInsets.only(top: safe.top, left: safe.left, right: safe.right),
                        child: Column(
                          children: [
                            _buildHeader(),
                            _buildChips(sheetContext, filters),
                            if (context.watch<OfflineModeProvider?>()?.isOffline ?? false)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                                child: Text(t.localLibrary.offline),
                              ),
                            _buildFilterSummary(filters),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Status bar zone: stays when the panel is gone, so the
                  // clock and Dynamic Island keep a readable backdrop.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: safe.top + 12,
                    child: CatalogEdgeFade(color: background, fromTop: true),
                  ),
                  // Home indicator zone.
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: safe.bottom + 16,
                    child: CatalogEdgeFade(color: background, fromTop: false),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _schedulePanelMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _panelKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      if (_panelMeasured && (box.size.height - _panelHeight).abs() < 0.5) return;
      setState(() {
        _panelHeight = box.size.height;
        _panelMeasured = true;
      });
    });
  }

  Widget _buildHeader() {
    return AutomationNode(
      id: AutomationIds.catalogHeader,
      instance: widget.kind.automationInstance,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const AppIcon(Symbols.arrow_back_rounded, fill: 1),
            ),
            // Dense Library (variant 3): the count sits next to the title
            // instead of on a line of its own.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      widget.kind.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: AutomationNode(
                      id: AutomationIds.catalogCount,
                      instance: widget.kind.automationInstance,
                      role: 'region',
                      child: Text(
                        t.unifiedCatalog.titlesLoaded(count: _catalog.snapshot.groups.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: tokens(context).textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AutomationNode(
              id: AutomationIds.catalogHeaderSearch,
              instance: widget.kind.automationInstance,
              role: 'button',
              child: IconButton(
                onPressed: () {
                  if (!widget.isTabRoot) Navigator.of(context).maybePop();
                  widget.onSearchTap?.call();
                },
                icon: const AppIcon(Symbols.search_rounded),
                tooltip: t.common.search,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sources, Filters and Sort use the same compact line for Movies and Series.
  /// Long labels scroll as a group instead of making one catalogue two rows
  /// high while the other stays one row high.
  Widget _buildChips(BuildContext sheetContext, UnifiedCatalogFilterSelection filters) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: mobileRailInset),
      child: Row(
        children: [
          AutomationNode(
            id: AutomationIds.catalogChipSources,
            instance: widget.kind.automationInstance,
            role: 'button',
            child: FocusableFilterChip(
              variant: FilterChipVariant.toolbar,
              icon: Symbols.dns_rounded,
              label: _sourcesLabel(filters),
              onPressed: () => _openFilters(sheetContext, initialSection: MobileCatalogFilterSection.servers),
            ),
          ),
          const SizedBox(width: 8),
          AutomationNode(
            id: AutomationIds.catalogChipFilters,
            instance: widget.kind.automationInstance,
            role: 'button',
            child: FocusableFilterChip(
              variant: FilterChipVariant.toolbar,
              icon: Symbols.filter_list_rounded,
              label: t.unifiedCatalog.filters.title,
              badgeCount: filters.activeCount,
              onPressed: () => _openFilters(sheetContext, initialSection: MobileCatalogFilterSection.status),
            ),
          ),
          const SizedBox(width: 8),
          AutomationNode(
            id: AutomationIds.catalogChipSort,
            instance: widget.kind.automationInstance,
            role: 'button',
            child: FocusableFilterChip(
              variant: FilterChipVariant.toolbar,
              icon: Symbols.swap_vert_rounded,
              label: mobileCatalogSortLabel(_preferences.sort),
              onPressed: () => _openSort(sheetContext),
            ),
          ),
        ],
      ),
    );
  }

  /// What is narrowing the result, on a line of its own only while something
  /// does: an unfiltered catalogue spends no height on it.
  Widget _buildFilterSummary(UnifiedCatalogFilterSelection filters) {
    final summary = _filterSummary(filters);
    if (summary == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(mobileRailInset, 6, mobileRailInset, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          summary,
          key: const ValueKey('catalog.filterSummary'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: tokens(context).textMuted),
        ),
      ),
    );
  }

  Widget _buildBody(UnifiedCatalogFilterSelection filters) {
    final snapshot = _catalog.snapshot;

    if (!_preferencesLoaded || (_catalog.isInitialLoading && snapshot.groups.isEmpty)) {
      return Padding(
        padding: EdgeInsets.only(top: _panelHeight),
        // The body sits between the left and right safe edges; size to it.
        child: LayoutBuilder(
          builder: (context, constraints) => CatalogSkeletonGrid(cardWidth: _cardWidth(constraints.maxWidth)),
        ),
      );
    }

    if (snapshot.groups.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: _panelHeight),
        child: _buildEmptyState(filters, snapshot),
      );
    }
    return _buildGrid(filters, snapshot);
  }

  Widget _buildEmptyState(UnifiedCatalogFilterSelection filters, UnifiedCatalogSnapshot snapshot) {
    if (snapshot.initialLoadFailed || _catalog.loadFailed) {
      return CatalogEmptyState(
        title: t.unifiedCatalog.states.errorTitle,
        body: t.unifiedCatalog.states.errorBody,
        actionLabel: t.common.retry,
        onAction: _catalog.refresh,
      );
    }
    if (!filters.isEmpty) {
      return CatalogEmptyState(
        title: t.unifiedCatalog.states.filterEmptyTitle,
        body: t.unifiedCatalog.states.filterEmptyBody,
        actionLabel: t.unifiedCatalog.states.clearFilters,
        onAction: () => _updatePreferences(_preferences.copyWith(filters: UnifiedCatalogFilterSelection.empty)),
      );
    }
    return CatalogEmptyState(title: t.unifiedCatalog.states.emptyTitle, body: t.unifiedCatalog.states.emptyBody);
  }

  Widget _buildGrid(UnifiedCatalogFilterSelection filters, UnifiedCatalogSnapshot snapshot) {
    return MobileRefreshScope(
      onRefresh: _catalog.refresh,
      // The panel overlays the grid, so the spinner starts below it.
      edgeOffset: _panelHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = _cardWidth(constraints.maxWidth);
          final cardHeight = cardWidth / (2 / 3) + MediaCardGridLayout.textExtentFor(context);
          return NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              _onHeaderMetrics(notification.metrics);
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _onScroll();
                return _onHeaderScroll(notification);
              },
              child: ScrollCrown(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(mobileRailInset, _panelHeight + 8, mobileRailInset, 0),
                      sliver: AutomationNode(
                        id: AutomationIds.catalogGrid,
                        instance: widget.kind.automationInstance,
                        role: 'grid',
                        child: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: mobileRailGutter,
                            crossAxisSpacing: mobileRailGutter,
                            childAspectRatio: cardWidth / cardHeight,
                          ),
                          delegate: SliverChildBuilderDelegate((context, index) {
                            if (index >= snapshot.groups.length) {
                              if (snapshot.hasMore && !_catalog.isLoadingMore) {
                                unawaited(_catalog.loadMore());
                              }
                              return const SkeletonMediaCard();
                            }
                            final group = snapshot.groups[index];
                            return AutomationNode(
                              id: AutomationIds.catalogGridItem,
                              instance: '${widget.kind.automationInstance}.$index',
                              role: 'grid.item',
                              child: Builder(
                                builder: (cardContext) => MobileMediaCard(
                                  group: group,
                                  shape: MobileCardShape.portrait,
                                  width: cardWidth,
                                  onTap: () => _openDetails(group),
                                  onLongPress: () => unawaited(_openQuickMenu(cardContext, group)),
                                ),
                              ),
                            );
                          }, childCount: snapshot.groups.length + (snapshot.hasMore ? 3 : 0)),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
