import 'dart:async';
import 'dart:collection';
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'download_artwork_helpers.dart';
import 'local_library/local_library_sync.dart' show LocalPosterResult;

import 'package:cached_network_image_ce/cached_network_image.dart' show FileResponse;
// CE's public conditional export hides the IO-only httpClientFactory parameter
// behind a narrower unsupported-platform stub.
// ignore: implementation_imports
import 'package:cached_network_image_ce/src/cache/default_cache_manager.dart' as ce_cache;
import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart';

final _artworkHttpClient = MediaServerHttpClient(usePlexApiClient: true);
final _artworkRequestLimiter = _RequestLimiter(6);
// Across retiring/new profile providers as well as one sequential sync.
final _localPosterRevalidationLimiter = _RequestLimiter(3);

/// How long one artwork download may wait for its response headers, and how
/// long its body may go without a chunk. Without these a socket that died
/// while the app was suspended never reports back, keeps one of the few
/// download slots, and leaves its tile on the placeholder until a restart.
@visibleForTesting
Duration artworkHeaderTimeout = const Duration(seconds: 15);
@visibleForTesting
Duration artworkBodyIdleTimeout = const Duration(seconds: 20);

/// Tells artwork widgets that a failed image is worth another attempt: the app
/// came back from the background, or a server came back online. Widgets that
/// show a loaded image ignore it.
class ArtworkReloadSignal extends ChangeNotifier {
  ArtworkReloadSignal._();
  static final ArtworkReloadSignal instance = ArtworkReloadSignal._();

  void requestReload() => notifyListeners();
}

/// On-disk location for the artwork cache.
///
/// [getApplicationCacheDirectory] maps to iOS `Library/Caches`, which the OS
/// purges under storage pressure — dropping the whole poster cache and forcing
/// a re-download of every image on the next launch. On iOS and macOS,
/// Application Support is not auto-purged, so the cache survives restarts. On
/// tvOS there is no such place: the app's path provider maps Application
/// Support into `Library/Caches` (the only writable directory), so tvOS may
/// still empty this cache. A dedicated subfolder keeps the 3000-object pruning
/// scoped to artwork.
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

  /// Artwork requests holding a download slot right now.
  @visibleForTesting
  static int get debugInFlightDownloads => _inFlightArtworkDownloads.length;

  /// The client every artwork download goes through, over [inner], so a test
  /// can drive the limiter and the timeouts without a cache directory.
  @visibleForTesting
  static http.Client debugHttpClient(http.Client inner) => _SharedHttpClient(inner);

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

  /// Stop answering for [baseUrl]'s origin. With [owner], only when [owner]
  /// is still the registered supplier: a client replaced by a newer one for
  /// the same server (a profile rebind) must not take the newer one's
  /// headers with it when it closes after it.
  static void unregister(String baseUrl, {Future<Map<String, String>> Function()? owner}) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return;
    final origin = originOf(uri);
    if (owner != null && !identical(_suppliers[origin], owner)) return;
    _suppliers.remove(origin);
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

  // One entry per in-flight request. Tracked as a set so a client that is
  // (against CE's usual one-per-download pattern) reused for multiple sends
  // never overwrites and leaks an earlier permit.
  final Set<_ArtworkDownload> _downloads = {};

  _SharedHttpClient(this._inner);

  void _finish(_ArtworkDownload download) {
    if (!_downloads.remove(download)) return;
    _inFlightArtworkDownloads.remove(download);
    download.permit.release();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Applied before the permit so a slow token refresh does not hold one of
    // the few concurrent artwork slots.
    final auth = await ArtworkAuthorizationRegistry.headersFor(request.url);
    for (final entry in auth.entries) {
      request.headers.putIfAbsent(entry.key, () => entry.value);
    }
    final permit = await _artworkRequestLimiter.acquire();
    final download = _ArtworkDownload(permit, request.url);
    _downloads.add(download);
    _inFlightArtworkDownloads.add(download);
    try {
      final response = await _inner
          .send(_abortableCopy(request, download.abortTrigger))
          .timeout(
            artworkHeaderTimeout,
            onTimeout: () {
              download.abort();
              throw TimeoutException('Artwork response headers', artworkHeaderTimeout);
            },
          );
      download.unreadBody = response.stream;
      return http.StreamedResponse(
        _guardBody(response.stream, download, () => _finish(download)),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error) {
      _logArtworkFailure(download, error);
      _finish(download);
      rethrow;
    }
  }

  @override
  void close() {
    // Backstop: CE throws on a non-200/202 status BEFORE reading the body, so
    // the stream-drain release never fires. CE always calls close() per
    // download, so release any still-held permit here — otherwise a few
    // 404/500 posters would exhaust the limiter and freeze all artwork.
    for (final download in _downloads.toList()) {
      download.abort();
      // An abort after the headers does not free a body nobody listens to: on
      // the dart:io client it stays paused and its connection never returns to
      // the pool. Listening and cancelling does.
      final unread = download.unreadBody;
      download.unreadBody = null;
      if (unread != null) unawaited(unread.listen(null, onError: (Object _) {}).cancel());
      _finish(download);
    }
  }
}

