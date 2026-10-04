import 'package:http/http.dart' as http;

import '../../models/seerr/seerr_media.dart';
import '../../models/seerr/seerr_request.dart';
import '../../utils/app_logger.dart';
import '../../exceptions/media_server_exceptions.dart';
import '../../utils/media_server_http_client.dart';
import 'seerr_constants.dart';
import 'seerr_session.dart';
import 'seerr_types.dart';

export 'seerr_types.dart';

part 'seerr_client_requests.dart';

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

  /// Title/year/artwork per `mediaType:tmdbId`, so paging through the request
  /// list and switching filters never refetches the same title. Bounded by the
  /// number of distinct titles a session looks at, which is small.
  final Map<String, _SeerrMediaDisplay> _displayCache = {};

  /// Lookups currently on the wire, so two hydration passes that overlap (a
  /// fast filter switch, a load-more landing on top of a reload) share one call
  /// per title instead of racing for the same one.
  final Map<String, Future<void>> _displayInFlight = {};

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
  Future<SeerrMediaPage> discoverMovies({
    int page = 1,
    int? genre,
    int? watchProvider,
    String? watchRegion,
    String? sortBy,
    List<int>? keywords,
  }) => _mediaPage('/discover/movies', {
    'page': page,
    'genre': ?genre,
    if (keywords != null && keywords.isNotEmpty) 'keywords': keywords.join(','),
    'watchProviders': ?watchProvider?.toString(),
    'watchRegion': ?watchRegion,
    'sortBy': ?sortBy,
  });
  Future<SeerrMediaPage> discoverTv({
    int page = 1,
    int? genre,
    int? watchProvider,
    String? watchRegion,
    String? sortBy,
    List<int>? keywords,
  }) => _mediaPage('/discover/tv', {
    'page': page,
    'genre': ?genre,
    if (keywords != null && keywords.isNotEmpty) 'keywords': keywords.join(','),
    'watchProviders': ?watchProvider?.toString(),
    'watchRegion': ?watchRegion,
    'sortBy': ?sortBy,
  });

  /// `GET /search/keyword`: TMDB keywords matching [query], for the
  /// `keywords` filter of discover (comma-separated ids). Empty on a shape
  /// without results.
  Future<List<({int id, String name})>> searchKeyword(String query) async {
    final resp = await _send(
      () => _http.get('/search/keyword', queryParameters: {'query': query, 'page': 1}, headers: _authHeaders()),
    );
    final results = resp.data is Map ? (resp.data as Map)['results'] : null;
    return [
      if (results is List)
        for (final r in results)
          if (r is Map && _int(r['id']) != null && r['name'] != null) (id: _int(r['id'])!, name: r['name'].toString()),
    ];
  }

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

  /// `GET /tv/{tvId}/season/{seasonNumber}`: the season with its `episodes`
  /// (name, overview, episodeNumber), as TMDB describes them.
  Future<Map<String, dynamic>> getTvSeason(int tmdbId, int seasonNumber) => _detail('/tv/$tmdbId/season/$seasonNumber');

  /// Typed movie/tv detail for the media detail screen (hero, genres, cast, …).
  Future<SeerrMediaDetail> getMediaDetail({required int tmdbId, required bool isMovie}) async {
    final json = isMovie ? await getMovie(tmdbId) : await getTv(tmdbId);
    return SeerrMediaDetail.fromJson(json, mediaType: isMovie ? 'movie' : 'tv');
  }

  Future<SeerrMediaPage> getRecommendations({required int tmdbId, required bool isMovie, int page = 1}) =>
      _mediaPage('/${isMovie ? 'movie' : 'tv'}/$tmdbId/recommendations', {'page': page});

  /// `GET /movie/{id}/similar` / `GET /tv/{id}/similar`: TMDB titles that share
  /// genres and keywords, where recommendations follow viewer behaviour.
  Future<SeerrMediaPage> getSimilar({required int tmdbId, required bool isMovie, int page = 1}) =>
      _mediaPage('/${isMovie ? 'movie' : 'tv'}/$tmdbId/similar', {'page': page});

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
      throw SeerrException.network(e.message, statusCode: e.statusCode);
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
