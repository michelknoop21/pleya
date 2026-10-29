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

  /// Search on the title, read the numbers off the results, confirm on the
  /// client. The contract has no lookup by number, so this is the same route
  /// the Jellyfin client takes.
  ///
  /// It throws, instead of answering empty, wherever the server cannot answer
  /// "do you have this": an identity without a TMDB number (the only number a
  /// Pleya Server proves), an identity whose kind is unknown (a TMDB number is
  /// per kind), and a server that predates `external_ids`. An empty answer is
  /// a "no" the caller caches and counts as checked; these are "could not be
  /// checked", and the caller reports them that way.
  Future<List<({MediaItem item, ExternalIds ids})>> _identityCandidates(MediaIdentity identity) async {
    final title = identity.title;
    final tmdb = identity.externalIds.tmdb;
    final kind = identity.kind;
    if (title == null || title.trim().isEmpty) return const [];
    if (!wireCapabilities.search)
      throw StateError('PleyaServerClient: search is not available, cannot look up ${identity.title}');
    if (tmdb == null || (kind != MediaKind.movie && kind != MediaKind.show)) {
      throw StateError('PleyaServerClient: ${identity.title} cannot be proven here without a TMDB number and a kind');
    }

    // Asked per kind so episodes cannot crowd the page, and paged so a short
    // common title cannot hide the wanted one past the first page. A search
    // that is still not exhausted after a few pages is "could not check".
    final wireKind = kind == MediaKind.movie ? PleyaItemKind.movie : PleyaItemKind.show;
    final found = <PleyaItem>[];
    String? cursor;
    for (var pages = 0; ; pages++) {
      if (pages >= 5) throw StateError('PleyaServerClient: too many results for ${identity.title} to look up');
      final answer = await _getJsonDetailed(
        '/search',
        queryParameters: {'q': title.trim(), 'kind': wireKind.wire, 'limit': '100', 'cursor': ?cursor},
        timeout: MediaServerTimeouts.searchPerServer,
      );
      final json = answer.json;
      if (json == null) throw StateError('PleyaServerClient: /search gave no answer');
      final PleyaItemPage page;
      try {
        page = PleyaItemPage.fromJson(json);
      } on PleyaWireFormatException catch (e) {
        appLogger.w('PleyaServerClient: /search did not match the contract', error: e);
        throw StateError('PleyaServerClient: /search did not match the contract');
      }
      found.addAll(page.knownItems);
      cursor = page.nextCursor;
      if (cursor == null) break;
    }

    final sameKind = [
      for (final item in found)
        if (item.kind == wireKind) item,
    ];
    // Results exist, none of them speaks the field: an older server. Reading
    // that as "no match" would cache a wrong negative for the title.
    if (found.isNotEmpty && found.every((item) => !item.externalIdsReported)) {
      throw StateError('PleyaServerClient: this server predates external_ids');
    }
    return [
      for (final item in sameKind)
        (
          item: PleyaServerMappers.mediaItem(item, serverId: serverId.toString(), serverName: serverName),
          ids: ExternalIds(tmdb: item.externalIds.tmdb),
        ),
    ];
  }
}
