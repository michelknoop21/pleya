import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart' show FileInfo, HttpExceptionWithStatus;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../utils/app_logger.dart';
import 'image_cache_service.dart';

/// Copies Top Shelf carousel artwork into the app-group container.
///
/// The Top Shelf extension cannot send headers, and Pleya Server artwork needs
/// a bearer header, so its backdrops rendered black. The app downloads each
/// image through the shared artwork transport (which adds that header for the
/// origins that registered one) and hands the extension a `file://` URL. Plex
/// and Jellyfin take the same path, which also keeps their token-bearing URLs
/// out of the shared payload.
class TopShelfImages {
  TopShelfImages({
    Future<File> Function(String url)? fetch,
    this.timeout = const Duration(seconds: 20),
    this.retryAfter = const Duration(minutes: 5),
  }) : _fetch = fetch ?? _download;

  final Future<File> Function(String url) _fetch;
  final Duration timeout;

  /// How long a URL whose download failed is left alone. The shelf resyncs on every
  /// Continue Watching refresh, every 20 to 40 seconds during playback, and
  /// without a pause it restarted all ~25 full-screen downloads each time.
  final Duration retryAfter;

  /// Downloads still running, across syncs, with their start. [timeout] stops
  /// the wait, not the download, so the next sync joins the running one
  /// instead of starting a second copy of it. One older than three times
  /// [timeout] is taken for hung and replaced, or it would hold that image off
  /// the shelf until the app restarts.
  final Map<String, ({Future<File> download, DateTime started})> _inFlight = {};
  final Map<String, DateTime> _retryAt = {};

  /// Through the app's artwork cache, so an image the Home already showed is
  /// not downloaded again.
  static Future<File> _download(String url) async {
    final info = await PlexImageCacheManager.instance.getFileStream(url).firstWhere((r) => r is FileInfo);
    return (info as FileInfo).file;
  }

  /// A name derived from a one-way hash of the URL: no path, id or token in
  /// it, and a changed image (or a rotated token) gets a new file.
  static String fileNameFor(String imageUri) =>
      'ts_${sha256.convert(utf8.encode(imageUri)).toString().substring(0, 32)}.jpg';

  /// [items] with `imageUri` rewritten to a file in [dir]. An item whose image
  /// cannot be stored is left out, because the carousel shows nothing without
  /// artwork and the remote URL may carry a token. Old files stay until
  /// [removeUnused] runs, after the payload that replaces them is written.
  Future<List<Map<String, dynamic>>> localize(List<Map<String, dynamic>> items, Directory dir) async {
    await dir.create(recursive: true);
    final current = {for (final item in items) item['imageUri']};
    _retryAt.removeWhere((url, _) => !current.contains(url));
    // Items can share an image (two episodes of one series both carry the
    // show's backdrop) and so a file name. They share one download instead of
    // racing on one `.part` file, where the loser dropped out of the carousel.
    final downloads = <String, Future<bool>>{};
    final stored = await Future.wait(items.map((item) => _store(item, dir, downloads)));
    return [for (final item in stored) ?item];
  }

  /// Deletes the files in [dir] that [items] (a [localize] result) does not
  /// use, so the folder holds one shelf at most. Run it once the payload with
  /// [items] is written: until then the previous payload still points at the
  /// old files, and tvOS may read it.
  Future<void> removeUnused(List<Map<String, dynamic>> items, Directory dir) async {
    final keep = {for (final item in items) p.basename(Uri.parse(item['imageUri'] as String).toFilePath())};
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is File && !keep.contains(p.basename(entry.path))) {
        try {
          await entry.delete();
        } catch (e) {
          appLogger.w('Top Shelf: could not delete a stale image', error: e);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _store(
    Map<String, dynamic> item,
    Directory dir,
    Map<String, Future<bool>> downloads,
  ) async {
    final url = item['imageUri'];
    if (url is! String || url.isEmpty) return null;
    final target = File(p.join(dir.path, fileNameFor(url)));
    final stored = await (downloads[target.path] ??= _save(url, target, item['title']));
    return stored ? {...item, 'imageUri': target.uri.toString()} : null;
  }

  Future<bool> _save(String url, File target, Object? title) async {
    try {
      if (!await target.exists()) {
        final retryAt = _retryAt[url];
        if (retryAt != null && DateTime.now().isBefore(retryAt)) return false;
        final source = await _join(url, title).timeout(timeout);
        // Copy then rename, so the extension never reads a half-written file.
        final partial = await source.copy('${target.path}.part');
        await partial.rename(target.path);
      }
      _retryAt.remove(url);
      return true;
    } catch (e) {
      // The URL may carry a token; log the title only.
      appLogger.w('Top Shelf: image for $title not stored', error: _describe(e));
      return false;
    }
  }

  /// The running download for [url], or a new one registered in [_inFlight]
  /// until it ends. A hung download that was replaced does not unregister its
  /// successor when it ends after all.
  Future<File> _join(String url, Object? title) {
    final now = DateTime.now();
    final running = _inFlight[url];
    if (running != null && now.difference(running.started) < timeout * 3) return running.download;
    late final Future<File> download;
    bool current() => identical(_inFlight[url]?.download, download);
    download = _track(url, title, current).whenComplete(() {
      if (current()) _inFlight.remove(url);
    });
    _inFlight[url] = (download: download, started: now);
    return download;
  }

  /// [_fetch] with its failure recorded, unless a newer download replaced it
  /// ([current] false): its failure says nothing about that one. An outcome
  /// that comes after [timeout] is logged here, because [_save] has stopped
  /// listening and that late error is the actual reason the image is missing.
  Future<File> _track(String url, Object? title, bool Function() current) async {
    final watch = Stopwatch()..start();
    try {
      // Future.sync: a fetch that throws synchronously still ends after [_join]
      // registered the download, so [current] can read it.
      return await Future.sync(() => _fetch(url));
    } catch (e) {
      // Only a download that ended in an error. A timed-out one is still
      // running, and the next sync joins it.
      if (current()) _retryAt[url] = DateTime.now().add(retryAfter);
      if (watch.elapsed >= timeout) {
        appLogger.w('Top Shelf: download for $title failed after ${watch.elapsed.inSeconds} s', error: _describe(e));
      }
      rethrow;
    }
  }

  /// The error type, plus the status for an HTTP error; never the message,
  /// which may carry the URL and its token.
  static Object _describe(Object e) => e is HttpExceptionWithStatus ? 'HTTP ${e.statusCode}' : e.runtimeType;
}
