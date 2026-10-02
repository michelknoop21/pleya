part of '../../jellyfin_client.dart';

mixin _JellyfinWatchStateMethods on MediaServerCacheMixin {
  JellyfinConnection get connection;
  FailoverHttpClient get _http;

  @override
  Future<void> markWatched(MediaItem item) async {
    final response = await _http.post(
      connection.playedItemPath(item.id),
      queryParameters: {'userId': connection.userId},
    );
    throwIfHttpError(response);
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    final response = await _http.delete(
      connection.playedItemPath(item.id),
      queryParameters: {'userId': connection.userId},
    );
    throwIfHttpError(response);
  }

  /// Only Emby can: `HideFromResume`. Jellyfin has no equivalent, which is
  /// why its capabilities keep the menu entry hidden.
  @override
  Future<void> removeFromContinueWatching(MediaItem item) async {
    if (!connection.isEmby) {
      throw UnsupportedError('Jellyfin does not support removing items from Continue Watching.');
    }
    final response = await _http.post(
      '/Users/${_segment(connection.userId)}/Items/${_segment(item.id)}/HideFromResume',
      queryParameters: {'Hide': 'true'},
    );
    throwIfHttpError(response);
  }

  @override
  Future<void> rate(MediaItem item, double rating) async {
    // Lossy mapping — Jellyfin only stores a binary like/dislike. Treat
    // a negative input as "clear the rating" (DELETE), >= 6/10 as a like
    // (POST Likes=true), and the rest as a dislike (POST Likes=false).
    final response = rating < 0
        ? await _http.delete(connection.ratingPath(item.id), queryParameters: {'userId': connection.userId})
        : await _http.post(
            connection.ratingPath(item.id),
            queryParameters: {'userId': connection.userId, 'Likes': (rating >= 6.0).toString()},
          );
    throwIfHttpError(response);
  }
}
