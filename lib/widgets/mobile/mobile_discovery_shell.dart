/// The scaffold Home and a landing both build around their slivers:
/// Material over the theme's background, pull-to-refresh, a scrollable
/// list. Home and the landings differ in which slivers they put inside —
/// hero, chip bar, empty state — not in this shell.
library;

import 'package:flutter/material.dart';

import 'mobile_refresh_scope.dart';
import '../skeletons.dart';

/// The 34pt/w800 title style both Home's `Voor jou` heading and a landing's
/// title row draw.
const mobileDiscoveryTitleStyle = TextStyle(fontSize: 34, fontWeight: FontWeight.w800);

/// The three-row skeleton both Home and a landing show while loading.
const mobileHubRowsSkeletonSliver = SliverToBoxAdapter(
  child: Column(children: [SkeletonHubRow(), SkeletonHubRow(), SkeletonHubRow()]),
);

/// The tail sliver both screens use to clear the bottom bar / home indicator.
SliverToBoxAdapter mobileDiscoveryTailSliver(BuildContext context) =>
    SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16));

/// Material over the theme's background, wrapped in pull-to-refresh, over a
/// [CustomScrollView] of [slivers].
Widget mobileDiscoveryScaffold({
  required BuildContext context,
  required Future<void> Function() onRefresh,
  required List<Widget> slivers,
}) {
  return Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: MobileRefreshScope(onRefresh: onRefresh, child: CustomScrollView(slivers: slivers)),
  );
}
