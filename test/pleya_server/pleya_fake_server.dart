import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/pleya_server_client.dart';

/// A Pleya Server in a MockClient, good enough to browse.
///
/// Answers the real paths with real contract shapes, including cursors, so the
/// client's paging walk is exercised rather than mocked around. Everything it
/// serves is built from the same field names the fixtures use, which is what
/// keeps it from drifting into a shape the server would never send.
class PleyaFakeServer {
  PleyaFakeServer({
    this.watchState = false,
    this.setupRequired = false,
    this.pageSizeCap = 100,
    this.artworkBytes = const [0x89, 0x50, 0x4e, 0x47],
  });

  /// Whether `/info` advertises watch state. Controls whether the client asks
  /// for the two playback hubs at all.
  final bool watchState;

  final bool setupRequired;

  /// The largest page this server will hand back regardless of `limit`, so a
  /// test can force the client to walk more than one page.
  final int pageSizeCap;

  final List<int> artworkBytes;

  /// Every path the client asked for, in order. The assertions about "did it
  /// ask twice" read this.
  final List<String> requests = [];

  final Map<String, Map<String, dynamic>> items = {};
  final List<Map<String, dynamic>> libraries = [];

  /// library id -> ordered item ids.
  final Map<String, List<String>> libraryItems = {};

  /// parent id -> ordered child ids.
  final Map<String, List<String>> children = {};

  /// hub id -> ordered item ids.
  final Map<String, List<String>> hubs = {'recently_added': [], 'continue_watching': [], 'next_up': []};

  /// query -> ordered result ids.
  final Map<String, List<String>> searchResults = {};

  int refreshCount = 0;

  /// Reject every access token from here on, the way a server that restarted
  /// and lost its signing key does. The next refresh mints one that works
  /// again.
  bool rejectCurrentAccessTokens = false;

  /// Answer every request with a transport failure, the way an unplugged NAS
  /// does. Distinct from a 401: offline is not signed out.
  bool unreachable = false;

  void addLibrary({required String id, required String title, required String kind, int? itemCount}) {
    libraries.add({'id': id, 'title': title, 'kind': kind, 'item_count': itemCount ?? 0});
    libraryItems.putIfAbsent(id, () => []);
  }

  Map<String, dynamic> addItem({
    required String id,
    required String kind,
    required String title,
    String? libraryId,
    String? parentId,
    int? index,
    int? year,
    int? durationMs,
    int? childCount,
    int? episodeCount,
    int? watchedEpisodeCount,
    String? posterId,
    String? edition,
    Map<String, dynamic>? userState,
    String addedAt = '2026-06-18T21:34:02Z',
  }) {
    final item = <String, dynamic>{
      'id': id,
      'kind': kind,
      'title': title,
      'sort_title': title,
      'year': year,
      'added_at': addedAt,
      'duration_ms': durationMs,
      'parent_id': parentId,
      'index': index,
      'child_count': childCount,
      'episode_count': episodeCount,
      'watched_episode_count': watchedEpisodeCount,
      'artwork': {'poster_id': posterId, 'backdrop_id': null},
      'versions': durationMs == null
          ? <Map<String, dynamic>>[]
          : [
              {
                'id': '$id-v1',
                'container': 'mkv',
                'duration_ms': durationMs,
                'file_count': 1,
                'edition': edition,
                'video_streams': const [],
                'audio_streams': const [],
                'subtitle_streams': const [],
              },
            ],
      'user_state': userState,
    };
    items[id] = item;
    if (libraryId != null) libraryItems.putIfAbsent(libraryId, () => []).add(id);
    if (parentId != null) children.putIfAbsent(parentId, () => []).add(id);
    return item;
  }

  PleyaServerConnection connection({String refreshToken = 'rt-1'}) => PleyaServerConnection(
    id: 'pleyaServer.srv-1',
    baseUrl: 'http://nas.lan:8832',
    serverId: 'srv-1',
    serverName: 'Zolder',
    userName: 'michel',
    refreshToken: refreshToken,
    createdAt: DateTime.utc(2026, 8, 19),
  );

  PleyaServerClient client() => PleyaServerClient.create(connection(), httpClientFactory: () => MockClient(_handle));

  http.Client asHttpClient() => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    if (unreachable) throw const PleyaFakeServerUnreachable();
    final path = request.url.path.replaceFirst('/pleya/v1', '');
    final query = request.url.queryParameters;
    requests.add(request.url.path + (query.isEmpty ? '' : '?${request.url.query}'));

    if (path == '/info') return _json(_info());
    if (path == '/auth/refresh') {
      refreshCount++;
      return _json({
        'access_token': 'at-$refreshCount',
        'refresh_token': 'rt-${refreshCount + 1}',
        'token_type': 'bearer',
        'expires_in_ms': 900000,
      });
    }
    final expected = rejectCurrentAccessTokens ? null : 'Bearer at-$refreshCount';
    if (expected == null || request.headers['Authorization'] != expected) {
      return _json(_error('auth.invalid_token'), status: 401);
    }
    if (path == '/server') {
      return _json(const {'id': 'srv-1', 'name': 'Zolder', 'version': '0.2.0', 'started_at': '2026-08-18T19:25:33Z'});
    }
    if (path == '/libraries') return _json({'items': libraries});
    if (path.startsWith('/artwork/')) {
      return http.Response.bytes(artworkBytes, 200, headers: const {'content-type': 'image/png'});
    }

