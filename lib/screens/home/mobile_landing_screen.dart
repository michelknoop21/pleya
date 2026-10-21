/// The iPhone Series and Films landings: header, title line with the
/// "Alle series"/"Alle films" action, and the landing rails. iOS Unified 2026
/// fase 2, `docs/ios-unified-2026-fase2-plan.md` stap 2, against the frozen
/// `01-series-landing.png` and `02-films-landing.png`.
///
/// One screen for both kinds rather than two near-identical files: the images
/// differ in the title, the action label and which projection they read, and
/// nothing else. [MobileLandingKind] is that difference, made explicit.
///
/// Deliberately no hero and no chip bar. Those belong to Home, which is a
/// different surface with a different question ("what should I watch"), while a
/// landing answers "show me everything of one kind". [DEC-104] records the
/// split.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../media/unified/unified_route_context.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/tv_discovery_landing_provider.dart';
import '../../screens/tv/tv_unified_activation.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../services/unified_catalog/mobile_media_source_picker_route.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/mobile/mobile_discovery_shell.dart';
import '../../widgets/mobile/mobile_media_rail.dart';
import '../../widgets/mobile/mobile_page_header.dart';
import '../libraries/content_state_builder.dart' show SliverEmptyState, SliverErrorState;
import 'mobile_catalog_screen.dart';

/// Which landing this is. Deliberately not [UnifiedHubKind], which has five
/// values: `episode`, `mixed` and `other` are rows Home keeps and no landing
/// can show, so a landing parameterised on that enum would have three cases
/// with no meaning.
enum MobileLandingKind {
  series,
  movies;

  /// The instance suffix that keeps this landing's automation ids apart from
  /// the other one's while both are mounted.
  String get automationInstance => name;

  /// The single-kind catalogue surface this landing shows — the same
  /// partition the Home chip filters on ([UnifiedHubKind.singleKindSurface]).
  UnifiedCatalogSurface get surface => switch (this) {
    MobileLandingKind.series => UnifiedCatalogSurface.series,
    MobileLandingKind.movies => UnifiedCatalogSurface.movies,
  };

  String get screenAutomationId => switch (this) {
    MobileLandingKind.series => AutomationIds.screenSeries,
    MobileLandingKind.movies => AutomationIds.screenMovies,
  };

  String get title => switch (this) {
    MobileLandingKind.series => t.unifiedCatalog.seriesTitle,
    MobileLandingKind.movies => t.unifiedCatalog.moviesTitle,
  };

  String get viewAllLabel => switch (this) {
    MobileLandingKind.series => t.unifiedCatalog.discovery.allSeries,
    MobileLandingKind.movies => t.unifiedCatalog.discovery.allMovies,
  };

  /// The complete-catalogue screen this landing's "Alle series/films ›"
  /// action opens (iOS Unified 2026 fase 3).
  MobileCatalogKind get catalogKind => switch (this) {
    MobileLandingKind.series => MobileCatalogKind.series,
    MobileLandingKind.movies => MobileCatalogKind.movies,
  };
}

class MobileLandingScreen extends StatelessWidget {
  final MobileLandingKind kind;

  /// Opens the search surface, the same callback Home's header gets.
  final VoidCallback? onSearchTap;

  const MobileLandingScreen({super.key, required this.kind, this.onSearchTap});

