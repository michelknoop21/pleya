import '../media/media_item.dart';

/// A client whose items can be matched against the user's Plex/Jellyfin
/// servers by the sync bridge (LocalServerSyncBridge): local folders and
/// Pleya Share guests. The bridge overlays real artwork/metadata onto these
/// items and syncs watch progress in both directions.
abstract interface class ServerMatchableClient {
  Future<List<MediaItem>> scanAllItems();

  void applyServerMetadata(
    String itemId, {
    String? thumbUrl,
    String? artUrl,
    String? logoUrl,
    String? summary,
    int? year,
  });

  Future<void> applyServerWatchState(String itemId, {int? viewOffsetMs, bool? watched});
}
