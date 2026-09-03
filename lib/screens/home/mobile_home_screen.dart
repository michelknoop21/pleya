/// The iPhone Home surface: header, chips, hero, Verder kijken, rails. iOS
/// Unified 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 8.
///
/// `DiscoverScreen._buildContent` picks this on `PlatformDetector.isPhone`;
/// desktop, iPad and TV keep their existing trees untouched. The three
/// headeractions (Nu aan het kijken, Samen kijken, Afstandsbediening) stay in
/// the header until fase 6 migrates the root navigation (DEC-091) — that is
/// why this header is fuller than the Home comp, a known, approved fase-1
/// deviation, not an oversight.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:provider/provider.dart';

import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_route_context.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/tv_discovery_landing_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../services/unified_catalog/mobile_activation.dart';
import '../../utils/home_hero_layout.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/video_player_navigation.dart';
import '../../widgets/media_card_grid_layout.dart';
import '../../widgets/mobile/mobile_chip_bar.dart';
import '../../widgets/mobile/mobile_hero_card.dart';
import '../../widgets/mobile/mobile_media_card.dart';
import '../../widgets/mobile/mobile_media_rail.dart';
import '../../widgets/mobile/mobile_page_header.dart';
import '../../widgets/mobile/mobile_refresh_scope.dart';
import '../../widgets/mobile/mobile_source_picker_sheet.dart';
import '../../widgets/skeletons.dart';
import '../libraries/content_state_builder.dart' show SliverErrorState;

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  MobileHomeChip _chip = MobileHomeChip.home;

  Future<void> _openDetails(UnifiedMediaGroup group) async {
    await navigateToMediaItemDetails(context, group.representativeSource.item);
  }

  Future<void> _play(UnifiedMediaGroup group) async {
    await activateMobileMediaGroup(
      context,
      group: group,
      intent: UnifiedActivationIntent.play,
      availabilityFor: (source) => source.availability,
      coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
      showPicker:
          ({
            required sources,
            required initialFocusSourceKey,
            preferredSourceKey,
            preferredServerId,
            required coverage,
          }) {
            return showMobileSourcePickerSheet(
              context,
              representative: group.representativeSource.item,
              sources: sources,
              preferredSourceKey: preferredSourceKey,
              currentSourceKey: initialFocusSourceKey,
              preferredServerId: preferredServerId,
              coverage: coverage,
            );
          },
      onRouted: (source) => navigateToVideoPlayer(context, metadata: source.item),
    );
  }

  /// The rail directly under the hero, so the hero-plus-first-rail viewport
  /// fill (`homeHeroHeight`) budgets against the right shape. Verder kijken
  /// (16:9) when it exists, else the first hub's shape (portrait 2:3).
  double _firstRailHeight(BuildContext context, {required bool wide}) {
    final cardWidth = wide ? mobileRailWideCardWidth : mobileRailCardWidth;
    final aspect = wide ? 16 / 9 : 2 / 3;
    const titleRowHeight = 28.0; // MobileMediaRail's title row + its gap.
    return titleRowHeight + cardWidth / aspect + MediaCardGridLayout.textExtentFor(context);
  }

  Widget _heroSliver(BuildContext context, SliverConstraints constraints, TvHomeProjectionProvider homeProjection) {
    final width = MediaQuery.sizeOf(context).width - 32;
    // The space this hero actually has, not the whole viewport: the header and
    // the chip bar are scrolled past before it starts. Measuring against the
    // full extent filled the hero down to the bottom bar and pushed the first
    // rail entirely below the fold, which is the one thing `homeHeroHeight`
    // exists to prevent.
    final available = constraints.viewportMainAxisExtent - constraints.precedingScrollExtent;
    final hasContinueWatching = homeProjection.continueWatching?.isEmpty == false;
    final height =
        homeHeroHeight(
          useSideNav: false,
          viewportExtent: available,
          screenHeight: MediaQuery.sizeOf(context).height,
          screenWidth: MediaQuery.sizeOf(context).width,
          statusBarHeight: MediaQuery.paddingOf(context).top,
          firstRailHeight: _firstRailHeight(context, wide: hasContinueWatching),
        ) -
        16;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MobileHeroCard(
          groups: homeProjection.heroGroups,
          width: width,
          height: height,
          onPlay: _play,
          onSecondaryAction: _openDetails,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discover = context.watch<DiscoverProvider>();
    final homeProjection = context.watch<TvHomeProjectionProvider>();
    final landing = context.watch<TvDiscoveryLandingProvider>();
    final layout = context.watch<HomeLayoutProvider>();
    final activeProfile = context.watch<ActiveProfileProvider?>()?.active;

    final rawHubs = switch (_chip) {
      MobileHomeChip.home => homeProjection.hubs,
      MobileHomeChip.series => landing.seriesRails,
      MobileHomeChip.movies => landing.movieRails,
    };
    final hubs = applyHomeLayoutToUnifiedRows(rawHubs, hiddenRowIds: layout.hiddenRowIds, order: layout.order);
    final continueWatching = _chip == MobileHomeChip.home ? homeProjection.continueWatching : null;

    final isLoading = discover.isLoading;
    final errorMessage = discover.errorMessage;
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
                onSearchTap: () {}, // Route to Zoeken lands in fase 4.
              ),
            ),
            SliverToBoxAdapter(
              child: MobileChipBar(selected: _chip, onSelected: (chip) => setState(() => _chip = chip)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (_chip == MobileHomeChip.home)
              SliverLayoutBuilder(builder: (context, constraints) => _heroSliver(context, constraints, homeProjection)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            if (isLoading)
              const SliverToBoxAdapter(child: Column(children: [SkeletonHubRow(), SkeletonHubRow(), SkeletonHubRow()])),
            if (errorMessage != null) SliverErrorState(message: errorMessage, onRetry: discover.load),
            if (!isLoading && errorMessage == null) ...[
              if (continueWatching != null && !continueWatching.isEmpty)
                SliverToBoxAdapter(
                  child: MobileMediaRail(
                    hub: continueWatching,
                    railIndex: 0,
                    shape: MobileCardShape.wide,
                    isContinueWatching: true,
                    onCardTap: _openDetails,
                  ),
                ),
              for (var i = 0; i < hubs.length; i++)
                SliverToBoxAdapter(
                  child: MobileMediaRail(hub: hubs[i], railIndex: i + 1, onCardTap: _openDetails),
                ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: bottomPadding + 16)),
          ],
        ),
      ),
    );
  }
}