  Future<void> _openDetails(BuildContext context, UnifiedMediaGroup group) async {
    final manager = context.read<MultiServerProvider>().serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );
    await openMobileMediaGroup(
      context,
      group: group,
      intent: UnifiedActivationIntent.details,
      availabilityFor: (source) => unifiedSourceAvailability(source, health),
      coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discover = context.watch<DiscoverProvider>();
    final landing = context.watch<TvDiscoveryLandingProvider>();
    final layout = context.watch<HomeLayoutProvider>();
    final activeProfile = context.watch<ActiveProfileProvider?>()?.active;

    final rawHubs = switch (kind) {
      MobileLandingKind.series => landing.seriesRails,
      MobileLandingKind.movies => landing.movieRails,
    };
    final hubs = applyHomeLayoutToUnifiedRows(rawHubs, hiddenRowIds: layout.hiddenRowIds, order: layout.order);

    // Loading and error come from DiscoverProvider, not from the landing
    // provider: TvDiscoveryLandingProvider does no fetching of its own, has no
    // error surface, and reprojects whatever Discover already holds. Reading
    // its `isProjecting` here would show a skeleton for the reprojection and
    // nothing at all for the fetch that feeds it.
    final isLoading = discover.isLoading;
    final errorMessage = discover.errorMessage;

    return AutomationScreen(
      id: kind.screenAutomationId,
      readiness: () => isLoading ? const AutomationReadiness.loading('hubs') : const AutomationReadiness.ready(),
      child: mobileDiscoveryScaffold(
        context: context,
        onRefresh: discover.load,
        slivers: [
          SliverToBoxAdapter(
            child: MobilePageHeader(
              activeProfile: activeProfile,
              onSearchTap: onSearchTap ?? () {},
              automationId: AutomationIds.landingHeader,
              searchAutomationId: AutomationIds.landingHeaderSearch,
              avatarAutomationId: AutomationIds.landingHeaderAvatar,
              automationInstance: kind.automationInstance,
            ),
          ),
          SliverToBoxAdapter(
            child: _TitleRow(kind: kind, onSearchTap: onSearchTap),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          if (isLoading) mobileHubRowsSkeletonSliver,
          if (!isLoading && errorMessage != null) SliverErrorState(message: errorMessage, onRetry: discover.load),
          // A landing has no hero, so an empty projection is a blank page
          // rather than a page missing its rows. Home can leave this out;
          // this screen cannot.
          if (!isLoading && errorMessage == null && hubs.isEmpty)
            SliverEmptyState(
              message: t.unifiedCatalog.discovery.emptyTitle,
              icon: Symbols.inbox_rounded,
              subtitle: t.unifiedCatalog.discovery.emptyBody,
            ),
          if (!isLoading && errorMessage == null)
            for (var i = 0; i < hubs.length; i++)
              SliverToBoxAdapter(
                child: MobileMediaRail(
                  hub: hubs[i],
                  railIndex: i,
                  automationId: AutomationIds.landingRail,
                  itemAutomationId: AutomationIds.landingRailItem,
                  instancePrefix: kind.automationInstance,
                  onCardTap: (group) => _openDetails(context, group),
                ),
              ),
          mobileDiscoveryTailSliver(context),
        ],
      ),
    );
  }
}

/// `Series` with `Alle series ›` on the same line, as the northstar draws it.
///
/// The action opened the complete catalogue as of iOS Unified 2026 fase 3
/// (`docs/ios-unified-2026-fase3-plan.md`): a plain `Navigator.push` of
/// [MobileCatalogScreen], the same kind of push a detail card already is:
/// see that screen's own doc comment for why this is a push and not a tab
/// state. Before fase 3 the action was drawn and inert; fase 3 put exactly
/// one handler underneath and changed nothing else about this row.
class _TitleRow extends StatelessWidget {
  final MobileLandingKind kind;
  final VoidCallback? onSearchTap;

  const _TitleRow({required this.kind, this.onSearchTap});

  void _openCatalog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileCatalogScreen(kind: kind.catalogKind, onSearchTap: onSearchTap),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AutomationNode(
      id: AutomationIds.landingTitle,
      instance: kind.automationInstance,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(kind.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: mobileDiscoveryTitleStyle),
            ),
            AutomationNode(
              id: AutomationIds.landingViewAll,
              instance: kind.automationInstance,
              role: 'button',
              child: InkWell(
                onTap: () => _openCatalog(context),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kind.viewAllLabel,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: tokens(context).textMuted),
                    ),
                    Icon(Symbols.chevron_right_rounded, size: 20, color: tokens(context).textMuted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
