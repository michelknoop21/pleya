import 'dart:convert';
import 'dart:io';

import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';

/// Reads and decodes one `library-*.json`. Meant to run inside an isolate with
/// only [path] captured, so the index bytes are never copied between isolates.
({MediaLibrary library, Map<String, MediaItem> rows, DateTime? completed, DateTime? scanned, int? scannedUpdatedAt})
decodeLibraryFile(String path) {
  final data =
      const Utf8Decoder().fuse(const JsonDecoder()).convert(File(path).readAsBytesSync()) as Map<String, dynamic>;
  final raw = data['library'] as Map<String, dynamic>;
  final library = MediaLibrary(
    id: raw['id'] as String,
    backend: MediaBackend.values.byName(raw['backend'] as String),
    title: raw['title'] as String,
    kind: MediaKind.fromString(raw['kind'] as String),
    serverId: raw['serverId'] as String,
    serverName: raw['serverName'] as String?,
  );
  final rows = <String, MediaItem>{};
  for (final value in data['items'] as List) {
    final item = MediaItem.fromJson(value as Map<String, dynamic>);
    rows[item.globalKey] = item;
  }
  return (
    library: library,
    rows: rows,
    completed: DateTime.tryParse(data['completed'] as String? ?? ''),
    scanned: DateTime.tryParse(data['scanned'] as String? ?? ''),
    scannedUpdatedAt: data['scannedUpdatedAt'] as int?,
  );
}
