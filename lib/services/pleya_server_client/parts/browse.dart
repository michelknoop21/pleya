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
mixin _PleyaServerBrowseMethods {
  // Members the shell provides. Declared here so this mixin can be read on its
  // own and so the compiler, rather than a reader, checks the seam.
  ServerId get serverId;
  String? get serverName;
  PleyaServerConnection get connection;
  PleyaServerCursorLedger get _cursors;
  PleyaCapabilities get wireCapabilities;
  Future<Map<String, dynamic>?> _getJson(String path, {Map<String, dynamic>? queryParameters, AbortController? abort});

  /// How many extra pages a single request may walk before giving up.
  ///
  /// Ten pages of at most 500 is five thousand items, which covers a jump to
  /// the far end of a normal library. Beyond that the answer is short rather
  /// than late.
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
  /// Three keys, both directions. This is a fixed list and not a server call,
  /// because the protocol has no sort-listing endpoint: the enum on
  /// `/libraries/{id}/items` is the whole truth and it is frozen in v1.
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
  ];

  Future<LibraryPage<MediaItem>> fetchLibraryContent(String libraryId, LibraryQuery query) =>
      fetchLibraryPagedContent(libraryId, query: query);

  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    if (!wireCapabilities.browse) return const LibraryPage(items: [], totalCount: 0);
    final sort = _sortFor(query.sort);
    return _walkPage(
      path: '/libraries/${Uri.encodeComponent(libraryId)}/items',
      ledgerKey: PleyaServerCursorLedger.key(scope: 'library:$libraryId', sort: sort),
      offset: query.offset,
      limit: query.limit,
      extraQuery: {'sort': sort},
      libraryId: libraryId,
      abort: abort,
    );
  }

  /// The contract's sort spelling for a neutral [LibrarySort].
  ///
  /// A field the protocol does not carry falls back to title rather than being
  /// passed through. The server would answer 400 on an unknown value, and a
  /// library that renders in the wrong order beats one that renders an error.
  String _sortFor(LibrarySort? sort) {
    final descending = sort?.direction == LibrarySortDirection.descending;
    final key = switch (sort?.field) {
      'addedAt' || 'added_at' => PleyaSortKey.addedAt,
      'year' || 'productionYear' || 'originallyAvailableAt' => PleyaSortKey.year,
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
  }) async {
    if (!wireCapabilities.browse) return const LibraryPage(items: [], totalCount: 0);
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

  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async =>
      (await _hubPage(PleyaHubId.continueWatching, limit: count ?? 20)).items;

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
    return _walkPage(
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
      PleyaHubId.recentlyAdded => ('$key.recent', t.discover.recentlyAdded, 'mixed'),
      PleyaHubId.continueWatching => ('$key.continue', t.discover.continueWatching, 'mixed'),
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
    Map<String, String> extraQuery = const {},
    String? libraryId,
    String? parentId,
    AbortController? abort,
  }) async {
    final pageSize = limit <= 0 ? 100 : (limit > _maxPageSize ? _maxPageSize : limit);
    var position = offset <= 0 ? 0 : _cursors.nearestKnownOffset(ledgerKey, offset);
    var cursor = position == 0 ? null : _cursors.cursorFor(ledgerKey, position);
    final collected = <PleyaItem>[];
    var walked = 0;

    while (true) {
      final json = await _getJson(
        path,
        queryParameters: {'limit': '$pageSize', ...extraQuery, 'cursor': ?cursor},
        abort: abort,
      );
      if (json == null) break;
      final PleyaItemPage page;
      try {
        page = PleyaItemPage.fromJson(json);
      } on PleyaWireFormatException catch (e) {
        appLogger.w('PleyaServerClient: $path did not match the contract', error: e);
        break;
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
      if (++walked >= _maxCursorWalk) {
        appLogger.d('PleyaServerClient: stopped walking $path after $_maxCursorWalk pages');
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
