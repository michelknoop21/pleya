import 'package:http/http.dart' as http;

import '../../models/seerr/seerr_media.dart';
import '../../models/seerr/seerr_request.dart';
import '../../utils/app_logger.dart';
import '../../exceptions/media_server_exceptions.dart';
import '../../utils/media_server_http_client.dart';
import 'seerr_constants.dart';
import 'seerr_session.dart';

/// Typed seerr error so callers can distinguish auth (401), permission (403)
/// and network/other failures for user-facing messaging.
class SeerrException implements Exception {
  final String message;
  final bool isAuth;
  final bool isForbidden;
  final bool isNetwork;

  const SeerrException(this.message, {this.isAuth = false, this.isForbidden = false, this.isNetwork = false});

  factory SeerrException.auth() => const SeerrException('Not authenticated', isAuth: true);
  factory SeerrException.forbidden() => const SeerrException('Not permitted', isForbidden: true);
  factory SeerrException.network(String m) => SeerrException(m, isNetwork: true);
  factory SeerrException.http(int code, Object? body) {
    // Overseerr/Jellyseerr return {"message": ...} on failure — surface it.
    final msg = body is Map ? body['message']?.toString() : null;
    return SeerrException(msg != null && msg.isNotEmpty ? msg : 'HTTP $code');
  }

  @override
  String toString() => message;
}

/// A page of discover/search results.
typedef SeerrMediaPage = ({List<SeerrMedia> items, int page, int totalPages});

/// A user's remaining request quota.
typedef SeerrQuota = ({int? movieRemaining, int? movieLimit, int? tvRemaining, int? tvLimit});

/// A TMDB genre (id + display name) from `/genres/movie` or `/genres/tv`.
typedef SeerrGenre = ({int id, String name});

/// A streaming service from `/watchproviders/*`. [logoPath] is a TMDB path, so
/// it still needs the image base URL prefixed before use.
class SeerrWatchProvider {
  final int id;
  final String name;
  final String? logoPath;

  const SeerrWatchProvider({required this.id, required this.name, this.logoPath});

  static SeerrWatchProvider? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String || name.isEmpty) return null;
    final logo = json['logoPath'];
    return SeerrWatchProvider(id: id, name: name, logoPath: logo is String && logo.isNotEmpty ? logo : null);
  }
}

/// HTTP client for one Jellyseerr / Overseerr server, bound to a [SeerrSession].
///
/// Auth: apiKey mode sends `X-Api-Key`; plex/local modes capture the
/// `connect.sid` cookie at login and replay it as a `Cookie` header. `package:
/// http` has no cookie jar, so we track it ourselves; on a 401 we silently
/// re-authenticate (Plex token or stored local credentials) and retry once.
class SeerrClient {
  SeerrClient(this._session, {this.onSessionUpdated, this.plexTokenProvider, http.Client? httpClient})
    : _http = MediaServerHttpClient(
        client: httpClient,
        baseUrl: '${SeerrConstants.normalizeBaseUrl(_session.baseUrl)}${SeerrConstants.apiPrefix}',
        connectTimeout: SeerrConstants.requestTimeout,
        receiveTimeout: SeerrConstants.requestTimeout,
      );

  SeerrSession _session;
  final MediaServerHttpClient _http;

  /// Called whenever the session mutates (cookie refresh, user cached) so the
  /// provider can persist it.
  final void Function(SeerrSession session)? onSessionUpdated;

  /// Supplies the current Plex token for silent re-auth in plex mode.
  final Future<String?> Function()? plexTokenProvider;

  SeerrSession get session => _session;

  Map<String, dynamic>? _cachedStatus;
  DateTime? _statusFetchedAt;

  void dispose() => _http.close();

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// `POST /auth/plex`. Captures the session cookie and caches the user.
  Future<SeerrSession> loginWithPlexToken(String authToken) async {
    final resp = await _rawSend(() => _http.post('/auth/plex', body: {'authToken': authToken}, headers: const {}));
    _throwIfError(resp);
    _session = _session.copyWith(cookie: _extractCookie(resp.headers) ?? _session.cookie);
    _applyUser(resp.data);
    _emit();
    return _session;
  }

  /// `POST /auth/local`. Keeps credentials for later silent re-auth.
  Future<SeerrSession> loginLocal(String email, String password) async {
    final resp = await _rawSend(
      () => _http.post('/auth/local', body: {'email': email, 'password': password}, headers: const {}),
    );
    _throwIfError(resp);
    _session = _session.copyWith(
      cookie: _extractCookie(resp.headers) ?? _session.cookie,
      email: email,
      password: password,
    );
    _applyUser(resp.data);
    _emit();
    return _session;
  }

