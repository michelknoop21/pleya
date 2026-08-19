import 'dart:async';
import 'dart:collection';
import 'dart:io' show Directory;

import 'package:cached_network_image_ce/cached_network_image.dart' show FileResponse;
// CE's public conditional export hides the IO-only httpClientFactory parameter
// behind a narrower unsupported-platform stub.
// ignore: implementation_imports
import 'package:cached_network_image_ce/src/cache/default_cache_manager.dart' as ce_cache;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/media_server_http_client.dart';

final _artworkHttpClient = MediaServerHttpClient(usePlexApiClient: true);
final _artworkRequestLimiter = _RequestLimiter(6);

/// Durable on-disk location for the artwork cache.
///
/// [getApplicationCacheDirectory] maps to iOS `Library/Caches`, which the OS
/// purges under storage pressure — dropping the whole poster cache and forcing
/// a re-download of every image on the next launch. Application Support is not
/// auto-purged, so the cache survives restarts. A dedicated subfolder keeps the
/// 3000-object pruning scoped to artwork.
Future<Directory> _artworkCacheDirectory() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/artwork_cache');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<void> closeArtworkHttpClientGracefully({Duration drainTimeout = const Duration(seconds: 5)}) {
  return _artworkHttpClient.closeGracefully(drainTimeout: drainTimeout);
}

/// Shared cache manager for media-server image artwork. Used for both Plex and
/// Jellyfin artwork (the class name predates Jellyfin support — it's
/// backend-neutral).
///
/// Uses the platform-native HTTP client so iOS/macOS (CupertinoClient) and
/// Android (CronetClient) benefit from HTTP/2, while the wrapper below keeps
/// image fan-out bounded so weak TV devices don't decode a whole rail at once.
/// On Linux this uses the same finite-connection tuning as Plex API traffic.
class PlexImageCacheManager extends ce_cache.DefaultCacheManager {
  static final PlexImageCacheManager instance = PlexImageCacheManager._();

  PlexImageCacheManager._()
    : super(
        stalePeriod: const Duration(days: 14),
        maxNrOfCacheObjects: 3000,
        httpClientFactory: () => _SharedHttpClient(_artworkHttpClient.inner),
        cacheDirectoryProvider: _artworkCacheDirectory,
      );

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) {
    // Plezy already requests server-sized artwork URLs. Avoid CE's disk-resize
    // path, which decodes downloaded images before writing resized PNG copies.
    return getFileStream(url, key: key, headers: headers, withProgress: withProgress);
  }
}

/// Per-origin authorization for artwork downloads.
///
/// Plex and Jellyfin put their token in the artwork URL, so their images need
/// nothing here. Pleya Protocol does not allow that: `GET /artwork/{id}` is
/// class `authenticated` and accepts a bearer header only, with the stream
/// token explicitly scoped to `/stream` and `/subtitles`. Putting an access
/// token in a query string would be a protocol violation, not a shortcut.
///
/// The app renders artwork through `CachedNetworkImage`, which carries a URL
/// and no headers, and threading a header parameter through every image call
/// site would be a refactor with a wide blast radius for one backend. This
/// registry solves it at the one point every artwork download already passes
/// through: a backend registers a header supplier for its origin, and
/// [_SharedHttpClient] applies it.
///
/// Backend-neutral on purpose. It knows about origins and headers, not about
/// Pleya Server.
class ArtworkAuthorizationRegistry {
  ArtworkAuthorizationRegistry._();

  static final Map<String, Future<Map<String, String>> Function()> _suppliers = {};

  /// The `scheme://host:port` form used as the registry key. Comparing whole
  /// origins rather than hosts keeps two servers on one machine apart.
  static String originOf(Uri uri) =>
      Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null).toString();

  static void register(String baseUrl, Future<Map<String, String>> Function() headers) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return;
    _suppliers[originOf(uri)] = headers;
  }

  static void unregister(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return;
    _suppliers.remove(originOf(uri));
  }

  /// Headers for [uri], or an empty map when nothing is registered for its
  /// origin. A supplier that throws yields nothing rather than failing the
  /// download: a poster that 401s is a missing poster, not a crash.
  static Future<Map<String, String>> headersFor(Uri uri) async {
    final supplier = _suppliers[originOf(uri)];
    if (supplier == null) return const {};
    try {
      return await supplier();
    } catch (_) {
      return const {};
    }
  }

  @visibleForTesting
  static void clear() => _suppliers.clear();
}

/// CE closes each factory-created client after a download. Wrap the app-wide
/// shared client so image requests reuse its platform transport without
/// transferring ownership of its lifecycle, and cap artwork fan-out globally.
///
/// CE creates one client per download and always calls [close] in a finally.
/// Crucially, on a non-200/202 status it throws *before ever reading the body
/// stream* (default_cache_manager `_downloadFile`), so tying the permit release
/// to the body draining leaks a permit on every 404/500. A handful of missing
/// or server-rejected posters would then exhaust the global limiter and freeze
/// ALL artwork until an app restart. [close] is the guaranteed backstop: it
/// releases the permit whether or not the body was ever consumed.
class _SharedHttpClient extends http.BaseClient {
  final http.Client _inner;

  // One permit per in-flight request. Tracked as a set so a client that is
  // (against CE's usual one-per-download pattern) reused for multiple sends
  // never overwrites and leaks an earlier permit.
  final Set<_RequestPermit> _permits = {};

  _SharedHttpClient(this._inner);

  void _releaseOne(_RequestPermit permit) {
    if (_permits.remove(permit)) permit.release();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Applied before the permit so a slow token refresh does not hold one of
    // the few concurrent artwork slots.
    final auth = await ArtworkAuthorizationRegistry.headersFor(request.url);
    if (auth.isNotEmpty) request.headers.addAll(auth);
    final permit = await _artworkRequestLimiter.acquire();
    _permits.add(permit);
    try {
      final response = await _inner.send(request);
      return http.StreamedResponse(
        _releaseWhenDone(response.stream, () => _releaseOne(permit)),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      _releaseOne(permit);
      rethrow;
    }
  }

  @override
  void close() {
    // Backstop: CE throws on a non-200/202 status BEFORE reading the body, so
    // the stream-drain release never fires. CE always calls close() per
    // download, so release any still-held permit here — otherwise a few
    // 404/500 posters would exhaust the limiter and freeze all artwork.
    for (final permit in _permits.toList()) {
      _releaseOne(permit);
    }
  }
}

Stream<List<int>> _releaseWhenDone(Stream<List<int>> stream, void Function() release) async* {
  try {
    await for (final chunk in stream) {
      yield chunk;
    }
  } finally {
    release();
  }
}

class _RequestLimiter {
  final int maxConcurrent;
  final Queue<Completer<_RequestPermit>> _queue = Queue<Completer<_RequestPermit>>();
  int _active = 0;

  _RequestLimiter(this.maxConcurrent);

  Future<_RequestPermit> acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value(_RequestPermit(this));
    }

    final completer = Completer<_RequestPermit>();
    _queue.add(completer);
    return completer.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete(_RequestPermit(this));
      return;
    }
    if (_active > 0) _active--;
  }
}

class _RequestPermit {
  final _RequestLimiter _limiter;
  bool _released = false;

  _RequestPermit(this._limiter);

  void release() {
    if (_released) return;
    _released = true;
    _limiter._release();
  }
}
