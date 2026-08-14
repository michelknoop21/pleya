import 'dart:convert';

/// Ceiling for the body the app POSTs to the log relay.
///
/// The relay refuses anything over 1 MB with a 413, and the in-memory buffer
/// ([MemoryLogOutput.maxLogSizeBytes]) is five times that, so a device that
/// has been playing all evening produces a log the server will never take.
/// The margin under 1 MB leaves room for the header and the truncation notice.
const int logUploadMaxBytes = 900 * 1024;

/// Reserved for the truncation notice so the composed body stays under
/// [logUploadMaxBytes] no matter how large the dropped part turns out to be.
const int _noticeBudget = 200;

/// Builds the body for a log upload, clipped to what the relay accepts.
///
/// Drops the oldest entries rather than the newest: whatever went wrong
/// happened just before the user pressed upload, so the tail is the part worth
/// keeping. [header] (app version, device, TV mode) always survives: it is
/// the first thing a bug report is read for.
String buildLogUploadBody({required String header, required String entries, int maxBytes = logUploadMaxBytes}) {
  final prefix = header.isEmpty ? '' : '$header\n---\n';
  final prefixBytes = utf8.encode(prefix).length;
  final entryBytes = utf8.encode(entries);

  if (prefixBytes + entryBytes.length <= maxBytes) return '$prefix$entries';

  final allowed = maxBytes - prefixBytes - _noticeBudget;
  // A header that already fills the budget leaves nothing to keep; the version
  // lines are still worth uploading on their own.
  if (allowed <= 0) return prefix;

  // Cut on the byte list and then discard the first (possibly partial) line,
  // so a multi-byte character on the boundary can never split.
  final decoded = utf8.decode(entryBytes.sublist(entryBytes.length - allowed), allowMalformed: true);
  final firstBreak = decoded.indexOf('\n');
  final tail = firstBreak == -1 ? decoded : decoded.substring(firstBreak + 1);
  final droppedKb = ((entryBytes.length - utf8.encode(tail).length) / 1024).ceil();

  return '$prefix[truncated: $droppedKb KB of older log lines dropped to fit the upload limit]\n$tail';
}
