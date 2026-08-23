import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../connection/connection.dart';
import '../exceptions/media_server_exceptions.dart';
import '../media/download_resolution.dart';
import '../media/ids.dart';
import '../media/library_filter_result.dart';
import '../media/library_first_character.dart';
import '../media/library_query.dart';
import '../media/live_tv_dvr_support.dart';
import '../media/live_tv_support.dart';
import '../media/media_backend.dart';
import '../media/media_file_info.dart';
import '../media/media_hub.dart';
import '../media/media_identity.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_playlist.dart';
import '../media/media_server_client.dart';
import '../media/media_sort.dart';
import '../media/media_source_info.dart';
import '../media/media_version.dart';
import '../media/noop_live_tv_support.dart';
import '../media/playback_report_metadata.dart';
import '../media/server_capabilities.dart';
import '../i18n/strings.g.dart';
import '../models/pleya_server/pleya_wire.dart';
import '../models/pleya_server/pleya_wire_library.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids.dart';
import '../utils/media_server_http_client.dart';
import '../utils/media_server_timeouts.dart';
import 'api_cache.dart';
import 'playback_initialization_types.dart';
import 'pleya_server_api_cache.dart';
import 'pleya_server_auth_service.dart';
import 'image_cache_service.dart';
import 'pleya_server_capabilities.dart';
import 'pleya_server_cursor_ledger.dart';
import 'pleya_server_mappers.dart';
import 'pleya_server_session.dart';
import 'pleya_server_watch_ledger.dart';
import 'scrub_preview_source.dart';

part 'pleya_server_client/parts/seam.dart';
part 'pleya_server_client/parts/artwork.dart';
part 'pleya_server_client/parts/browse.dart';
part 'pleya_server_client/parts/search.dart';
part 'pleya_server_client/parts/playback.dart';
part 'pleya_server_client/parts/unsupported.dart';