  /// `GET /status` — server version + config. TTL-cached (~60s).
  Future<Map<String, dynamic>> getStatus({bool force = false}) async {
    final cached = _cachedStatus;
    final at = _statusFetchedAt;
    if (!force && cached != null && at != null && DateTime.now().difference(at) < SeerrConstants.statusCacheTtl) {
      return cached;
    }
    final resp = await _send(() => _http.get('/status', headers: _authHeaders()));
    final data = resp.data is Map ? (resp.data as Map).cast<String, dynamic>() : <String, dynamic>{};
    _cachedStatus = data;
    _statusFetchedAt = DateTime.now();
    return data;
  }

  /// `GET /auth/me` — the authenticated seerr user (id, displayName,
  /// permissions). Caches those onto the session.
  Future<Map<String, dynamic>> getMe() async {
    final resp = await _send(() => _http.get('/auth/me', headers: _authHeaders()));
    final data = resp.data is Map ? (resp.data as Map).cast<String, dynamic>() : <String, dynamic>{};
    _applyUser(data);
    _emit();
    return data;
  }

  /// `GET /user/{id}/quota` — remaining request quota.
  Future<SeerrQuota> getQuota(int userId) async {
    final resp = await _send(() => _http.get('/user/$userId/quota', headers: _authHeaders()));
    final data = resp.data is Map ? resp.data as Map : const {};
    ({int? remaining, int? limit}) read(Object? q) {
      if (q is! Map) return (remaining: null, limit: null);
      return (remaining: _int(q['remaining']), limit: _int(q['limit']));
    }

    final movie = read(data['movie']);
    final tv = read(data['tv']);
    return (movieRemaining: movie.remaining, movieLimit: movie.limit, tvRemaining: tv.remaining, tvLimit: tv.limit);
  }

  // ---------------------------------------------------------------------------
  // Discover / search / detail
  // ---------------------------------------------------------------------------

  Future<SeerrMediaPage> search(String query, {int page = 1}) => _mediaPage('/search', {'query': query, 'page': page});

  /// [watchProvider] is a TMDB provider id (Netflix, Disney+, …). It only means
  /// anything together with [watchRegion], because availability is per country.
  Future<SeerrMediaPage> discoverMovies({int page = 1, int? genre, int? watchProvider, String? watchRegion}) =>
      _mediaPage('/discover/movies', {
        'page': page,
        'genre': ?genre,
        'watchProviders': ?watchProvider?.toString(),
        'watchRegion': ?watchRegion,
      });
  Future<SeerrMediaPage> discoverTv({int page = 1, int? genre, int? watchProvider, String? watchRegion}) => _mediaPage(
    '/discover/tv',
    {'page': page, 'genre': ?genre, 'watchProviders': ?watchProvider?.toString(), 'watchRegion': ?watchRegion},
  );

