import 'dart:convert';

import 'package:http/http.dart' as http;

/// The one TMDB route Big P's `trending_titles` calls without Seerr:
/// `/3/trending/{movie|tv}/week`, behind `/tmdb` on the fixture port (the app
/// reaches it through `TmdbClient.verifyBase`).
///
/// Part of the titles are the ones `catalog.mixed.v1` holds in the library
/// (Aurora, Basalt, Cascade, Driftwood, same years), so they link to it; the
/// rest are not in any library. Together they are eight, past the point where
/// the TV result list goes dense (BP-09). Auth is the key the scenario types
/// into Instellingen, as `api_key` (a v3 key) or as a Bearer token.
class TmdbFakeServer {
  TmdbFakeServer({this.apiKey = 'verify-tmdb-key'});

  final String apiKey;

  static const movies = [
    (id: 9101, title: 'Aurora', date: '2021-03-01'),
    (id: 9102, title: 'Basalt', date: '2022-03-01'),
    (id: 9103, title: 'Cascade', date: '2023-03-01'),
    (id: 9104, title: 'Dunmore', date: '2025-03-01'),
    (id: 9105, title: 'Ember Reach', date: '2025-06-01'),
  ];
  static const shows = [
    (id: 9201, title: 'Driftwood', date: '2024-03-01'),
    (id: 9202, title: 'Fenwick', date: '2025-03-01'),
    (id: 9203, title: 'Harbor Light', date: '2026-03-01'),
  ];

  Future<http.Response> handle(http.Request request) async {
    final given =
        request.url.queryParameters['api_key'] ?? request.headers['authorization']?.replaceFirst('Bearer ', '');
    if (given != apiKey) return _json({'status_message': 'Invalid API key'}, status: 401);
    final match = RegExp(r'^/tmdb/3/trending/(movie|tv)/week$').firstMatch(request.url.path);
    if (match == null) return _json({'status_message': 'not found'}, status: 404);
    final isMovie = match.group(1) == 'movie';
    return _json({
      'page': 1,
      'results': [
        if (isMovie)
          for (final m in movies) {'id': m.id, 'title': m.title, 'release_date': m.date, 'overview': ''}
        else
          for (final s in shows) {'id': s.id, 'name': s.title, 'first_air_date': s.date, 'overview': ''},
      ],
    });
  }

  http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}
