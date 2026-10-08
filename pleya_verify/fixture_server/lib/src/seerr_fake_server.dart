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
/// The request routes follow `server/routes/request.ts` of seerr-team/seerr
/// (develop at 53e45647) where that matters to a scenario, including the parts
/// that are not flattering: the list has no `declined` case and answers such a
/// filter with every status, and `PUT` only acts on a `mediaType`, never reads
/// `is4k`, and assigns the target fields from the body whether they are there
/// or not. A fixture that was kinder than the source would let a scenario pass
/// on a capability no server has.
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
    final method = request.method;

    final single = RegExp(r'/request/(\d+)(?:/(approve|decline))?$').firstMatch(path);
    if (single != null) return _requestRoute(method, int.parse(single.group(1)!), single.group(2), request);
    if (method == 'POST' && path.endsWith('/request')) return _createRequest(request);
    final quota = RegExp(r'/user/(\d+)/quota$').firstMatch(path);
    if (quota != null) {
      return _json({
        'movie': {'limit': 0},
        'tv': {'limit': 0},
      });
    }
    final service = RegExp(r'/service/(radarr|sonarr)(?:/(\d+))?$').firstMatch(path);
    if (service != null) return _serviceRoute(service.group(1)!, service.group(2));

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

  /// `GET`, `PUT`, `DELETE /request/{id}` and `POST /request/{id}/approve|decline`.
  http.Response _requestRoute(String method, int id, String? decision, http.Request request) {
    final row = requests.where((r) => r['id'] == id).firstOrNull;
    if (row == null) return _json({'message': 'Request not found.'}, status: 404);

    if (decision != null) {
      if (method != 'POST') return _json({'message': 'not found'}, status: 404);
      if (row['status'] != 1) {
        return _json({'message': 'Only pending requests can be approved or declined.'}, status: 409);
      }
      row['status'] = decision == 'approve' ? 2 : 3;
      return _json(row);
    }

    switch (method) {
      case 'GET':
        return _json(row);
      case 'DELETE':
        requests.remove(row);
        return http.Response('', 204);
      case 'PUT':
        return _updateRequest(row, _body(request));
      default:
        return _json({'message': 'not found'}, status: 404);
    }
  }

  /// `PUT /request/{id}`, as the route reads. The single fixture user is an
  /// admin, so the permission branch always passes.
  http.Response _updateRequest(Map<String, dynamic> row, Map<String, dynamic> body) {
    if (row['status'] != 1) return _json({'message': 'Only pending requests can be modified.'}, status: 409);
    final mediaType = body['mediaType'];
    // Neither branch runs without a type: the route answers 200 and saves
    // nothing. `is4k` is never read.
    if (mediaType != 'movie' && mediaType != 'tv') return _json(row);

    // Assigned from the body whether present or not.
    for (final key in const ['serverId', 'profileId', 'rootFolder', 'tags']) {
      row[key] = body[key];
    }
    if (mediaType == 'tv') {
      row['languageProfileId'] = body['languageProfileId'];
      final seasons = body['seasons'];
      if (seasons is! List || seasons.isEmpty) {
        return _json({
          'message': 'Missing seasons. If you want to cancel a series request, use the DELETE method.',
        }, status: 500);
      }
      row['seasons'] = [
        for (final n in seasons) {'seasonNumber': n, 'status': 1},
      ];
    }
    return _json(row);
  }

  http.Response _createRequest(http.Request request) {
    final body = _body(request);
    final mediaType = body['mediaType']?.toString() ?? 'movie';
    final tmdbId = body['mediaId'];
    if (tmdbId is! int) return _json({'message': 'mediaId required'}, status: 500);
    if (requests.any((r) => (r['media'] as Map)['tmdbId'] == tmdbId && r['type'] == mediaType && r['status'] != 3)) {
      return _json({'message': 'Request for this media already exists.'}, status: 409);
    }
    final id = requests.fold<int>(0, (max, r) => (r['id'] as int) > max ? r['id'] as int : max) + 1;
    final row = <String, dynamic>{
      'id': id,
      'status': 1,
      'type': mediaType,
      'is4k': body['is4k'] == true,
      'createdAt': '2026-10-08T00:00:00.000Z',
      'requestedBy': {'id': 1, 'displayName': 'verify-admin'},
      'media': {'tmdbId': tmdbId, 'mediaType': mediaType, 'status': 2},
      'seasons': [
        if (body['seasons'] is List)
          for (final n in body['seasons'] as List) {'seasonNumber': n, 'status': 1},
      ],
      'serverId': body['serverId'],
      'profileId': body['profileId'],
      'rootFolder': body['rootFolder'],
      'tags': body['tags'],
      'languageProfileId': body['languageProfileId'],
    };
    requests.add(row);
    final detail = _details['$mediaType:$tmdbId'];
    if (detail != null) detail['mediaInfo'] = {'status': 2};
    return _json(row, status: 201);
  }

  /// One HD instance per service, enough for the admin target section.
  http.Response _serviceRoute(String kind, String? id) {
    final name = kind == 'radarr' ? 'Radarr' : 'Sonarr';
    if (id == null) {
      return _json([
        {'id': 0, 'name': name, 'is4k': false, 'isDefault': true, 'activeProfileId': 1, 'activeDirectory': '/media'},
      ]);
    }
    return _json({
      'profiles': [
        {'id': 1, 'name': 'HD-1080p'},
      ],
      'rootFolders': [
        {'path': '/media'},
      ],
    });
  }

  Map<String, dynamic> _body(http.Request request) {
    if (request.body.isEmpty) return const {};
    final decoded = jsonDecode(request.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : const {};
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
    // The route's own switch: pending, approved and available (completed) are
    // cases, and everything else, `declined` included, is the default branch
    // that returns every status.
    final statuses = switch (query['filter']) {
      'pending' => const [1],
      'approved' || 'processing' => const [2],
      'available' || 'completed' => const [5],
      'failed' => const [4],
      _ => const [1, 2, 3, 4, 5],
    };
    final requestedBy = int.tryParse(query['requestedBy'] ?? '');
    final filtered = requests
        .where((r) => statuses.contains(r['status']))
        .where((r) => requestedBy == null || (r['requestedBy'] as Map)['id'] == requestedBy)
        .toList();
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
    int requestedById = 1,
    List<int> seasons = const [],
    int seasonCount = 0,
    int? serverId,
    int? profileId,
    String? rootFolder,
  }) {
    requests.add({
      'id': id,
      'status': status,
      'type': mediaType,
      'is4k': false,
      'createdAt': '2026-09-01T00:00:00.000Z',
      'requestedBy': {'id': requestedById, 'displayName': requestedByName},
      'media': {'tmdbId': tmdbId, 'mediaType': mediaType, 'status': status == 5 ? 5 : 3},
      'seasons': [
        for (final n in seasons) {'seasonNumber': n, 'status': status},
      ],
      'serverId': serverId,
      'profileId': profileId,
      'rootFolder': rootFolder,
      'tags': null,
      'languageProfileId': null,
    });
    _details['$mediaType:$tmdbId'] = {
      'id': tmdbId,
      if (mediaType == 'tv') 'name': title else 'title': title,
      if (mediaType == 'tv') 'firstAirDate': year == null ? null : '$year-01-01',
      if (mediaType != 'tv') 'releaseDate': year == null ? null : '$year-01-01',
      'posterPath': posterPath,
      'seasons': [
        for (var n = 1; n <= seasonCount; n++) {'seasonNumber': n, 'episodeCount': 8},
      ],
      'mediaInfo': {
        'status': status == 5 ? 5 : 3,
        'seasons': [
          for (final n in seasons) {'seasonNumber': n, 'status': 2},
        ],
      },
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
