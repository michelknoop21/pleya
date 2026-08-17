import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../exceptions/media_server_exceptions.dart';
import '../models/livetv_channel.dart';
import 'plex_cloud_http_client.dart';

/// Plex refused the payload. Measured: a `source` that does not name an EPG
/// provider this account actually has answers 400 `Bad source value`, and
/// nothing is stored. Carries the server's own words, because "saving
/// sometimes fails" is not a diagnosis.
class PlexEpgRejected implements Exception {
  const PlexEpgRejected(this.message);

  final String message;

  @override
  String toString() => 'PlexEpgRejected: $message';
}

/// The token was refused. [statusCode] is kept because 401 and 403 are not the
/// same thing: 401 says the credential is no good, 403 can also mean the
/// credential is fine but this operation is not allowed. The UI treats them
/// alike; a diagnosis six months from now will not, and recovering the
/// distinction later would cost an API change.
class PlexEpgUnauthorized implements Exception {
  const PlexEpgUnauthorized({required this.statusCode, this.message});

  final int statusCode;
  final String? message;

  @override
  String toString() => 'PlexEpgUnauthorized($statusCode): ${message ?? 'no message'}';
}

/// Thin HTTP layer over the favorite-channel list Plex keeps in its cloud.
///
/// The list belongs to a plex.tv account, not to a media server, so it needs
/// the account token and must never see a PMS token. That is why this lives
/// next to [PlexWatchlistClient] on [PlexCloudHttpClient] instead of inside
/// `PlexClient`, whose HTTP client merges the server token into every request
/// including absolute-URL ones.
///
/// Errors propagate instead of being swallowed. That is not a style choice: a
/// read that fails silently and returns an empty list is indistinguishable from
/// an account with no favorites, and the caller then writes that emptiness back
/// as the complete list. See `docs/DECISIONS.md`, DEC-021.
class PlexEpgClient {
  static const String base = 'https://epg.provider.plex.tv';
  static const String favoriteChannelsPath = '/settings/favoriteChannels';

  /// The EPG host wants this on every call. It belongs to the host, so it is
  /// declared once on the transport instead of repeated per operation.
  static const Map<String, String> providerHeaders = {'X-Plex-Provider-Version': '5.1'};

  final PlexCloudHttpClient _cloud;

  PlexEpgClient._(this._cloud);

  factory PlexEpgClient({required String clientIdentifier, String product = 'Pleya'}) {
    return PlexEpgClient._(
      PlexCloudHttpClient(clientIdentifier: clientIdentifier, product: product, extraHeaders: providerHeaders),
    );
  }

  @visibleForTesting
  factory PlexEpgClient.forTesting({
    required http.Client httpClient,
    String clientIdentifier = 'test-client',
    String product = 'Pleya',
  }) {
    return PlexEpgClient._(
      PlexCloudHttpClient(
        clientIdentifier: clientIdentifier,
        product: product,
        extraHeaders: providerHeaders,
        httpClient: httpClient,
      ),
    );
  }

  Map<String, String> headersForToken(String token) => _cloud.headersForToken(token);

  void dispose() => _cloud.dispose();

  /// The account's favorite channels.
  ///
  /// A 200 whose container has no `FavoriteChannel` key is a genuinely empty
  /// list, which is what an account without favorites answers. Anything else
  /// throws; deciding that a failure means "empty" is exactly what destroys the
  /// list on the next write.
  Future<List<FavoriteChannel>> fetchFavoriteChannels({required String token}) async {
    final response = await _guard(() => _cloud.get('$base$favoriteChannelsPath', token: token));
    final container = _mediaContainer(response.data);
    final channels = container?['FavoriteChannel'];
    if (channels is! List) return const [];
    return [
      for (final entry in channels)
        if (entry is Map<String, dynamic>) FavoriteChannel.fromJson(entry),
    ];
  }

  /// Replace the whole list. Plex has no per-entry endpoint: a write is always
  /// the complete list, which is why the caller must be sure it holds the
  /// complete list before calling this.
  Future<void> setFavoriteChannels({required String token, required List<FavoriteChannel> channels}) async {
    await _guard(
      () => _cloud.put('$base$favoriteChannelsPath', token: token, body: [for (final c in channels) c.toJson()]),
    );
  }

  /// Turn the transport's HTTP failures into the two cases a caller can act on,
  /// and let everything else through untouched.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on MediaServerHttpException catch (e) {
      final status = e.statusCode;
      if (status == 401 || status == 403) {
        throw PlexEpgUnauthorized(statusCode: status!, message: _errorMessage(e.responseData));
      }
      if (status == 400) {
        throw PlexEpgRejected(_errorMessage(e.responseData) ?? 'the request was rejected');
      }
      rethrow;
    }
  }

  static String? _errorMessage(dynamic data) {
    if (data is Map) {
      final error = data['Error'];
      if (error is Map && error['message'] is String) return error['message'] as String;
      if (data['message'] is String) return data['message'] as String;
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  static Map<String, dynamic>? _mediaContainer(dynamic data) {
    if (data is! Map) return null;
    final container = data['MediaContainer'];
    return container is Map<String, dynamic> ? container : null;
  }
}
