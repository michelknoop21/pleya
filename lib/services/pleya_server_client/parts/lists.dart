part of '../../pleya_server_client.dart';

/// Collections and playlists (S19, chapter 14b).
///
/// Two different rights live here. A playlist is personal: every user manages
/// his own, and no role check applies. A collection the app writes is canonical,
/// the server-wide counterpart of a Plex collection or a Jellyfin BoxSet, so
/// every write passes [_assertCurrentCollectionOwner] first and goes out with
/// `everyone` as its visibility. The server is more permissive about the
/// resource itself: it lets any user keep lists of his own, which the web client
/// offers. The app does not.
///
/// Both resources span the server rather than a library, so `libraryId` selects
/// nothing and a row carries no library of its own. Reads gate on the capability
/// and answer empty without it; writes answer false.
mixin _PleyaServerListMethods on _PleyaServerRequests, _PleyaServerBrowseMethods {
  void assertCanManageCollections();

  static const int _listPageSize = 100;

  /// The largest page these routes take, smaller than the catalogue's.
  static const int _maxListPage = 200;

  /// A stable order for a cursor walk: a list that changes while someone
  /// scrolls would move under `-updated_at`.
  static const String _listSort = 'title';

  bool get _canWriteCollections => wireCapabilities.collections && !isOfflineMode;
  bool get _canWritePlaylists => wireCapabilities.playlists && !isOfflineMode;

  String _collectionPath(String id) => '/collections/${Uri.encodeComponent(id)}';
  String _playlistPath(String id) => '/playlists/${Uri.encodeComponent(id)}';

  /// The owner rule against the role the server holds now. The local check
  /// refuses without a round trip, the second one sees a role lost on the
  /// server, and a role that cannot be confirmed refuses as well: a stale
  /// `owner` is exactly what this is here to catch.
  Future<void> _assertCurrentCollectionOwner() async {
    assertCanManageCollections();
    if (!await _refreshRole()) {
      throw const MediaServerAuthException('The server role could not be confirmed', statusCode: 403);
    }
    assertCanManageCollections();
  }

  // ── Reading ──

  Future<LibraryPage<M>> _walkLists<W, M>({
    required String path,
    required W Function(Map<String, dynamic>) parse,
    required M Function(W) map,
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final offset = start ?? 0;
    final limit = size == null || size <= 0 ? _listPageSize : size;
    final ledgerKey = PleyaServerCursorLedger.key(scope: path, sort: _listSort);
    if (offset == 0) _cursors.invalidate(ledgerKey);
    var position = offset == 0 ? 0 : _cursors.nearestKnownOffset(ledgerKey, offset);
    var cursor = position == 0 ? null : _cursors.cursorFor(ledgerKey, position);
    var restarted = false;
    final window = <W>[];
    while (true) {
      final answer = await _getJsonDetailed(
        path,
        queryParameters: {
          'limit': '${limit > _maxListPage ? _maxListPage : limit}',
          'sort': _listSort,
          'cursor': ?cursor,
        },
        abort: abort,
      );
      if (answer.errorCode == 'library.cursor_invalid' && cursor != null && !restarted) {
        restarted = true;
        _cursors.invalidate(ledgerKey);
        position = 0;
        cursor = null;
        window.clear();
        continue;
      }
      final json = answer.json;
      if (json == null) throw StateError('$path page was not received');
      final page = PleyaListPage.fromJson(json, parse);
      _cursors.recordPage(
        ledgerKey,
        offset: position,
        count: page.items.length,
        nextCursor: page.nextCursor,
        totalEstimate: page.totalEstimate,
      );
      final skip = offset > position ? offset - position : 0;
      window.addAll(page.items.skip(skip));
      position += page.items.length;
      if (window.length >= limit || page.nextCursor == null || page.items.isEmpty) {
        return LibraryPage(
          items: [for (final row in window.take(limit)) map(row)],
          totalCount: page.nextCursor == null ? position : _cursors.totalEstimate(ledgerKey) ?? position + 1,
          offset: offset,
        );
      }
      cursor = page.nextCursor;
    }
  }

  Future<LibraryPage<MediaItem>> _listItemsPage(String path, {int? start, int? size, AbortController? abort}) {
    final offset = start ?? 0;
    final ledgerKey = PleyaServerCursorLedger.key(scope: path, sort: 'position');
    if (offset == 0) _cursors.invalidate(ledgerKey);
    return _walkPage(path: path, ledgerKey: ledgerKey, offset: offset, limit: size ?? _listPageSize, abort: abort);
  }

  Future<List<MediaPlaylist>> fetchPlaylists({String playlistType = 'video', bool? smart}) async {
    final all = <MediaPlaylist>[];
    while (true) {
      final page = await fetchPlaylistsPage(
        playlistType: playlistType,
        smart: smart,
        start: all.length,
        size: _listPageSize,
      );
      all.addAll(page.items);
      if (page.items.isEmpty || all.length >= page.totalCount) return all;
    }
  }

  /// Pleya Server playlists are manual lists of video, so a request for smart
  /// or audio playlists has an empty answer.
  Future<LibraryPage<MediaPlaylist>> fetchPlaylistsPage({
    String playlistType = 'video',
    bool? smart,
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    if (!wireCapabilities.playlists || isOfflineMode || playlistType != 'video' || smart == true) {
      return const LibraryPage(items: [], totalCount: 0);
    }
    return _walkLists(
      path: '/playlists',
      parse: PleyaPlaylist.fromJson,
      map: _mapPlaylist,
      start: start,
      size: size,
      abort: abort,
    );
  }

  MediaPlaylist _mapPlaylist(PleyaPlaylist wire) =>
      PleyaServerMappers.playlist(wire, serverId: serverId.toString(), serverName: serverName);

  Future<MediaPlaylist?> fetchPlaylistMetadata(String id) async {
    if (!wireCapabilities.playlists) return null;
    final json = await _getJson(_playlistPath(id));
    return json == null ? null : _mapPlaylist(PleyaPlaylist.fromJson(json));
  }

  Future<List<MediaItem>> fetchPlaylistItems(String id, {int offset = 0, int limit = 100}) async =>
      (await fetchPlaylistPage(id, start: offset, size: limit)).items;

  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, AbortController? abort}) async {
    if (!wireCapabilities.playlists) return const LibraryPage(items: [], totalCount: 0);
    return _listItemsPage('${_playlistPath(id)}/items', start: start, size: size, abort: abort);
  }

  Future<List<MediaItem>> fetchCollections(String libraryId) async {
    final all = <MediaItem>[];
    while (true) {
      final page = await fetchCollectionsPage(libraryId, start: all.length, size: _listPageSize);
      all.addAll(page.items);
      if (page.items.isEmpty || all.length >= page.totalCount) return all;
    }
  }

  Future<LibraryPage<MediaItem>> fetchCollectionsPage(
    String libraryId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    if (!wireCapabilities.collections || isOfflineMode) return const LibraryPage(items: [], totalCount: 0);
    return _walkLists(
      path: '/collections',
      parse: PleyaCollection.fromJson,
      map: (wire) => PleyaServerMappers.collection(
        wire,
        serverId: serverId.toString(),
        serverName: serverName,
        libraryId: libraryId.isEmpty ? null : libraryId,
      ),
      start: start,
      size: size,
      abort: abort,
    );
  }

  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    String? libraryId,
    String? libraryTitle,
    AbortController? abort,
  }) async {
    if (!wireCapabilities.collections) return const LibraryPage(items: [], totalCount: 0);
    return _listItemsPage('${_collectionPath(collectionId)}/items', start: start, size: size, abort: abort);
  }

  // ── Playlists: personal, no role check ──

  Future<MediaPlaylist?> createPlaylist({required String title, required List<MediaItem> items}) async {
    if (!_canWritePlaylists) return null;
    final json = await _adminSend('POST', '/playlists', body: PleyaPlaylistTitleRequest(title: title).toJson());
    if (json == null) return null;
    final created = PleyaPlaylist.fromJson(json);
    if (items.isEmpty) return _mapPlaylist(created);
    final path = _playlistPath(created.id);
    await _seed(path, await _playableIds(items));
    return await fetchPlaylistMetadata(created.id) ?? _mapPlaylist(created);
  }

  Future<bool> addToPlaylist({required String playlistId, required List<MediaItem> items}) async {
    if (!_canWritePlaylists) return false;
    final ids = await _playableIds(items);
    if (ids.isNotEmpty) await _append(_playlistPath(playlistId), ids);
    return true;
  }

  Future<bool> deletePlaylist(MediaPlaylist playlist) async {
    if (!_canWritePlaylists) return false;
    await _adminSend('DELETE', _playlistPath(playlist.id));
    return true;
  }

  /// The protocol reorders by replacing the list, which is one transaction on
  /// the server. Rows of a kind this build does not know stay in the request,
  /// or the replace would drop them. [afterItem] places the row against its
  /// neighbour, so a list that moved since it was loaded keeps the intent;
  /// [newIndex] is the fallback when that neighbour is gone.
  Future<bool> movePlaylistItem({
    required String playlistId,
    required MediaItem item,
    required int newIndex,
    required MediaItem? afterItem,
  }) async {
    if (!_canWritePlaylists) return false;
    final path = '${_playlistPath(playlistId)}/items';
    final ids = await _allItemIds(path);
    if (!ids.remove(item.id)) return false;
    final anchor = afterItem == null ? -1 : ids.indexOf(afterItem.id);
    final target = afterItem == null
        ? 0
        : anchor >= 0
        ? anchor + 1
        : newIndex.clamp(0, ids.length);
    ids.insert(target, item.id);
    await _adminSend('PUT', path, body: PleyaListItemsRequest(itemIds: ids).toJson());
    return true;
  }

  Future<bool> removeFromPlaylist({required String playlistId, required MediaItem item}) async {
    if (!_canWritePlaylists) return false;
    await _adminSend('DELETE', '${_playlistPath(playlistId)}/items/${Uri.encodeComponent(item.id)}');
    return true;
  }

  // ── Collections: canonical, the owner's alone ──

  Future<String?> createCollection({
    required String libraryId,
    required String title,
    required List<MediaItem> items,
    MediaKind? itemKind,
  }) async {
    if (!_canWriteCollections) return null;
    await _assertCurrentCollectionOwner();
    final json = await _adminSend(
      'POST',
      '/collections',
      body: PleyaCreateCollectionRequest(title: title, visibility: PleyaCollectionVisibility.everyone).toJson(),
    );
    if (json == null) return null;
    final created = PleyaCollection.fromJson(json);
    await _seed(_collectionPath(created.id), [for (final item in items) item.id]);
    return created.id;
  }

  Future<bool> addToCollection({required String collectionId, required List<MediaItem> items}) async {
    if (!_canWriteCollections) return false;
    await _assertCurrentCollectionOwner();
    if (items.isNotEmpty) await _append(_collectionPath(collectionId), [for (final item in items) item.id]);
    return true;
  }

  Future<bool> removeFromCollection({required String collectionId, required MediaItem item}) async {
    if (!_canWriteCollections) return false;
    await _assertCurrentCollectionOwner();
    await _adminSend('DELETE', '${_collectionPath(collectionId)}/items/${Uri.encodeComponent(item.id)}');
    return true;
  }

  Future<bool> deleteCollection(MediaItem collection) async {
    if (!_canWriteCollections) return false;
    await _assertCurrentCollectionOwner();
    await _adminSend('DELETE', _collectionPath(collection.id));
    return true;
  }

  // ── Shared write steps ──

  Future<void> _append(String listPath, List<String> ids) =>
      _adminSend('POST', '$listPath/items', body: PleyaListItemsRequest(itemIds: ids).toJson());

  /// Fill a list that was created a moment ago. Creating and filling are two
  /// requests, and a list left behind empty after the second failed would look
  /// like a success, so it is taken away again. The caller sees the failure.
  Future<void> _seed(String listPath, List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _append(listPath, ids);
    } catch (_) {
      try {
        await _adminSend('DELETE', listPath);
      } catch (e) {
        appLogger.d('PleyaServerClient: could not clear away $listPath', error: e);
      }
      rethrow;
    }
  }

  /// A playlist takes films and episodes; the contract leaves it to the client
  /// to put a show's episodes in. Order is kept, and an episode reached twice
  /// goes in once because the server refuses a duplicate id.
  Future<List<String>> _playableIds(List<MediaItem> items) async {
    final ids = <String>{};
    for (final item in items) {
      if (item.kind != MediaKind.show && item.kind != MediaKind.season) {
        ids.add(item.id);
        continue;
      }
      var start = 0;
      while (true) {
        final page = await fetchPlayableDescendantsPage(item.id, start: start, size: _maxListPage);
        ids.addAll(page.items.map((leaf) => leaf.id));
        start += page.items.length;
        if (page.items.isEmpty || start >= page.totalCount) break;
      }
    }
    return ids.toList();
  }

  /// Every id in a list as the requester sees it. A page that does not arrive
  /// throws: replacing a list from half a read would delete the other half.
  Future<List<String>> _allItemIds(String path) async {
    final ids = <String>[];
    String? cursor;
    while (true) {
      final answer = await _getJsonDetailed(path, queryParameters: {'limit': '$_maxListPage', 'cursor': ?cursor});
      final json = answer.json;
      if (json == null) throw StateError('$path page was not received');
      final page = PleyaItemPage.fromJson(json);
      ids.addAll(page.items.map((item) => item.id));
      cursor = page.nextCursor;
      if (cursor == null) return ids;
    }
  }
}
