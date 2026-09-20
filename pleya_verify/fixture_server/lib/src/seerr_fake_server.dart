import 'dart:convert';

import 'package:http/http.dart' as http;

/// A Jellyseerr/Overseerr routing kernel, good enough to browse and request.
///
/// Answers the `/api/v1` surface `lib/services/seerr/seerr_client.dart`
/// actually calls in API-key mode: status, the authenticated user, request
/// listing/counts, the discover buckets, and `/movie/{id}`/`/tv/{id}`. Auth is
/// a single `X-Api-Key` header checked against [apiKey] — no cookie flow,
/// since Pleya Verify never needs the Plex/local login modes to seed a
/// scenario.
///
/// A request row's `media` object never carries title or poster — real
/// Overseerr's does not either, only the tmdb id and availability status — so
/// `SeerrRequest.needsDisplayData` is always true here, exactly like
/// production, and `SeerrClient.hydrateRequests`'s round-trip to
/// `/movie/{id}`/`/tv/{id}` is what fills the card in. [addRequest] still
/// takes title/year/poster for the caller's convenience; they land in
/// [_details] and answer that round-trip instead of skipping it.
class SeerrFakeServer {
  SeerrFakeServer({this.apiKey = 'verify-seerr-key'});

  final String apiKey;

  final List<Map<String, dynamic>> requests = [];
  final Map<String, List<Map<String, dynamic>>> discover = {
    'trending': [],
    'movies': [],
    'tv': [],
    'movies-upcoming': [],
    'tv-upcoming': [],
  };
  final List<Map<String, dynamic>> movieGenres = [];
  final List<Map<String, dynamic>> tvGenres = [];

  /// What `/movie/{id}` and `/tv/{id}` answer, keyed by `'$mediaType:$tmdbId'`.
  final Map<String, Map<String, dynamic>> _details = {};

  void reset() {
    requests.clear();
    for (final bucket in discover.values) {
      bucket.clear();
    }
    movieGenres.clear();
    tvGenres.clear();
    _details.clear();
  }

  Future<http.Response> handle(http.Request request) async {
    if (request.headers['x-api-key'] != apiKey) {
      return _json({
        'response': {'result': 'error', 'message': 'Invalid API key'},
      }, status: 401);
    }

    final path = request.url.path;
    final query = request.url.queryParameters;

    if (path.endsWith('/status')) {
      return _json({'version': '1.33.2'});
    }
    if (path.endsWith('/auth/me')) {
      return _json({'id': 1, 'displayName': 'verify-admin', 'permissions': 2});
    }
    if (path.endsWith('/request/count')) {
      return _json(_requestCounts());
    }
    if (path.endsWith('/request')) {
      return _json(_requestPage(query));
    }
    if (path.endsWith('/discover/trending')) {
      return _json(_discoverPage(discover['trending']!, query));
    }
    if (path.endsWith('/discover/movies/upcoming')) {
      return _json(_discoverPage(discover['movies-upcoming']!, query));
    }
    if (path.endsWith('/discover/tv/upcoming')) {
      return _json(_discoverPage(discover['tv-upcoming']!, query));
    }
    if (path.endsWith('/discover/movies')) {
      return _json(_discoverPage(discover['movies']!, query));
    }
    if (path.endsWith('/discover/tv')) {
      return _json(_discoverPage(discover['tv']!, query));
    }
    if (path.endsWith('/genres/movie')) {
      return _json(movieGenres);
    }
    if (path.endsWith('/genres/tv')) {
      return _json(tvGenres);
    }
    if (path.endsWith('/watchproviders/movies') || path.endsWith('/watchproviders/tv')) {
      return _json(const []);
    }
    final movieMatch = RegExp(r'/movie/(\d+)$').firstMatch(path);
    if (movieMatch != null) return _detailResponse('movie', int.parse(movieMatch.group(1)!));
    final tvMatch = RegExp(r'/tv/(\d+)$').firstMatch(path);
    if (tvMatch != null) return _detailResponse('tv', int.parse(tvMatch.group(1)!));

    return _json({'message': 'not found'}, status: 404);
  }

  http.Response _detailResponse(String mediaType, int tmdbId) {
    final detail = _details['$mediaType:$tmdbId'];
    return detail == null ? _json({'message': 'not found'}, status: 404) : _json(detail);
  }

