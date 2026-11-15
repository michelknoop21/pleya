import 'dart:typed_data';

import '../../media/media_item.dart';
import '../../media/media_server_client.dart';

class LocalLibraryPaused implements Exception {}

/// The scan enumerated the whole library and saved it, but [skipped] titles
/// without a stored row got no detail answer and are not in the snapshot.
class LocalLibraryPartialScan implements Exception {
  const LocalLibraryPartialScan(this.skipped);
  final int skipped;
  @override
  String toString() => 'LocalLibraryPartialScan: $skipped titles left for the next scan';
}

class LocalPosterResult {
  const LocalPosterResult({this.bytes, this.etag, this.lastModified, required this.variant});
  final Uint8List? bytes; // null means a successful conditional 304.
  final String? etag;
  final String? lastModified;
  final String variant;
}

typedef LocalPosterRevalidator =
    Future<LocalPosterResult> Function(MediaServerClient client, MediaItem item, Map<String, dynamic> validators);

typedef LocalPosterLoader = Future<Uint8List> Function(MediaServerClient client, MediaItem item);
