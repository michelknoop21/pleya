/// One row of the fase-8 Home content feed (hoofdstuk 27 fase 8's
/// `tv_content_row.dart`, north star 33.2).
///
/// ## Why this is a delegation and not a second rail
///
/// 33.2 draws Home's focused row and 33.3 draws the Films landing's, and they
/// are the same picture: one expanded 16:9 frame with a white ring, 2:3
/// neighbours at constant height, one metadata block underneath bounded to the
/// focused tile's width. That is [TvDiscoveryRail], built and proven in fase 6,
/// with widget tests, goldens and a focus contract already standing behind it.
///
/// So this file is the Home row's *name and boundary*, not a copy of its
/// mechanics. The roadmap names `tv_content_row.dart` as a fase-8 production
/// owner, and it is one: it is where the Home feed's row contract lives, what
/// the feed builds, and the single seam where Home's rows could ever diverge
/// from a landing's. Duplicating four hundred lines of focus nodes, scroll
/// controller, virtualisation and metadata layout to satisfy a filename would
/// have produced two implementations of one picture, which drift apart on their
/// first shared bug fix — the exact failure
/// `docs/tvos-unified-fase6-home-rows-deviation.md` argued against when it
/// declined to bend `tv_browse_rail.dart` into the unified shape one phase
/// early.
///
/// ## What the Home row does own
///
/// Two things the deviation moved into this phase, both blocking:
///
/// 1. **No duplicate logical title in one row.** Not enforced here — enforced
///    upstream, in `TvHomeProjectionProvider`'s projection, which is what makes
///    it correct rather than cosmetic: the row receives [UnifiedMediaGroup]s
///    that the identity pipeline already collapsed, with every concrete source
///    still on `group.sources`. A widget-level de-dupe would have had to guess
///    at identity from titles, which hoofdstuk 11.4 forbids.
/// 2. **Activation via the fase-4 coördinator.** [onActivate] takes the group,
///    never the item; the feed hands it straight to
///    `TvDiscoveryActivationMixin`. `navigateToMediaItem` does not appear on
///    this path at all, which is why a multi-source Home card now offers the
///    same picker as everywhere else instead of silently playing one server.
library;

import 'package:flutter/material.dart';

import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import 'tv_discovery_rail.dart';
import 'tv_unified_layout.dart';

class TvContentRow extends StatelessWidget {
  const TvContentRow({
    super.key,
    required this.hub,
    required this.onActivate,
    this.onContextMenu,
    required this.railKey,
    this.clientFor,
    this.initialFocusedGroupId,
    this.onFocusedGroupChanged,
    this.onNavigateUp,
    this.onNavigateDown,
    this.automationRailIndex,
  });

  /// A projected Home row: Continue Watching, or one of
  /// `TvHomeProjectionProvider.hubs`. Already unified, already deduplicated,
  /// already visibility-filtered — see the library doc.
  final UnifiedMediaHub hub;

  final ValueChanged<UnifiedMediaGroup> onActivate;

  /// Hoofdstuk 23's menu, handed straight down to the rail.
  final ValueChanged<UnifiedMediaGroup>? onContextMenu;

  /// Owned by the feed and keyed on [UnifiedMediaHub.hubId], so a
  /// re-projection that reorders rows keeps each row's own focus nodes and
  /// scroll position (hoofdstuk 17.5).
  final GlobalKey<TvDiscoveryRailState> railKey;

  final MediaServerClient? Function(String serverId)? clientFor;
  final String? initialFocusedGroupId;
  final ValueChanged<String>? onFocusedGroupChanged;

  /// Rail to rail, called with the column the step leaves from — see
  /// [TvDiscoveryRail.onNavigateUp]. UP that runs out of rows above goes back
  /// to the hero's last-used CTA.
  final ValueChanged<int>? onNavigateUp;

  final ValueChanged<int>? onNavigateDown;

  /// This row's position in the feed, for Pleya Verify addressing only.
  final int? automationRailIndex;

  /// The row's full vertical extent — heading, tile band, metadata block —
  /// constant by construction, so which tile holds the focus can never move
  /// the rows underneath it.
  static double height(double scale) => TvDiscoveryLayout.railSectionHeight(scale);

  @override
  Widget build(BuildContext context) {
    return TvDiscoveryRail(
      key: railKey,
      title: hub.title,
      groups: hub.groups,
      isPartial: hub.isPartial,
      clientFor: clientFor,
      initialFocusedGroupId: initialFocusedGroupId,
      onFocusedGroupChanged: onFocusedGroupChanged,
      onActivate: onActivate,
      onContextMenu: onContextMenu,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      automationRailIndex: automationRailIndex,
    );
  }
}