  /// `GET /watchproviders/{movies|tv}` — the streaming services this region has,
  /// ordered by TMDB display priority. Empty list on any hiccup: the row simply
  /// does not appear rather than breaking discover.
  Future<List<SeerrWatchProvider>> getWatchProviders({required bool movies, required String region}) async {
    try {
      final resp = await _send(
        () => _http.get(
          movies ? '/watchproviders/movies' : '/watchproviders/tv',
          queryParameters: {'watchRegion': region},
          headers: _authHeaders(),
        ),
      );
      final data = resp.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => SeerrWatchProvider.tryFromJson(e.cast<String, dynamic>()))
          .whereType<SeerrWatchProvider>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<SeerrMediaPage> discoverTrending({int page = 1}) => _mediaPage('/discover/trending', {'page': page});
  Future<SeerrMediaPage> discoverUpcomingMovies({int page = 1}) =>
      _mediaPage('/discover/movies/upcoming', {'page': page});
  Future<SeerrMediaPage> discoverUpcomingTv({int page = 1}) => _mediaPage('/discover/tv/upcoming', {'page': page});

  /// `GET /genres/movie` / `GET /genres/tv` — the TMDB genre list for filtering
  /// discover. Returns an empty list on any parse/transport hiccup.
  Future<List<SeerrGenre>> getMovieGenres() => _genres('/genres/movie');
  Future<List<SeerrGenre>> getTvGenres() => _genres('/genres/tv');

  Future<List<SeerrGenre>> _genres(String path) async {
    final resp = await _send(() => _http.get(path, headers: _authHeaders()));
    final data = resp.data;
    if (data is! List) return const [];
    final out = <SeerrGenre>[];
    for (final g in data) {
      if (g is! Map) continue;
      final id = _int(g['id']);
      final name = g['name']?.toString();
      if (id != null && name != null && name.isNotEmpty) out.add((id: id, name: name));
    }
    return out;
  }

  Future<Map<String, dynamic>> getMovie(int tmdbId) => _detail('/movie/$tmdbId');
  Future<Map<String, dynamic>> getTv(int tmdbId) => _detail('/tv/$tmdbId');

  /// Typed movie/tv detail for the media detail screen (hero, genres, cast, …).
  Future<SeerrMediaDetail> getMediaDetail({required int tmdbId, required bool isMovie}) async {
    final json = isMovie ? await getMovie(tmdbId) : await getTv(tmdbId);
    return SeerrMediaDetail.fromJson(json, mediaType: isMovie ? 'movie' : 'tv');
  }

  Future<SeerrMediaPage> getRecommendations({required int tmdbId, required bool isMovie, int page = 1}) =>
      _mediaPage('/${isMovie ? 'movie' : 'tv'}/$tmdbId/recommendations', {'page': page});

  Future<Map<String, dynamic>> _detail(String path) async {
    final resp = await _send(() => _http.get(path, headers: _authHeaders()));
    return resp.data is Map ? (resp.data as Map).cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<SeerrMediaPage> _mediaPage(String path, Map<String, dynamic> query) async {
    final resp = await _send(() => _http.get(path, queryParameters: query, headers: _authHeaders()));
    final data = resp.data;
    if (data is! Map) return (items: const <SeerrMedia>[], page: 1, totalPages: 1);
    final results = data['results'];
    final items = <SeerrMedia>[];
    if (results is List) {
      for (final r in results) {
        if (r is Map) {
          final m = SeerrMedia.tryFromJson(r.cast<String, dynamic>());
          if (m != null) items.add(m);
        }
      }
    }
    return (items: items, page: _int(data['page']) ?? 1, totalPages: _int(data['totalPages']) ?? 1);
  }

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  /// `POST /request`. [seasons] is only sent for TV; pass a list of season
  /// numbers. Advanced (admin) options are optional.
  Future<void> createRequest({
    required String mediaType,
    required int tmdbId,
    List<int>? seasons,
    bool is4k = false,
    int? serverId,
    int? profileId,
    String? rootFolder,
  }) async {
    final body = <String, dynamic>{
      'mediaType': mediaType,
      'mediaId': tmdbId,
      'is4k': is4k,
      if (mediaType == 'tv' && seasons != null) 'seasons': seasons,
      'serverId': ?serverId,
      'profileId': ?profileId,
      'rootFolder': ?rootFolder,
    };
    final resp = await _send(() => _http.post('/request', body: body, headers: _authHeaders()));
    _throwIfError(resp);
  }

  /// `GET /request/count`. Feeds the counts next to the filter tabs. Returns
  /// zeros when the server does not answer, so the tabs degrade to plain labels
  /// instead of the screen failing over a decoration.
  Future<({int total, int pending, int approved, int available, int processing})> getRequestCounts() async {
    const empty = (total: 0, pending: 0, approved: 0, available: 0, processing: 0);
    try {
      final resp = await _send(() => _http.get('/request/count', headers: _authHeaders()));
      final data = resp.data;
      if (data is! Map) return empty;
      return (
        total: _int(data['total']) ?? 0,
        pending: _int(data['pending']) ?? 0,
        approved: _int(data['approved']) ?? 0,
        available: _int(data['available']) ?? 0,
        processing: _int(data['processing']) ?? 0,
      );
    } catch (_) {
      return empty;
    }
  }

  /// `GET /request`. [filter] is one of all/pending/approved/processing/
  /// available/unavailable. [requestedBy] scopes to a user (own requests).
  Future<({List<SeerrRequest> items, int totalPages})> getRequests({
    String filter = 'all',
    int page = 1,
    int take = 20,
    int? requestedBy,
  }) async {
    final resp = await _send(
      () => _http.get(
        '/request',
        queryParameters: {
          'take': take,
          'skip': (page - 1) * take,
          'filter': filter,
          'sort': 'added',
          'requestedBy': ?requestedBy,
        },
        headers: _authHeaders(),
      ),
    );
    final data = resp.data;
    if (data is! Map) return (items: const <SeerrRequest>[], totalPages: 1);
    final results = data['results'];
    final items = <SeerrRequest>[];
    if (results is List) {
      for (final r in results) {
        if (r is Map) {
          final req = SeerrRequest.tryFromJson(r.cast<String, dynamic>());
          if (req != null) items.add(req);
        }
      }
    }
    final pageInfo = data['pageInfo'];
    final totalPages = pageInfo is Map ? _int(pageInfo['pages']) ?? 1 : 1;
    return (items: items, totalPages: totalPages);
  }

  Future<void> updateRequest(int id, {List<int>? seasons, bool? is4k}) async {
    final body = <String, dynamic>{'seasons': ?seasons, 'is4k': ?is4k};
    final resp = await _send(() => _http.put('/request/$id', body: body, headers: _authHeaders()));
    _throwIfError(resp);
  }

  Future<void> deleteRequest(int id) async {
    final resp = await _send(() => _http.delete('/request/$id', headers: _authHeaders()));
    _throwIfError(resp);
  }

  Future<void> approveRequest(int id) async {
    final resp = await _send(() => _http.post('/request/$id/approve', headers: _authHeaders()));
    _throwIfError(resp);
  }

  Future<void> declineRequest(int id) async {
    final resp = await _send(() => _http.post('/request/$id/decline', headers: _authHeaders()));
    _throwIfError(resp);
  }

  Future<List<SeerrServiceServer>> getRadarrServers() => _serviceServers('/service/radarr');
  Future<List<SeerrServiceServer>> getSonarrServers() => _serviceServers('/service/sonarr');

  Future<List<SeerrServiceServer>> _serviceServers(String path) async {
    final resp = await _send(() => _http.get(path, headers: _authHeaders()));
    return SeerrServiceServer.listFrom(resp.data);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Map<String, String> _authHeaders() {
    if (_session.isApiKeyMode) {
      final key = _session.apiKey;
      return key == null ? const {} : {'X-Api-Key': key};
    }
    final cookie = _session.cookie;
    return cookie == null ? const {} : {'Cookie': cookie};
  }

  /// Send with a single silent re-auth + retry on 401 (cookie modes only).
  Future<MediaServerResponse> _send(Future<MediaServerResponse> Function() send) async {
    var resp = await _rawSend(send);
    if (resp.statusCode == 401 && !_session.isApiKeyMode) {
      if (await _reauth()) resp = await _rawSend(send);
    }
    _throwIfError(resp);
    return resp;
  }

  /// Run the transport, mapping transport failures to a typed network error.
  Future<MediaServerResponse> _rawSend(Future<MediaServerResponse> Function() send) async {
    try {
      return await send();
    } on MediaServerHttpException catch (e) {
      throw SeerrException.network(e.message);
    }
  }

  Future<bool> _reauth() async {
    try {
      switch (_session.authMode) {
        case SeerrAuthMode.plex:
          final token = await plexTokenProvider?.call();
          if (token == null || token.isEmpty) return false;
          await loginWithPlexToken(token);
          return _session.cookie != null;
        case SeerrAuthMode.local:
          final email = _session.email;
          final password = _session.password;
          if (email == null || password == null) return false;
          await loginLocal(email, password);
          return _session.cookie != null;
        case SeerrAuthMode.apiKey:
          return false;
      }
    } catch (e) {
      appLogger.d('Seerr re-auth failed', error: e);
      return false;
    }
  }

  void _applyUser(Object? data) {
    if (data is! Map) return;
    _session = _session.copyWith(
      userId: _int(data['id']) ?? _session.userId,
      displayName:
          (data['displayName'] ?? data['username'] ?? data['plexUsername'])?.toString() ?? _session.displayName,
      permissions: _int(data['permissions']) ?? _session.permissions,
    );
  }

  void _emit() => onSessionUpdated?.call(_session);

  void _throwIfError(MediaServerResponse r) {
    if (r.statusCode == 401) throw SeerrException.auth();
    if (r.statusCode == 403) throw SeerrException.forbidden();
    if (r.statusCode >= 400) throw SeerrException.http(r.statusCode, r.data);
  }

  /// Extract `connect.sid=<value>` from a (possibly comma-folded) Set-Cookie
  /// header so we can replay it as a `Cookie` request header.
  static String? _extractCookie(Map<String, String> headers) {
    String? raw;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        raw = entry.value;
        break;
      }
    }
    if (raw == null) return null;
    final match = RegExp(r'connect\.sid=([^;,\s]+)').firstMatch(raw);
    return match == null ? null : 'connect.sid=${match.group(1)}';
  }

  static int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));
}
