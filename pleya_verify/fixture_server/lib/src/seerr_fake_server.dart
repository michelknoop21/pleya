import 'dart:convert';

import 'package:http/http.dart' as http;

/// A Jellyseerr/Overseerr routing kernel, good enough to browse and request.
///
/// Answers the `/api/v1` surface `lib/services/seerr/seerr_client.dart`
/// actually calls in API-key mode: status, the authenticated user, request
/// listing/counts, and the discover buckets. Auth is a single `X-Api-Key`
/// header checked against [apiKey] — no cookie flow, since Pleya Verify never
/// needs the Plex/local login modes to seed a scenario.
///
/// Every request row embeds its own title/poster directly, so the client's
/// best-effort hydration round-trip to `/movie/{id}`/`/tv/{id}` is never
/// needed and those two endpoints are not implemented here.
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

  void reset() {
    requests.clear();
    for (final bucket in discover.values) {
      bucket.clear();
    }
    movieGenres.clear();
    tvGenres.clear();
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

    return _json({'message': 'not found'}, status: 404);
  }

  Map<String, dynamic> _requestCounts() {
    var pending = 0, approved = 0, available = 0, processing = 0;
    for (final r in requests) {
      switch (r['status']) {
        case 1:
          pending++;
        case 2:
          approved++;
        case 4:
          processing++;
        case 5:
          available++;
      }
    }
    return {'total': requests.length, 'pending': pending, 'approved': approved, 'available': available, 'processing': processing};
  }

  Map<String, dynamic> _requestPage(Map<String, String> query) {
    final filter = query['filter'] ?? 'all';
    final filtered = filter == 'all'
        ? requests
        : requests.where((r) => _statusName(r['status'] as int) == filter).toList();
    return {
      'results': filtered,
      'pageInfo': {'pages': 1},
    };
  }

  String _statusName(int status) => switch (status) {
    1 => 'pending',
    2 => 'approved',
    4 => 'processing',
    5 => 'available',
    _ => 'unavailable',
  };

  Map<String, dynamic> _discoverPage(List<Map<String, dynamic>> items, Map<String, String> query) {
    return {'page': int.tryParse(query['page'] ?? '1') ?? 1, 'totalPages': 1, 'results': items};
  }

  /// Registers one request row. [status] follows Overseerr's own encoding:
  /// 1 pending, 2 approved, 3 declined, 4 processing, 5 available.
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
      'media': {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'title': title,
        'releaseDate': year == null ? null : '$year-01-01',
        'posterPath': posterPath,
        'status': status == 5 ? 5 : 3,
      },
    });
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
