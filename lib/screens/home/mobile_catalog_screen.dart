/// "Alle films" and "Alle series": the complete unified catalogue on a phone.
/// iOS Unified 2026 fase 3, mockups `03-alle-films.png` and
/// `04-filters-sheet.png`.
///
/// One screen for both kinds, the way `MobileLandingScreen` is one screen for
/// both landings. `UnifiedCatalogs` already anticipated it — "the shared
/// catalog screen takes its provider as a constructor argument either way,
/// because it is deliberately kind-agnostic" — so the kind reaches this screen
/// as a title and a catalogue, and nothing below it branches on the two.
///
/// **Pushed above the shell, not mounted inside it** (DEC-094). Alle films is a
/// nested surface under the Films destination, not a sixth root destination:
/// Films → Alle films → detail → player is one stack, and the back arrow
/// mockup 03 draws is a real pop. The bottom bar is therefore not on screen
/// here, which is a known deviation from the frozen render of 03 and 06 rather
/// than an accident; both mockups draw the bar under a pushed page.
///
/// Distinct from `LibraryBrowseTab`, which stays exactly as it is. That screen
/// browses one library on one server, with its alpha jump bar and its
/// source-specific filters. This one browses every eligible library on every
/// eligible server as one merged, de-duplicated list — a different question,
/// and the reason rapport §5 keeps both.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../navigation/mobile_shell_scope.dart';
import '../../navigation/navigation_tabs.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/unified_catalog_provider.dart';
import '../../providers/unified_catalogs.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/mobile/mobile_catalog_grid.dart';
import '../../widgets/mobile/mobile_catalog_header.dart';
import '../../widgets/mobile/mobile_filter_categories.dart';
import '../../widgets/mobile/mobile_filter_sheet.dart';
import '../../widgets/mobile/mobile_refresh_scope.dart';
import '../../widgets/mobile/mobile_sort_sheet.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/skeletons.dart';
import '../libraries/content_state_builder.dart' show SliverErrorState;
import 'mobile_catalog_controller.dart';
import 'mobile_landing_screen.dart';

/// Pushes the catalogue for [kind] onto the profile session's navigator.
///
/// A plain `MaterialPageRoute` on the ambient navigator, the same way
/// `navigateToMediaItemDetails` pushes detail. That navigator is
/// `ProfileSessionScreen`'s, so the route lands inside `ProfileNavigationScope`
/// and everything it opens in turn — detail, the player — keeps working.
Future<void> navigateToMobileCatalog(BuildContext context, MobileLandingKind kind) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => MobileCatalogScreen(kind: kind)));
}

class MobileCatalogScreen extends StatefulWidget {
  final MobileLandingKind kind;

  const MobileCatalogScreen({super.key, required this.kind});

  @override
  State<MobileCatalogScreen> createState() => _MobileCatalogScreenState();
}

class _MobileCatalogScreenState extends State<MobileCatalogScreen> {
  MobileCatalogController? _controller;
  UnifiedCatalogProvider? _catalog;

