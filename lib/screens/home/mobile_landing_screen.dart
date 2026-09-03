/// The iPhone Series and Films landings. iOS Unified 2026 fase 2, mockups
/// `01-series-landing.png` and `02-films-landing.png`.
///
/// One screen for both, because the two mockups are the same surface over a
/// different set of hubs: the same header, the same large title, the same
/// rails, the same card family. The difference is which projection it reads
/// and what it is called, and that is what [MobileLandingKind] carries.
///
/// No hero and no Verder kijken. The landings show rails in provider order
/// (rapport §5), and Verder kijken lives on Home alone (DEC-086). Both
/// mockups confirm it.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../navigation/mobile_shell_scope.dart';
import '../../navigation/navigation_tabs.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/tv_discovery_landing_provider.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/mobile/mobile_discovery_slivers.dart';
import '../../widgets/mobile/mobile_media_rail.dart';
import '../../widgets/mobile/mobile_page_header.dart';
import '../../widgets/mobile/mobile_page_title_row.dart';
import '../../widgets/mobile/mobile_refresh_scope.dart';
import 'mobile_catalog_screen.dart';

/// Which half of the catalog a landing shows.
enum MobileLandingKind {
  series,
  movies;

  /// The page title: "Series" / "Films".
  String get title => switch (this) {
    MobileLandingKind.series => t.unifiedCatalog.seriesTitle,
    MobileLandingKind.movies => t.unifiedCatalog.moviesTitle,
  };

  /// The entry to the complete catalog: "Alle series" / "Alle films".
  String get viewAllLabel => switch (this) {
    MobileLandingKind.series => t.unifiedCatalog.discovery.allSeries,
    MobileLandingKind.movies => t.unifiedCatalog.discovery.allMovies,
  };

  List<UnifiedMediaHub> railsOf(TvDiscoveryLandingProvider landing) => switch (this) {
    MobileLandingKind.series => landing.seriesRails,
    MobileLandingKind.movies => landing.movieRails,
  };
}

class MobileLandingScreen extends StatelessWidget {
  final MobileLandingKind kind;

  const MobileLandingScreen({super.key, required this.kind});

  Future<void> _openDetails(BuildContext context, UnifiedMediaGroup group) async {
    await navigateToMediaItemDetails(context, group.representativeSource.item);
  }

  @override
  Widget build(BuildContext context) {
    final discover = context.watch<DiscoverProvider>();
    final landing = context.watch<TvDiscoveryLandingProvider>();
    final activeProfile = context.watch<ActiveProfileProvider?>()?.active;

    final hubs = kind.railsOf(landing);
    // The projection runs after DiscoverProvider settles, so the rails are
    // briefly empty on a screen that is no longer loading. Showing the
    // skeletons through that window is what keeps the surface from flashing an
    // empty page between the two.
    final isLoading = discover.isLoading || landing.isProjecting;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: MobileRefreshScope(
        onRefresh: discover.load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: MobilePageHeader(
                activeProfile: activeProfile,
                automationId: AutomationIds.landingHeader,
                onSearchTap: () => MobileShellScope.maybeOf(context)?.openTab(NavigationTabId.search),
              ),
            ),
            SliverToBoxAdapter(
              // The seam fase 2 left deliberately empty (DEC-093) now has the
              // surface it was waiting for. One line, as promised.
              child: MobilePageTitleRow(
                title: kind.title,
                viewAllLabel: kind.viewAllLabel,
                onViewAll: () => navigateToMobileCatalog(context, kind),
              ),
            ),
            ...mobileDiscoverySlivers(
              hubs: hubs,
              isLoading: isLoading,
              errorMessage: discover.errorMessage,
              onRetry: discover.load,
              onCardTap: (group) => _openDetails(context, group),
              surface: MobileRailSurface.landing,
              firstHubRailIndex: 0,
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomPadding + 16)),
          ],
        ),
      ),
    );
  }
}
