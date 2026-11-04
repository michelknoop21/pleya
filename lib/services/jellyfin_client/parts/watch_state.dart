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

  bool get movesCopyWithoutViewing => true;

  /// `UserData` and not `/Sessions/Playing`: a start adds to `PlayCount`, and on
  /// Jellyfin 10.x it clears `Played` as well. Jellyfin only writes the fields a
  /// body carries. Emby does not say what it does with the others, so it gets
  /// its own values back.
  Future<bool> writeCopyState(
    MediaItem item, {
    required Duration position,
    Duration? duration,
    required bool watched,
  }) async {
    if (watched) {
      await markWatched(item);
      return true;
    }
    final ticks = msToJellyfinTicks(position.inMilliseconds);
    final response = await _http.post(
      connection.userDataPath(item.id),
      queryParameters: connection.isEmby ? null : {'userId': connection.userId},
      body: connection.isEmby
          ? {...await _embyUserData(item.id), 'PlaybackPositionTicks': ticks}
          : {'PlaybackPositionTicks': ticks},
    );
    throwIfHttpError(response);
    return true;
  }

  Future<Map<String, dynamic>> _embyUserData(String itemId) async {
    final response = await _http.get('/Users/${_segment(connection.userId)}/Items/${_segment(itemId)}');
    throwIfHttpError(response);
    final data = response.data;
    final userData = data is Map<String, dynamic> ? data['UserData'] : null;
    if (userData is! Map<String, dynamic>) throw StateError('No user data for $itemId');
    return userData;
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