/// [MediaServerClient] over a Pleya Server, speaking Pleya Protocol v1.
///
/// Modelled on the Jellyfin client rather than the Plex one, because the shape
/// matches: one endpoint, one identity, no account cloud in front and no server
/// discovery. What it deliberately does not copy is Jellyfin's semantics. The
/// protocol is its own thing and the mapper is the only place the two
/// vocabularies meet.
///
/// ## Capabilities come off the wire
///
/// `GET /info` is the source of truth, refreshed on every health probe. Before
/// the first successful answer the client runs on
/// [PleyaServerCapabilityResolver.unknown], which claims nothing at all: a
/// connection that has not answered is not a server that browses, and a screen
/// that assumes otherwise calls an endpoint that may not be there.
///
/// ## What this covers
///
/// PS-3 brought libraries, browsing, children, hubs, search and artwork. PS-4
/// adds direct play and watch state, with the ownership model from DEC-049
/// behind it. Downloads, playlists, collections, favourites, ratings and Live
/// TV are later phases and answer through `_PleyaServerUnsupportedMethods`.
// The private fields below are assigned from named constructor parameters
// rather than through initializing formals, because Dart has no private named
// parameter. dart_code_linter flags the pattern; here it is unavoidable.
// ignore_for_file: prefer_initializing_formals
class PleyaServerClient
    with
        MediaServerCacheMixin,
        _PleyaServerRequests,
        _PleyaServerBrowseMethods,
        _PleyaServerSearchMethods,
        _PleyaServerArtworkMethods,
        _PleyaServerPlaybackMethods,
        _PleyaServerUnsupportedMethods
    implements MediaServerClient, ScopedMediaServerClient, GracefullyCloseable {
  PleyaServerClient._({required PleyaServerSession session, required MediaServerHttpClient http})
    : _session = session,
      _http = http;

  /// Build a client for [connection].
  ///
  /// No network traffic happens here. The first request mints an access token
  /// from the stored refresh token, and [refreshCapabilities] fills in what the
  /// server can do; until then the client is deliberately incapable.
  ///
  /// [onConnectionUpdated] is how a rotated refresh token reaches the
  /// connection registry. Without it a restart would present a retired token
  /// and spend the chain.
  static PleyaServerClient create(
    PleyaServerConnection connection, {
    PleyaServerAuthService? auth,
    Future<void> Function(PleyaServerConnection connection)? onConnectionUpdated,
    http.Client Function()? httpClientFactory,
  }) {
    final authService = auth ?? PleyaServerAuthService(httpClientFactory: httpClientFactory);
    final session = PleyaServerSession(connection: connection, auth: authService, onTokensRotated: onConnectionUpdated);
    final client = PleyaServerClient._(
      session: session,
      http: MediaServerHttpClient(
        baseUrl: '${connection.baseUrl}$pleyaProtocolPrefix',
        defaultHeaders: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
        client: httpClientFactory?.call(),
      ),
    );
    client._registerArtworkAuthorization();
    return client;
  }

  @override
  final PleyaServerSession _session;
  final MediaServerHttpClient _http;

  @override
  final PleyaServerCursorLedger _cursors = PleyaServerCursorLedger();

  @override
  final PleyaServerWatchLedger _watchLedger = PleyaServerWatchLedger();

  bool _offlineMode = false;
  ServerCapabilities _capabilities = PleyaServerCapabilityResolver.unknown;
  PleyaCapabilities _wireCapabilities = PleyaCapabilities.unknown;

  @override
  PleyaServerConnection get connection => _session.connection;

  /// Let a revoked session spend its stored refresh token one more time.
  /// Only ever driven by an explicit user action; see
  /// [PleyaServerSession.retryAfterRejection] for why a timer must not call
  /// this.
  void retrySessionAfterRejection() => _session.retryAfterRejection();

  /// Raw protocol capabilities as the server last reported them. The client's
  /// own calls gate on this; [capabilities] is the app-facing translation and
  /// is narrower by design.
  @override
  PleyaCapabilities get wireCapabilities => _wireCapabilities;

  @override
  ServerId get serverId => ServerId(connection.serverId);

  /// The connection row id. Cache rows key on this rather than on the server
  /// id so two connections to the same server (a rare but legal setup) do not
  /// share cached answers.
  @override
  String get scopedServerId => connection.id;

  @override
  String? get serverName => connection.serverName;

  @override
  MediaBackend get backend => MediaBackend.pleyaServer;

  @override
  ServerCapabilities get capabilities => _capabilities;

  @override
  ApiCache get cache => PleyaServerApiCache.instance;

  @override
  bool get isOfflineMode => _offlineMode;

  @override
  void setOfflineMode(bool offline) => _offlineMode = offline;

  /// The protocol has no server-side watched threshold. 90% matches what both
  /// other backends use, so the same title crosses the line at the same place
  /// on every server a profile can reach, and it is the same fraction the
  /// server falls back to when a report carries no `completed`.
  @override
  double get watchedThreshold => 0.9;

  /// A stopped report past the threshold carries `completed: true`, and the
  /// server marks the item watched from it. The in-player auto-scrobble must
  /// therefore not also call [markWatched]: that would be a second explicit
  /// action, a second revision, and on a tracker a second scrobble.
  @override
  bool get marksWatchedOnPlaybackStopped => wireCapabilities.watchState;

  /// The access token as a header, never as a query parameter.
  ///
  /// mpv can set headers, so the stream token that exists for players that
  /// cannot stays out of this path: a credential that never enters a URL never
  /// enters a log, a referrer or a shell history either.
  ///
  /// The value is whatever the session last minted. That is not a cache with a
  /// staleness problem: every progress report during playback goes through the
  /// authorised path, so the header the player would be handed on a reopen is
  /// at most one report old. Before the first request there is nothing to hand
  /// over, and [getPlaybackInitialization] awaits a token precisely so the URL
  /// it returns is openable straight away.
  @override
  Map<String, String> get streamHeaders {
    final token = _session.cachedAccessToken;
    return token == null ? const {} : {'Authorization': 'Bearer $token'};
  }

  @override
  void close() {
    _unregisterArtworkAuthorization();
    _http.close();
  }

  @override
  Future<void> closeGracefully({Duration drainTimeout = const Duration(seconds: 2)}) async {
    close();
  }

  /// Re-read `GET /info` and apply what it says.
  ///
  /// Public and unauthenticated, so this works even when the token is dead,
  /// which is what makes it usable as the first half of a health probe.
  Future<PleyaInfo?> refreshCapabilities() async {
    try {
      final response = await _http.get('/info', timeout: MediaServerTimeouts.jellyfinProbe);
      if (response.statusCode != 200) return null;
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final info = PleyaInfo.fromJson(data);
      _wireCapabilities = info.capabilities;
      _capabilities = PleyaServerCapabilityResolver.resolve(info.capabilities);
      return info;
    } catch (e) {
      appLogger.d('PleyaServerClient: /info unavailable', error: e);
      return null;
    }
  }

  /// Reachable *and* the token still works.
  ///
  /// Two calls on purpose. `/info` is public, so a server that answers it while
  /// `/server` returns 401 is up with a dead session, and that is a different
  /// banner than a server that is down. Doing only the authenticated call would
  /// collapse the two into "offline".
  @override
  Future<HealthStatus> checkHealth() async {
    final info = await refreshCapabilities();
    if (info == null) return HealthStatus.offline;
    if (info.auth.setupRequired) {
      // The server was reset and has no owner again. Every stored token is
      // meaningless, and calling that "offline" would hide the one thing the
      // user has to do about it.
      return HealthStatus.authError;
    }
    try {
      final response = await _authorizedGet('/server', timeout: MediaServerTimeouts.jellyfinProbe);
      if (response.statusCode == 401 || response.statusCode == 403) return HealthStatus.authError;
      if (response.statusCode >= 400) return HealthStatus.offline;
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final detail = PleyaServerDetail.fromJson(data);
        if (detail.name.isNotEmpty && detail.name != connection.serverName) {
          appLogger.i('PleyaServerClient: server renamed to ${detail.name}');
        }
      }
      return HealthStatus.online;
    } on MediaServerAuthException catch (e) {
      return _provesSignedOut(e) ? HealthStatus.authError : HealthStatus.offline;
    } catch (_) {
      return HealthStatus.offline;
    }
  }

  /// Whether [error] is evidence that the session is actually gone, as opposed
  /// to evidence that this attempt did not work.
  ///
  /// [MediaServerAuthException] is a family, and minting a token throws more
  /// than rejections: a rate limiter saying "later", a proxy answering the
  /// refresh with an HTML page, a wire-contract mismatch, a 409. Catching the
  /// family and calling all of it `authError` is what put "Sessie verlopen"
  /// over a server that was merely throttled. Plex and Jellyfin already gate on
  /// a proven 401 or 403; this brings Pleya Server in line.
  static bool _provesSignedOut(MediaServerAuthException error) => switch (error) {
    // Throttled. Retrying later is exactly right, and telling someone to sign
    // in again does nothing for them.
    PleyaRateLimitedException() => false,
    // No token at all. Nothing to retry, only a sign-in helps.
    PleyaNoStoredCredentialsException() => true,
    // Pleya's own verdict, both of them carrying a protocol code.
    PleyaRefreshChainRevokedException() => true,
    PleyaAuthRejectedException() => true,
    // Anything else: a 409 conflict, a refresh answer that was not the
    // contract, a bare 401 from a box in between. None of those is proof.
    _ => false,
  };

  @override
  Future<bool> isHealthy() async => (await checkHealth()) == HealthStatus.online;

  @override
  Future<String?> getMachineIdentifier() async {
    final info = await refreshCapabilities();
    return info?.serverId ?? (connection.serverId.isEmpty ? null : connection.serverId);
  }

  // ---------------------------------------------------------------------------
  // The authorized request path
  // ---------------------------------------------------------------------------

  /// GET an authenticated protocol path, minting a token when needed and
  /// retrying exactly once on a 401.
  ///
  /// The single retry is not a general-purpose backoff. It covers one specific
  /// case: a server that restarted and dropped its signing key, which makes a
  /// token the session still believes in come back rejected. Retrying more than
  /// once would turn a genuinely revoked chain into a loop.
  Future<MediaServerResponse> _authorizedGet(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? timeout,
    AbortController? abort,
  }) async {
    final response = await _http.get(
      path,
      queryParameters: queryParameters,
      headers: await _session.authHeaders(),
      timeout: timeout,
      abort: abort,
    );
    if (response.statusCode != 401) return response;
    _session.invalidateAccessToken();
    return _http.get(
      path,
      queryParameters: queryParameters,
      headers: await _session.authHeaders(),
      timeout: timeout,
      abort: abort,
    );
  }

  /// POST a protocol path with a JSON body and hand back its JSON object.
  ///
  /// Same null contract as [_getJson]: offline mode, a non-2xx answer and a
  /// body that is not an object all answer null. A write that could not apply
  /// is not an error the UI has to render, and the interface says so.
  @override
  Future<Map<String, dynamic>?> _postJson(String path, Map<String, dynamic> body) async {
    if (_offlineMode) return null;
    try {
      final response = await _http.post(
        path,
        body: jsonEncode(body),
        headers: await _session.authHeaders(),
        timeout: MediaServerTimeouts.interactive,
      );
      if (response.statusCode == 401) {
        _session.invalidateAccessToken();
        final retry = await _http.post(
          path,
          body: jsonEncode(body),
          headers: await _session.authHeaders(),
          timeout: MediaServerTimeouts.interactive,
        );
        return retry.statusCode >= 400 ? null : _asObject(path, retry);
      }
      if (response.statusCode >= 400) {
        final error = PleyaError.tryParse(response.data);
        appLogger.d('PleyaServerClient: POST $path -> ${response.statusCode} ${error?.code ?? ''}');
        return null;
      }
      return _asObject(path, response);
    } catch (e) {
      appLogger.d('PleyaServerClient: POST $path failed', error: e);
      return null;
    }
  }

  Map<String, dynamic>? _asObject(String path, MediaServerResponse response) {
    final data = response.data;
    return data is Map<String, dynamic> ? data : null;
  }

  /// GET a protocol path and hand back its JSON object, or null.
  ///
  /// Null covers three cases the callers treat the same way: offline mode, a
  /// non-2xx answer, and a body that is not an object. A caller that has to
  /// tell them apart uses [_authorizedGet] directly, which is what
  /// [checkHealth] does.
  @override
  Future<Map<String, dynamic>?> _getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? timeout,
    AbortController? abort,
  }) async {
    if (_offlineMode) return null;
    try {
      final response = await _authorizedGet(path, queryParameters: queryParameters, timeout: timeout, abort: abort);
      if (response.statusCode >= 400) {
        final error = PleyaError.tryParse(response.data);
        appLogger.d('PleyaServerClient: $path -> ${response.statusCode} ${error?.code ?? ''}');
        return null;
      }
      final data = response.data;
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      appLogger.d('PleyaServerClient: $path failed', error: e);
      return null;
    }
  }
}
