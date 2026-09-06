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
/// asks for; it owns no source logic: activation goes through the same
/// `navigateToMediaItemDetails` call the rails above it already use, on the
/// group's representative source, not a second picker.
///
/// A push, not a tab state: `06-film-detail.png` shows the northstar's own
/// pushed detail screen still carrying the bottom bar with Films lit, which
/// today's `media_detail_screen.dart` push does not do either. The bar in
/// every northstar mockup is generic device chrome for the reviewer, not a
/// functional requirement, so this is a plain `Navigator.push` like a detail
/// page, not a new IndexedStack state.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/unified_catalog_provider.dart';
import '../../providers/unified_catalogs.dart';
import '../../services/unified_catalog/unified_artwork_prefetcher.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_catalog_query_store.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/media_card_grid_layout.dart';
import '../../widgets/mobile/mobile_catalog_filters_sheet.dart';
import '../../widgets/mobile/mobile_catalog_sort_sheet.dart';
import '../../widgets/mobile/mobile_media_card.dart';
import '../../widgets/mobile/mobile_media_rail.dart' show mobileRailGutter, mobileRailInset;
import '../../widgets/mobile/mobile_refresh_scope.dart';
import '../../widgets/skeleton_media_card.dart';

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
  const MobileCatalogScreen({super.key, required this.kind, this.onSearchTap, this.debugPrefetcher});

  final MobileCatalogKind kind;

  /// Closes this screen and opens search, the same target the landing's own
  /// header search action reaches. Threaded in from `_TitleRow` rather than
  /// reached directly: Search is a tab on `MainScreen`, which this push
  /// covers (see this file's own doc comment on why a push covers the bar),
  /// so search can only become visible again once this screen is gone.
  final VoidCallback? onSearchTap;

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
    final stored = await UnifiedCatalogQueryStore.read(widget.kind.mediaKind);
    if (!mounted) return;
    final pruned = stored.copyWith(
      filters: stored.filters.withKnownSources(knownServerIds: _knownServerIds, knownLibraryKeys: _knownLibraryKeys),
    );
    setState(() {
      _preferences = pruned;
      _preferencesLoaded = true;
    });
    if (pruned != stored) unawaited(UnifiedCatalogQueryStore.write(widget.kind.mediaKind, pruned));
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

  Future<void> _openSort() async {
    final result = await showMobileCatalogSortSheet(context, current: _preferences.sort);
    if (result == null || !mounted) return;
    await _updatePreferences(_preferences.copyWith(sort: result));
  }

  Future<void> _openFilters({required MobileCatalogFilterSection initialSection}) async {
    final result = await showMobileCatalogFiltersSheet(
      context,
      selection: _preferences.filters,
      capabilities: _capabilities,
      libraries: _catalog.eligibleLibraries,
      clientFor: (serverId) => context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId)),
      initialSection: initialSection,
    );
    if (result == null || !mounted) return;
    await _updatePreferences(_preferences.copyWith(filters: result));
  }

  Future<void> _openDetails(UnifiedMediaGroup group) =>
      navigateToMediaItemDetails(context, group.representativeSource.item);

  /// "All sources" until something is excluded, then how many are left:
  /// same rule `TvUnifiedCatalogScreen._sourcesLabel` uses.
  String _sourcesLabel(UnifiedCatalogFilterSelection filters) {
    if (!filters.restrictsSources) return t.unifiedCatalog.allSources;
    final count = _catalog.participatingLibraries.map((l) => l.serverId.value).toSet().length;
    return count == 1 ? t.unifiedCatalog.oneSource : t.unifiedCatalog.sources(count: count);
  }

  /// The right-hand half of the count row: what is actively narrowing the
  /// result, or nothing at all. Genre and year only: server/library
  /// restriction already shows on the sources chip, and repeating it here
  /// would say the same thing twice.
  String? _filterSummary(UnifiedCatalogFilterSelection filters) {
    final parts = <String>[];
    if (filters.genres.isNotEmpty) parts.add((filters.genres.toList()..sort()).join(', '));
    if (filters.years.isNotEmpty) {
      final years = filters.years.toList()..sort();
      parts.add(years.length == 1 ? '${years.first}' : '${years.first}-${years.last}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
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
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              _buildChips(filters),
              const SizedBox(height: 8),
              _buildCountRow(filters),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(filters)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AutomationNode(
      id: AutomationIds.catalogHeader,
      instance: widget.kind.automationInstance,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const AppIcon(Symbols.arrow_back_rounded, fill: 1),
            ),
            Expanded(
              child: Text(
                widget.kind.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            AutomationNode(
              id: AutomationIds.catalogHeaderSearch,
              instance: widget.kind.automationInstance,
              role: 'button',
              child: IconButton(
                onPressed: () {
                  Navigator.of(context).maybePop();
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

  Widget _buildChips(UnifiedCatalogFilterSelection filters) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: mobileRailInset),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            AutomationNode(
              id: AutomationIds.catalogChipSources,
              instance: widget.kind.automationInstance,
              role: 'button',
              child: FocusableFilterChip(
                icon: Symbols.dns_rounded,
                label: _sourcesLabel(filters),
                selected: filters.restrictsSources,
                onPressed: () => _openFilters(initialSection: MobileCatalogFilterSection.servers),
              ),
            ),
            const SizedBox(width: 8),
            _FilterChipWithBadge(
              automationId: AutomationIds.catalogChipFilters,
              automationInstance: widget.kind.automationInstance,
              badgeCount: filters.activeCount,
              chip: FocusableFilterChip(
                icon: Symbols.filter_list_rounded,
                label: t.unifiedCatalog.filters.title,
                selected: !filters.isEmpty,
                onPressed: () => _openFilters(initialSection: MobileCatalogFilterSection.status),
              ),
            ),
            const SizedBox(width: 8),
            AutomationNode(
              id: AutomationIds.catalogChipSort,
              instance: widget.kind.automationInstance,
              role: 'button',
              child: FocusableFilterChip(
                icon: Symbols.swap_vert_rounded,
                label: mobileCatalogSortLabel(_preferences.sort),
                onPressed: _openSort,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountRow(UnifiedCatalogFilterSelection filters) {
    final summary = _filterSummary(filters);
    return AutomationNode(
      id: AutomationIds.catalogCount,
      instance: widget.kind.automationInstance,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: mobileRailInset),
        child: Row(
          children: [
            Text(
              t.unifiedCatalog.titlesLoaded(count: _catalog.snapshot.groups.length),
              style: TextStyle(color: tokens(context).textMuted),
            ),
            if (summary != null) ...[
              const Spacer(),
              Flexible(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: tokens(context).textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(UnifiedCatalogFilterSelection filters) {
    final snapshot = _catalog.snapshot;

    if (!_preferencesLoaded || (_catalog.isInitialLoading && snapshot.groups.isEmpty)) {
      return _CatalogSkeletonGrid(cardWidth: _cardWidth(MediaQuery.sizeOf(context).width));
    }

    if (snapshot.groups.isEmpty) {
      if (snapshot.initialLoadFailed || _catalog.loadFailed) {
        return _EmptyState(
          title: t.unifiedCatalog.states.errorTitle,
          body: t.unifiedCatalog.states.errorBody,
          actionLabel: t.common.retry,
          onAction: _catalog.refresh,
        );
      }
      if (!filters.isEmpty) {
        return _EmptyState(
          title: t.unifiedCatalog.states.filterEmptyTitle,
          body: t.unifiedCatalog.states.filterEmptyBody,
          actionLabel: t.unifiedCatalog.states.clearFilters,
          onAction: () => _updatePreferences(_preferences.copyWith(filters: UnifiedCatalogFilterSelection.empty)),
        );
      }
      return _EmptyState(title: t.unifiedCatalog.states.emptyTitle, body: t.unifiedCatalog.states.emptyBody);
    }

    return MobileRefreshScope(
      onRefresh: _catalog.refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = _cardWidth(constraints.maxWidth);
          final cardHeight = cardWidth / (2 / 3) + MediaCardGridLayout.textExtentFor(context);
          return NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _onScroll();
              return false;
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(mobileRailInset, 8, mobileRailInset, 0),
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
                          child: MobileMediaCard(
                            group: group,
                            shape: MobileCardShape.portrait,
                            width: cardWidth,
                            onTap: () => _openDetails(group),
                          ),
                        );
                      }, childCount: snapshot.groups.length + (snapshot.hasMore ? 3 : 0)),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A [FocusableFilterChip] with a small badge on top, for the Filters chip's
/// active count (mockup 03). `FocusableFilterChip` itself has no badge
/// parameter and is reused too widely elsewhere to grow one for this single
/// caller, so the badge is a local composition rather than a shared-widget
/// change.
class _FilterChipWithBadge extends StatelessWidget {
  const _FilterChipWithBadge({
    required this.automationId,
    required this.automationInstance,
    required this.badgeCount,
    required this.chip,
  });

  final String automationId;
  final String automationInstance;
  final int badgeCount;
  final Widget chip;

  @override
  Widget build(BuildContext context) {
    return AutomationNode(
      id: automationId,
      instance: automationInstance,
      role: 'button',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                alignment: Alignment.center,
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 2:3 grid on its own geometry, before the first round of results
/// lands, same reasoning `TvCatalogSkeletonGrid` gives: the placeholder is
/// the page's own layout, not a centred spinner that gets replaced by a
/// differently-shaped wall of posters a frame later.
class _CatalogSkeletonGrid extends StatelessWidget {
  const _CatalogSkeletonGrid({required this.cardWidth});

  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final cardHeight = cardWidth / (2 / 3) + MediaCardGridLayout.textExtentFor(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowExtent = cardHeight + mobileRailGutter;
        final rows = constraints.maxHeight.isFinite ? (constraints.maxHeight / rowExtent).ceil().clamp(1, 6) : 3;
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: mobileRailInset, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var row = 0; row < rows; row++) ...[
                if (row > 0) const SizedBox(height: mobileRailGutter),
                Row(
                  children: [
                    for (var column = 0; column < 3; column++) ...[
                      if (column > 0) const SizedBox(width: mobileRailGutter),
                      SizedBox(width: cardWidth, height: cardHeight, child: const SkeletonMediaCard()),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: tk.textMuted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
