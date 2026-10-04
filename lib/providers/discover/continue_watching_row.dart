import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../services/data_aggregation_service.dart';
import '../../services/settings_service.dart';
import '../../services/system_shelf_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/watch_state_notifier.dart';
import '../continue_watching_hidden_provider.dart';
import '../hidden_libraries_provider.dart';
import '../multi_server_provider.dart';

/// The Continue Watching row of Home: the whole on-deck list and its preview, the
/// titles hidden on this device or waiting in the removal queue, the
/// watched-movie suppression that beats the scrobble race, the reaction to
/// watch events, and the platform launcher shelf that mirrors the row. The
/// owning provider decides when to fetch and when a full load bumps its
/// generation; this class only holds and publishes the row.
class ContinueWatchingRow {
  ContinueWatchingRow({
    required this._multiServer,
    required this._hiddenLibraries,
    required this._isDisposed,
    required this._notify,
    this.hidden,
    this.pendingRemovalKeys,
  }) {
    _lastHiddenKeys = hidden?.keys ?? const {};
    hidden?.addListener(_onHiddenChanged);
  }

  /// The row shows the first 20 of [all]; the whole list is fetched so the
  /// title can count it and the overview reads it from memory (DEC-144 fase 2).
  static const int previewLimit = 20;

  final MultiServerProvider _multiServer;
  final HiddenLibrariesProvider _hiddenLibraries;
  final bool Function() _isDisposed;
  final VoidCallback _notify;

  /// Titles hidden from Verder kijken on this device (DEC-144 fase 3). Filtered
  /// out of every fetch; a restore brings the title back on the next one.
  final ContinueWatchingHiddenProvider? hidden;
  Set<String> _lastHiddenKeys = const {};

  /// Global keys of removals still queued for a server that was unreachable,
  /// so a card dismissed before a restart does not come back while its write
  /// is still waiting (hoofdstuk 13.4 point 3).
  final Future<Set<String>> Function()? pendingRemovalKeys;

  /// Kept apart from [_suppressedKeys] on purpose. That set cleans itself as
  /// soon as a fetch no longer lists a key, and a server that is still
  /// unreachable lists nothing, so a queued removal folded into it would be
  /// forgotten on the first fetch and its card would return the moment the
  /// server reconnected, before the replay. This one is re-read from the queue
  /// and empties only when the queue row does.
  Set<String> _queuedRemovalKeys = const {};

  List<MediaItem> _all = const [];
  List<MediaItem> _items = [];

  /// False while [all] came from a snapshot (which only ever held the row), so
  /// the overview still fetches instead of trusting a 20-item "all".
  bool allFromNetwork = false;

  /// Global keys of watched movies filtered out of every apply until the
  /// server stops returning them — beats the scrobble race deterministically
  /// (see [onWatchStateChanged] / [apply]).
  final Set<String> _suppressedKeys = {};

  /// Online servers whose Continue Watching fetch succeeded in the current
  /// list. Tracked separately from hubs so a transient failure in one surface
  /// does not cache the other as loaded forever or force unnecessary
  /// refetches.
  Set<String> loadedServerIds = {};

  Future<void>? _systemShelfSyncFuture;
  List<MediaItem>? _pendingSystemShelfItems;
  List<MediaItem> _topShelfHero = const [];

  List<MediaItem> get items => _items;

  /// Everything in Verder kijken after merging, deduplicating and hiding.
  List<MediaItem> get all => _all;

  /// Reads the hidden list and the removal queue. Awaited before a fetch is
  /// started, never between starting and awaiting one.
  Future<void> prepare() async {
    await hidden?.ensureInitialized();
    await readQueuedRemovalKeys();
  }

  Future<void> readQueuedRemovalKeys() async {
    final read = pendingRemovalKeys;
    if (read == null) return;
    try {
      _queuedRemovalKeys = await read();
    } catch (e) {
      appLogger.d('ContinueWatchingRow: queued removal keys unavailable', error: e);
    }
  }

  /// The whole on-deck list, from every server or only [serverIds].
  Future<OnDeckAggregationResult> fetch({Set<String>? serverIds}) {
    return _multiServer.aggregationService.getOnDeckFromAllServers(
      hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
      serverIds: serverIds,
    );
  }

  /// Merges [fresh] from newly-online servers into the stored list. Returns
  /// false when the owner was disposed while the merge ran.
  Future<bool> merge(OnDeckAggregationResult fresh) async {
    final merged = await _multiServer.aggregationService.mergeContinueWatching(_all, fresh.items);
    if (_isDisposed()) return false;
    apply(merged);
    loadedServerIds = {...loadedServerIds, ...fresh.succeededServerIds};
    return true;
  }

