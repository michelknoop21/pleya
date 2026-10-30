import 'dart:convert';

import 'package:http/http.dart' as http;

/// One collection or playlist in [FakeLists].
class FakeList {
  FakeList({
    required this.id,
    required this.title,
    this.isOwner = true,
    this.visibility = 'private',
    List<String>? itemIds,
  }) : itemIds = itemIds ?? [];

  final String id;
  String title;
  bool isOwner;
  String visibility;
  final List<String> itemIds;
}

/// Chapter 14b as far as the app's client needs it: the eighteen routes, the
/// rights a single requester can meet (`403 library.list_not_owner` on a
/// collection of someone else) and a playlist's refusal of a show. Which rows a
/// viewer may see is the real server's business and is proved there.
class FakeLists {
  FakeLists({required this.itemKind, required this.page, required this.posterOf});

  /// The kind of a catalogue item, null when it does not exist.
  final String? Function(String id) itemKind;

  /// The server's own cursor page over item ids.
  final Map<String, dynamic> Function(List<String> ids, Map<String, String> query) page;

  /// The poster artwork id of an item.
  final String? Function(String id) posterOf;

  final collections = <String, FakeList>{};
  final playlists = <String, FakeList>{};

  /// Every write in order, as `METHOD path`, so a test can tell that nothing
  /// went out.
  final writes = <String>[];

  /// The body of the last write to `/collections`.
  Map<String, dynamic>? lastCollectionBody;

  var _nextId = 1;

  void clear() {
    collections.clear();
    playlists.clear();
    writes.clear();
    lastCollectionBody = null;
    _nextId = 1;
  }

  static const _timestamp = '2026-10-30T12:00:00Z';

  http.Response? handle(http.Request request, String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty || parts.first != 'collections' && parts.first != 'playlists') return null;
    final isCollection = parts.first == 'collections';
    final lists = isCollection ? collections : playlists;
    final method = request.method;
    if (method != 'GET') writes.add('$method $path');

    if (parts.length == 1) {
      if (method == 'GET') return _pageOf(lists, request.url.queryParameters, isCollection);
      if (method == 'POST') return _create(request, lists, isCollection);
      return null;
    }
    final list = lists[Uri.decodeComponent(parts[1])];
    if (list == null) return _error('library.not_found', 404);
    if (parts.length == 2) {
      if (method == 'GET') return _json(_wire(list, isCollection));
      if (!list.isOwner) return _error('library.list_not_owner', 403);
      if (method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (isCollection) lastCollectionBody = body;
        list.title = body['title'] as String? ?? list.title;
        list.visibility = body['visibility'] as String? ?? list.visibility;
        return _json(_wire(list, isCollection));
      }
      if (method == 'DELETE') {
        lists.remove(list.id);
        return http.Response('', 204);
      }
      return null;
    }
    if (parts[2] != 'items') return null;
    if (method == 'GET') return _json(page(list.itemIds, request.url.queryParameters));
    if (!list.isOwner) return _error('library.list_not_owner', 403);
    if (parts.length == 4) {
      final id = Uri.decodeComponent(parts[3]);
      if (itemKind(id) == null) return _error('library.not_found', 404);
      list.itemIds.remove(id);
      return http.Response('', 204);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final ids = (body['item_ids'] as List).cast<String>();
    if (ids.toSet().length != ids.length) return _error('library.list_invalid', 400);
    for (final id in ids) {
      final kind = itemKind(id);
      if (kind == null) return _error('library.not_found', 404);
      if (!isCollection && (kind == 'show' || kind == 'season')) return _error('library.list_invalid', 400);
    }
    if (method == 'PUT') {
      list.itemIds
        ..clear()
        ..addAll(ids);
    } else {
      list.itemIds.addAll(ids.where((id) => !list.itemIds.contains(id)));
    }
    return http.Response('', 204);
  }

  http.Response _create(http.Request request, Map<String, FakeList> lists, bool isCollection) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (isCollection) lastCollectionBody = body;
    final id = '${isCollection ? 'collection' : 'playlist'}-${_nextId++}';
    final list = FakeList(
      id: id,
      title: body['title'] as String,
      visibility: body['visibility'] as String? ?? 'private',
    );
    lists[id] = list;
    return _json(_wire(list, isCollection), status: 201);
  }

  http.Response _pageOf(Map<String, FakeList> lists, Map<String, String> query, bool isCollection) {
    final rows = lists.values.toList()..sort((a, b) => a.title.compareTo(b.title));
    final limit = int.tryParse(query['limit'] ?? '') ?? 100;
    final start = query['cursor'] == null ? 0 : int.parse(query['cursor']!);
    final window = rows.skip(start).take(limit).toList();
    final next = start + window.length;
    return _json({
      'items': [for (final list in window) _wire(list, isCollection)],
      'next_cursor': next < rows.length ? '$next' : null,
      'total_estimate': rows.length,
    });
  }

  Map<String, dynamic> _wire(FakeList list, bool isCollection) => {
    'id': list.id,
    'title': list.title,
    if (isCollection) ...{
      'owner': {'id': list.isOwner ? 'user-owner' : 'user-other', 'username': list.isOwner ? 'michel' : 'sanne'},
      'is_owner': list.isOwner,
      'visibility': list.visibility,
    } else
      'duration_ms': 0,
    'item_count': list.itemIds.length,
    'artwork': list.itemIds.map(posterOf).whereType<String>().take(4).toList(),
    'created_at': _timestamp,
    'updated_at': _timestamp,
  };

  http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

  http.Response _error(String code, int status) => _json({
    'error': {'code': code, 'message': code, 'retryable': false},
  }, status: status);
}