  MediaKind get _mediaKind => widget.kind == MobileLandingKind.movies ? MediaKind.movie : MediaKind.show;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    // The catalogue itself lives in the profile subtree and outlives this
    // route, so navigating away and back returns to the same merge and the
    // same loaded pages. The controller is this route's own — it holds the
    // view settings, which are re-read from storage on each open.
    final catalog = context.read<UnifiedCatalogs>().forKind(_mediaKind);
    final controller = MobileCatalogController(
      catalog: catalog,
      kind: _mediaKind,
      clientFor: context.read<MultiServerProvider>().serverManager.getClient,
    );
    _catalog = catalog;
    _controller = controller;
    catalog.addListener(_onCatalogChanged);
    controller.addListener(_onCatalogChanged);
    controller.start();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _catalog?.removeListener(_onCatalogChanged);
    _controller
      ?..removeListener(_onCatalogChanged)
      ..dispose();
    super.dispose();
  }

  /// [sheetContext] must sit *below* this screen's own [OverlaySheetHost], so
  /// it is threaded in from the [Builder] under it rather than taken from
  /// `this.context` — which is above the host and finds no scope.
  Future<void> _openFilters(BuildContext sheetContext, MobileFilterCategory initial) async {
    final controller = _controller!;
    final applied = await showMobileFilterSheet(
      sheetContext,
      selection: controller.selection,
      capabilities: controller.capabilities,
      options: controller.options,
      eligibleLibraries: controller.eligibleLibraries,
      initialCategory: initial,
    );
    if (applied != null) await controller.setFilters(applied);
  }

  Future<void> _openSort(BuildContext sheetContext) async {
    final controller = _controller!;
    final chosen = await showMobileSortSheet(sheetContext, current: controller.sort);
    if (chosen != null) await controller.setSort(chosen);
  }

  Future<void> _openDetails(UnifiedMediaGroup group) =>
      navigateToMediaItemDetails(context, group.representativeSource.item);

  /// Three states rather than a bool, so a scenario waiting on this screen can
  /// tell a slow merge from a failed one instead of timing out on both.
  AutomationReadiness _readiness() {
    final controller = _controller;
    final catalog = _catalog;
    if (controller == null || catalog == null) return const AutomationReadiness.loading('controller');
    if (!controller.isReady) return const AutomationReadiness.loading('preferences');
    if (catalog.isInitialLoading) return const AutomationReadiness.loading('catalog');
    if (catalog.loadFailed || catalog.snapshot.initialLoadFailed) {
      return const AutomationReadiness.error('catalog');
    }
    return const AutomationReadiness.ready();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final catalog = _catalog!;
    final isLoading = !controller.isReady || catalog.isInitialLoading;

    return AutomationScreen(
      id: AutomationIds.screenCatalog,
      readiness: _readiness,
      // Its own host, like every other pushed screen (`media_detail_screen`,
      // `hub_detail_screen`, `seerr_media_detail_screen`, …). The shell mounts
      // one in `main_screen.dart`, but this route sits *above* the shell, so
      // `OverlaySheetController.of` would find nothing and the filter and sort
      // sheets would fail to open. A simulator probe is what caught it: the
      // widget tests each mounted a host themselves, so none of them could.
      child: OverlaySheetHost(
        child: Builder(
          builder: (sheetContext) => Scaffold(
            body: MobileRefreshScope(
              onRefresh: catalog.refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  _maybeLoadMore(notification, catalog);
                  return false;
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: MobileCatalogHeader(
                        title: widget.kind.viewAllLabel,
                        onBack: () => Navigator.of(context).maybePop(),
                        onSearch: () => MobileShellScope.maybeOf(context)?.openTab(NavigationTabId.search),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: MobileCatalogControls(
                        restrictedSourceCount: controller.restrictedSourceCount,
                        activeFilterCount: controller.activeFilterCount,
                        sort: controller.sort,
                        onSources: () => _openFilters(sheetContext, MobileFilterCategory.servers),
                        onFilters: () => _openFilters(sheetContext, MobileFilterCategory.status),
                        onSort: () => _openSort(sheetContext),
                      ),
                    ),
                    ..._body(controller: controller, catalog: catalog, isLoading: isLoading),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Asks for the next page once the grid is within one viewport of its end.
  ///
  /// One viewport of lead time rather than the exact bottom: `loadMore` fans
  /// out to every participating library and merges what comes back, so a
  /// trigger at the last pixel would always show the spinner. The provider
  /// itself drops a re-entrant call, so a burst of scroll notifications during
  /// a fetch costs nothing.
  void _maybeLoadMore(ScrollNotification notification, UnifiedCatalogProvider catalog) {
    if (notification.metrics.axis != Axis.vertical) return;
    if (catalog.isLoadingMore || catalog.isInitialLoading || !catalog.snapshot.hasMore) return;
    final metrics = notification.metrics;
    if (!metrics.hasContentDimensions) return;
    if (metrics.pixels < metrics.maxScrollExtent - metrics.viewportDimension) return;
    catalog.loadMore();
  }

  List<Widget> _body({
    required MobileCatalogController controller,
    required UnifiedCatalogProvider catalog,
    required bool isLoading,
  }) {
    final snapshot = catalog.snapshot;

    if (isLoading) {
      return const [
        SliverToBoxAdapter(child: Column(children: [SkeletonHubRow(), SkeletonHubRow()])),
      ];
    }

    // Two separate failures, and a user can only act on one of them. The
    // provider's own `loadFailed` covers "nothing was even asked"; the
    // snapshot's covers "everything that was asked failed". Either leaves the
    // grid with nothing to draw, so both take the full-page error.
    if (catalog.loadFailed || snapshot.initialLoadFailed) {
      return [SliverErrorState(message: t.unifiedCatalog.states.errorBody, onRetry: catalog.refresh)];
    }

    if (snapshot.groups.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _EmptyState(
            hasFilters: controller.activeFilterCount > 0 || controller.selection.restrictsSources,
            onClear: controller.clearFilters,
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: MobileCatalogStatusLine(
          loadedCount: snapshot.groups.length,
          filterSummary: mobileActiveFilterSummary(
            selection: controller.selection,
            capabilities: controller.capabilities,
          ),
        ),
      ),
      MobileCatalogGrid(groups: snapshot.groups, onCardTap: _openDetails),
      SliverToBoxAdapter(
        child: MobileCatalogFooter(
          isLoadingMore: catalog.isLoadingMore,
          hasMore: snapshot.hasMore,
          onLoadMore: catalog.loadMore,
          failedLibraryCount: snapshot.failedLibraryIds.length,
        ),
      ),
    ];
  }
}

/// Empty with filters and empty without are different situations with
/// different exits, so they get different words and only one of them offers a
/// button.
class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  final VoidCallback onClear;

  const _EmptyState({required this.hasFilters, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
      child: Column(
        children: [
          Text(
            hasFilters ? t.unifiedCatalog.states.filterEmptyTitle : t.unifiedCatalog.states.emptyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters ? t.unifiedCatalog.states.filterEmptyBody : t.unifiedCatalog.states.emptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onClear, child: Text(t.unifiedCatalog.states.clearFilters)),
          ],
        ],
      ),
    );
  }
}
