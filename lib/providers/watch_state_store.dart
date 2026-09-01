import 'dart:async';
import '../media/ids.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../media/media_item.dart';
import '../media/watch_progress.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/watch_state_resolver.dart';
import '../utils/global_key_utils.dart';
import '../utils/watch_state_notifier.dart';

@immutable
class WatchStatePatch {
  final bool? isWatched;
  final bool hasViewOffsetMs;
  final int? viewOffsetMs;

  const WatchStatePatch({this.isWatched, this.hasViewOffsetMs = false, this.viewOffsetMs});

  factory WatchStatePatch.fromSnapshot(WatchStateSnapshot snapshot) => WatchStatePatch(
    isWatched: snapshot.isWatched,
    hasViewOffsetMs: snapshot.hasViewOffsetMs,
    viewOffsetMs: snapshot.viewOffsetMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchStatePatch &&
          other.isWatched == isWatched &&
          other.hasViewOffsetMs == hasViewOffsetMs &&
          other.viewOffsetMs == viewOffsetMs;

  @override
  int get hashCode => Object.hash(isWatched, hasViewOffsetMs, viewOffsetMs);
}

class _WatchStatePatchEntry {
  final WatchStatePatch patch;
  final int sequence;

  /// Wall clock at which this patch was recorded, so a server snapshot can
  /// prove it is describing a *later* viewing than the patch does. [sequence]
  /// only orders patches against each other and says nothing about the server.
  final int createdAtMsEpoch;

