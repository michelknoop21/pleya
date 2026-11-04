import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../utils/media_server_http_client.dart';

/// The server's ten minutes of extraction, plus room to collect the result.
const Duration pleyaSubtitleRetryLimit = Duration(minutes: 11);
const Duration _defaultRetryAfter = Duration(seconds: 5);
const int _maxRetryAfterSeconds = 60;

/// The track did not arrive: a final answer, the limit, or an abort.
class PleyaSubtitleUnavailable implements Exception {
  const PleyaSubtitleUnavailable(this.statusCode);

  final int? statusCode;

  @override
  String toString() => 'PleyaSubtitleUnavailable($statusCode)';
}

/// Seconds only: the contract says `Retry-After: 5`, and 0 must not become a busy loop.
Duration pleyaRetryAfter(String? header) {
  final seconds = int.tryParse(header?.trim() ?? '');
  if (seconds == null || seconds < 0) return _defaultRetryAfter;
  return Duration(seconds: seconds.clamp(1, _maxRetryAfterSeconds));
}

/// Repeats [get] while the server answers `503`, the only "not yet" it has.
///
/// A large Matroska file has to be read completely, so an embedded track can
/// take minutes. The request stays short and a repeat joins the running
/// extraction, or starts it once the single worker is free. Everything else is
/// the outcome: `401`, `404`, `502` and a transport failure are not repeated.
Future<String> fetchPleyaSubtitleWhenReady({
  required Future<MediaServerResponse> Function(AbortController abort) get,
  required AbortController abort,
  Duration limit = pleyaSubtitleRetryLimit,
}) async {
  final attempt = AbortController();
  unawaited(abort.trigger.then((_) => attempt.abort()));
  final deadline = Timer(limit, attempt.abort);
  try {
    while (true) {
      final response = await get(attempt);
      if (attempt.isAborted) throw const PleyaSubtitleUnavailable(null);
      final body = response.data;
      if (response.statusCode == 200 && body is String && body.isNotEmpty) return body;
      if (response.statusCode != 503) throw PleyaSubtitleUnavailable(response.statusCode);
      await _pause(pleyaRetryAfter(_retryAfterHeader(response)), attempt);
      if (attempt.isAborted) throw const PleyaSubtitleUnavailable(null);
    }
  } finally {
    deadline.cancel();
  }
}

String? _retryAfterHeader(MediaServerResponse response) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == 'retry-after') return entry.value;
  }
  return null;
}

Future<void> _pause(Duration wait, AbortController abort) {
  final done = Completer<void>();
  final timer = Timer(wait, done.complete);
  unawaited(
    abort.trigger.then((_) {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    }),
  );
  return done.future;
}

/// Writes [text] under the app's temporary directory; the player deletes it.
Future<File> writePleyaSubtitleFile(String text, String format, {Directory? directory}) async {
  final root = directory ?? await getTemporaryDirectory();
  final folder = Directory(p.join(root.path, 'pleya_subtitles'));
  await folder.create(recursive: true);
  return File(p.join(folder.path, '${const Uuid().v4()}.$format')).writeAsString(text, flush: true);
}
