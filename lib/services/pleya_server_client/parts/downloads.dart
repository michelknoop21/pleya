part of '../../pleya_server_client.dart';

/// Offline downloads (S23). The server prepares the file and states its
/// SHA-256; the app's existing queue fetches `file_url` and verifies it.
mixin _PleyaServerDownloadMethods on _PleyaServerRequests {
  /// How often a preparing download is asked about, and how long to wait for
  /// the server to finish hashing a large file before giving up.
  @visibleForTesting
  Duration downloadPollInterval = const Duration(seconds: 2);
  @visibleForTesting
  Duration downloadPrepareTimeout = const Duration(minutes: 10);

  Future<PleyaDownload?> createDownload(String itemId, {String? versionId}) async {
    if (!wireCapabilities.downloads) return null;
    final json = await _postJson('/downloads', {'item_id': itemId, 'version_id': ?versionId});
    return json == null ? null : PleyaDownload.fromJson(json);
  }

  Future<PleyaDownload?> getDownload(String downloadId) async {
    final json = await _getJson('/downloads/$downloadId');
    return json == null ? null : PleyaDownload.fromJson(json);
  }

  /// The SHA-256 the server states for the download behind [fileUrl] (the
  /// `…/downloads/{id}/file` url the queue was handed), or null when [fileUrl]
  /// is not such a url or the server does not know the download any more. A
  /// download belongs to its user, so the session that created it can ask
  /// again after the app restarted and the in-memory digest is gone.
  Future<String?> expectedDigestForUrl(String fileUrl) async {
    final segments = Uri.tryParse(fileUrl)?.pathSegments ?? const <String>[];
    final at = segments.lastIndexOf('downloads');
    if (at < 0 || at + 2 >= segments.length || segments[at + 2] != 'file') return null;
    return (await getDownload(segments[at + 1]))?.sha256;
  }

  Future<bool> deleteDownload(String downloadId) async {
    if (!wireCapabilities.downloads) return false;
    await _adminSend('DELETE', '/downloads/$downloadId');
    return true;
  }

  Future<DownloadResolution> resolveDownload(MediaItem item, {int mediaIndex = 0}) async {
    if (!wireCapabilities.downloads) return const DownloadResolution(videoUrl: null);
    final versions = item.mediaVersions ?? const <MediaVersion>[];
    if (versions.isEmpty) return const DownloadResolution(videoUrl: null);
    final version = versions[mediaIndex >= 0 && mediaIndex < versions.length ? mediaIndex : 0];

    var download = await createDownload(item.id, versionId: version.id);
    final deadline = DateTime.now().add(downloadPrepareTimeout);
    while (download != null && !download.isReady && !download.isFailed) {
      if (DateTime.now().isAfter(deadline)) throw Exception('The server did not finish preparing the download');
      await Future<void>.delayed(downloadPollInterval);
      download = await getDownload(download.id);
    }
    if (download == null || download.isFailed) throw Exception('The server could not prepare the download');

    final container = version.container;
    final url = Uri.parse('${connection.baseUrl}${download.fileUrl}');
    return DownloadResolution(
      videoUrl: (container == null ? url : url.replace(queryParameters: {'container': container})).toString(),
      mediaSourceId: version.id,
      headers: await _session.authHeaders(),
      sha256: download.sha256,
    );
  }
}
