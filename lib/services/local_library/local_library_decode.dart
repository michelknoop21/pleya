import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';

final _json = const Utf8Decoder().fuse(const JsonDecoder());
const _quote = 0x22, _backslash = 0x5C;
const _openBrace = 0x7B, _closeBrace = 0x7D, _openBracket = 0x5B, _closeBracket = 0x5D;

/// Reads and decodes one `library-*.json`. Meant to run inside an isolate with
/// only [path] captured, so the index bytes are never copied between isolates.
///
/// The file is read in blocks and every row is decoded on its own. Before, the
/// whole file, a JSON tree of every row and the rows themselves were alive
/// together, which doubled the memory peak of a load.
///
/// Relies on the layout the store writes: `items` is the only array directly
/// under the root object. The bytes outside the rows are kept and decoded at
/// the end, so a truncated or corrupt file still throws a [FormatException].
({MediaLibrary library, Map<String, MediaItem> rows, DateTime? completed, DateTime? scanned, int? scannedUpdatedAt})
decodeLibraryFile(String path) {
  final rows = <String, MediaItem>{};
  final envelope = BytesBuilder(), pending = BytesBuilder();
  final block = Uint8List(1 << 16);
  var depth = 0, inString = false, escaped = false, inItems = false, inRow = false;
  final file = File(path).openSync();
  try {
    for (var n = file.readIntoSync(block); n > 0; n = file.readIntoSync(block)) {
      // First byte of this block that still has to go to the envelope or a row.
      var from = 0;
      for (var i = 0; i < n; i++) {
        final byte = block[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (byte == _backslash) {
            escaped = true;
          } else if (byte == _quote) {
            inString = false;
          }
        } else if (byte == _quote) {
          inString = true;
        } else if (byte == _openBrace || byte == _openBracket) {
          depth++;
          if (depth == 2 && byte == _openBracket && !inItems) {
            envelope.add(Uint8List.sublistView(block, from, i + 1));
            inItems = true;
          } else if (depth == 3 && inItems && !inRow) {
            inRow = true;
            from = i;
          }
        } else if (byte == _closeBrace || byte == _closeBracket) {
          depth--;
          if (depth == 2 && inRow) {
            final end = Uint8List.sublistView(block, from, i + 1);
            final bytes = pending.isEmpty ? end : (pending..add(end)).takeBytes();
            final item = MediaItem.fromJson(_json.convert(bytes) as Map<String, dynamic>);
            rows[item.globalKey] = item;
            inRow = false;
          } else if (depth == 1 && inItems) {
            inItems = false;
            from = i;
          }
        }
      }
      // The commas between two rows belong to neither.
      if (inRow) {
        pending.add(Uint8List.sublistView(block, from, n));
      } else if (!inItems) {
        envelope.add(Uint8List.sublistView(block, from, n));
      }
    }
  } finally {
    file.closeSync();
  }
  final data = _json.convert(envelope.takeBytes()) as Map<String, dynamic>;
  final raw = data['library'] as Map<String, dynamic>;
  final library = MediaLibrary(
    id: raw['id'] as String,
    backend: MediaBackend.values.byName(raw['backend'] as String),
    title: raw['title'] as String,
    kind: MediaKind.fromString(raw['kind'] as String),
    serverId: raw['serverId'] as String,
    serverName: raw['serverName'] as String?,
  );
  return (
    library: library,
    rows: rows,
    completed: DateTime.tryParse(data['completed'] as String? ?? ''),
    scanned: DateTime.tryParse(data['scanned'] as String? ?? ''),
    scannedUpdatedAt: data['scannedUpdatedAt'] as int?,
  );
}
