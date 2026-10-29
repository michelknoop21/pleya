part of '../../pleya_server_client.dart';

/// Search across every library on one server.
///
/// One endpoint, one page of ordinary items. The contract has no separate
/// result type and no grouping per kind: the client groups, and does not have
/// to learn a second shape to do it.
mixin _PleyaServerSearchMethods on _PleyaServerRequests {
  /// Search titles on this server.
  ///
  /// No `kind` is sent, and that is the whole of [DEC-045]: without one the
  /// server answers with movies, shows and episodes and leaves seasons out,
  /// because a season's title is "Season 3" and carries nothing anyone types.
  /// Sending `kind=season` is the opt-in, and no browse or search path in the
  /// app wants it: a season is reached through its show.
  ///
  /// Cross-server search fans out in `data_aggregation_service`, which calls
  /// this once per server and merges. That layer needs no backend check, and
  /// this method exists in exactly the shape that keeps it that way.
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async {
    final trimmed = query.trim();
    // `q` has minLength 1 in the contract, so an empty query is a 400 rather
    // than an empty result. Answering locally keeps a stray keystroke off the
    // wire and out of the error log.
    if (trimmed.isEmpty || !wireCapabilities.search) return const [];
    final json = await _getJson(
      '/search',
      queryParameters: {'q': trimmed, 'limit': '${limit.clamp(1, 500)}'},
      timeout: MediaServerTimeouts.searchPerServer,
    );
    if (json == null) return const [];
    try {
      final page = PleyaItemPage.fromJson(json);
      return PleyaServerMappers.items(page.knownItems, serverId: serverId.toString(), serverName: serverName);
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: /search did not match the contract', error: e);
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Identity lookups
  // ---------------------------------------------------------------------------

  /// The one title on this server that is provably [identity], or null.
  ///
  /// Proof is a shared provider number and nothing else. Pleya Server has no
  /// guid, and a same-named title is not evidence, so the title fallback the
  /// other backends use is switched off here. Ambiguity (two titles carrying
  /// the number) never resolves, as for every backend.
  Future<MediaItem?> findByIdentity(MediaIdentity identity) async =>
      identity.pickMatch(await _identityCandidates(identity), allowTitleFallback: false);

  /// Every title on this server that is provably [identity]: a server can hold
  /// the same film in two libraries, and each copy is a source.
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async =>
      identity.pickAllMatches(await _identityCandidates(identity), allowTitleFallback: false);

  /// Asks the server for the titles that carry the number of [identity], per
  /// library of the right kind. The lookup is by number only: the folder name,
  /// the translated title and the year the server holds play no part, which is
  /// the point (a title search that comes back empty proves nothing about a
  /// number). Library rights come for free: only libraries the user may list are
  /// asked, and every hit is stamped with its library so hidden libraries are
  /// filtered the same way as for any other backend.
  ///
  /// It throws instead of answering empty wherever it cannot say "not here":
  /// [IdentityLookupUnsupported] for an identity without a TMDB number or kind
  /// and for a server without `capabilities.external_id_lookup`,
  /// [IdentityLookupUnavailable] for anything that stops an answer arriving.
  Future<List<({MediaItem item, ExternalIds ids})>> _identityCandidates(MediaIdentity identity) async {
    final tmdb = identity.externalIds.tmdb;
    final kind = identity.kind;
    if (tmdb == null || (kind != MediaKind.movie && kind != MediaKind.show)) {
      throw IdentityLookupUnsupported('${identity.title} has no TMDB number and kind to ask by');
    }
    if (!wireCapabilities.externalIdLookup) {
      throw const IdentityLookupUnsupported('this server cannot look titles up by number');
    }

    final librariesAnswer = await _getJsonDetailed('/libraries', timeout: MediaServerTimeouts.searchPerServer);
    final librariesJson = librariesAnswer.json;
    if (librariesJson == null)
      throw IdentityLookupUnavailable('/libraries gave no answer (${librariesAnswer.errorCode})');
    final List<PleyaLibrary> libraries;
    try {
      libraries = PleyaLibrary.listFromJson(librariesJson);
    } on PleyaWireFormatException {
      throw const IdentityLookupUnavailable('/libraries did not match the contract');
    }

    final wantedLibraryKind = kind == MediaKind.movie ? PleyaLibraryKind.movies : PleyaLibraryKind.shows;
    final wantedItemKind = kind == MediaKind.movie ? PleyaItemKind.movie : PleyaItemKind.show;
    final out = <({MediaItem item, ExternalIds ids})>[];
    for (final library in libraries.where((l) => l.kind == wantedLibraryKind)) {
      String? cursor;
      for (var pages = 0; ; pages++) {
        if (pages >= 3) throw IdentityLookupUnavailable('too many results for tmdb:$tmdb in ${library.id}');
        final answer = await _getJsonDetailed(
          '/libraries/${Uri.encodeComponent(library.id)}/items',
          queryParameters: {'external_id': 'tmdb:$tmdb', 'limit': '100', 'cursor': ?cursor},
          timeout: MediaServerTimeouts.searchPerServer,
        );
        final json = answer.json;
        if (json == null) {
          // A library that vanished between the two calls has nothing to give.
          if (answer.errorCode?.endsWith('not_found') ?? false) break;
          throw IdentityLookupUnavailable('${library.id} gave no answer (${answer.errorCode ?? 'no response'})');
        }
        final PleyaItemPage page;
        try {
          page = PleyaItemPage.fromJson(json);
        } on PleyaWireFormatException {
          throw IdentityLookupUnavailable('${library.id} did not match the contract');
        }
        // Believe the number on the item, not the filter alone: a server that
        // ignored the parameter returns everything, and everything is not a hit.
        final hits = [
          for (final item in page.knownItems)
            if (item.kind == wantedItemKind && item.externalIds.tmdb == tmdb) item,
        ];
        for (final item in hits) {
          out.add((
            item: PleyaServerMappers.mediaItem(
              item,
              serverId: serverId.toString(),
              serverName: serverName,
              libraryId: library.id,
              libraryTitle: library.title,
            ),
            ids: ExternalIds(tmdb: item.externalIds.tmdb),
          ));
        }
        cursor = page.nextCursor;
        if (cursor == null) break;
      }
    }
    return out;
  }
}
