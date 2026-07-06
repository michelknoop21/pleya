import '../media/media_hub.dart';
import '../media/ids.dart';
import '../media/media_library.dart';
import 'global_key_utils.dart';

/// Sorts home hubs by the user's library order. Hubs without a known library
/// stay after known-library hubs, preserving their relative server order.
bool sortMediaHubsByLibraryOrder(List<MediaHub> hubs, List<MediaLibrary> libraryOrder) {
  if (hubs.length < 2 || libraryOrder.isEmpty) return false;

  final orderByGlobalKey = <String, int>{};
  for (var i = 0; i < libraryOrder.length; i++) {
    orderByGlobalKey.putIfAbsent(libraryOrder[i].globalKey, () => i);
  }

  final indexedHubs = [for (var i = 0; i < hubs.length; i++) (index: i, hub: hubs[i])];
  indexedHubs.sort((a, b) {
    final aIndex = _hubLibraryOrderIndex(a.hub, orderByGlobalKey);
    final bIndex = _hubLibraryOrderIndex(b.hub, orderByGlobalKey);
    if (aIndex == null && bIndex == null) return a.index.compareTo(b.index);
    if (aIndex == null) return 1;
    if (bIndex == null) return -1;

    final order = aIndex.compareTo(bIndex);
    if (order != 0) return order;
    return a.index.compareTo(b.index);
  });

  var changed = false;
  for (var i = 0; i < hubs.length; i++) {
    final hub = indexedHubs[i].hub;
    if (!identical(hubs[i], hub)) changed = true;
    hubs[i] = hub;
  }
  return changed;
}

/// Coarse relevance class for a hub, lower = surfaced higher. Personalized
/// rows (Top Picks, Because You Watched) lead, then Next-Up-adjacent rows,
/// then freshness, then quality/curation, then everything else. Keyed off the
/// hub's identifier/id/title so it works for both Plex and synthesized hubs.
int hubPriorityClass(MediaHub hub) {
  final haystack = '${hub.identifier ?? ''} ${hub.id} ${hub.title}'.toLowerCase();
  bool has(List<String> keys) => keys.any(haystack.contains);

  if (has(['becauseyouwatched', 'because you watched', 'foryou', 'for you', 'top picks', 'toppicks', 'recommend', 'suggest'])) {
    return 0;
  }
  if (hub.usesContinueWatchingAction || has(['nextup', 'next up', 'ondeck', 'on deck', 'continue'])) {
    return 1;
  }
  if (has(['recentlyadded', 'recently added', 'latest', 'newly'])) return 2;
  if (has(['toprated', 'top rated', 'popular', 'trending', 'highest', 'critically'])) return 3;
  return 4;
}

/// Reorders [hubs] by [hubPriorityClass], preserving the incoming order within
/// each class (so a prior library-order sort still governs same-class hubs).
/// Returns true if the order changed. Mutates [hubs] in place.
bool sortMediaHubsByPriority(List<MediaHub> hubs) {
  if (hubs.length < 2) return false;

  final indexed = [for (var i = 0; i < hubs.length; i++) (index: i, hub: hubs[i])];
  indexed.sort((a, b) {
    final byClass = hubPriorityClass(a.hub).compareTo(hubPriorityClass(b.hub));
    return byClass != 0 ? byClass : a.index.compareTo(b.index);
  });

  var changed = false;
  for (var i = 0; i < hubs.length; i++) {
    if (!identical(hubs[i], indexed[i].hub)) changed = true;
    hubs[i] = indexed[i].hub;
  }
  return changed;
}

int? _hubLibraryOrderIndex(MediaHub hub, Map<String, int> orderByGlobalKey) {
  final hubLibraryKey = _globalKey(serverIdOrNull(hub.serverId), hub.libraryId);
  final hubIndex = hubLibraryKey == null ? null : orderByGlobalKey[hubLibraryKey];
  if (hubIndex != null) return hubIndex;

  int? bestIndex;
  for (final item in hub.items) {
    final key = _globalKey(serverIdOrNull(item.serverId ?? hub.serverId), item.libraryId);
    final index = key == null ? null : orderByGlobalKey[key];
    if (index != null && (bestIndex == null || index < bestIndex)) {
      bestIndex = index;
    }
  }
  return bestIndex;
}

String? _globalKey(ServerId? serverId, String? libraryId) {
  if (serverId == null || libraryId == null) return null;
  return buildGlobalKey(ServerId(serverId), libraryId);
}
