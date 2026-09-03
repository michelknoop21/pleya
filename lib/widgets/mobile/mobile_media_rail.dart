/// One horizontal row of [MobileMediaCard]s under a title, for
/// `MobileHomeScreen` and the fase-2 landings. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 4.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../theme/mono_tokens.dart';
import '../media_card_grid_layout.dart';
import 'mobile_media_card.dart';
import 'mobile_media_card_cell.dart';

/// Card width so 3.3 cards sit in a 393pt-wide phone viewport (mockup 01):
/// inset 16 either side, gutter 12 between cards.
const double mobileRailCardWidth = 118;

/// Verder-kijken card width. Not northstar-pinned the way
/// [mobileRailCardWidth] is (H's "Verder kijken als 16:9-kaarten" has no
/// mockup with a measured card size) — chosen so roughly two cards show at
/// once, the usual continue-watching density.
const double mobileRailWideCardWidth = 220;

const double mobileRailGutter = 12;
const double mobileRailInset = 16;

/// Which surface a rail belongs to, and therefore which automation ids it
/// mounts.
///
/// The shell keeps every root destination alive in one `IndexedStack`, so Home
/// and both fase-2 landings are built at the same time. Were they all to mount
/// `home.rail`, a scenario asserting on `home.rail[0]` would be addressing
/// three different rails at once. The pair travels together because a rail and
/// its cards have to agree on which surface they are.
enum MobileRailSurface {
  home(AutomationIds.homeRail, AutomationIds.homeRailItem),
  landing(AutomationIds.landingRail, AutomationIds.landingRailItem);

  const MobileRailSurface(this.railId, this.itemId);

  final String railId;
  final String itemId;
}

class MobileMediaRail extends StatelessWidget {
  final UnifiedMediaHub hub;
  final int railIndex;
  final MobileCardShape shape;
  final VoidCallback? onViewAll;
  final void Function(UnifiedMediaGroup group)? onCardTap;

  /// Continue Watching's rows offer "Remove from Continue Watching" in the
  /// long-press menu; other rails do not.
  final bool isContinueWatching;

  /// Defaults to [MobileRailSurface.home] so fase 1's call sites and their
  /// pinned ids stay exactly as they were.
  final MobileRailSurface surface;

  const MobileMediaRail({
    super.key,
    required this.hub,
    required this.railIndex,
    this.shape = MobileCardShape.portrait,
    this.onViewAll,
    this.onCardTap,
    this.isContinueWatching = false,
    this.surface = MobileRailSurface.home,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidth = shape == MobileCardShape.wide ? mobileRailWideCardWidth : mobileRailCardWidth;
    final aspect = shape == MobileCardShape.wide ? 16 / 9 : 2 / 3;
    final cardHeight = cardWidth / aspect + MediaCardGridLayout.textExtentFor(context);

    return AutomationNode(
      id: surface.railId,
      instance: '$railIndex',
      role: 'rail',
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: mobileRailInset),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hub.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                if (onViewAll != null)
                  TextButton(
                    onPressed: onViewAll,
                    child: Text(
                      t.common.viewAll,
                      style: TextStyle(color: tokens(context).textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: cardHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: mobileRailInset),
              itemCount: hub.groups.length,
              itemBuilder: (context, index) {
                final group = hub.groups[index];
                return Padding(
                  padding: EdgeInsets.only(right: index == hub.groups.length - 1 ? 0 : mobileRailGutter),
                  child: AutomationNode(
                    id: surface.itemId,
                    instance: '$railIndex.$index',
                    role: 'grid.item',
                    child: MobileMediaCardCell(
                      group: group,
                      shape: shape,
                      width: cardWidth,
                      isContinueWatching: isContinueWatching,
                      onTap: onCardTap == null ? null : () => onCardTap!(group),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
