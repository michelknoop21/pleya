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
import '../hidden_libraries_provider.dart';
import '../multi_server_provider.dart';

/// The Continue Watching row of Home: the on-deck list, its "more" probe, the
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
  });

  /// Preview row caps at 20; one extra item is fetched as a probe so
  /// [hasMore] can show the "more" affordance without a second request.
  static const int previewLimit = 20;
  static const int _probeLimit = previewLimit + 1;

  final MultiServerProvider _multiServer;
  final HiddenLibrariesProvider _hiddenLibraries;
  final bool Function() _isDisposed;
  final VoidCallback _notify;

  List<MediaItem> _items = [];
  bool _hasMore = false;

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

  List<MediaItem> get items => _items;
  bool get hasMore => _hasMore;

  /// The probe-sized on-deck fetch, from every server or only [serverIds].
  Future<OnDeckAggregationResult> fetch({Set<String>? serverIds}) {
    return _multiServer.aggregationService.getOnDeckFromAllServers(
      limit: _probeLimit,
      hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
      serverIds: serverIds,
    );
  }

  /// Merges [fresh] from newly-online servers into the stored list. Returns
  /// false when the owner was disposed while the merge ran.
  Future<bool> merge(OnDeckAggregationResult fresh) async {
    final hadMore = _hasMore;
    final merged = await _multiServer.aggregationService.mergeContinueWatching(_items, fresh.items, limit: _probeLimit);
    if (_isDisposed()) return false;
    apply(merged);
    // The stored list is already trimmed, so the merge can't see old items
    // past the cap — a previously-true "more" affordance stays true.
    if (hadMore) _hasMore = true;
    loadedServerIds = {...loadedServerIds, ...fresh.succeededServerIds};
    return true;
  }

  /// Background refresh of Continue Watching only — never flips load states
  /// or surfaces errors (a stale row beats an error flash), never refetches
  /// hubs.
  Future<void> refresh() async {
    try {
      if (!_multiServer.hasConnectedServers) return;
      final fetched = await _multiServer.aggregationService.getOnDeckFromAllServers(
        limit: _probeLimit,
        hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
      );
      if (_isDisposed()) return;
      apply(fetched.items);
      loadedServerIds = fetched.succeededServerIds;
      _notify();
      unawaited(syncShelf());
    } catch (e) {
      appLogger.w('Failed to refresh Continue Watching', error: e);
    }
  }

  /// The full unlimited Continue Watching list for the hub's load-more path.
  Future<List<MediaItem>> loadAll() async {
    if (!_multiServer.hasConnectedServers) return const [];
    await _hiddenLibraries.ensureInitialized();
    if (_isDisposed()) return const [];
    final fetched = await _multiServer.aggregationService.getOnDeckFromAllServers(
      hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
    );
    return fetched.items;
  }

  void apply(List<MediaItem> fetched) {
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
    final hasMore = fetched.length > previewLimit;
    _items = hasMore ? fetched.take(previewLimit).toList() : fetched;
    _hasMore = hasMore;
  }

  /// Swaps [updatedItem] in for the first item that [matches].
  void replaceWhere(bool Function(MediaItem item) matches, MediaItem updatedItem) {
    final index = _items.indexWhere(matches);
    if (index != -1) {
      _items = List.of(_items)..[index] = updatedItem;
    }
  }

  /// Watch on-deck items and their parent shows/seasons (an episode's watch
  /// flip changes what Continue Watching should show for its series).
  Set<String>? get watchedIds {
    final keys = <String>{};
    for (final item in _items) {
      keys.add(item.id);
      if (item.parentId != null) keys.add(item.parentId!);
      if (item.grandparentId != null) keys.add(item.grandparentId!);
    }
    return keys;
  }

  Set<String>? get watchedGlobalKeys {
    // Suppressed movies are no longer in the list but must keep receiving
    // events: a rewatch (unwatched/progress) has to lift the suppression.
    final keys = <String>{..._suppressedKeys};
    for (final item in _items) {
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
      case WatchStateChangeType.progressUpdate:
        // A rewatch must resurface immediately, but a trailing near-complete
        // progress event (isNowWatched) must not undo the watched suppression.
        if (event.isNowWatched != true) _suppressedKeys.remove(event.globalKey);
      default:
        break;
    }
    unawaited(refresh());
  }

  void _remove(String globalKey) {
    final remaining = _items.where((item) => item.globalKey != globalKey).toList();
    if (remaining.length != _items.length) {
      _items = remaining;
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
          final syncableOnDeck = onDeck
              .where((item) {
                final serverId = item.serverId;
                return serverId != null && _multiServer.getClientForServer(ServerId(serverId)) != null;
              })
              .toList(growable: false);
          await SystemShelfService().syncFromContinueWatching(
            syncableOnDeck,
            _clientForShelfItem,
            hideSpoilers: settings.read(SettingsService.hideSpoilers),
          );
        } catch (e) {
          appLogger.w('Failed to sync system shelf', error: e);
        }
      }
    } finally {
      _systemShelfSyncFuture = null;
    }
  }

  MediaServerClient _clientForShelfItem(ServerId serverId) {
    final direct = _multiServer.getClientForServer(serverId);
    if (direct != null) return direct;
    throw Exception('No owning client available for $serverId');
  }

  /// Drops a queued shelf pass; the owner is going away.
  void dispose() {
    _pendingSystemShelfItems = null;
  }
}
