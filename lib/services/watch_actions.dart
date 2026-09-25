import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../providers/multi_server_provider.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/offline_watch_provider.dart';
import '../utils/haptics.dart';
import '../utils/provider_extensions.dart';
import '../utils/watch_state_notifier.dart';
import 'trackers/tracker_coordinator.dart';

enum WatchMarkOutcome {
  /// Queued for later sync: the item's own server could not take the write.
  /// The offline provider emitted the event.
  queuedOffline,

  /// Marked on the server; event emitted, trackers fired.
  marked,

  /// Nothing to do: the item names no server, so there is nothing to write to
  /// and no queue row to key.
  skipped,
}

/// Orchestrates watched/unwatched marks: routes offline marks to the offline
/// queue, online marks to the backend client, emits the single
/// [WatchStateNotifier] event, and fires trackers. UI surfaces call this
/// instead of hand-rolling the offline/online + tracker dance; snackbars and
/// refresh callbacks stay with the caller. Client `markWatched`/`markUnwatched`
/// are transport-only — they must never be called directly from UI code.
class WatchActions {
  WatchActions._();

  /// Marks [item] watched/unwatched. [offline] overrides the
  /// [OfflineModeProvider] read for callers that already know (e.g. screens
  /// rendering downloaded content).
  ///
  /// **Durability is decided per server, not app-wide.** The queue is keyed by
  /// `serverId`, so the only question that matters is whether *this item's*
  /// server can take the write. [OfflineModeProvider.isOffline] answers a
  /// different one: it is false as soon as any visible server is up. Routing on
  /// it alone sent a mark for a server that was down to the online branch,
  /// where [ProviderExtensions.tryGetMediaClientForServer] hands back the
  /// registered client regardless of health, and the write was lost. The same
  /// mark with every server down was queued and synced later.
  static Future<WatchMarkOutcome> setWatched(
    BuildContext context,
    MediaItem item, {
    required bool watched,
    bool? offline,
  }) async {
    Haptics.selection();
    final serverId = item.serverId;
    if (serverId == null) return WatchMarkOutcome.skipped;
    final id = ServerId(serverId);

    Future<WatchMarkOutcome> queueForLater() async {
      final offlineWatch = context.read<OfflineWatchProvider>();
      if (watched) {
        await offlineWatch.markAsWatched(serverId: id, itemId: item.id);
      } else {
        await offlineWatch.markAsUnwatched(serverId: id, itemId: item.id);
      }
      return WatchMarkOutcome.queuedOffline;
    }

    final isOffline = offline ?? context.read<OfflineModeProvider>().isOffline;
    // Short-circuits before the provider read, so a caller that already knows
    // it is offline does not need [MultiServerProvider] in its tree.
    final client = isOffline ? null : context.tryGetMediaClientForServer(id);
    if (client == null) return queueForLater();

    // [MultiServerManager.isServerOnline], not the provider's: the provider
    // narrows the same answer to the active profile's visible servers, and
    // that is a display scope, not a reachability one. Every other surface
    // that asks whether a source can be written to now resolves it here
    // (`unifiedSourceAvailability`), and the client lookup above is unfiltered
    // too. Filtering only this half would defer a write to a reachable server
    // while the TV menu, reading the unfiltered answer, reported it as done.
    final manager = context.read<MultiServerProvider>().serverManager;
    // A rejected token reads as not-online, but it is not something a
    // reconnect fixes, so it does not belong in a queue that waits for one.
    // The write is attempted, the 401 reaches the caller, and the caller puts
    // the re-auth prompt on screen. `tv_unified_context_actions` draws the
    // same line for its own fan-out.
    final authRejected = manager.authErrorServerIds.contains(serverId);
    if (!authRejected && !manager.isServerOnline(id)) return queueForLater();

    if (watched) {
      await client.markWatched(item);
    } else {
      await client.markUnwatched(item);
    }
    WatchStateNotifier().notifyWatched(item: item, isNowWatched: watched, cacheServerId: client.cacheServerId);
    unawaited(
      watched
          ? TrackerCoordinator.instance.markWatched(item, client)
          : TrackerCoordinator.instance.markUnwatched(item, client),
    );
    return WatchMarkOutcome.marked;
  }

  /// Removes [item] from Continue Watching without touching watch state.
  /// Throws when no client is bound for the item's server (mirrors the
  /// pre-existing menu behaviour so callers surface an error snackbar).
  static Future<void> removeFromContinueWatching(BuildContext context, MediaItem item) async {
    final client = context.getMediaClientForServer(ServerId(item.serverId!));
    await client.removeFromContinueWatching(item);
    WatchStateNotifier().notifyRemovedFromContinueWatching(item: item);
  }
}