/// One artwork request between acquiring its permit and letting it go.
class _ArtworkDownload {
  _ArtworkDownload(this.permit, this.url);

  final _RequestPermit permit;
  final Uri url;
  final Stopwatch elapsed = Stopwatch()..start();
  final Completer<void> _abort = Completer<void>();

  /// Set when the app was suspended while this request was in flight. tvOS
  /// drops every socket in that state and such a request never calls back.
  bool crossedSuspend = false;

  /// The transport's response body until someone starts reading it.
  Stream<List<int>>? unreadBody;

  Future<void> get abortTrigger => _abort.future;

  void abort() {
    if (!_abort.isCompleted) _abort.complete();
  }
}

final Set<_ArtworkDownload> _inFlightArtworkDownloads = {};

/// Marks the artwork downloads that are in flight while the app goes to the
/// background. See [abortArtworkDownloadsFromBeforeSuspend].
void markArtworkDownloadsSuspended() {
  for (final download in _inFlightArtworkDownloads) {
    download.crossedSuspend = true;
  }
}

/// Aborts the downloads that were in flight when the app was suspended and
/// asks failed tiles to try again. Returns how many were aborted.
///
/// Downloads started after the resume are left alone: on desktop a resume is
/// every window focus, and aborting healthy requests there would only cost a
/// second download.
int abortArtworkDownloadsFromBeforeSuspend() {
  final stale = _inFlightArtworkDownloads.where((download) => download.crossedSuspend).toList();
  for (final download in stale) {
    download.abort();
  }
  if (stale.isNotEmpty) {
    appLogger.i(
      'Artwork: aborted ${stale.length} download(s) from before the suspend '
      '(active=${_artworkRequestLimiter.active} queued=${_artworkRequestLimiter.queued})',
    );
  }
  ArtworkReloadSignal.instance.requestReload();
  return stale.length;
}

/// Download slots in use and waiting, for log lines.
String artworkDownloadStats() =>
    'artworkActive=${_artworkRequestLimiter.active} artworkQueued=${_artworkRequestLimiter.queued}';

DateTime _lastArtworkFailureLog = DateTime.fromMillisecondsSinceEpoch(0);
int _artworkFailuresSinceLog = 0;

/// One line per failed download would bury a log when a server is down, so
/// failures are counted and reported at most once every five seconds. Host and
/// path only: Plex and Jellyfin carry their token in the query string.
void _logArtworkFailure(_ArtworkDownload download, Object error) {
  _artworkFailuresSinceLog++;
  final now = DateTime.now();
  if (now.difference(_lastArtworkFailureLog) < const Duration(seconds: 5)) return;
  appLogger.w(
    'Artwork download failed ($_artworkFailuresSinceLog since last log): ${error.runtimeType} '
    'after ${download.elapsed.elapsedMilliseconds}ms host=${download.url.host} path=${download.url.path} '
    'active=${_artworkRequestLimiter.active} queued=${_artworkRequestLimiter.queued}',
  );
  _artworkFailuresSinceLog = 0;
  _lastArtworkFailureLog = now;
}

