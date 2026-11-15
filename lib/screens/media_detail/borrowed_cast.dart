import 'dart:async';

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_role.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/media_server_timeouts.dart';

/// Cast photos taken from another server that has the same title.
///
/// Pleya Server sends a cast list without pictures: the protocol has no image
/// field for a person. A title that also lives on Plex or Jellyfin has those
/// pictures one request away, so the detail page shows them next to the names
/// it already has. Only the picture is borrowed. The names, the order and the
/// person ids stay those of the page's own source, so nothing that navigates
/// from a card changes.
class BorrowedCast {
  const BorrowedCast({required this.client, required this.thumbByName});

  /// The server the pictures come from; their paths only mean something there.
  final MediaServerClient client;
  final Map<String, String> thumbByName;

  static String nameKey(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String? thumbFor(MediaRole role) => role.thumbPath == null ? thumbByName[nameKey(role.tag)] : null;

  /// The picture path to draw for [role] and the client to load it with.
  static ({String? thumbPath, MediaServerClient? client}) resolve(
    MediaRole role,
    MediaServerClient? pageClient,
    BorrowedCast? borrowed,
  ) {
    final lent = borrowed?.thumbFor(role);
    if (lent == null) return (thumbPath: role.thumbPath, client: pageClient);
    return (thumbPath: lent, client: borrowed!.client);
  }
}

/// Looks for cast photos on the other sources of a title.
///
/// Returns null when the page already has a photo, when there is no other
/// source, or when none of them has one. Asks at most [maxSources] servers and
/// never throws: a missing photo is not worth an error on a detail page.
Future<BorrowedCast?> borrowCastPhotos({
  required List<MediaRole> pageRoles,
  required String pageSourceKey,
  required Iterable<String> sourceKeys,
  required MediaServerClient? Function(ServerId serverId) clientFor,
  int maxSources = 2,
  Duration timeout = MediaServerTimeouts.interactive,
}) async {
  if (pageRoles.isEmpty || pageRoles.any((role) => (role.thumbPath ?? '').isNotEmpty)) return null;
  final wanted = {for (final role in pageRoles) BorrowedCast.nameKey(role.tag)};
  final pageServer = parseGlobalKey(pageSourceKey)?.serverId;
  var asked = 0;
  for (final key in sourceKeys) {
    if (key == pageSourceKey) continue;
    final parsed = parseGlobalKey(key);
    if (parsed == null || parsed.serverId == pageServer) continue;
    final client = clientFor(parsed.serverId);
    if (client == null) continue;
    if (asked++ >= maxSources) break;
    try {
      final MediaItem? item = await client.fetchItem(parsed.ratingKey).timeout(timeout);
      final thumbs = <String, String>{
        for (final role in item?.roles ?? const <MediaRole>[])
          if ((role.thumbPath ?? '').isNotEmpty && wanted.contains(BorrowedCast.nameKey(role.tag)))
            BorrowedCast.nameKey(role.tag): role.thumbPath!,
      };
      if (thumbs.isNotEmpty) {
        appLogger.d('Cast photos: borrowed ${thumbs.length}/${pageRoles.length} from another source');
        return BorrowedCast(client: client, thumbByName: thumbs);
      }
    } catch (error) {
      appLogger.d('Cast photos: another source did not answer (${error.runtimeType})');
    }
  }
  return null;
}
