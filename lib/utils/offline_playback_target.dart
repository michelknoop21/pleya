import '../media/media_item.dart';
import '../media/media_item_types.dart';

/// Select only a completed video download owned by the active profile. Cached
/// catalog rows must never be passed as [downloaded]. Server IDs remain part
/// of identity even when two servers use the same show/season/item ID.
MediaItem? offlinePlaybackTarget(MediaItem item, Iterable<MediaItem> downloaded, {MediaItem? preferred}) {
  final eligible =
      downloaded.where((candidate) {
        if (candidate.serverId != item.serverId) return false;
        if (item.isShow) return candidate.isEpisode && candidate.grandparentId == item.id;
        if (item.isSeason) return candidate.isEpisode && candidate.parentId == item.id;
        return candidate.globalKey == item.globalKey;
      }).toList()..sort((a, b) {
        final season = (a.parentIndex ?? 0).compareTo(b.parentIndex ?? 0);
        return season != 0 ? season : (a.index ?? 0).compareTo(b.index ?? 0);
      });
  return eligible.where((candidate) => candidate.globalKey == preferred?.globalKey).firstOrNull ??
      eligible.where((candidate) => !candidate.isWatched).firstOrNull ??
      eligible.firstOrNull;
}
