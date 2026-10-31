import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../exceptions/media_server_exceptions.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/continue_watching_hidden_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/offline_watch_provider.dart';
import '../utils/app_logger.dart';
import '../utils/haptics.dart';
import '../utils/provider_extensions.dart';
import '../utils/watch_state_notifier.dart';
import 'trackers/tracker_coordinator.dart';
import 'multi_server_manager.dart';
import 'unified_catalog/unified_title_discovery.dart';
import 'unified_catalog/unified_title_playback.dart';
import 'unified_catalog/unified_title_scope.dart';

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
  ///
  /// [unifiedTitle] is the title [item] belongs to, read from the
  /// [UnifiedTitleScope] above [context] when omitted: the mark then reaches
  /// every other source of it. A title can have more sources than its card
  /// showed, so the rest is looked up afterwards, without anyone waiting.
  /// [reachedElsewhere] names the sources a caller handles itself.
  static Future<WatchMarkOutcome> setWatched(
    BuildContext context,
    MediaItem item, {
    required bool watched,
    bool? offline,
    UnifiedTitlePlayback? unifiedTitle,
    Set<String> reachedElsewhere = const {},
  }) async {
    Haptics.selection();
    final known = unifiedTitle ?? UnifiedTitleScope.maybeOf(context);
    final discovery = offline == true ? null : UnifiedTitleDiscovery.of(context);
    final copies = _CopyWriter.of(context);
    final outcome = await _setOne(context, item, watched: watched, offline: offline);
    if (outcome == WatchMarkOutcome.skipped) return outcome;
    final reached = {item.globalKey, ...reachedElsewhere};
    if (known != null && known.holds(item)) await copies.reachOtherSources(known, item, reached, watched: watched);
    if (discovery != null) unawaited(_reachFound(copies, discovery, item, reached, watched: watched));
    return outcome;
  }

  static Future<void> _reachFound(
    _CopyWriter copies,
    UnifiedTitleDiscovery discovery,
    MediaItem item,
    Set<String> reached, {
    required bool watched,
  }) async {
    final title = await discovery.titleOf(item);
    if (title != null) await copies.reachOtherSources(title, item, reached, watched: watched);
  }

  /// The mark on one more copy of a title that was marked already: the server
  /// gets it, Trakt, the trackers and the interactions do not. One mark is one
  /// viewing, however many servers hold the title. Falls back to the queue, so
  /// this does not throw for a server that refuses.
  static Future<WatchMarkOutcome> markCopy(BuildContext context, MediaItem item, {required bool watched}) =>
      _CopyWriter.of(context).write(item, watched: watched);

  static Future<WatchMarkOutcome> _setOne(
    BuildContext context,
    MediaItem item, {
    required bool watched,
    bool? offline,
  }) async {
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

  /// Takes [item] out of Continue Watching without touching watch state: the
  /// one path every menu goes through (DEC-144 fase 3).
  ///
  /// A source that can remove server-side is removed there. One that cannot
  /// (Jellyfin, Emby, local folders) is hidden on this device instead, through
  /// [ContinueWatchingHiddenProvider]; that used to throw `UnsupportedError`
  /// out of the tvOS menu. Either way the row drops the card at once.
  ///
  /// Throws when no client is bound for the item's server (callers surface an
  /// error snackbar), and when a local hide is needed but no hidden store is
  /// in scope.
  static Future<ContinueWatchingRemoval> removeFromContinueWatching(BuildContext context, MediaItem item) async {
    final client = context.getMediaClientForServer(ServerId(item.serverId!));
    // Read before the first await; the surface may be gone afterwards.
    final hidden = context.read<ContinueWatchingHiddenProvider?>();
    if (client.capabilities.continueWatchingRemoval) {
      await client.removeFromContinueWatching(item);
      WatchStateNotifier().notifyRemovedFromContinueWatching(item: item);
      return ContinueWatchingRemoval.removedOnServer;
    }
    if (hidden == null) {
      throw UnsupportedError('No hidden store in scope to hide ${item.globalKey} from Continue Watching');
    }
    await hidden.hide(item);
    WatchStateNotifier().notifyRemovedFromContinueWatching(item: item);
    return ContinueWatchingRemoval.hiddenOnDevice;
  }
}

/// Marks the other copies of a title. Holds on to what it reads from the
/// context: a lookup can outlast the screen that started the mark.
class _CopyWriter {
  _CopyWriter(this._manager, this._queue, this._profiles) : _profileId = _profiles?.activeId;

  factory _CopyWriter.of(BuildContext context) => _CopyWriter(
    context.read<MultiServerProvider?>()?.serverManager,
    context.read<OfflineWatchProvider?>(),
    context.read<ActiveProfileProvider?>(),
  );

  final MultiServerManager? _manager;
  final OfflineWatchProvider? _queue;
  final ActiveProfileProvider? _profiles;

  /// Who marked it. A lookup can outlast a profile switch, and the next
  /// profile's token has no business writing this mark.
  final String? _profileId;

  /// The mark on [item] already landed: nothing a second server does undoes it
  /// or reaches the caller. Adds what it wrote to to [reached].
  Future<void> reachOtherSources(
    UnifiedTitlePlayback title,
    MediaItem item,
    Set<String> reached, {
    required bool watched,
  }) async {
    try {
      for (final copy in await title.copiesOf(item)) {
        if (reached.add(copy.globalKey)) await write(copy, watched: watched);
      }
    } catch (e, st) {
      appLogger.w('Could not reach the other sources of ${item.globalKey}', error: e, stackTrace: st);
    }
  }

  Future<WatchMarkOutcome> write(MediaItem copy, {required bool watched}) async {
    final serverId = copy.serverId;
    if (serverId == null || _profiles?.activeId != _profileId) return WatchMarkOutcome.skipped;
    final id = ServerId(serverId);
    final client = _manager?.getClient(id);
    if (client != null && (_manager?.isServerOnline(id) ?? false)) {
      try {
        if (watched) {
          await client.markWatched(copy);
        } else {
          await client.markUnwatched(copy);
        }
        WatchStateNotifier().notifyWatched(
          item: copy,
          isNowWatched: watched,
          cacheServerId: client.cacheServerId,
          isCopy: true,
        );
        return WatchMarkOutcome.marked;
      } catch (e, st) {
        appLogger.w('Could not mark ${copy.globalKey}', error: e, stackTrace: st);
        // Waiting does not fix a refusal, and a row would replay under whoever
        // signs in next (hoofdstuk 13.2).
        if (!isRetryableServerWriteFailure(e)) return WatchMarkOutcome.skipped;
      }
    }
    try {
      await _queue?.markCopy(serverId: id, itemId: copy.id, watched: watched);
    } catch (e, st) {
      appLogger.w('Could not keep the mark on ${copy.globalKey}', error: e, stackTrace: st);
      return WatchMarkOutcome.skipped;
    }
    return WatchMarkOutcome.queuedOffline;
  }
}

/// How [WatchActions.removeFromContinueWatching] took the title out.
enum ContinueWatchingRemoval { removedOnServer, hiddenOnDevice }