  const _WatchStatePatchEntry(this.patch, this.sequence, this.createdAtMsEpoch);
}

/// The single session-local layer for watch-state freshness.
///
/// Server fetches remain the source of truth; [MediaItem] snapshots are never
/// hand-mutated to reflect watch events. Instead, every watch event lands here
/// as a patch, and consumers resolve items at point of use ([apply] /
/// [patchForItem]). Resolution is hierarchy-aware: an item's effective patch
/// is the newest among its own and its [MediaItem.parentChain] ancestors', so
/// marking a show/season reaches every descendant, while a later per-item
/// event still overrides an older container mark.
class WatchStateStore extends ChangeNotifier with DisposableChangeNotifierMixin {
  WatchStateStore({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _subscription = WatchStateNotifier().stream.listen(_onWatchStateEvent);
  }

  /// How far a server snapshot's [MediaItem.lastViewedAt] has to run ahead of a
  /// patch before the server is believed over it.
  ///
  /// Zero would be wrong: this device reports its own progress while playing,
  /// so the server's timestamp for the very playback a patch describes lands
  /// within seconds of the patch itself. Without a margin the bridge the patch
  /// exists for would collapse and "minutes left" would lag again. Anything
  /// beyond the margin cannot be this session's own report; it is another
  /// device that watched further, and then the server is the better source.
  ///
  /// The same threshold answers hoofdstuk 13.2's tier 2 — which of two
  /// sources' timestamps may be trusted to order them — so it lives in
  /// `lib/media/watch_progress.dart` next to the other shared watch decision
  /// and is aliased here rather than written twice.
  static const Duration serverWinsMargin = watchStateReliabilityMargin;

  final DateTime Function() _now;

  StreamSubscription<WatchStateEvent>? _subscription;
  final Map<String, _WatchStatePatchEntry> _patches = {};
  String? _activeProfileId;
  Map<String, String?> _activeClientScopesByServer = const {};
  int _sequence = 0;

  _WatchStatePatchEntry? _entryFor(String globalKey) {
    _WatchStatePatchEntry? scopedEntry;
    final parsed = parseGlobalKey(globalKey);
    if (parsed != null) {
      final scoped = _activeClientScopesByServer[parsed.serverId];
      if (scoped != null && scoped.isNotEmpty) {
        scopedEntry = _patches[buildGlobalKey(ServerId(scoped), parsed.ratingKey)];
      }
    }
    final unscopedEntry = _patches[globalKey];
    if (scopedEntry == null) return unscopedEntry;
    if (unscopedEntry == null) return scopedEntry;
    return scopedEntry.sequence >= unscopedEntry.sequence ? scopedEntry : unscopedEntry;
  }

  WatchStatePatch? patchForGlobalKey(String globalKey) => _entryFor(globalKey)?.patch;

  WatchStatePatch? patchForItem(MediaItem item) {
    var best = _entryFor(item.globalKey);
    if (item.parentChain.isNotEmpty) {
      final serverId = serverIdOrNull(item.serverId);
      for (final parentId in item.parentChain) {
        // Mirror MediaItem.globalKey's bare-id fallback when serverId is missing.
        final entry = _entryFor(serverId != null ? buildGlobalKey(serverId, parentId) : parentId);
        if (entry != null && (best == null || entry.sequence > best.sequence)) best = entry;
      }
    }
    if (best == null || _serverOutranks(item, best)) return null;
    return best.patch;
  }

  /// Whether [item] carries a viewing the server recorded after [entry] was
  /// made, which is how a second device announces that it watched further.
  ///
  /// Patches are session-local and never expire on their own, so without this
  /// the position left behind here would keep overriding fresher server data
  /// for as long as the app stays alive.
  bool _serverOutranks(MediaItem item, _WatchStatePatchEntry entry) {
    final lastViewedAt = item.lastViewedAt;
    if (lastViewedAt == null || lastViewedAt <= 0) return false;
    final serverMs = lastViewedAt * 1000;
    return serverMs - entry.createdAtMsEpoch > serverWinsMargin.inMilliseconds;
  }

  MediaItem apply(MediaItem item) {
    return applyPatch(item, patchForItem(item));
  }

  List<MediaItem> applyAll(List<MediaItem> items) {
    if (_patches.isEmpty) return items;
    return [for (final item in items) apply(item)];
  }

  static MediaItem applyPatch(MediaItem item, WatchStatePatch? patch) {
    if (patch == null) return item;
    return WatchStateSnapshot(
      isWatched: patch.isWatched,
      hasViewOffsetMs: patch.hasViewOffsetMs,
      viewOffsetMs: patch.viewOffsetMs,
    ).apply(item);
  }

  void setActiveProfileId(String? profileId) {
    if (_activeProfileId == profileId) return;
    _activeProfileId = profileId;
    if (_patches.isEmpty) return;
    _patches.clear();
    safeNotifyListeners();
  }

  void setActiveClientScopesByServer(Map<String, String?> scopes) {
    final normalized = <String, String?>{
      for (final entry in scopes.entries)
        if (entry.value != null && entry.value!.isNotEmpty && entry.value != entry.key) entry.key: entry.value,
    };
    if (mapEquals(_activeClientScopesByServer, normalized)) return;
    _activeClientScopesByServer = Map.unmodifiable(normalized);
    if (_patches.isNotEmpty) safeNotifyListeners();
  }

  void _onWatchStateEvent(WatchStateEvent event) {
    final snapshot = WatchStateResolver.fromEvent(event);
    if (snapshot.isEmpty) return;
    final patch = WatchStatePatch.fromSnapshot(snapshot);

    final cacheServerId = event.cacheServerId;
    final key = cacheServerId != null && cacheServerId.isNotEmpty && cacheServerId != event.serverId
        ? buildGlobalKey(ServerId(cacheServerId), event.itemId)
        : event.globalKey;
    _patches[key] = _WatchStatePatchEntry(patch, ++_sequence, _now().millisecondsSinceEpoch);
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}

/// Point-of-use watch-state resolution. All fall back to the item as-is when
/// no [WatchStateStore] is in the tree (tests, isolated subtrees).
extension WatchStateResolution on BuildContext {
  /// Build-time resolution: subscribes this context to the item's effective
  /// patch, so the widget rebuilds when a newer event lands for it (or an
  /// ancestor). Use in `build`.
  MediaItem withFreshWatchState(MediaItem item) {
    try {
      final patch = select<WatchStateStore, WatchStatePatch?>((store) => store.patchForItem(item));
      return WatchStateStore.applyPatch(item, patch);
    } on ProviderNotFoundException {
      return item;
    }
  }

  /// Point-in-time resolution for handlers and non-build code paths.
  MediaItem readFreshWatchState(MediaItem item) {
    try {
      return read<WatchStateStore>().apply(item);
    } on ProviderNotFoundException {
      return item;
    }
  }

  List<MediaItem> readFreshWatchStateAll(List<MediaItem> items) {
    try {
      return read<WatchStateStore>().applyAll(items);
    } on ProviderNotFoundException {
      return items;
    }
  }
}