  /// Background refresh of Continue Watching only — never flips load states
  /// or surfaces errors (a stale row beats an error flash), never refetches
  /// hubs.
  Future<void> refresh() async {
    try {
      if (!_multiServer.hasConnectedServers) return;
      await readQueuedRemovalKeys();
      final fetched = await fetch();
      if (_isDisposed()) return;
      apply(fetched.items, fromNetwork: true);
      loadedServerIds = fetched.succeededServerIds;
      _notify();
      unawaited(syncShelf());
    } catch (e) {
      appLogger.w('Failed to refresh Continue Watching', error: e);
    }
  }

  /// The full Continue Watching list for the overview: from memory once a
  /// network load holds it, fetched otherwise.
  Future<List<MediaItem>> loadAll({required bool loaded}) async {
    if (loaded && allFromNetwork) return _all;
    if (!_multiServer.hasConnectedServers) return const [];
    await _hiddenLibraries.ensureInitialized();
    if (_isDisposed()) return const [];
    final fetched = await fetch();
    return _withoutHiddenAndQueued([
      for (final item in fetched.items)
        if (!_suppressedKeys.contains(item.globalKey)) item,
    ]);
  }

  /// [fromNetwork] says whether [fetched] is the whole list; null leaves the
  /// flag as it was (a delta merge extends what was already there).
  void apply(List<MediaItem> fetched, {bool? fromNetwork}) {
    if (fromNetwork != null) allFromNetwork = fromNetwork;
    if (_suppressedKeys.isNotEmpty) {
      // Self-cleaning: once the server stops returning a suppressed item, its
      // scrobble has landed and the suppression is no longer needed.
      // Vals alarm: beide kanten zijn String-sleutels.
      // ignore: avoid-collection-methods-with-unrelated-types
      _suppressedKeys.retainAll({for (final item in fetched) item.globalKey});
      if (_suppressedKeys.isNotEmpty) {
        fetched = fetched.where((item) => !_suppressedKeys.contains(item.globalKey)).toList();
      }
    }
    _set(_withoutHiddenAndQueued(fetched));
  }

  void _set(List<MediaItem> all) {
    _all = all;
    _items = all.length > previewLimit ? all.take(previewLimit).toList() : all;
  }

  /// Titles hidden on this device and titles whose removal is still queued.
  List<MediaItem> _withoutHiddenAndQueued(List<MediaItem> items) {
    final hiddenKeys = hidden?.keys ?? const <String>{};
    if (hiddenKeys.isEmpty && _queuedRemovalKeys.isEmpty) return items;
    return [
      for (final item in items)
        if (!hiddenKeys.contains(item.globalKey) && !_queuedRemovalKeys.contains(item.globalKey)) item,
    ];
  }

  /// A hide drops the title at once; a restore lifts its suppression and
  /// refetches, because the item itself is no longer in memory.
  void _onHiddenChanged() {
    final current = hidden?.keys ?? const <String>{};
    final restored = _lastHiddenKeys.difference(current);
    _lastHiddenKeys = current;
    if (restored.isNotEmpty) {
      _suppressedKeys.removeAll(restored);
      unawaited(refresh());
    }
    final remaining = _all.where((item) => !current.contains(item.globalKey)).toList();
    if (remaining.length != _all.length) {
      _set(remaining);
      _notify();
    }
  }

  /// Swaps [updatedItem] in for the first item that [matches]. On the whole
  /// list, so the overview and the row agree after a player return.
  void replaceWhere(bool Function(MediaItem item) matches, MediaItem updatedItem) {
    final index = _all.indexWhere(matches);
    if (index != -1) _set(List.of(_all)..[index] = updatedItem);
  }

  /// Watch on-deck items and their parent shows/seasons (an episode's watch
  /// flip changes what Continue Watching should show for its series).
  Set<String>? get watchedIds {
    final keys = <String>{};
    for (final item in _all) {
      keys.add(item.id);
      if (item.parentId != null) keys.add(item.parentId!);
      if (item.grandparentId != null) keys.add(item.grandparentId!);
    }
    return keys;
  }

  Set<String>? get watchedGlobalKeys {
    // Suppressed movies are no longer in the list but must keep receiving
    // events: a rewatch (unwatched/progress) has to lift the suppression.
    final keys = <String>{..._suppressedKeys, ...?hidden?.keys};
    for (final item in _all) {
      final serverId = item.serverId;
      if (serverId == null) return null;

      keys.add(buildGlobalKey(ServerId(serverId), item.id));
      if (item.parentId != null) keys.add(buildGlobalKey(ServerId(serverId), item.parentId!));
      if (item.grandparentId != null) keys.add(buildGlobalKey(ServerId(serverId), item.grandparentId!));
    }
    return keys;
  }

