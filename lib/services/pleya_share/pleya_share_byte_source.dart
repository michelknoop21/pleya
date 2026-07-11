import 'dart:io';

import 'package:saf_stream/saf_stream.dart';

import '../../utils/app_logger.dart';
import 'pleya_share_protocol.dart';

/// Serves media file bytes over HTTP with Range support, reading from either
/// a plain filesystem path (iOS/macOS/desktop) or an Android SAF
/// `content://` URI (via saf_stream, which supports a start offset).
class PleyaShareByteSource {
  PleyaShareByteSource._();

  static final _saf = SafStream();

  static bool _isContentUri(String uri) => uri.startsWith('content://');

  /// Total size in bytes, or null when unknown (SAF item without size).
  static Future<int?> length(String uri, {int? knownSize}) async {
    if (knownSize != null && knownSize > 0) return knownSize;
    if (_isContentUri(uri)) return null;
    try {
      return await File(uri).length();
    } catch (_) {
      return null;
    }
  }

  /// Write the (range of the) file at [uri] to [response] and close it.
  /// Sets status/headers; caller must not have written anything yet.
  static Future<void> serve(HttpRequest request, String uri, {int? knownSize}) async {
    final response = request.response;
    final total = await length(uri, knownSize: knownSize);

    HttpByteRange? range;
    if (total != null) {
      try {
        range = HttpByteRange.parse(request.headers.value(HttpHeaders.rangeHeader), total);
      } on RangeNotSatisfiableException {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await response.close();
        return;
      }
    }

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType.parse(videoContentType(uri));
    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(HttpHeaders.contentRangeHeader, range.contentRange);
      response.contentLength = range.length;
    } else if (total != null) {
      response.contentLength = total;
    }

    try {
      final start = range?.start ?? 0;
      Stream<List<int>> stream;
      if (_isContentUri(uri)) {
        stream = await _saf.readFileStream(uri, start: start > 0 ? start : null);
        if (range != null) stream = _take(stream, range.length);
      } else {
        stream = File(uri).openRead(start, range == null ? null : range.end + 1);
      }
      await response.addStream(stream);
    } catch (e, st) {
      // Client seeks/disconnects abort the socket mid-stream — that's routine.
      appLogger.d('PleyaShare: stream ended early for $uri', error: e, stackTrace: st);
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Truncate [source] after [count] bytes (SAF streams have no end offset).
  static Stream<List<int>> _take(Stream<List<int>> source, int count) async* {
    var remaining = count;
    await for (final chunk in source) {
      if (chunk.length >= remaining) {
        yield chunk.sublist(0, remaining);
        return;
      }
      remaining -= chunk.length;
      yield chunk;
    }
  }
}
