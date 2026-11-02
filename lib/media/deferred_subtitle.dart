import 'dart:io';

import '../utils/media_server_http_client.dart' show AbortController;

/// A subtitle track that only exists as a file once the server has prepared it.
///
/// mpv fetches a subtitle URL once and gives up, so a backend whose answer can
/// be "not yet" hands the player this instead of a URL. [load] does the waiting
/// and resolves to a local file the caller owns. Playback never waits for it.
class DeferredSubtitle {
  const DeferredSubtitle({this.title, this.language, required this.load});

  final String? title;
  final String? language;
  final Future<File> Function(AbortController abort) load;
}