/// A copy of [request] that [abortTrigger] can cut short. CE builds a plain
/// request, which the transport could otherwise never abandon.
http.BaseRequest _abortableCopy(http.BaseRequest request, Future<void> abortTrigger) {
  final own = request is http.Abortable ? request.abortTrigger : null;
  final copy =
      http.AbortableStreamedRequest(
          request.method,
          request.url,
          abortTrigger: own == null ? abortTrigger : Future.any<void>([abortTrigger, own]),
        )
        ..headers.addAll(request.headers)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..contentLength = request.contentLength;
  unawaited(request.finalize().pipe(copy.sink).catchError((Object _) {}));
  return copy;
}

Stream<List<int>> _guardBody(Stream<List<int>> stream, _ArtworkDownload download, void Function() done) async* {
  download.unreadBody = null;
  try {
    final guarded = stream.timeout(
      artworkBodyIdleTimeout,
      onTimeout: (sink) {
        download.abort();
        sink.addError(TimeoutException('Artwork response body', artworkBodyIdleTimeout));
        sink.close();
      },
    );
    await for (final chunk in guarded) {
      yield chunk;
    }
  } catch (error) {
    _logArtworkFailure(download, error);
    rethrow;
  } finally {
    done();
  }
}

class _RequestLimiter {
  final int maxConcurrent;
  final Queue<Completer<_RequestPermit>> _queue = Queue<Completer<_RequestPermit>>();
  int _active = 0;

  _RequestLimiter(this.maxConcurrent);

  int get active => _active;
  int get queued => _queue.length;

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

/// Conditional network validation for permanent local posters. This deliberately
/// awaits the HTTP answer rather than accepting CE's first (possibly stale)
/// FileInfo. Uses the existing shared transport/auth/limiter, not another cache.
Future<LocalPosterResult> revalidateLocalPoster(
  String url,
  Map<String, dynamic> validators, {
  Map<String, String> headers = const {},
  http.Client? transport,
}) async {
  final permit = await _localPosterRevalidationLimiter.acquire();
  final variant = artworkStorageKey(url);
  final sameVariant = validators['variant'] == variant;
  final client = transport ?? _SharedHttpClient(_artworkHttpClient.inner);
  final abort = AbortController();
  final timeout = Timer(const Duration(seconds: 30), abort.abort);
  try {
    final request = http.AbortableRequest('GET', Uri.parse(url), abortTrigger: abort.trigger);
    request.headers.addAll({
      ...headers,
      'Cache-Control': 'no-cache',
      if (sameVariant && validators['etag'] is String) 'If-None-Match': validators['etag'] as String,
      if (sameVariant && validators['etag'] == null && validators['lastModified'] is String)
        'If-Modified-Since': validators['lastModified'] as String,
    });
    final response = await client.send(request);
    final etag = response.headers['etag'];
    final modified = response.headers['last-modified'];
    if (response.statusCode == 304 &&
        sameVariant &&
        (validators['etag'] != null || validators['lastModified'] != null)) {
      await response.stream.drain<void>();
      return LocalPosterResult(
        variant: variant,
        etag: etag ?? validators['etag'] as String?,
        lastModified: modified ?? validators['lastModified'] as String?,
      );
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw StateError('Artwork HTTP ${response.statusCode}');
    }
    // Match the existing server's source-image bound; never buffer an entire
    // artwork set. Stop reading an oversized or empty body, retain prior bytes.
    const maxBytes = 12 * 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) throw StateError('Artwork body exceeds limit');
      bytes.add(chunk);
    }
    if (bytes.isEmpty) throw StateError('Empty artwork body');
    return LocalPosterResult(bytes: bytes.takeBytes(), variant: variant, etag: etag, lastModified: modified);
  } finally {
    timeout.cancel();
    abort.abort();
    permit.release();
    // The wrapper releases permits; it does not close the app-wide transport.
    if (transport == null) client.close();
  }
}
