import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../exceptions/media_server_exceptions.dart';
import '../media/ids.dart';
import '../media/episode_collection.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../media/unified/unified_media_source.dart';
import '../media/unified/unified_watch_state.dart';
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
import 'unified_catalog/unified_copy_proof.dart';
import 'unified_catalog/unified_title_scope.dart';
import 'unified_catalog/watch_mark_order.dart';

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
    final copies = WatchCopyWriter.of(context);
    final stamp = WatchMarkOrder.next(item.globalKey);
    final outcome = await _setOne(context, item, watched: watched, offline: offline);
    if (outcome == WatchMarkOutcome.skipped) return outcome;
    // Nobody waits for the copies: a hung server must not hold the mark, and a
    // newer mark on this item stops what is still on its way.
    final reaching = _reachCopies(
      copies,
      known != null && known.holds(item) ? known : null,
      discovery,
      item,
      {item.globalKey, ...reachedElsewhere},
      watched: watched,
      isCurrent: (copy) =>
          WatchMarkOrder.isLatest(item.globalKey, stamp) && !WatchMarkOrder.markedAfter(copy.globalKey, stamp),
    );
    _reaching.add(reaching);
    unawaited(reaching.whenComplete(() => _reaching.remove(reaching)));
    return outcome;
  }

  static final Set<Future<void>> _reaching = {};

  /// Done when the copies of every mark so far are.
  @visibleForTesting
  static Future<void> copiesReached() => Future.wait(_reaching.toList());

  static Future<void> _reachCopies(
    WatchCopyWriter copies,
    UnifiedTitlePlayback? known,
    UnifiedTitleDiscovery? discovery,
    MediaItem item,
    Set<String> reached, {
    required bool watched,
    required bool Function(MediaItem copy) isCurrent,
  }) async {
    try {
      if (known != null) await copies.reachOtherSources(known, item, reached, watched: watched, isCurrent: isCurrent);
      final found = await discovery?.titleOf(item);
      if (found != null) await copies.reachOtherSources(found, item, reached, watched: watched, isCurrent: isCurrent);
    } catch (e, st) {
      appLogger.w('Could not reach the other sources of ${item.globalKey}', error: e, stackTrace: st);
    }
  }

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

    final queue = context.read<OfflineWatchProvider?>();
    final profileId = queue?.activeProfileId;
    if (watched) {
      await client.markWatched(item);
    } else {
      await client.markUnwatched(item);
    }
    await queue?.forgetHeldCopy(client, item, serverId: id, profileId: profileId);
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

/// What became of a mark on another copy.
enum WatchCopyOutcome {
  /// The server took it.
  written,

  /// Waiting in the queue for a server that can take it.
  held,

  /// Not for this copy: another cut, or a server someone else runs.
  leftAlone,

  /// It should have landed and did not, and waiting will not help.
  skipped,
}

/// Marks the other copies of a title: the server gets it, Trakt, the trackers
/// and the interactions do not. One mark is one viewing, however many servers
/// hold the title. Holds on to what it reads from the context: a lookup can
/// outlast the screen that started the mark.
class WatchCopyWriter {
  WatchCopyWriter(this._manager, this._queue, this._profiles)
    : _profileId = _profiles?.activeId,
      _queueProfileId = _queue?.activeProfileId;

