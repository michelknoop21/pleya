/// What every mobile discovery surface draws below its header: the loading
/// skeletons, the error state, and the rails themselves.
///
/// Extracted from `MobileHomeScreen` when fase 2 added the Series and Films
/// landings, which show the same three states over a different set of hubs.
/// Behaviour-preserving: the three conditions stay independent of each other,
/// exactly as they were written inline, and Home passes the arguments that
/// reproduce its own rail numbering.
library;

import 'package:flutter/material.dart';

import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../screens/libraries/content_state_builder.dart' show SliverErrorState;
import '../skeletons.dart';
import 'mobile_media_card.dart';
import 'mobile_media_rail.dart';

/// Builds the sliver list. Returns slivers rather than a scroll view: the
/// caller owns the `CustomScrollView`, because what sits above these (header,
/// chips, hero) differs per surface.
List<Widget> mobileDiscoverySlivers({
  required List<UnifiedMediaHub> hubs,
  required bool isLoading,
  required String? errorMessage,
  required VoidCallback onRetry,
  required void Function(UnifiedMediaGroup group) onCardTap,
  required MobileRailSurface surface,

  /// Rail index of `hubs.first`. Home reserves 0 for Verder kijken and starts
  /// its hubs at 1, whether or not that row has anything in it, because fase 1
  /// pinned those ids. A landing has no Verder kijken (DEC-086) and starts at
  /// 0.
  required int firstHubRailIndex,

  /// Drawn above [hubs] at rail index 0, 16:9 and with the Continue Watching
  /// context-menu actions. Home only.
  UnifiedMediaHub? continueWatching,
}) {
  return [
    if (isLoading)
      const SliverToBoxAdapter(child: Column(children: [SkeletonHubRow(), SkeletonHubRow(), SkeletonHubRow()])),
    if (errorMessage != null) SliverErrorState(message: errorMessage, onRetry: onRetry),
    if (!isLoading && errorMessage == null) ...[
      if (continueWatching != null && !continueWatching.isEmpty)
        SliverToBoxAdapter(
          child: MobileMediaRail(
            hub: continueWatching,
            railIndex: 0,
            shape: MobileCardShape.wide,
            isContinueWatching: true,
            surface: surface,
            onCardTap: onCardTap,
          ),
        ),
      for (var i = 0; i < hubs.length; i++)
        SliverToBoxAdapter(
          child: MobileMediaRail(
            hub: hubs[i],
            railIndex: i + firstHubRailIndex,
            surface: surface,
            onCardTap: onCardTap,
          ),
        ),
    ],
  ];
}
