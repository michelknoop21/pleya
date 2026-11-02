import 'media_item.dart';

/// Whether the requester owns this collection. Pleya Server says so per
/// collection, and another user's shared collection answers a write with
/// `library.list_not_owner` whatever the role. Plex and Jellyfin carry no such
/// marker: a collection there is the library's.
extension CollectionOwnership on MediaItem {
  bool get isOwnCollection => raw?['is_owner'] != false;
}
