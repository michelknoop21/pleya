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
