import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';

const int playlistItemsPageSize = 200;

/// Page through every item in a playlist via the backend-neutral client API.
Future<List<MediaItem>> fetchAllPlaylistItems(
  MediaServerClient client,
  String playlistId, {
  int pageSize = playlistItemsPageSize,
}) async {
  final all = <MediaItem>[];
  var offset = 0;
  while (true) {
    final page = await client.fetchPlaylistPage(playlistId, start: offset, size: pageSize);
    if (page.items.isEmpty) break;
    all.addAll(page.items);
    if (all.length >= page.totalCount) break;
    offset += page.items.length;
  }
  return all;
}

/// Page through every item in a collection via the backend-neutral client API.
Future<List<MediaItem>> fetchAllCollectionItemsPaged(
  MediaServerClient client,
  String collectionId, {
  int pageSize = 100,
  String? libraryId,
  String? libraryTitle,
}) async {
  final all = <MediaItem>[];
  var offset = 0;
  while (true) {
    final page = await client.fetchCollectionPage(
      collectionId,
      start: offset,
      size: pageSize,
      libraryId: libraryId,
      libraryTitle: libraryTitle,
    );
    if (page.items.isEmpty) break;
    all.addAll(page.items);
    if (all.length >= page.totalCount || page.items.length < pageSize) break;
    offset += page.items.length;
  }
  return all;
}

/// Every row of a collection that plays, in list order. A collection can hold a
/// show or a season; those become their episodes, because a queue only plays leaves.
Future<List<MediaItem>> fetchAllPlayableCollectionItems(MediaServerClient client, String collectionId) async {
  final rows = await fetchAllCollectionItemsPaged(client, collectionId);
  final playable = <MediaItem>[];
  for (final row in rows) {
    if (row.kind == MediaKind.show || row.kind == MediaKind.season) {
      playable.addAll(await client.fetchPlayableDescendants(row.id));
    } else if (row.kind.isPlayable) {
      playable.add(row);
    }
  }
  return playable;
}
