part of '../../pleya_server_client.dart';

/// `DELETE /items/{id}` (chapter 17h): a title and everything under it leaves
/// the catalogue and its files are erased from storage. Off unless the server
/// admin switched it on and a media root was measured writable, which the
/// `media_delete` capability says. Without it nothing is sent and the answer
/// is false, as before this route existed.
mixin _PleyaServerMediaDeleteMethods on _PleyaServerRequests implements MediaDeletionGate {
  void assertCanAdministerServer();

  @override
  bool get supportsMediaDeletion => wireCapabilities.mediaDelete;

  /// Throws on every non-2xx answer, with the protocol code as the message
  /// (`library.media_delete_incomplete` when a file stayed behind): a delete
  /// that only partly happened must not read as a success.
  Future<bool> deleteMediaItem(MediaItem item) async {
    if (!wireCapabilities.mediaDelete) return false;
    assertCanAdministerServer();
    try {
      await _adminSend('DELETE', '/items/${adminPathSegment(item.id)}');
    } on MediaServerHttpException catch (e) {
      final error = PleyaError.tryParse(e.responseData);
      if (error?.code != 'library.media_delete_incomplete') rethrow;
      final details = error?.details ?? const <String, dynamic>{};
      final failed = details['failed'];
      throw MediaDeletionIncompleteException(
        removedFiles: (details['removed_files'] as num?)?.toInt() ?? 0,
        removedItems: (details['removed_items'] as num?)?.toInt() ?? 0,
        failedPaths: [
          if (failed is List)
            for (final f in failed.whereType<Map<String, dynamic>>())
              if (f['path'] case final String path) path,
        ],
      );
    }
    return true;
  }
}