  void onWatchStateChanged(WatchStateEvent event) {
    switch (event.changeType) {
      case WatchStateChangeType.removedFromContinueWatching:
        // Suppress, not merely remove. Hoofdstuk 13.4 point 6: the card must
        // not come back because the server is slow to stop listing it, and
        // for a membership whose removal is still queued (point 3) it will
        // keep listing it until the replay lands. The suppression is
        // self-cleaning in [apply].
        _suppressedKeys.add(event.globalKey);
        _remove(event.globalKey);
      case WatchStateChangeType.watched when event.mediaType == MediaKind.movie.id && event.isNowWatched != false:
        // A finished movie leaves the row for good; suppress its key so the
        // background refetch can't race the server's scrobble processing and
        // bring it back with stale in-progress metadata. Episodes are left to
        // the refetch: the server swaps in the next episode of the series.
        _suppressedKeys.add(event.globalKey);
        _remove(event.globalKey);
      case WatchStateChangeType.unwatched:
        _suppressedKeys.remove(event.globalKey);
        unawaited(hidden?.restore(event.globalKey));
      case WatchStateChangeType.progressUpdate:
        // A rewatch must resurface immediately, but a trailing near-complete
        // progress event (isNowWatched) must not undo the watched suppression.
        // The same holds for a title hidden on this device: playing it again
        // is the viewer saying it belongs in the row.
        if (event.isNowWatched != true) {
          _suppressedKeys.remove(event.globalKey);
          unawaited(hidden?.restore(event.globalKey));
        }
      default:
        break;
    }
    unawaited(refresh());
  }

  void _remove(String globalKey) {
    final remaining = _all.where((item) => item.globalKey != globalKey).toList();
    if (remaining.length != _all.length) {
      // Not through [apply]: its self-cleaning would drop the very
      // suppression this removal just added.
      _set(remaining);
      _notify();
    }
  }

  // --- Platform launcher shelf ----------------------------------------------

  /// Sync the current row to the platform launcher shelf. Rapid updates
  /// coalesce: a sync that arrives while one is in flight queues exactly one
  /// follow-up pass with the latest items.
  Future<void> syncShelf() async {
    _pendingSystemShelfItems = List<MediaItem>.unmodifiable(_items);
    if (_systemShelfSyncFuture != null) {
      await _systemShelfSyncFuture;
      return;
    }

    final syncFuture = _drainSystemShelfSyncQueue();
    _systemShelfSyncFuture = syncFuture;
    await syncFuture;
  }

  Future<void> _drainSystemShelfSyncQueue() async {
    try {
      while (_pendingSystemShelfItems != null) {
        final onDeck = _pendingSystemShelfItems!;
        _pendingSystemShelfItems = null;
        if (_isDisposed()) return;

        try {
          final settings = await SettingsService.getInstance();
          bool syncable(MediaItem item) {
            final serverId = item.serverId;
            return serverId != null && _multiServer.getClientForServer(ServerId(serverId)) != null;
          }

          await SystemShelfService().syncFromContinueWatching(
            onDeck.where(syncable).toList(growable: false),
            _clientForShelfItem,
            hideSpoilers: settings.read(SettingsService.hideSpoilers),
            hero: _topShelfHero.where(syncable).toList(growable: false),
          );
        } catch (e) {
          appLogger.w('Failed to sync system shelf', error: e);
        }
      }
    } finally {
      _systemShelfSyncFuture = null;
    }
  }

  /// The Home hero's films for the Top Shelf carousel. Resyncs on change.
  void setTopShelfHero(List<MediaItem> hero) {
    // Only the tvOS Top Shelf reads the hero; elsewhere this would rewrite
    // Android Watch Next for nothing.
    if (!SystemShelfService().drivesTopShelfCarousel) return;
    // By key: a Home refresh hands back new instances of the same films.
    List<String> keys(List<MediaItem> items) => [for (final item in items) item.globalKey];
    if (listEquals(keys(hero), keys(_topShelfHero))) return;
    _topShelfHero = List.unmodifiable(hero);
    unawaited(syncShelf());
  }

  MediaServerClient _clientForShelfItem(ServerId serverId) {
    final direct = _multiServer.getClientForServer(serverId);
    if (direct != null) return direct;
    throw Exception('No owning client available for $serverId');
  }

  /// Drops a queued shelf pass; the owner is going away.
  void dispose() {
    hidden?.removeListener(_onHiddenChanged);
    _pendingSystemShelfItems = null;
  }
}
