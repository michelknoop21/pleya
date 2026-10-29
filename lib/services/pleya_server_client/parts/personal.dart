part of '../../pleya_server_client.dart';

/// Favorites, ratings and remembered tracks (S20). Each call is gated on its
/// own capability flag: a server that does not advertise the flag has no such
/// route, and the answer is "not done" rather than a request that 404s.
mixin _PleyaServerPersonalMethods on _PleyaServerRequests, _PleyaServerBrowseMethods {
  Future<void> setFavorite(MediaItem item, bool isFavorite) async {
    if (!await setItemFavorite(item.id, isFavorite)) throw UnsupportedError('Server favorites unavailable');
    _cursors.clear();
  }

  Future<LibraryPage<MediaItem>> fetchFavorites({MediaKind? kind, int offset = 0, int limit = 100}) async {
    if (!wireCapabilities.favorites) return const LibraryPage(items: [], totalCount: 0);
    if (offset < 0 || limit <= 0) throw ArgumentError('Invalid favorites page');
    if (kind != null && kind != MediaKind.movie && kind != MediaKind.show) {
      return const LibraryPage(items: [], totalCount: 0);
    }
    final key = PleyaServerCursorLedger.key(scope: 'favorites:${kind?.name ?? 'titles'}', sort: 'favorited');
    if (offset == 0) _cursors.invalidate(key);
    return _walkPage(
      path: '/favorites',
      ledgerKey: key,
      offset: offset,
      limit: limit,
      itemFilter: (item) => kind == null
          ? item.kind == PleyaItemKind.movie || item.kind == PleyaItemKind.show
          : item.kind == (kind == MediaKind.movie ? PleyaItemKind.movie : PleyaItemKind.show),
    );
  }

  Future<void> rate(MediaItem item, double rating) async {
    if (!wireCapabilities.ratings) throw UnsupportedError('Server ratings unavailable');
    if (!rating.isFinite || (rating >= 0 && (rating < 1 || rating > 10))) {
      throw ArgumentError.value(rating, 'rating', 'Expected 1–10, or a negative value to clear');
    }
    await setItemRating(item.id, rating < 0 ? null : rating.round());
  }

  /// Mark or unmark an item as a favorite. True when the server applied it.
  Future<bool> setItemFavorite(String itemId, bool favorite) async {
    if (!wireCapabilities.favorites) return false;
    await _adminSend(favorite ? 'PUT' : 'DELETE', '/favorites/${Uri.encodeComponent(itemId)}');
    return true;
  }

  /// Rate an item 1 to 10, or clear the rating with null.
  Future<bool> setItemRating(String itemId, int? rating) async {
    if (!wireCapabilities.ratings) return false;
    if (rating == null) {
      await _adminSend('DELETE', '/ratings/${Uri.encodeComponent(itemId)}');
    } else {
      await _adminSend('PUT', '/ratings/${Uri.encodeComponent(itemId)}', body: {'rating': rating});
    }
    return true;
  }

  Future<TrackLanguageChoice?> getTrackLanguageChoice(String itemId) async {
    final preference = await getTrackPreference(itemId);
    if (preference == null) return null;
    final choice = TrackLanguageChoice(
      audioLanguage: preference.audioLanguage,
      subtitleLanguage: preference.subtitleLanguage,
      subtitlesOff: preference.subtitleMode == 'off',
      subtitleForced: preference.subtitleMode == 'forced',
      updatedAt: 0,
      fromServer: true,
      provenance: TrackChoiceProvenance(
        serverId: connection.serverId,
        backend: MediaBackend.pleyaServer,
        serverItemId: preference.sourceItemId ?? itemId,
        serverAccountId: connection.accountUserId,
      ),
    );
    return choice.isEmpty ? null : choice;
  }

  Future<void> _languageWrites = Future<void>.value();

  Future<T> _withLanguageWrite<T>(Future<T> Function() action) {
    final result = _languageWrites.then((_) => action());
    _languageWrites = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<void> saveTrackLanguageChoice(String itemId, TrackLanguageChoice choice) => _withLanguageWrite(() async {
    if (!wireCapabilities.trackPreferences || choice.isEmpty) return;
    final previous = await getTrackLanguageChoice(itemId);
    String? language(String? value) {
      if (value == null || value.isEmpty) return null;
      final code = LanguageCodes.getIso6391Code(value) ?? value.toLowerCase().trim().split(RegExp('[-_]')).first;
      if (!RegExp(r'^[a-z]{2,3}$').hasMatch(code)) throw ArgumentError.value(value, 'language');
      return code;
    }

    final off = choice.hasSubtitle ? choice.subtitlesOff : previous?.subtitlesOff ?? false;
    final forced = choice.hasSubtitle ? choice.subtitleForced : previous?.subtitleForced ?? false;
    final subtitle = off ? null : choice.subtitleLanguage ?? previous?.subtitleLanguage;
    await saveTrackPreference(
      itemId,
      audioLanguage: language(choice.audioLanguage ?? previous?.audioLanguage),
      subtitleLanguage: language(subtitle),
      subtitleMode: off
          ? 'off'
          : subtitle == null
          ? null
          : forced
          ? 'forced'
          : 'on',
    );
  });

  /// The remembered audio and subtitle choice that applies to [itemId]. The
  /// server falls back from an episode to its season and show, so a choice
  /// made once carries over. Null when nothing is remembered or the server
  /// has no such feature.
  Future<PleyaTrackPreference?> getTrackPreference(String itemId) async {
    if (!wireCapabilities.trackPreferences) return null;
    final json = await _adminSend('GET', '/track-preferences/${Uri.encodeComponent(itemId)}');
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
      '/track-preferences/${Uri.encodeComponent(itemId)}',
      body: {'audio_language': ?audioLanguage, 'subtitle_language': ?subtitleLanguage, 'subtitle_mode': ?subtitleMode},
    );
    return true;
  }

  Future<bool> clearItemTrackPreference(String itemId, {String? expectedAccountId}) => _withLanguageWrite(() async {
    if (expectedAccountId != null && connection.accountUserId != expectedAccountId) {
      throw StateError('Track preference belongs to another account');
    }
    if (!wireCapabilities.trackPreferences) return false;
    await _adminSend('DELETE', '/track-preferences/${Uri.encodeComponent(itemId)}');
    return true;
  });

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