  factory WatchCopyWriter.of(BuildContext context) => WatchCopyWriter(
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
  final String? _queueProfileId;

  /// The mark on [item] already landed: nothing a second server does undoes it
  /// or reaches the caller. Adds what it wrote to to [reached], and leaves a
  /// copy alone when [isCurrent] says a newer mark took over.
  Future<void> reachOtherSources(
    UnifiedTitlePlayback title,
    MediaItem item,
    Set<String> reached, {
    required bool watched,
    required bool Function(MediaItem copy) isCurrent,
  }) async {
    for (final copy in await title.copiesOf(item)) {
      if (!isCurrent(copy)) continue;
      if (reached.add(copy.globalKey) && runtimesAreComparable(item, copy)) await write(copy, watched: watched);
    }
  }

  /// Whether viewing data may go to [source]. Not when its server is known to be
  /// someone else's. One that is down stays in: the queue holds its write.
  bool isOwn(UnifiedMediaSource source) => !(_manager?.isSomeoneElsesServer(source.serverId) ?? false);

  static bool _isSpecial(MediaItem copy) =>
      (copy.isEpisode && isSpecialSeasonNumber(copy.parentIndex)) ||
      (copy.isSeason && isSpecialSeasonNumber(copy.index));

  /// The mark of [origin] on [copy], for a caller that fans out itself. Follows
  /// what [UnifiedTitlePlayback.copiesOf] does for a title: a card can hold two
  /// titles on title and year, another cut stays as it is, a Special has no
  /// copy, and a series only gets the seasons both sides hold.
  Future<WatchCopyOutcome> writeFor(
    UnifiedMediaSource origin,
    UnifiedMediaSource target, {
    required bool watched,
  }) async {
    final copy = target.item;
    if (!runtimesAreComparable(origin.item, copy) || !isOwn(target) || _isSpecial(copy)) {
      return WatchCopyOutcome.leftAlone;
    }
    final manager = _manager;
    if (manager == null) return WatchCopyOutcome.skipped;
    if (!await _proof.sameTitle(origin, target)) return WatchCopyOutcome.leftAlone;
    if (!copy.isShow) return write(copy, watched: watched);
    final seasons = await seasonsInCommon(origin.item, copy, clientFor: manager.getClient);
    var outcome = WatchCopyOutcome.skipped;
    for (final season in seasons) {
      final written = await write(season, watched: watched);
      if (outcome != WatchCopyOutcome.written) outcome = written;
    }
    return outcome;
  }

  late final _proof = UnifiedCopyProof(
    (id) => (_manager?.isServerOnline(id) ?? false) ? _manager?.getClient(id) : null,
  );

  Future<WatchCopyOutcome> write(MediaItem copy, {required bool watched}) async {
    final serverId = copy.serverId;
    if (serverId == null || _profiles?.activeId != _profileId) return WatchCopyOutcome.skipped;
    if (_manager?.isSomeoneElsesServer(ServerId(serverId)) ?? true) return WatchCopyOutcome.leftAlone;
    // A rejected token: a reconnect does not fix it, and a row would replay
    // under whoever signs in next.
    if (_manager?.authErrorServerIds.contains(serverId) ?? false) return WatchCopyOutcome.skipped;
    WatchMarkOrder.next(copy.globalKey);
    final id = ServerId(serverId);
    final client = _manager?.getClient(id);
    if (client != null && (_manager?.isServerOnline(id) ?? false)) {
      try {
        if (watched) {
          await client.markWatched(copy);
        } else {
          await client.markUnwatched(copy);
        }
        await _queue?.forgetHeldCopy(client, copy, serverId: id, profileId: _queueProfileId);
        WatchStateNotifier().notifyWatched(
          item: copy,
          isNowWatched: watched,
          cacheServerId: client.cacheServerId,
          isCopy: true,
        );
        return WatchCopyOutcome.written;
      } catch (e, st) {
        appLogger.w('Could not mark ${copy.globalKey}', error: e, stackTrace: st);
        // Waiting does not fix a refusal, and a row would replay under whoever
        // signs in next (hoofdstuk 13.2).
        if (!isRetryableServerWriteFailure(e)) return WatchCopyOutcome.skipped;
      }
    }
    if (_profiles?.activeId != _profileId) return WatchCopyOutcome.skipped;
    try {
      final held = await _queue?.markCopy(serverId: id, itemId: copy.id, watched: watched, profileId: _queueProfileId);
      return held == true ? WatchCopyOutcome.held : WatchCopyOutcome.skipped;
    } catch (e, st) {
      appLogger.w('Could not keep the mark on ${copy.globalKey}', error: e, stackTrace: st);
      return WatchCopyOutcome.skipped;
    }
  }
}

/// How [WatchActions.removeFromContinueWatching] took the title out.
enum ContinueWatchingRemoval { removedOnServer, hiddenOnDevice }
