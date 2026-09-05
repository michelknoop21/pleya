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
/// landing answers "show me everything of one kind". [DEC-094] records the
/// split.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/tv_discovery_landing_provider.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/mobile/mobile_media_rail.dart';
import '../../widgets/mobile/mobile_page_header.dart';
import '../../widgets/mobile/mobile_refresh_scope.dart';
import '../../widgets/skeletons.dart';
import '../libraries/content_state_builder.dart' show SliverEmptyState, SliverErrorState;

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

  UnifiedHubKind get hubKind => switch (this) {
    MobileLandingKind.series => UnifiedHubKind.show,
    MobileLandingKind.movies => UnifiedHubKind.movie,
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
}

class MobileLandingScreen extends StatelessWidget {
  final MobileLandingKind kind;

  /// Opens the search surface, the same callback Home's header gets.
  final VoidCallback? onSearchTap;

  const MobileLandingScreen({super.key, required this.kind, this.onSearchTap});

  Future<void> _openDetails(BuildContext context, UnifiedMediaGroup group) async {
    await navigateToMediaItemDetails(context, group.representativeSource.item);
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
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return AutomationScreen(
      id: kind.screenAutomationId,
      readiness: () => isLoading ? const AutomationReadiness.loading('hubs') : const AutomationReadiness.ready(),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: MobileRefreshScope(
          onRefresh: discover.load,
          child: CustomScrollView(
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
              SliverToBoxAdapter(child: _TitleRow(kind: kind)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              if (isLoading)
                const SliverToBoxAdapter(
                  child: Column(children: [SkeletonHubRow(), SkeletonHubRow(), SkeletonHubRow()]),
                ),
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
              SliverToBoxAdapter(child: SizedBox(height: bottomPadding + 16)),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Series` with `Alle series ›` on the same line, as the northstar draws it.
///
/// The action is **drawn and inert** until fase 3 builds the complete
/// catalogue behind it. Sending it to `LibraryBrowseTab` in the meantime was
/// rejected: that opens a library-bound, server-specific screen, while this
/// button promises a catalogue that spans every source. A button that does the
/// wrong thing is worse than one that cannot do it yet ([DEC-094]).
///
/// Inert means visible and not tappable, not greyed away: fase 3 puts one
/// handler underneath and nothing else changes.
class _TitleRow extends StatelessWidget {
  final MobileLandingKind kind;

  const _TitleRow({required this.kind});

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
              child: Text(
                kind.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
            ),
            AutomationNode(
              id: AutomationIds.landingViewAll,
              instance: kind.automationInstance,
              role: 'button',
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
          ],
        ),
      ),
    );
  }
}