    final libraryMatch = RegExp(r'^/libraries/([^/]+)/items$').firstMatch(path);
    if (libraryMatch != null) {
      final ids = libraryItems[Uri.decodeComponent(libraryMatch.group(1)!)];
      if (ids == null) return _json(_error('library.not_found'), status: 404);
      return _json(_page(_sorted(ids, query['sort']), query));
    }

    final childrenMatch = RegExp(r'^/items/([^/]+)/children$').firstMatch(path);
    if (childrenMatch != null) {
      final parent = Uri.decodeComponent(childrenMatch.group(1)!);
      if (!items.containsKey(parent)) return _json(_error('library.not_found'), status: 404);
      return _json(_page(children[parent] ?? const [], query));
    }

    final itemMatch = RegExp(r'^/items/([^/]+)$').firstMatch(path);
    if (itemMatch != null) {
      final item = items[Uri.decodeComponent(itemMatch.group(1)!)];
      if (item == null) return _json(_error('library.not_found'), status: 404);
      return _json(item);
    }

    final hubMatch = RegExp(r'^/hubs/([^/]+)$').firstMatch(path);
    if (hubMatch != null) {
      final hub = hubMatch.group(1)!;
      final ids = hubs[hub];
      if (ids == null) return _json(_error('library.not_found'), status: 404);
      final libraryId = query['library_id'];
      final scoped = libraryId == null
          ? ids
          : ids.where((id) => (libraryItems[libraryId] ?? const []).contains(id)).toList();
      return _json(_page(scoped, query));
    }

    if (path == '/search') {
      final q = (query['q'] ?? '').toLowerCase();
      final kind = query['kind'];
      var results = searchResults[q];
      results ??= items.entries
          .where((e) => (e.value['title'] as String).toLowerCase().contains(q))
          // DEC-045: without an explicit kind the server leaves seasons out.
          .where((e) => kind == null ? e.value['kind'] != 'season' : e.value['kind'] == kind)
          .map((e) => e.key)
          .toList();
      return _json(_page(results, query));
    }

    return _json(_error('library.not_found'), status: 404);
  }

  List<String> _sorted(List<String> ids, String? sort) {
    final descending = sort != null && sort.startsWith('-');
    final key = descending ? sort.substring(1) : (sort ?? 'title');
    final sorted = [...ids];
    sorted.sort((a, b) {
      final left = items[a]!;
      final right = items[b]!;
      final result = switch (key) {
        'added_at' => (left['added_at'] as String).compareTo(right['added_at'] as String),
        'year' => ((left['year'] as int?) ?? 0).compareTo((right['year'] as int?) ?? 0),
        _ => (left['sort_title'] as String? ?? left['title'] as String).compareTo(
          right['sort_title'] as String? ?? right['title'] as String,
        ),
      };
      return descending ? -result : result;
    });
    return sorted;
  }

  /// A cursor is the index it opens, encoded. Opaque enough for a test and
  /// still a string the client must not read anything out of.
  Map<String, dynamic> _page(List<String> ids, Map<String, String> query) {
    final requested = int.tryParse(query['limit'] ?? '') ?? 100;
    final limit = requested > pageSizeCap ? pageSizeCap : requested;
    final start = query['cursor'] == null ? 0 : int.parse(utf8.decode(base64Url.decode(query['cursor']!)));
    final window = ids.skip(start).take(limit).toList();
    final next = start + window.length;
    return {
      'items': [for (final id in window) items[id]!],
      'next_cursor': next < ids.length ? base64Url.encode(utf8.encode('$next')) : null,
      'total_estimate': ids.length,
    };
  }

  Map<String, dynamic> _info() => {
    'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
    'server': {'id': 'srv-1'},
    'capabilities': {
      'browse': true,
      'search': true,
      'artwork': true,
      'watch_state': watchState,
      'playback_plan': false,
      'transcode': false,
      'downloads': false,
      'live_tv': false,
      'realtime': false,
      'users': false,
    },
    'auth': {
      'methods': ['password'],
      'setup_required': setupRequired,
    },
  };

  Map<String, dynamic> _error(String code) => {
    'error': {'code': code, 'message': code, 'retryable': false},
  };

  http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});
}

/// A transport failure that is not an HTTP answer. Named rather than borrowing
/// a `dart:io` type so the fake does not depend on the platform's socket
/// errors.
class PleyaFakeServerUnreachable implements Exception {
  const PleyaFakeServerUnreachable();

  @override
  String toString() => 'PleyaFakeServerUnreachable';
}
