/// The activation path a Films or Series *landing* card shares with the
/// fase-5 catalog grid (`tv_unified_catalog_screen.dart`'s own `_activate`):
/// hand the whole [UnifiedMediaGroup] to `activateUnifiedMediaGroup`, which is
/// the one place hoofdstuk 4.4 allows a concrete `serverId:itemId` to be
/// chosen. No ranking, no representative-source shortcut, no second picker —
/// and no second copy of this wiring either, which is what a mixin is for
/// instead of pasting the fase-5 screen's version into two more files.
///
/// ## What differs from the fase-5 catalog's own activation
///
/// The catalog page scopes `catalogServerIds` to the libraries its own merge
/// is paging — the servers it can honestly claim to have already checked. A
/// discovery landing has no paging cursor to ask; its rows come from whatever
/// `DiscoverProvider` already fetched from every visible, online server, so
/// that visible/online set — not a catalog's `participatingLibraries` — is the
/// honest claim here. `resolveMoreSources` still exists to widen it exactly
/// like the catalog's does (hoofdstuk 14.5): a duplicate on a library
/// discovery never surfaced is not visible from either page's own fetch.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_route_context.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/api_cache.dart';
import '../../services/unified_catalog/source_resolver.dart';
import 'tv_media_source_picker_route.dart';
import 'tv_unified_activation.dart';

mixin TvDiscoveryActivationMixin<T extends StatefulWidget> on State<T> {
  SourceAllResolver? _resolver;
  String? _resolverProfileId;

  Future<void> activateDiscoveryGroup(
    UnifiedMediaGroup group, {
    VoidCallback? onManageServers,
    // Both default to the fase-6 discovery landing's own original call
    // shape — details intent, no direct-play — so this stays a pure
    // signature addition. The TV Home hero (hoofdstuk 9.5) is the first
    // caller to pass `intent: play, playDirectly: true` for its Afspelen
    // pill, since a hero press means "start this now", not "open the
    // details" the way a discovery tile press does.
    UnifiedActivationIntent intent = UnifiedActivationIntent.details,
    bool playDirectly = false,
  }) async {
    final multiServer = context.read<MultiServerProvider>();
    final manager = multiServer.serverManager;
    final health = unifiedServerHealth(
      isOnline: manager.isServerOnline,
      authErrorServerIds: manager.authErrorServerIds,
    );

    await activateUnifiedMediaGroup(
      context,
      group: group,
      intent: intent,
      playDirectly: playDirectly,
      environment: buildUnifiedActivationEnvironment(
        group: group,
        health: health,
        catalogServerIds: {
          for (final serverId in manager.serverIds)
            if (manager.isServerVisible(ServerId(serverId))) serverId,
        },
        // The provider notifies on every server health change, matching the
        // fase-5 catalog's own use of it for hoofdstuk 14.4.
        availabilityRevision: multiServer,
        resolver: _sourceResolver(multiServer),
        onManageServers: onManageServers,
      ),
    );
  }

  /// The hoofdstuk 12.8 fan-out, built once per profile — same caching
  /// rationale as the fase-5 catalog's own resolver: rebuilding it per
  /// activation would throw away its positive/negative cache between titles.
  SourceAllResolver? _sourceResolver(MultiServerProvider multiServer) {
    final profileId = context.read<ActiveProfileProvider>().activeId;
    if (profileId == null) return null;
    if (_resolver != null && _resolverProfileId == profileId) return _resolver;
    _resolverProfileId = profileId;
    final manager = multiServer.serverManager;
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    return _resolver = SourceAllResolver(
      profileId: profileId,
      serversFor: () => [
        for (final serverId in manager.serverIds)
          if (manager.isServerVisible(ServerId(serverId)))
            (
              serverId: ServerId(serverId),
              backend: manager.getClient(ServerId(serverId))?.backend ?? MediaBackend.plex,
              client: manager.getClient(ServerId(serverId)),
              online: manager.isServerOnline(ServerId(serverId)),
              hasAuthError: manager.authErrorServerIds.contains(serverId),
            ),
      ],
      // Library visibility, read live: the resolver is cached per profile and
      // must see a hide that lands after it was built. Server visibility is
      // already closed by the `isServerVisible` guard above; this closes the
      // other half, so a hidden library on a visible server cannot come back
      // as a picker row.
      hiddenLibraryKeysFor: () => hiddenLibraries.hiddenLibraryKeys,
      cache: ApiCache.forBackend(MediaBackend.plex),
    );
  }
}
