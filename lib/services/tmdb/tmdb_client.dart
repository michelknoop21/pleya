import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../automation/pleya_verify.dart';

enum TmdbKind {
  movie('movie', 'release_dates,credits,watch/providers,external_ids'),
  tv('tv', 'content_ratings,credits,watch/providers,external_ids');

  const TmdbKind(this.path, this.appends);

  final String path;
  final String appends;
}

class TmdbException implements Exception {
  TmdbException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'TmdbException($statusCode): $message';
}

/// The token was rejected (HTTP 401).
class TmdbAuthException extends TmdbException {
  TmdbAuthException(super.message) : super(statusCode: 401);
}

/// Thin TMDB v3 client returning decoded JSON maps. Pleya ships no TMDB key;
/// the token always comes from the user (their own v4 read token or v3 key).
class TmdbClient {
  TmdbClient(this._token, {http.Client? httpClient, Uri? base}) : _http = httpClient ?? http.Client(), _base = base;

  /// Pleya Verify only: where the fixture server stands in for TMDB. The
  /// fixture port is picked per run, so it cannot be a build-time define; it
  /// is read off the Ollama fixture the scenario already connected, and only
  /// on a loopback `http` address in a Verify build. Everywhere else null,
  /// and the client talks to [_host].
  static Uri? verifyBase(String? providerUrl, {bool enabled = kPleyaVerify}) {
    if (!enabled || providerUrl == null) return null;
    final uri = Uri.tryParse(providerUrl);
    if (uri == null || uri.scheme != 'http' || !const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) return null;
    return Uri(scheme: 'http', host: uri.host, port: uri.hasPort ? uri.port : 80, path: '/tmdb');
  }

  static const _host = 'api.themoviedb.org';
  static const _timeout = Duration(seconds: 4);

  final String _token;
  final http.Client _http;
  final Uri? _base;

  /// A v4 read access token is a JWT; anything else is treated as a v3 key.
  bool get _isBearer => _token.startsWith('eyJ');

  /// Details plus ratings, credits, providers and external ids in one call.
  Future<Map<String, dynamic>> details(TmdbKind kind, int id, {String? language}) =>
      _get('/3/${kind.path}/$id', {'append_to_response': kind.appends, 'language': ?language});

  Future<List<Map<String, dynamic>>> trending(TmdbKind kind, {String? language, int page = 1}) async =>
      _results(await _get('/3/trending/${kind.path}/week', _listQuery(language, page)));

  Future<List<Map<String, dynamic>>> recommendations(TmdbKind kind, int id, {String? language, int page = 1}) async =>
      _results(await _get('/3/${kind.path}/$id/recommendations', _listQuery(language, page)));

  Future<List<Map<String, dynamic>>> similar(TmdbKind kind, int id, {String? language, int page = 1}) async =>
      _results(await _get('/3/${kind.path}/$id/similar', _listQuery(language, page)));

  Map<String, String> _listQuery(String? language, int page) => {'language': ?language, if (page > 1) 'page': '$page'};

  /// `/search/multi` has no year filter, so [year] filters on the
  /// release or first-air date client-side.
  Future<List<Map<String, dynamic>>> searchMulti(String query, {int? year}) async {
    final results = _results(await _get('/3/search/multi', {'query': query}));
    if (year == null) return results;
    return results.where((r) {
      final date = (r['release_date'] ?? r['first_air_date']) as String?;
      return date != null && date.startsWith('$year');
    }).toList();
  }

  /// [source] is a TMDB external_source such as `imdb_id` or `tvdb_id`.
  Future<Map<String, dynamic>> findByExternal(String id, String source) =>
      _get('/3/find/${Uri.encodeComponent(id)}', {'external_source': source});

  List<Map<String, dynamic>> _results(Map<String, dynamic> body) =>
      ((body['results'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();

  Future<Map<String, dynamic>> _get(String path, [Map<String, String> query = const {}]) async {
    final params = {...query, if (!_isBearer) 'api_key': _token};
    final base = _base;
    final uri = base == null
        ? Uri.https(_host, path, params)
        : base.replace(path: '${base.path}$path', queryParameters: params.isEmpty ? null : params);
    final headers = {'Accept': 'application/json', if (_isBearer) 'Authorization': 'Bearer $_token'};
    final http.Response res;
    try {
      res = await _http.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw TmdbException('timeout on $path');
    } on http.ClientException catch (e) {
      throw TmdbException('network error on $path: ${e.message}');
    }
    if (res.statusCode == 401) throw TmdbAuthException('unauthorized on $path');
    if (res.statusCode != 200) throw TmdbException('HTTP ${res.statusCode} on $path', statusCode: res.statusCode);
    final Object? body;
    try {
      body = jsonDecode(res.body);
    } on FormatException catch (e) {
      throw TmdbException('invalid JSON on $path: ${e.message}');
    }
    if (body is! Map<String, dynamic>) throw TmdbException('unexpected body on $path');
    return body;
  }
}
