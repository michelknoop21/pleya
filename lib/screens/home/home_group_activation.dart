/// Opening a Home title on a touch device: the iPhone Home and the iPad hero
/// hand a [UnifiedMediaGroup] here and neither picks a source itself.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../media/unified/source_availability.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../media/unified/unified_route_context.dart';
import '../../providers/home_extra_rows_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/unified_catalog/mobile_media_source_picker_route.dart';
import '../tv/tv_unified_activation.dart';

/// Live, not the stamped [UnifiedMediaSource.availability]: a freshly
/// projected group's sources default to [SourceAvailability.unknown], and
/// reading that would send every activation through the picker's
/// no-usable-source path regardless of whether the server is actually up.
SourceAvailability Function(UnifiedMediaSource source) homeSourceAvailability(BuildContext context) {
  final manager = context.read<MultiServerProvider>().serverManager;
  final health = unifiedServerHealth(isOnline: manager.isServerOnline, authErrorServerIds: manager.authErrorServerIds);
  return (source) => unifiedSourceAvailability(source, health);
}

/// A Nu op tv card tunes its channel; every other title opens its detail page.
Future<void> openHomeGroupDetails(BuildContext context, UnifiedMediaGroup group) async {
  if (await context.read<HomeExtraRowsProvider?>()?.activateLiveTv(context, group) ?? false) return;
  if (!context.mounted) return;
  await openMobileMediaGroup(
    context,
    group: group,
    intent: UnifiedActivationIntent.details,
    availabilityFor: homeSourceAvailability(context),
    coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
  );
}

/// Afspelen. A stand-in hero slide can be a Nu op tv card, which tunes here too.
Future<void> playHomeGroup(BuildContext context, UnifiedMediaGroup group) async {
  if (await context.read<HomeExtraRowsProvider?>()?.activateLiveTv(context, group) ?? false) return;
  if (!context.mounted) return;
  await openMobileMediaGroup(
    context,
    group: group,
    intent: UnifiedActivationIntent.play,
    availabilityFor: homeSourceAvailability(context),
    coverage: SourceCoverageState.complete({for (final s in group.sources) s.serverId.value}),
    playDirectly: true,
  );
}
