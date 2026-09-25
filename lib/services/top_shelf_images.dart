import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart' show FileInfo;
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
  TopShelfImages({Future<File> Function(String url)? fetch, this.timeout = const Duration(seconds: 20)})
    : _fetch = fetch ?? _download;

  final Future<File> Function(String url) _fetch;
  final Duration timeout;

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
  /// artwork and the remote URL may carry a token. Files in [dir] that no
  /// current item uses are deleted, so the folder holds one shelf at most.
  Future<List<Map<String, dynamic>>> localize(List<Map<String, dynamic>> items, Directory dir) async {
    await dir.create(recursive: true);
    final stored = await Future.wait(items.map((item) => _store(item, dir)));
    final result = [for (final item in stored) ?item];
    final keep = {for (final item in result) p.basename(Uri.parse(item['imageUri'] as String).toFilePath())};
    await for (final entry in dir.list()) {
      if (entry is File && !keep.contains(p.basename(entry.path))) {
        try {
          await entry.delete();
        } catch (e) {
          appLogger.w('Top Shelf: could not delete a stale image', error: e);
        }
      }
    }
    return result;
  }

  Future<Map<String, dynamic>?> _store(Map<String, dynamic> item, Directory dir) async {
    final url = item['imageUri'];
    if (url is! String || url.isEmpty) return null;
    final target = File(p.join(dir.path, fileNameFor(url)));
    try {
      if (!await target.exists()) {
        final source = await _fetch(url).timeout(timeout);
        // Copy then rename, so the extension never reads a half-written file.
        final partial = await source.copy('${target.path}.part');
        await partial.rename(target.path);
      }
      return {...item, 'imageUri': target.uri.toString()};
    } catch (e) {
      // The URL may carry a token; log the title only.
      appLogger.w('Top Shelf: image for ${item['title']} not stored', error: e.runtimeType);
      return null;
    }
  }
}
