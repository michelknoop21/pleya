/// One horizontal row of [MobileMediaCard]s under a title, for
/// `MobileHomeScreen` and the fase-2 landings. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 4.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/offline_mode_provider.dart';
import '../../screens/tv/tv_unified_activation.dart';
import '../../theme/mono_tokens.dart';
import '../media_card_grid_layout.dart';
import 'mobile_media_card.dart';
import 'mobile_unified_context_menu.dart';

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

class MobileMediaRail extends StatelessWidget {
  final UnifiedMediaHub hub;
  final int railIndex;
  final MobileCardShape shape;
  final VoidCallback? onViewAll;
  final void Function(UnifiedMediaGroup group)? onCardTap;

  /// Continue Watching's rows offer "Remove from Continue Watching" in the
  /// long-press menu; other rails do not.
  final bool isContinueWatching;

  /// Automation ids for this rail, defaulting to Home's.
  ///
  /// The landings pass their own, for the reason `MobilePageHeader.automationId`
  /// spells out: Home, Series and Films live in one `IndexedStack` at the same
  /// time, so `home.rail[0]` would name three different rows at once.
  final String automationId;
  final String itemAutomationId;

  /// Prefix in front of the row index, so two surfaces sharing an id set stay
  /// apart: `landing.rail[series.0]` next to `landing.rail[movies.0]`.
  final String? instancePrefix;

  const MobileMediaRail({
    super.key,
    required this.hub,
    required this.railIndex,
    this.shape = MobileCardShape.portrait,
    this.onViewAll,
    this.onCardTap,
    this.isContinueWatching = false,
    this.automationId = AutomationIds.homeRail,
    this.itemAutomationId = AutomationIds.homeRailItem,
    this.instancePrefix,
  });

  /// `<railIndex>` on Home, `<prefix>.<railIndex>` on a landing.
  String get _railInstance => instancePrefix == null ? '$railIndex' : '$instancePrefix.$railIndex';

  @override
  Widget build(BuildContext context) {
    final cardWidth = shape == MobileCardShape.wide ? mobileRailWideCardWidth : mobileRailCardWidth;
    final aspect = shape == MobileCardShape.wide ? 16 / 9 : 2 / 3;
    final cardHeight = cardWidth / aspect + MediaCardGridLayout.textExtentFor(context);

    return AutomationNode(
      id: automationId,
      instance: _railInstance,
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
                    id: itemAutomationId,
                    instance: '$_railInstance.$index',
                    role: 'grid.item',
                    child: _RailCardCell(
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

/// One rail cell: tap opens detail on the group's representative source (a
/// read); long-press opens the unified, group-aware menu (I5, mockup 09) via
/// [showMobileUnifiedContextMenu] — markeer bekeken/onbekeken now reaches
/// every membership of [group], not just the representative one.
class _RailCardCell extends StatefulWidget {
  final UnifiedMediaGroup group;
  final MobileCardShape shape;
  final double width;
  final bool isContinueWatching;
  final VoidCallback? onTap;

  const _RailCardCell({
    required this.group,
    required this.shape,
    required this.width,
    required this.isContinueWatching,
    required this.onTap,
  });

  @override
  State<_RailCardCell> createState() => _RailCardCellState();
}

class _RailCardCellState extends State<_RailCardCell> {
  @override
  Widget build(BuildContext context) {
    return MobileMediaCard(
      group: widget.group,
      shape: widget.shape,
      width: widget.width,
      onTap: widget.onTap,
      onLongPress: () => unawaited(_showContextMenu(context)),
    );
  }

  Future<void> _showContextMenu(BuildContext context) async {
    final manager = context.read<MultiServerProvider>().serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );
    await showMobileUnifiedContextMenu(
      context,
      group: widget.group,
      availabilityFor: (source) => unifiedSourceAvailability(source, health),
      isInContinueWatching: widget.isContinueWatching,
      isOffline: context.read<OfflineModeProvider?>()?.isOffline ?? false,
    );
  }
}
