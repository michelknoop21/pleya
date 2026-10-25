part of '../../pleya_server_client.dart';

/// Favorites, ratings and remembered tracks (S20). Each call is gated on its
/// own capability flag: a server that does not advertise the flag has no such
/// route, and the answer is "not done" rather than a request that 404s.
mixin _PleyaServerPersonalMethods on _PleyaServerRequests {
  /// Mark or unmark an item as a favorite. True when the server applied it.
  Future<bool> setItemFavorite(String itemId, bool favorite) async {
    if (!wireCapabilities.favorites) return false;
    await _adminSend(favorite ? 'PUT' : 'DELETE', '/favorites/$itemId');
    return true;
  }

  /// Rate an item 1 to 10, or clear the rating with null.
  Future<bool> setItemRating(String itemId, int? rating) async {
    if (!wireCapabilities.ratings) return false;
    if (rating == null) {
      await _adminSend('DELETE', '/ratings/$itemId');
    } else {
      await _adminSend('PUT', '/ratings/$itemId', body: {'rating': rating});
    }
    return true;
  }

  /// The remembered audio and subtitle choice that applies to [itemId]. The
  /// server falls back from an episode to its season and show, so a choice
  /// made once carries over. Null when nothing is remembered or the server
  /// has no such feature.
  Future<PleyaTrackPreference?> getTrackPreference(String itemId) async {
    if (!wireCapabilities.trackPreferences) return null;
    final json = await _getJson('/track-preferences/$itemId');
    return json == null ? null : PleyaTrackPreference.fromJson(json);
  }

  Future<bool> saveTrackPreference(
    String itemId, {
    String? audioLanguage,
    String? subtitleLanguage,
    String? subtitleMode,
  }) async {
    if (!wireCapabilities.trackPreferences) return false;
    await _adminSend(
      'PUT',
      '/track-preferences/$itemId',
      body: {'audio_language': ?audioLanguage, 'subtitle_language': ?subtitleLanguage, 'subtitle_mode': ?subtitleMode},
    );
    return true;
  }

  Future<bool> clearItemTrackPreference(String itemId) async {
    if (!wireCapabilities.trackPreferences) return false;
    await _adminSend('DELETE', '/track-preferences/$itemId');
    return true;
  }

  /// The Pleya Verify fixture's kijklijst (`watchlist.studio.v1`): item ids,
  /// newest first. Only `WatchlistSourceFactory` in a `PLEYA_VERIFY` build
  /// asks; a real Pleya Server has no such route, and its 404 reads as empty.
  Future<List<String>> fetchVerifyWatchlistIds() async {
    final ids = (await _getJson('/verify/watchlist'))?['item_ids'];
    return ids is List
        ? [
            for (final id in ids)
              if (id is String) id,
          ]
        : const [];
  }
}
