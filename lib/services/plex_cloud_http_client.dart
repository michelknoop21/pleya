import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/media_server_http_client.dart';
import '../utils/media_server_timeouts.dart';

/// Transport to the plex.tv cloud hosts: discover, metadata, epg.
///
/// The whole reason this class exists is a negative one. It has no `baseUrl`,
/// no `defaultHeaders` and is never a `FailoverHttpClient`, so an absolute URL
/// cannot pick up server identity along the way: there is none to pick up.
/// `PlexClient` does the opposite, putting the **server** token in
/// `defaultHeaders`, and `MediaServerHttpClient` merges those into every
/// request including absolute-URL ones. That is how a PMS token ends up at a
/// host that has no business seeing it.
///
/// Every call takes its token as a required named parameter, so no path exists
/// where a request leaves without the caller having decided whose token it is.
///
/// The class stays deliberately small and dumb: transport and headers, nothing
/// else. No auth resolver, no scope knowledge, no retry. Deciding which token
/// may be used lives one layer up, with the thing that knows about profiles and
/// Home users.
class PlexCloudHttpClient {
  final MediaServerHttpClient _http;
  final String _clientIdentifier;
  final String _product;
  final Map<String, String> _extraHeaders;

  PlexCloudHttpClient._(this._http, this._clientIdentifier, this._product, this._extraHeaders);

  /// [extraHeaders] belongs to the host, not to the operation: the EPG host
  /// wants `X-Plex-Provider-Version`, the watchlist hosts want nothing extra.
  /// Passing it per call would mean every method has to remember it, and one
  /// forgotten method would then behave differently for no visible reason.
  factory PlexCloudHttpClient({
    required String clientIdentifier,
    String product = 'Pleya',
    Map<String, String> extraHeaders = const {},
  }) {
    return PlexCloudHttpClient._(
      MediaServerHttpClient(
        connectTimeout: MediaServerTimeouts.plexTvConnect,
        receiveTimeout: MediaServerTimeouts.plexTvReceive,
      ),
      clientIdentifier,
      product,
      _sanitizeExtraHeaders(extraHeaders),
    );
  }

  @visibleForTesting
  factory PlexCloudHttpClient.forTesting({
    required http.Client httpClient,
    String clientIdentifier = 'test-client',
    String product = 'Pleya',
    Map<String, String> extraHeaders = const {},
  }) {
    return PlexCloudHttpClient._(
      MediaServerHttpClient(client: httpClient),
      clientIdentifier,
      product,
      _sanitizeExtraHeaders(extraHeaders),
    );
  }

  /// The complete allowed header set for every call through this client.
  ///
  /// Kept to what `PlexAuthService` already sends, plus whatever the host was
  /// declared to need. Anything beyond that leaks device or server detail to
  /// plex.tv, and a test pins the set exactly.
  ///
  /// `X-Plex-Token` is written last so an extra header can never take its
  /// place. Header names are case-insensitive over the wire but a Dart map is
  /// not, so [_sanitizeExtraHeaders] has already dropped any casing variant of
  /// the token key before it gets here.
  Map<String, String> headersForToken(String token) => {
    'Accept': 'application/json',
    'X-Plex-Product': _product,
    'X-Plex-Client-Identifier': _clientIdentifier,
    ..._extraHeaders,
    'X-Plex-Token': token,
  };

  Future<MediaServerResponse> get(String url, {required String token, Map<String, dynamic>? queryParameters}) async {
    final response = await _http.get(url, queryParameters: queryParameters, headers: headersForToken(token));
    throwIfHttpError(response);
    return response;
  }

  Future<MediaServerResponse> put(
    String url, {
    required String token,
    Map<String, dynamic>? queryParameters,
    Object? body,
  }) async {
    final response = await _http.put(
      url,
      queryParameters: queryParameters,
      body: body,
      headers: headersForToken(token),
    );
    throwIfHttpError(response);
    return response;
  }

  void dispose() => _http.close();

  /// No caller gets to supply the auth header through the back door, in any
  /// casing. A `Map<String, String>` compares keys byte for byte while HTTP
  /// treats header names case-insensitively, so `x-plex-token` would sail past
  /// a naive check and then win or lose the merge depending on what the
  /// underlying client does with casing. Dropping it here makes the outcome the
  /// same either way.
  static Map<String, String> _sanitizeExtraHeaders(Map<String, String> headers) {
    final cleaned = Map<String, String>.of(headers)..removeWhere((key, _) => key.toLowerCase() == 'x-plex-token');
    return Map.unmodifiable(cleaned);
  }

  /// Proof for the boundary test that nothing is baked in.
  @visibleForTesting
  Map<String, String> get injectedDefaultHeaders => _http.defaultHeaders;

  @visibleForTesting
  String get injectedBaseUrl => _http.baseUrl;
}
