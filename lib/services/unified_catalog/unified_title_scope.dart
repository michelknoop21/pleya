/// Hands a detail page's [UnifiedTitlePlayback] to whatever starts a play or a
/// watched mark below it: the episode rows, the context menus, a nested season
/// page. They all end in `navigateToVideoPlayer` or `WatchActions`, and neither
/// should have to be told about a group by every caller.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_kids_profile_store.dart';
import '../../media/media_item.dart';
import '../../media/unified/unified_route_context.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/watch_state_store.dart';
import 'unified_title_playback.dart';

class UnifiedTitleScope extends InheritedWidget {
  const UnifiedTitleScope({super.key, required this.title, required super.child});

  final UnifiedTitlePlayback? title;

  /// Without a dependency: a play reads this once, it does not rebuild on it.
  static UnifiedTitlePlayback? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UnifiedTitleScope>()?.title;

  @override
  bool updateShouldNotify(UnifiedTitleScope oldWidget) => title != oldWidget.title;
}

/// What this profile may do with its servers, from the live providers.
UnifiedSourceGate? unifiedSourceGateOf(BuildContext context) {
  final multiServer = context.read<MultiServerProvider?>();
  if (multiServer == null) return null;
  final manager = multiServer.serverManager;
  final hiddenLibraries = context.read<HiddenLibrariesProvider?>();
  final profiles = context.read<ActiveProfileProvider?>();
  final watchState = context.read<WatchStateStore?>();
  MediaItem Function(MediaItem)? fresh;
  if (watchState != null) fresh = watchState.apply;
  return UnifiedSourceGate(
    clientFor: manager.getClient,
    isOnline: manager.isServerOnline,
    isAuthRejected: (serverId) => manager.authErrorServerIds.contains(serverId.value),
    isVisible: manager.isServerVisible,
    hiddenLibraryKeys: () => hiddenLibraries?.hiddenLibraryKeys ?? const {},
    isRestrictedProfile: () => assistantIsKidsProfile(profiles?.active),
    fresh: fresh,
  );
}

/// The title behind [route], or null when there is nothing to do across
/// sources: one source, or a route built without its group. Reads its gate
/// from the live providers, so it holds under a profile's own rights.
UnifiedTitlePlayback? unifiedTitleFor(BuildContext context, UnifiedMediaRouteContext? route) {
  if (route == null || !route.hasAlternativeSources || route.titleSources.length < 2) return null;
  final gate = unifiedSourceGateOf(context);
  if (gate == null) return null;
  return UnifiedTitlePlayback(routeContext: route, sources: route.titleSources, gate: gate);
}
