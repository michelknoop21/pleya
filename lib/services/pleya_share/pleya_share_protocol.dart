import 'dart:convert';

/// Wire-level constants and helpers for Pleya Share — the peer-to-peer
/// "phone as mini media server" feature.
///
/// Transport is plain HTTP on [sharePort] (separate from companion-remote
/// 48632 so both features toggle independently):
///
///   GET  /info                       → host metadata (pre-pairing, public)
///   POST /pair/start                 → begin code pairing (challenge)
///   POST /pair/complete              → finish code pairing → pairId+secret
///   POST /auth/start                 → begin reconnect (challenge)
///   POST /auth/complete              → finish reconnect → session token
///   GET  /library?token=…            → full item list as MediaItem JSON
///   GET  `/stream/<b64url(id)>?token=` → media bytes, Range-supported
///   POST /watch?token=…              → per-guest watch-state update
///   GET  /ping?token=…               → health check
///
/// Discovery: UDP broadcast beacons on [discoveryPort] with `app == beaconApp`.
class PleyaShareProtocol {
  PleyaShareProtocol._();

  static const int version = 1;
  static const int sharePort = 48634;
  static const int discoveryPort = 48633;
  static const String beaconApp = 'pleya-share';

  /// Encode a media item id (file URI) for use in a /stream path segment.
  static String encodeItemId(String id) => base64UrlEncode(utf8.encode(id)).replaceAll('=', '');

  static String decodeItemId(String encoded) {
    final padded = encoded.padRight((encoded.length + 3) & ~3, '=');
    return utf8.decode(base64Url.decode(padded));
  }
}

/// A parsed HTTP `Range` header against a known total length.
class HttpByteRange {
  final int start;

  /// Inclusive end offset.
  final int end;
  final int total;

  const HttpByteRange({required this.start, required this.end, required this.total});

  int get length => end - start + 1;
  String get contentRange => 'bytes $start-$end/$total';

  /// Parse a `Range: bytes=…` header. Returns null when [header] is absent or
  /// malformed (caller serves 200 with the full body). Throws
  /// [RangeNotSatisfiableException] for a syntactically valid but
  /// unsatisfiable range (caller serves 416).
  ///
  /// Supports the single-range forms `bytes=a-b`, `bytes=a-`, and `bytes=-n`
  /// (suffix). Multi-range requests fall back to the full body.
  static HttpByteRange? parse(String? header, int total) {
    if (header == null || total <= 0) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final startStr = match.group(1)!;
    final endStr = match.group(2)!;
    if (startStr.isEmpty && endStr.isEmpty) return null;

    int start;
    int end;
    if (startStr.isEmpty) {
      // Suffix form: last n bytes.
      final n = int.parse(endStr);
      if (n == 0) throw const RangeNotSatisfiableException();
      start = total - n < 0 ? 0 : total - n;
      end = total - 1;
    } else {
      start = int.parse(startStr);
      end = endStr.isEmpty ? total - 1 : int.parse(endStr);
      if (end > total - 1) end = total - 1;
      if (start > end || start >= total) throw const RangeNotSatisfiableException();
    }
    return HttpByteRange(start: start, end: end, total: total);
  }
}

class RangeNotSatisfiableException implements Exception {
  const RangeNotSatisfiableException();
}

/// Content types for the extensions the local scanner recognises; mpv doesn't
/// need them but they keep proxies/download managers honest.
String videoContentType(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
  return switch (ext) {
    'mp4' || 'm4v' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    'avi' => 'video/x-msvideo',
    'mov' => 'video/quicktime',
    'ts' || 'm2ts' => 'video/mp2t',
    'wmv' => 'video/x-ms-wmv',
    'mpg' || 'mpeg' || 'vob' => 'video/mpeg',
    'flv' => 'video/x-flv',
    '3gp' => 'video/3gpp',
    'ogv' => 'video/ogg',
    _ => 'application/octet-stream',
  };
}
