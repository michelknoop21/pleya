part of '../../pleya_server_client.dart';

/// Libraries, items, children and hubs on Pleya Protocol v1.
///
/// ## Offsets meet cursors here
///
/// `LibraryQuery` counts in offsets because Plex and Jellyfin do. The protocol
/// pages with an opaque cursor, on purpose: an offset into a list that is being
/// scanned shifts under the reader, and chapter 12.7 says so. The two do not
/// convert, so this file walks. A request for offset 0 starts at the top; one
/// for an offset the [PleyaServerCursorLedger] has a boundary for resumes
/// exactly; one for an offset in between walks forward from the nearest known
/// boundary, which is the pattern a scrolling grid produces anyway.
///
/// Walking is bounded by [_maxCursorWalk]. A caller that jumps far past
/// anything it has scrolled gets what the walk reached rather than a stall,
/// because a grid that is briefly short is repairable and a request that never
/// returns is not.
mixin _PleyaServerBrowseMethods on _PleyaServerRequests {
  /// How many *fruitless* pages in a row a single request may walk before
  /// giving up — pages that contributed nothing to the window being filled,
  /// because they fell entirely before the requested offset or held only items
  /// this build cannot classify.
  ///
  /// Counting every page instead made the bound fire on a healthy library that
  /// pages smaller than the window asked for, and the short page that came
  /// back reads as "library exhausted" one layer up. A page that contributes
  /// is progress and resets the count, so the bound is still what it was meant
  /// to be: a stop on a walk that is getting nowhere, not a cap on a walk that
  /// is working.
  static const int _maxCursorWalk = 10;

  /// The largest page the contract accepts. A bigger `limit` is clamped by the
  /// server and is explicitly not an error, but asking for more than this
  /// wastes a round-trip's worth of expectation.
  static const int _maxPageSize = 500;

  // ---------------------------------------------------------------------------
  // Libraries
  // ---------------------------------------------------------------------------

  Future<List<MediaLibrary>> fetchLibraries() async {
    final json = await _getJson('/libraries');
    if (json == null) return const [];
    try {
      final libraries = PleyaLibrary.listFromJson(json);
      return [
        for (final library in libraries)
          // A kind this build does not know is hidden rather than shown as an
          // unbrowsable row. The contract asks for exactly that.
          if (library.kind != null)
            PleyaServerMappers.library(library, serverId: serverId.toString(), serverName: serverName),
      ];
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: /libraries did not match the contract', error: e);
      return const [];
    }
  }

  /// Sort options the contract actually accepts.
  ///
  /// A fixed list and not a server call, because the protocol has no
  /// sort-listing endpoint: the enum on `/libraries/{id}/items` is the whole
  /// truth. Title, date added and year always; last watched and duration only
  /// under `capabilities.filters`, since an older server answers 400 on them.
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async => [
    MediaSort(key: 'title', descKey: 'title:desc', title: t.libraries.sortLabels.title, defaultDirection: 'asc'),
    MediaSort(
      key: 'addedAt',
      descKey: 'addedAt:desc',
      title: t.libraries.sortLabels.dateAdded,
      defaultDirection: 'desc',
    ),
    MediaSort(
      key: 'year',
      descKey: 'year:desc',
      title: t.libraries.sortLabels.productionYear,
      defaultDirection: 'desc',
    ),
    if (wireCapabilities.filters) ...[
      MediaSort(
        key: 'lastViewedAt',
        descKey: 'lastViewedAt:desc',
        title: t.libraries.sortLabels.lastPlayed,
        defaultDirection: 'desc',
      ),
      MediaSort(
        key: 'duration',
        descKey: 'duration:desc',
        title: t.libraries.sortLabels.runtime,
        defaultDirection: 'asc',
      ),
    ],
  ];

  Future<LibraryPage<MediaItem>> fetchLibraryContent(String libraryId, LibraryQuery query) =>
      fetchLibraryPagedContent(libraryId, query: query);

  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
    bool strictSnapshot = false,
  }) async {
    if (!wireCapabilities.browse) {
      if (strictSnapshot) throw StateError('Browse capability is not available for a snapshot');
      return const LibraryPage(items: [], totalCount: 0);
    }
    final filters = _filterParameters(query);
    if (filters.isNotEmpty && !wireCapabilities.filters) {
      // A server without the capability ignores these parameters and would hand
      // back the whole library as the answer to a filter. An empty page is
      // wrong in an honest way; an unfiltered one is wrong in a misleading way.
      if (strictSnapshot) throw StateError('Required snapshot filters are not supported');
      appLogger.w('PleyaServerClient: filters requested but the server does not advertise them');
      return const LibraryPage(items: [], totalCount: 0);
    }
    final sort = _sortFor(query.sort);
    final extra = <String, dynamic>{'sort': sort, ...filters};
    return _walkPage(
      path: '/libraries/${Uri.encodeComponent(libraryId)}/items',
      // The cursor belongs to a sort and a filter set, so both are in the key.
      ledgerKey: PleyaServerCursorLedger.key(scope: 'library:$libraryId', sort: '$sort|${_filterKey(filters)}'),
      offset: query.offset,
      limit: query.limit,
      extraQuery: extra,
      libraryId: libraryId,
      abort: abort,
      strictSnapshot: strictSnapshot,
    );
  }

  /// The wire spelling of the filters in [query], as repeated query parameters.
  ///
  /// The filter sheet hands over one comma-joined string per field (the Plex
  /// habit), so each entry is split again. Watch has three spellings on the
  /// neutral query and one on the wire; `watchedOnly` wins over `inProgressOnly`
  /// over `includeWatched: false`, which is the order of how much they narrow.
  Map<String, List<String>> _filterParameters(LibraryQuery query) {
    List<String> split(List<String>? raw) => [
      for (final entry in raw ?? const <String>[])
        for (final part in entry.split(','))
          if (part.trim().isNotEmpty) part.trim(),
    ];
    final out = <String, List<String>>{};
    void put(String key, List<String> values) {
      if (values.isNotEmpty) out[key] = values;
    }

    put('genre', split(query.genres));
    put('year', [
      for (final y in query.years ?? const <int>[])
        if (y >= 1800 && y <= 2200) '$y',
    ]);
    put('content_rating', split(query.officialRatings));
    put('audio_language', split(query.audioLanguages));
    for (final filter in query.filters) {
      if (filter.field == 'resolution') put('resolution', split(filter.values));
    }
    if (query.watchedOnly) {
      out['watch'] = const ['watched'];
    } else if (query.inProgressOnly) {
      out['watch'] = const ['in_progress'];
    } else if (!query.includeWatched) {
      out['watch'] = const ['unwatched'];
    }
    return out;
  }

  String _filterKey(Map<String, List<String>> filters) {
    final keys = filters.keys.toList()..sort();
    return keys.map((k) => '$k=${([...filters[k]!]..sort()).join(',')}').join('&');
  }

  /// The filter sheet's categories and values, from `GET /libraries/{id}/facets`.
  ///
  /// One call returns every category with its values, so the result is
  /// pre-populated the way Jellyfin's is and the sheet skips the per-category
  /// fetch. Category keys are Plex's (`genre`, `audioLanguage`, `year`,
  /// `contentRating`) because that is the vocabulary the sheet and the query
  /// translator share; `resolution` and the synthetic `unwatched` toggle are
  /// the two additions. A server without `capabilities.filters` answers empty,
  /// which is a sheet with nothing on it rather than one that cannot filter.
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async {
    if (!wireCapabilities.browse || !wireCapabilities.filters) return LibraryFilterResult.empty;
    final json = await _getJson('/libraries/${Uri.encodeComponent(libraryId)}/facets');
    if (json == null) return LibraryFilterResult.empty;
    final PleyaFacets facets;
    try {
      facets = PleyaFacets.fromJson(json);
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: facets did not match the contract', error: e);
      return LibraryFilterResult.empty;
    }

    final filters = <MediaFilter>[
      MediaFilter(
        filter: 'unwatched',
        filterType: 'boolean',
        key: 'pleya:unwatched',
        title: t.libraries.filterCategories.unwatched,
        type: 'filter',
      ),
    ];
    final values = <String, List<MediaFilterValue>>{};
    void category(String filter, String title, List<PleyaFacetValue> facet, {String Function(String)? label}) {
      if (facet.isEmpty) return;
      filters.add(
        MediaFilter(filter: filter, filterType: 'string', key: 'pleya:$filter', title: title, type: 'filter'),
      );
      values[filter] = [for (final v in facet) MediaFilterValue(key: v.value, title: label?.call(v.value) ?? v.value)];
    }

    final categories = t.libraries.filterCategories;
    category('genre', categories.genre, facets.genres);
    category(
      'audioLanguage',
      categories.audioLanguage,
      facets.audioLanguages,
      label: (code) => languageDisplayName(code) ?? code,
    );
    category('year', categories.year, facets.years);
    category('contentRating', categories.contentRating, facets.contentRatings);
    category('resolution', categories.resolution, facets.resolutions, label: (value) => value.toUpperCase());
    return LibraryFilterResult(filters: filters, cachedValues: values);
  }

  /// The contract's sort spelling for a neutral [LibrarySort].
  ///
  /// A field the protocol does not carry falls back to title rather than being
  /// passed through. The server would answer 400 on an unknown value, and a
  /// library that renders in the wrong order beats one that renders an error.
  /// The two sorts that only exist under `capabilities.filters` fall back the
  /// same way on a server without it.
  String _sortFor(LibrarySort? sort) {
    final descending = sort?.direction == LibrarySortDirection.descending;
    final key = switch (sort?.field) {
      'addedAt' || 'added_at' => PleyaSortKey.addedAt,
      'year' || 'productionYear' || 'originallyAvailableAt' => PleyaSortKey.year,
      'lastViewedAt' || 'last_played_at' when wireCapabilities.filters => PleyaSortKey.lastPlayedAt,
      'duration' when wireCapabilities.filters => PleyaSortKey.duration,
      _ => PleyaSortKey.title,
    };
    return key.query(descending: descending);
  }

  // ---------------------------------------------------------------------------
  // Items and children
  // ---------------------------------------------------------------------------

  Future<MediaItem?> fetchItem(String id) async {
    final json = await _getJson('/items/${Uri.encodeComponent(id)}');
    if (json == null) return null;
    try {
      final item = PleyaItem.fromJson(json);
      if (item.kind == null) return null;
      // The next playback_started claims the revision this client last saw. A
      // read that moves the item past it, say another device watched on, would
      // otherwise get that event refused as stale and leave the viewing
      // without an owner, so its progress would never be stored.
      _watchLedger.remember(item.id, item.userState?.revision);
      final ancestors = await _ancestorsOf(item);
      return PleyaServerMappers.mediaItem(
        item,
        serverId: serverId.toString(),
        serverName: serverName,
        parent: ancestors.parent,
        grandparent: ancestors.grandparent,
      );
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: /items/$id did not match the contract', error: e);
      return null;
    }
  }

  /// The provider numbers the server has proven for a movie or show, for the
  /// unified identity pipeline.
  ///
  /// Always a fresh read: the server can match a title later, and a cached
  /// answer would keep a title unrecognisable until the client restarts. The
  /// caller already caches per resolution pass.
  ///
  /// An empty answer means "no evidence", never "no match": a server that
  /// predates `external_ids`, an unmatched title, a season and an episode all
  /// come back the same way, and grouping then keeps the source on its own
  /// card. A transport failure throws, like the Plex client, so a cached empty
  /// answer cannot pin a title without evidence for the rest of a catalog
  /// merge. An answer from the server that is an error, say the item is gone,
  /// is a real answer and comes back empty.
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    final answer = await _getJsonDetailed('/items/${Uri.encodeComponent(itemId)}');
    final json = answer.json;
    if (json == null) {
      if (answer.errorCode == null) throw StateError('PleyaServerClient: no answer for /items/$itemId');
      return const ExternalIds();
    }
    try {
      final item = PleyaItem.fromJson(json);
      if (item.kind != PleyaItemKind.movie && item.kind != PleyaItemKind.show) return const ExternalIds();
      return ExternalIds(tmdb: item.externalIds.tmdb);
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: /items/$itemId did not match the contract', error: e);
      return const ExternalIds();
    }
  }

  /// An item plus the episode to resume.
  ///
  /// The second half is always null until PS-4. `next_up` is a home-screen hub
  /// and not a per-series answer, and the server reports
  /// `capabilities.watch_state: false`, so there is nothing to resume from.
  /// Synthesising "first unwatched episode" from a catalogue with no watch
  /// state would mean always the first episode, dressed as a resume point.
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: await fetchItem(id), onDeckEpisode: null);

  Future<List<MediaItem>> fetchChildren(String parentId) async {
    final page = await fetchChildrenPage(parentId, start: 0, size: _maxPageSize);
    return page.items;
  }

  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
    bool strictSnapshot = false,
  }) async {
    if (!wireCapabilities.browse) {
      if (strictSnapshot) throw StateError('Browse capability is not available for a snapshot');
      return const LibraryPage(items: [], totalCount: 0);
    }
    // Children have no sort parameter in the contract; the server returns them
    // in their natural order, which for seasons and episodes is the order a
    // viewer expects.
    return _walkPage(
      path: '/items/${Uri.encodeComponent(parentId)}/children',
      ledgerKey: PleyaServerCursorLedger.key(scope: 'children:$parentId', sort: 'natural'),
      offset: start ?? 0,
      limit: size ?? 100,
      parentId: parentId,
      abort: abort,
      strictSnapshot: strictSnapshot,
    );
  }

  /// Every playable leaf under [parentId].
  ///
  /// A movie is its own leaf, a season's children are episodes, and a show
  /// needs both hops. The contract has no recursive listing, so the hops are
  /// explicit; a season at a time keeps a long-running series from becoming one
  /// unbounded request.
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    final page = await fetchPlayableDescendantsPage(parentId, start: 0, size: _maxPageSize);
    return page.items;
  }

  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final direct = await fetchChildrenPage(parentId, start: 0, size: _maxPageSize, abort: abort);
    final leaves = <MediaItem>[];
    for (final child in direct.items) {
      if (child.kind == MediaKind.season || child.kind == MediaKind.show) {
        final grandchildren = await fetchChildrenPage(child.id, start: 0, size: _maxPageSize, abort: abort);
        leaves.addAll(grandchildren.items.where((item) => item.kind.isPlayable));
      } else if (child.kind.isPlayable) {
        leaves.add(child);
      }
    }
    final offset = start ?? 0;
    final window = leaves.skip(offset).take(size ?? leaves.length).toList();
    return LibraryPage(items: window, totalCount: leaves.length, offset: offset);
  }

  /// Null hands the caller back to the generic episode-queue path, which builds
  /// a queue from [fetchPlayableDescendants]. There is no server-side queue in
  /// the protocol and pretending otherwise would put a second, weaker ordering
  /// next to the one that already works.
  Future<List<MediaItem>?> fetchClientSideEpisodeQueue(String seriesId) async => null;

  // ---------------------------------------------------------------------------
  // Hubs
  // ---------------------------------------------------------------------------

  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async =>
      (await _hubPage(PleyaHubId.recentlyAdded, limit: limit)).items;

  Future<List<MediaItem>> fetchRecentlyAddedShows({int limit = 50}) async {
    final items = await fetchRecentlyAdded(limit: limit);
    return items.where((item) => item.kind == MediaKind.show).toList();
  }

  /// `continue_watching` and `next_up` merged by the same rule Jellyfin uses
  /// (DEC-144 fase 2); the home rows below still hand `next_up` over as its
  /// own row, unchanged.
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async {
    // Null means the whole list; a hub page is bounded, so ask for a page that
    // is in practice never full rather than silently capping at the preview.
    final limit = count ?? 200;
    // Asked regardless of the advertised watch-state capability: a server
    // without it answers both hubs with an empty list by design, and one that
    // leaves the flag out can still have a list (the Verify fixture does).
    final pages = await Future.wait([
      _hubPage(PleyaHubId.continueWatching, limit: limit),
      _hubPage(PleyaHubId.nextUp, limit: limit),
    ]);
    return mergeContinueWatchingAndNextUp(resume: pages[0].items, nextUp: pages[1].items, limit: count);
  }

  /// The three hubs the contract defines, as home rows.
  ///
  /// The server hands over building blocks and no screen layout; the client's
  /// own recommendation engine arranges them. Empty rows are dropped here as
  /// well as by the discover screen, because a server without watch state
  /// answers `continue_watching` and `next_up` with an empty list by design and
  /// two blank sections is not a home screen.
  Future<List<MediaHub>> fetchGlobalHubs({int limit = defaultHubPreviewLimit, bool includePlaybackHubs = true}) async {
    final requests = <PleyaHubId>[
      PleyaHubId.recentlyAdded,
      if (includePlaybackHubs && wireCapabilities.watchState) ...[PleyaHubId.continueWatching, PleyaHubId.nextUp],
    ];
    final pages = await Future.wait([for (final hub in requests) _hubPage(hub, limit: limit)]);
    return [
      for (var i = 0; i < requests.length; i++) _hub(requests[i], pages[i], limit: limit),
    ].where((hub) => hub.items.isNotEmpty).toList();
  }

  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    required String libraryName,
    MediaKind? libraryKind,
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
  }) async {
    final requests = <PleyaHubId>[
      PleyaHubId.recentlyAdded,
      if (includePlaybackHubs && wireCapabilities.watchState) ...[PleyaHubId.continueWatching, PleyaHubId.nextUp],
    ];
    final pages = await Future.wait([for (final hub in requests) _hubPage(hub, limit: limit, libraryId: libraryId)]);
    return [
      for (var i = 0; i < requests.length; i++) _hub(requests[i], pages[i], limit: limit, libraryId: libraryId),
    ].where((hub) => hub.items.isNotEmpty).toList();
  }

  Future<List<MediaItem>> fetchMoreHubItems(String hubId, {int? limit}) async =>
      (await fetchMoreHubItemsPage(hubId, start: 0, size: limit ?? 50)).items;

  Future<LibraryPage<MediaItem>> fetchMoreHubItemsPage(
    String hubId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final parsed = _parseHubKey(hubId);
    if (parsed == null) return const LibraryPage(items: [], totalCount: 0);
    final page = await _walkPage(
      path: '/hubs/${parsed.hub.wire}',
      ledgerKey: PleyaServerCursorLedger.key(
        scope: 'hub:${parsed.hub.wire}:${parsed.libraryId ?? ''}',
        sort: 'natural',
      ),
      offset: start ?? 0,
      limit: size ?? 50,
      extraQuery: {'library_id': ?parsed.libraryId},
      libraryId: parsed.libraryId,
      abort: abort,
    );
    // `_hub()` types Next Up as `episode` unconditionally (it is always a
    // per-episode queue, never classified from its content like the other
    // two hubs), so paging further into it must hold to that same kind —
    // otherwise a stray non-episode item would ride into a row every reader
    // downstream, from `UnifiedHubKind` to the Next Up card layout, has been
    // told only ever holds episodes.
    if (parsed.hub != PleyaHubId.nextUp) return page;
    final filtered = page.items.where((item) => item.kind == MediaKind.episode).toList();
    return filtered.length == page.items.length ? page : page.copyWith(items: filtered);
  }

  Future<LibraryPage<MediaItem>> _hubPage(PleyaHubId hub, {required int limit, String? libraryId}) => _walkPage(
    path: '/hubs/${hub.wire}',
    ledgerKey: PleyaServerCursorLedger.key(scope: 'hub:${hub.wire}:${libraryId ?? ''}', sort: 'natural'),
    offset: 0,
    limit: limit,
    extraQuery: {'library_id': ?libraryId},
    libraryId: libraryId,
  );

  MediaHub _hub(PleyaHubId hub, LibraryPage<MediaItem> page, {required int limit, String? libraryId}) {
    // The identifiers match what `MediaHub` already recognises as continue and
    // next-up rows, so the activation preference and the context menu behave
    // the same on this backend as on the other two.
    final key = libraryId == null ? 'home' : 'library.$libraryId';
    final (identifier, title, type) = switch (hub) {
      PleyaHubId.recentlyAdded => ('$key.recent', t.discover.recentlyAdded, _hubItemsType(page.items)),
      PleyaHubId.continueWatching => ('$key.continue', t.discover.continueWatching, _hubItemsType(page.items)),
      PleyaHubId.nextUp => ('$key.nextup', t.discover.nextUp, 'episode'),
    };
    return MediaHub(
      id: identifier,
      identifier: identifier,
      title: title,
      type: type,
      items: page.items,
      size: page.items.length,
      more: page.items.length >= limit,
      libraryId: libraryId,
      serverId: serverId.toString(),
      serverName: serverName,
    );
  }

  /// `movie` when every item is a movie, `show` when every item is
  /// show-related (`show`, `season` or `episode`, see [MediaKind.isShowRelated]),
  /// `mixed` otherwise (including the empty page and a genuine movie/show
  /// mix). Only Plex reports a hub's kind itself; neither the protocol nor
  /// Jellyfin does (see REV1's identical fix on the Jellyfin side, in
  /// `JellyfinMappers._hubItemsType`), so without this every Pleya Server hub
  /// came back `mixed` regardless of content, and
  /// [UnifiedHubKind.singleKindSurface] excludes `mixed` from both the Films
  /// and the Series landing, so recently added and continue watching could
  /// never appear on either, no matter what was in the library.
  ///
  /// An all-episode page (Continue Watching part-way through a season, a
  /// library's Recently Added stopping at the latest episodes) is grouped
  /// under `show`, not left as its own bucket: [MediaKind.episode] carries no
  /// `singleKindSurface` of its own, and treating it as neither-Films-nor-
  /// Series would make such a hub vanish from Series, which is exactly the
  /// destination its episodes belong to.
  String _hubItemsType(List<MediaItem> items) {
    if (items.isEmpty) return 'mixed';
    if (items.every((item) => item.kind == MediaKind.movie)) return 'movie';
    if (items.every((item) => item.kind.isShowRelated)) return 'show';
    return 'mixed';
  }

  ({PleyaHubId hub, String? libraryId})? _parseHubKey(String hubId) {
    final tokens = hubId.split('.');
    if (tokens.length < 2) return null;
    final suffix = tokens.last;
    final hub = switch (suffix) {
      'recent' => PleyaHubId.recentlyAdded,
      'continue' => PleyaHubId.continueWatching,
      'nextup' => PleyaHubId.nextUp,
      _ => null,
    };
    if (hub == null) return null;
    final libraryId = tokens.first == 'library' && tokens.length >= 3
        ? tokens.sublist(1, tokens.length - 1).join('.')
        : null;
    return (hub: hub, libraryId: libraryId);
  }

  // ---------------------------------------------------------------------------
  // The cursor walk
  // ---------------------------------------------------------------------------

  /// Fetch the window `[offset, offset + limit)` of a cursored listing.
  ///
  /// Records every boundary it crosses, so the next scroll step resumes instead
  /// of walking again.
  Future<LibraryPage<MediaItem>> _walkPage({
    required String path,
    required String ledgerKey,
    required int offset,
    required int limit,
    Map<String, dynamic> extraQuery = const {},
    String? libraryId,
    String? parentId,
    AbortController? abort,
    bool strictSnapshot = false,
  }) async {
    final pageSize = limit <= 0 ? 100 : (limit > _maxPageSize ? _maxPageSize : limit);
    var position = offset <= 0 ? 0 : _cursors.nearestKnownOffset(ledgerKey, offset);
    var cursor = position == 0 ? null : _cursors.cursorFor(ledgerKey, position);
    final collected = <PleyaItem>[];
    var walked = 0;
    var restarted = false;

    while (true) {
      final answer = await _getJsonDetailed(
        path,
        queryParameters: {'limit': '$pageSize', ...extraQuery, 'cursor': ?cursor},
        abort: abort,
      );
      // A stored cursor the server no longer accepts (it was issued before a
      // server update, or the catalogue moved under it) is not an empty list.
      // Forget this listing and walk once from the top. One restart only: a
      // server that refuses the cursors of its own fresh walk would otherwise
      // keep this loop going.
      if (answer.errorCode == 'library.cursor_invalid' && cursor != null && !restarted) {
        appLogger.d('PleyaServerClient: $path refused its cursor, walking again from the start');
        restarted = true;
        _cursors.invalidate(ledgerKey);
        position = 0;
        cursor = null;
        collected.clear();
        walked = 0;
        continue;
      }
      final json = answer.json;
      if (json == null) {
        if (strictSnapshot) throw StateError('Snapshot page was not received');
        break;
      }
      final PleyaItemPage page;
      try {
        page = PleyaItemPage.fromJson(json);
      } on PleyaWireFormatException catch (e) {
        if (strictSnapshot) rethrow;
        appLogger.w('PleyaServerClient: $path did not match the contract', error: e);
        break;
      }
      if (strictSnapshot && page.items.length != page.knownItems.length) {
        throw StateError('Snapshot contains unsupported items');
      }
      _cursors.recordPage(
        ledgerKey,
        offset: position,
        count: page.items.length,
        nextCursor: page.nextCursor,
        totalEstimate: page.totalEstimate,
      );

      // Items before the requested offset belong to an earlier window and are
      // dropped rather than returned; the walk only exists to reach the window.
      final skipInThisPage = offset > position ? offset - position : 0;
      if (skipInThisPage < page.knownItems.length) {
        collected.addAll(page.knownItems.skip(skipInThisPage));
      }
      position += page.items.length;

      if (collected.length >= limit || page.nextCursor == null || page.items.isEmpty) break;
      // The walk bound counts *fruitless* pages, not pages. Counting every
      // page made the cap fire on a healthy library that simply pages smaller
      // than the window asked for — the walk then returned a short page while
      // the cursor still pointed at more, and a short page is exactly how
      // UnifiedCatalogService decides a library is exhausted (E8). The rest of
      // that library silently never appeared, under an `isComplete` that said
      // the catalogue was finished. A page that contributed something is
      // progress, so it resets the count; the bound still stops a long stretch
      // of pages that give this window nothing.
      if (skipInThisPage < page.knownItems.length) {
        walked = 0;
      } else if (++walked >= _maxCursorWalk) {
        appLogger.d('PleyaServerClient: stopped walking $path after $_maxCursorWalk unproductive pages');
        break;
      }
      cursor = page.nextCursor;
    }

    final window = collected.length > limit ? collected.take(limit).toList() : collected;
    final items = PleyaServerMappers.items(
      window,
      serverId: serverId.toString(),
      serverName: serverName,
      libraryId: libraryId,
      parents: await _ancestorsFor(window, parentId: parentId),
    );
    final estimate = _cursors.totalEstimate(ledgerKey);
    if (strictSnapshot && estimate == null) throw StateError('Snapshot count is unavailable');
    return LibraryPage(items: items, totalCount: estimate ?? (offset + items.length), offset: offset);
  }

  // ---------------------------------------------------------------------------
  // Ancestors
  // ---------------------------------------------------------------------------

  /// The parent and grandparent of [item], fetched when they are not already
  /// at hand.
  ///
  /// The contract puts only `parent_id` on an item, so an episode's show title
  /// costs two extra reads. That is acceptable on a detail screen, where this
  /// is called once. It is not acceptable per row, which is why the list path
  /// uses [_ancestorsFor] instead.
  Future<({PleyaItem? parent, PleyaItem? grandparent})> _ancestorsOf(PleyaItem item) async {
    final parentId = item.parentId;
    if (parentId == null || item.kind == PleyaItemKind.movie) return (parent: null, grandparent: null);
    final parent = await _rawItem(parentId);
    if (parent == null) return (parent: null, grandparent: null);
    final grandparentId = parent.parentId;
    final grandparent = grandparentId == null ? null : await _rawItem(grandparentId);
    return (parent: parent, grandparent: grandparent);
  }

  /// Ancestors for a whole page, fetched once per distinct ancestor.
  ///
  /// A season of twenty-four episodes shares one parent and one grandparent, so
  /// this is two reads for the page rather than forty-eight. [parentId] seeds
  /// the map when the caller already knows which parent it asked for, which is
  /// the children case and removes one of the two.
  Future<Map<String, PleyaItem>> _ancestorsFor(List<PleyaItem> items, {String? parentId}) async {
    final needed = <String>{
      ?parentId,
      for (final item in items)
        if (item.kind == PleyaItemKind.episode || item.kind == PleyaItemKind.season) ?item.parentId,
    };
    if (needed.isEmpty) return const {};
    final resolved = <String, PleyaItem>{};
    for (final id in needed) {
      final parent = await _rawItem(id);
      if (parent != null) resolved[id] = parent;
    }
    // One more hop for the shows behind the seasons just resolved.
    final grandparentIds = {
      for (final parent in resolved.values)
        if (parent.kind == PleyaItemKind.season) ?parent.parentId,
    }..removeWhere(resolved.containsKey);
    for (final id in grandparentIds) {
      final grandparent = await _rawItem(id);
      if (grandparent != null) resolved[id] = grandparent;
    }
    return resolved;
  }

  final Map<String, PleyaItem> _itemCache = {};

  /// One item in wire form, memoised for the lifetime of the client.
  ///
  /// A show's title does not change between two rows of the same page, and it
  /// changes rarely enough between screens that a per-client cache is the right
  /// grain. Metadata edits are PS-7 and will need this invalidated; there is
  /// nothing to invalidate for yet.
  Future<PleyaItem?> _rawItem(String id) async {
    final cached = _itemCache[id];
    if (cached != null) return cached;
    final json = await _getJson('/items/${Uri.encodeComponent(id)}');
    if (json == null) return null;
    try {
      final item = PleyaItem.fromJson(json);
      _itemCache[id] = item;
      return item;
    } on PleyaWireFormatException {
      return null;
    }
  }
}