  Map<String, dynamic> _requestCounts() {
    var pending = 0, approved = 0, available = 0;
    for (final r in requests) {
      switch (r['status']) {
        case 1:
          pending++;
        case 2:
          approved++;
        case 5:
          available++;
      }
    }
    // `processing` has no fixture data behind it — real Overseerr derives it
    // from an approved request whose *media* isn't available yet, a second
    // axis (`SeerrMediaStatus`) this fixture doesn't model. The one screen
    // that reads counts (`TvSeerrRequestsView._countFor`) never asks for it.
    return {
      'total': requests.length,
      'pending': pending,
      'approved': approved,
      'available': available,
      'processing': 0,
    };
  }

  Map<String, dynamic> _requestPage(Map<String, String> query) {
    final filter = query['filter'] ?? 'all';
    final filtered = filter == 'all'
        ? requests
        : requests.where((r) => _statusName(r['status'] as int) == filter).toList();
    final requestedTake = int.tryParse(query['take'] ?? '');
    final take = requestedTake != null && requestedTake > 0 ? requestedTake : 20;
    final requestedSkip = int.tryParse(query['skip'] ?? '');
    final skip = requestedSkip != null && requestedSkip > 0 ? requestedSkip : 0;
    final page = filtered.skip(skip).take(take).toList();
    final pageCount = (filtered.length / take).ceil();
    return {
      'results': page,
      'pageInfo': {'pages': pageCount == 0 ? 1 : pageCount},
    };
  }

  /// `SeerrRequestStatus`'s own encoding (`lib/services/seerr/seerr_constants.dart`):
  /// 1 pending, 2 approved, 3 declined, 4 failed, 5 completed. The client's
  /// `filter` query names its "completed" bucket `available` instead.
  String _statusName(int status) => switch (status) {
    1 => 'pending',
    2 => 'approved',
    3 => 'declined',
    5 => 'available',
    _ => 'unavailable',
  };

  Map<String, dynamic> _discoverPage(List<Map<String, dynamic>> items, Map<String, String> query) {
    return {'page': int.tryParse(query['page'] ?? '1') ?? 1, 'totalPages': 1, 'results': items};
  }

  /// Registers one request row. [status] is `SeerrRequestStatus`'s encoding:
  /// 1 pending, 2 approved, 3 declined, 4 failed, 5 completed.
  ///
  /// [title]/[year]/[posterPath] never reach the request row itself — real
  /// Overseerr's `media` object does not carry them either — they seed
  /// `/movie/{tmdbId}` or `/tv/{tmdbId}` instead, so a client that actually
  /// performs the hydration round-trip finds the same title production would
  /// hand it back.
  void addRequest({
    required int id,
    required String mediaType,
    required int tmdbId,
    required String title,
    int? year,
    String? posterPath,
    int status = 1,
    String requestedByName = 'verify-admin',
  }) {
    requests.add({
      'id': id,
      'status': status,
      'type': mediaType,
      'is4k': false,
      'createdAt': '2026-09-01T00:00:00.000Z',
      'requestedBy': {'id': 1, 'displayName': requestedByName},
      'media': {'tmdbId': tmdbId, 'mediaType': mediaType, 'status': status == 5 ? 5 : 3},
    });
    _details['$mediaType:$tmdbId'] = {
      'id': tmdbId,
      if (mediaType == 'tv') 'name': title else 'title': title,
      if (mediaType == 'tv') 'firstAirDate': year == null ? null : '$year-01-01',
      if (mediaType != 'tv') 'releaseDate': year == null ? null : '$year-01-01',
      'posterPath': posterPath,
    };
  }

  /// Registers one discover-bucket result. `bucket` is one of the keys in
  /// [discover].
  void addDiscoverItem(
    String bucket, {
    required int tmdbId,
    required String mediaType,
    required String title,
    int? year,
    String? posterPath,
  }) {
    discover[bucket]!.add({
      'id': tmdbId,
      'mediaType': mediaType,
      'title': title,
      'releaseDate': year == null ? null : '$year-01-01',
      'posterPath': posterPath,
    });
  }

  http.Response _json(Object? body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});
}
