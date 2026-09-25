import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_library.dart';
import '../../services/recommendations/hub_dedup.dart';
import '../../utils/media_hub_ordering.dart';

/// Cross-server "Recently Added Shows" row. Null when empty so the row
/// disappears instead of rendering a headline over nothing. [MediaHub.serverId]
/// stays null on purpose: the row spans servers, and `homeRowId` only needs the
/// identifier to stay stable across loads.
MediaHub? buildLatestShowsHub(List<MediaItem> items) {
  if (items.isEmpty) return null;
  return MediaHub(
    id: 'home.latestshows',
    identifier: 'home.latestshows',
    title: t.discover.latestShows,
    type: 'show',
    items: items,
    size: items.length,
  );
}

/// Playback-progress hubs duplicate the top Continue Watching row.
List<MediaHub> filterDiscoverHubs(List<MediaHub> hubs) {
  return hubs.where((hub) {
    final hubId = hub.identifier?.toLowerCase() ?? '';
    final title = hub.title.toLowerCase();
    return !hubId.contains('ondeck') &&
        !hubId.contains('continue') &&
        !hubId.contains('nextup') &&
        !title.contains('continue watching') &&
        !title.contains('on deck') &&
        !title.contains('next up');
  }).toList();
}

/// Orders discover hubs by library order, then lifts personalized/next-up/
/// fresh rows toward the top via [hubPriorityClass]. Mutates in place.
void orderDiscoverHubs(List<MediaHub> hubs, List<MediaLibrary> libraries) {
  sortMediaHubsByLibraryOrder(hubs, libraries);
  sortMediaHubsByPriority(hubs);
}

/// [hubs] re-sorted for a changed library order, or null when the order
/// already held. Re-order only (items are already de-duplicated); a reorder
/// introduces no new cross-row duplicates, so there is no dedup pass here.
List<MediaHub>? reorderDiscoverHubs(List<MediaHub> hubs, List<MediaLibrary> libraries) {
  final sortedHubs = List<MediaHub>.from(hubs);
  final byLibrary = sortMediaHubsByLibraryOrder(sortedHubs, libraries);
  final byPriority = sortMediaHubsByPriority(sortedHubs);
  return byLibrary || byPriority ? sortedHubs : null;
}

/// Removes cross-row duplicate items (an item shown in too many hubs), seeded
/// with the Continue Watching keys so those aren't echoed throughout the feed.
List<MediaHub> dedupeDiscoverHubs(List<MediaHub> hubs, List<MediaItem> onDeck) {
  final continueWatchingKeys = {for (final item in onDeck) item.globalKey};
  return dedupeAcrossHubs(hubs, alreadyShownKeys: continueWatchingKeys);
}

/// [existing] with the hubs of [succeededServerIds] replaced by [fresh], then
/// filtered, ordered and de-duplicated like a full load. Cross-server hubs
/// (no server id) always stay.
List<MediaHub> mergeServerHubs(
  List<MediaHub> existing,
  List<MediaHub> fresh,
  Set<String> succeededServerIds, {
  required List<MediaLibrary> libraries,
  required List<MediaItem> onDeck,
}) {
  final mergedHubs = [
    ...existing.where((hub) => hub.serverId == null || !succeededServerIds.contains(hub.serverId)),
    ...filterDiscoverHubs(fresh),
  ];
  orderDiscoverHubs(mergedHubs, libraries);
  return dedupeDiscoverHubs(mergedHubs, onDeck);
}

/// The server of the first item with the bare [itemId], Continue Watching
/// first, then the hubs in order.
String? serverIdForItem(String itemId, List<MediaItem> onDeck, List<MediaHub> hubs) {
  for (final item in onDeck) {
    if (item.id == itemId) return item.serverId;
  }
  for (final hub in hubs) {
    for (final item in hub.items) {
      if (item.id == itemId) return item.serverId;
    }
  }
  return null;
}

/// [hubs] with [updatedItem] swapped in for the first item that [matches] in
/// each hub. The same list instance when nothing matched.
List<MediaHub> replaceItemInHubs(List<MediaHub> hubs, bool Function(MediaItem item) matches, MediaItem updatedItem) {
  var result = hubs;
  for (var i = 0; i < hubs.length; i++) {
    final hub = hubs[i];
    final itemIndex = hub.items.indexWhere(matches);
    if (itemIndex != -1) {
      final newItems = List<MediaItem>.from(hub.items);
      newItems[itemIndex] = updatedItem;
      result = List.of(result)..[i] = hub.copyWith(items: newItems);
    }
  }
  return result;
}
