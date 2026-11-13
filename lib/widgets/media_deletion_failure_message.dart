import '../exceptions/media_server_exceptions.dart';
import '../i18n/strings.g.dart';
import '../media/media_backend.dart';
import '../media/media_server_client.dart';
import '../services/plex_client.dart';

bool _isPlexBadRequest(Object error, MediaBackend? backend) =>
    backend == MediaBackend.plex && error is MediaServerHttpException && error.statusCode == 400;

/// Text for a failed delete.
///
/// Plex answers a delete with HTTP 400 both when 'Allow media deletion' is off
/// and when the server cannot remove the files itself (folder permissions, a
/// drive that is not mounted). [plexAllowsMediaDeletion] says which one it is:
/// `false` names the setting, `true` points at the files, `null` (not known)
/// names both and claims neither.
String mediaDeletionFailureMessage(Object error, MediaBackend? backend, {bool? plexAllowsMediaDeletion}) {
  final status = error is MediaServerHttpException ? error.statusCode : null;
  // Jellyfin and Emby answer 401/403 to a user without media deletion.
  if (backend == MediaBackend.jellyfin && (status == 401 || status == 403)) return t.mediaMenu.deletionForbidden;
  // On Plex a 401 is a token that no longer counts, which the connection's own
  // re-sign-in path handles; a 403 is an account the server will not let delete.
  if (backend == MediaBackend.plex && status == 401) return t.connections.reauthRequired;
  if (backend == MediaBackend.plex && status == 403) return t.mediaMenu.plexDeletionForbidden;
  if (!_isPlexBadRequest(error, backend)) return t.mediaMenu.mediaFailedToDelete;
  return switch (plexAllowsMediaDeletion) {
    false => t.mediaMenu.plexDeletionDisabled,
    true => t.mediaMenu.plexDeletionFilesNotRemovable,
    null => t.mediaMenu.plexDeletionRefusedUnknown,
  };
}

/// Like [mediaDeletionFailureMessage], but asks the Plex server for the
/// setting first. Only a Plex 400 costs a request; every other failure and
/// every other backend resolves without touching the network.
Future<String> resolveMediaDeletionFailureMessage(
  Object error,
  MediaBackend? backend,
  MediaServerClient? client,
) async {
  bool? allowed;
  if (client is PlexClient && _isPlexBadRequest(error, backend)) {
    allowed = await client.fetchAllowMediaDeletion();
  }
  return mediaDeletionFailureMessage(error, backend, plexAllowsMediaDeletion: allowed);
}
