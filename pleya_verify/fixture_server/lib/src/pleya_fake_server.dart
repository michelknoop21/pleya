import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixture_clock.dart';
import 'fixtures/sample_media.dart';

/// A Pleya Server routing kernel, good enough to browse.
///
/// Answers the real paths with real contract shapes, including cursors, so a
/// client's paging walk is exercised rather than mocked around. Everything it
/// serves is built from the same field names the fixtures use, which is what
/// keeps it from drifting into a shape the server would never send.
///
/// Pure — operates only on `package:http` types and plain Dart collections,
/// no app-specific dependency. Two adapters sit on top of [handle]:
/// `test/pleya_server/pleya_fake_server.dart` (an `http.MockClient`, for the
/// app's own unit tests) and `pleya_verify/fixture_server/bin/serve.dart` (a
/// real `dart:io` HTTP server, for Pleya Verify scenarios).
class PleyaFakeServer {
  PleyaFakeServer({
    this.watchState = false,
    this.watchStateOwnership = false,
    this.setupRequired = false,
    this.pageSizeCap = 100,
    this.artworkBytes = const [0x89, 0x50, 0x4e, 0x47],
    this.setupCode = 'VERIFY-SETUP-CODE',
    FixtureClock? clock,
  }) : clock = clock ?? FixtureClock(),
       _initialSetupRequired = setupRequired;

  /// Whether `/info` advertises the ownership model. Off by default, so a test
  /// that does not opt in proves what an older server sees: no base_revision,
  /// no cause, no backlog marker on the wire.
  final bool watchStateOwnership;

  /// Every watch-state event this server received, in order and as sent.
  final List<Map<String, dynamic>> watchEvents = [];

  /// Canonical state per item, the way the server keeps it. Deliberately thin:
  /// the six rules are tested against the real Go implementation, and repeating
  /// them here would test the fake.
  final Map<String, Map<String, dynamic>> watchStates = {};

  /// The next `POST /watch-state` answers with this owner verdict.
  bool ownedByThisSession = true;

  /// Whether `/info` advertises watch state. Controls whether the client asks
  /// for the two playback hubs at all.
  final bool watchState;

  /// Flips to `false` the moment `/auth/setup` succeeds — a fresh server
  /// only offers setup once. `/info` always reports the current value.
  bool setupRequired;

  /// [setupRequired]'s constructor value — [reset] restores it, the same way
  /// [FixtureClock.resetToStart] restores the clock.
  final bool _initialSetupRequired;

  /// The one-time code `/auth/setup` checks against. A real server prints
  /// this to its console on first boot; a scenario driver reads it straight
  /// off this field (or `/__verify/state`) instead.
  final String setupCode;

  /// username -> password, registered by a successful `/auth/setup` and
  /// checked by `/auth/login`. Empty on a fresh server with setup required.
  final Map<String, String> _credentials = {};

  final FixtureClock clock;

  /// The largest page this server will hand back regardless of `limit`, so a
  /// test can force the client to walk more than one page.
  final int pageSizeCap;

  final List<int> artworkBytes;

  /// Per-item artwork override, keyed by the id `GET /artwork/{id}` was
  /// asked for. Falls back to [artworkBytes] when an id has none registered
  /// — the named `catalog.*` fixtures populate this; ad hoc `addItem` calls
  /// (most existing tests) don't need to and keep seeing the shared bytes.
  final Map<String, List<int>> artworkById = {};

  /// version id -> playable bytes, auto-populated by [addItem] for every
  /// version it creates. `GET /stream/{version_id}` serves from here.
  final Map<String, List<int>> versionBytes = {};

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

  /// How `/auth/refresh` should answer, for the failures that are not a
  /// rejection but used to be treated as one.
  PleyaFakeRefreshOutcome refreshOutcome = PleyaFakeRefreshOutcome.rotate;

  /// One-shot: consumed by the next request whose path starts with
  /// [_QueuedFailure.pathPrefix] (or any request, when null). Set by
  /// `POST /__verify/fail_next`.
  _QueuedFailure? _queuedFailure;

  /// Extra latency injected before the next [_queuedLatencyCount] responses
  /// (any path). Set by `POST /__verify/latency`.
  Duration _queuedLatency = Duration.zero;
  int _queuedLatencyCount = 0;

  /// Queues a one-shot failure for the next request matching [pathPrefix]
  /// (any request when null). `/__verify/fail_next`'s implementation.
  void queueFailure({String? pathPrefix, required int status, String errorCode = 'storage.unavailable'}) {
    _queuedFailure = _QueuedFailure(pathPrefix: pathPrefix, status: status, errorCode: errorCode);
  }

  /// Queues [latency] before each of the next [count] responses (any path).
  /// `/__verify/latency`'s implementation.
  void queueLatency(Duration latency, {int count = 1}) {
    _queuedLatency = latency;
    _queuedLatencyCount = count;
  }

  /// Clears every mutable field back to a fresh instance's state. Used by
  /// the `/__verify/reset` control-plane route between scenario runs.
  void reset() {
    watchEvents.clear();
    watchStates.clear();
    ownedByThisSession = true;
    requests.clear();
    items.clear();
    libraries.clear();
    libraryItems.clear();
    children.clear();
    hubs.updateAll((_, __) => []);
    searchResults.clear();
    refreshCount = 0;
    rejectCurrentAccessTokens = false;
    unreachable = false;
    refreshOutcome = PleyaFakeRefreshOutcome.rotate;
    setupRequired = _initialSetupRequired;
    _credentials.clear();
    artworkById.clear();
    versionBytes.clear();
    clock.resetToStart();
    _queuedFailure = null;
    _queuedLatency = Duration.zero;
    _queuedLatencyCount = 0;
  }

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
    if (durationMs != null) versionBytes['$id-v1'] = sampleMediaMp4Bytes;
    return item;
  }

  /// Appends a new episode under [parentId] (a season or show acting as an
  /// episode-list parent) and keeps its `child_count`/`episode_count` in
  /// sync — `POST /__verify/add_episode`'s implementation, the mutation
  /// `media-detail.episode-refresh` ([C4] in the Pleya Verify plan) needs.
  /// Returns the new item's id, or `null` when [parentId] is unknown (the
  /// control plane turns that into 404).
  String? addEpisode({required String parentId, String? title, int? durationMs}) {
    final parent = items[parentId];
    if (parent == null) return null;
    final nextIndex = (children[parentId]?.length ?? 0) + 1;
    final id = '$parentId/added-$nextIndex-${clock.now.millisecondsSinceEpoch}';
    addItem(
      id: id,
      kind: 'episode',
      title: title ?? 'Episode $nextIndex',
      parentId: parentId,
      index: nextIndex,
      durationMs: durationMs ?? 1500000,
      addedAt: clock.now.toIso8601String(),
      posterId: id,
    );
    artworkById[id] = artworkById[parentId] ?? artworkBytes;
    if (parent['child_count'] is int) parent['child_count'] = (parent['child_count'] as int) + 1;
    if (parent['episode_count'] is int) parent['episode_count'] = (parent['episode_count'] as int) + 1;
    return id;
  }

  /// Sets [itemId]'s watch state to fully watched, the way a client's own
  /// `POST /watch-state` would after a completed play-through — without a
  /// scenario needing to script that whole flow just to get there.
  /// `POST /__verify/mark_watched`'s implementation.
  void markWatched(String itemId) {
    final previous = watchStates[itemId];
    final revision = ((previous?['revision'] as int?) ?? 0) + 1;
    watchStates[itemId] = {
      'position_ms': items[itemId]?['duration_ms'] ?? 0,
      'watched': true,
      'play_count': ((previous?['play_count'] as int?) ?? 0) + 1,
      'updated_at': clock.now.toIso8601String(),
      if (watchStateOwnership) 'revision': revision,
      if (watchStateOwnership) 'owned_by_this_session': ownedByThisSession,
    };
  }

  http.Client asHttpClient() => MockClient(handle);

  Future<http.Response> handle(http.Request request) async {
    if (unreachable) throw const PleyaFakeServerUnreachable();
    final path = request.url.path.replaceFirst('/pleya/v1', '');
    final query = request.url.queryParameters;
    requests.add(request.url.path + (query.isEmpty ? '' : '?${request.url.query}'));

    if (_queuedLatencyCount > 0) {
      _queuedLatencyCount--;
      await Future<void>.delayed(_queuedLatency);
    }
    final failure = _queuedFailure;
    if (failure != null && (failure.pathPrefix == null || path.startsWith(failure.pathPrefix!))) {
      _queuedFailure = null;
      return _json(_error(failure.errorCode), status: failure.status);
    }

    if (path == '/info') return _json(_info());
    if (path == '/auth/login') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final username = body['username'] as String?;
      final password = body['password'] as String?;
      if (username == null || _credentials[username] != password) {
        return _json(_error('auth.invalid_credentials'), status: 401);
      }
      return _json(_mintTokenPair());
    }
    if (path == '/auth/setup') {
      if (!setupRequired) {
        return _json(const {
          'error': {'code': 'auth.setup_already_done', 'message': 'owner exists', 'retryable': false},
        }, status: 409);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['setup_code'] != setupCode) {
        return _json(_error('auth.invalid_setup_code'), status: 401);
      }
      final username = body['username'] as String;
      final password = body['password'] as String;
      _credentials[username] = password;
      setupRequired = false;
      return _json(_mintTokenPair());
    }
    if (path == '/auth/refresh') {
      switch (refreshOutcome) {
        case PleyaFakeRefreshOutcome.rotate:
          break;
        case PleyaFakeRefreshOutcome.rateLimited:
          return _json(const {
            'error': {
              'code': 'auth.rate_limited',
              'message': 'slow down',
              'retryable': true,
              'details': {'retry_after_ms': 5000},
            },
          }, status: 429);
        case PleyaFakeRefreshOutcome.serverError:
          return _json(const {
            'error': {'code': 'storage.unavailable', 'message': 'database down', 'retryable': true},
          }, status: 503);
        case PleyaFakeRefreshOutcome.notTheContract:
          // A proxy or captive portal answering 200 with something that is not
          // the envelope. Used to be indistinguishable from a dead session.
          return http.Response('<html>sign in to the wifi</html>', 200);
        case PleyaFakeRefreshOutcome.bareUnauthorized:
          // A 401 with no protocol envelope: a gateway in front of the server,
          // not Pleya speaking.
          return http.Response('<html>401</html>', 401);
        case PleyaFakeRefreshOutcome.rejected:
          return _json(const {
            'error': {'code': 'auth.invalid_token', 'message': 'no', 'retryable': false},
          }, status: 401);
        case PleyaFakeRefreshOutcome.reused:
          return _json(const {
            'error': {'code': 'auth.refresh_token_reused', 'message': 'seen before', 'retryable': false},
          }, status: 401);
      }
      return _json(_mintTokenPair());
    }
    final expected = rejectCurrentAccessTokens ? null : 'Bearer at-$refreshCount';
    if (expected == null || request.headers['Authorization'] != expected) {
      return _json(_error('auth.invalid_token'), status: 401);
    }
    if (path == '/server') {
      return _json(const {'id': 'srv-1', 'name': 'Zolder', 'version': '0.2.0', 'started_at': '2026-08-18T19:25:33Z'});
    }
    if (path == '/libraries') return _json({'items': libraries});

    if (path == '/auth/stream-token') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({'stream_token': 'st-for-${body['version_id']}', 'expires_at': '2026-08-21T21:09:11Z'});
    }

    if (path == '/watch-state' && request.method == 'POST') {
      final event = jsonDecode(request.body) as Map<String, dynamic>;
      watchEvents.add(event);
      final itemId = event['item_id'] as String;
      final previous = watchStates[itemId];
      final revision = ((previous?['revision'] as int?) ?? 0) + 1;
      final state = {
        'position_ms': event['position_ms'],
        'watched': event['completed'] == true || event['explicit_action'] == 'mark_watched',
        'play_count': (previous?['play_count'] as int?) ?? 0,
        'updated_at': '2026-08-21T20:00:00Z',
        if (watchStateOwnership) 'revision': revision,
        if (watchStateOwnership) 'owned_by_this_session': ownedByThisSession,
      };
      watchStates[itemId] = state;
      return _json(state);
    }

    if (path == '/watch-state') {
      return _json({
        'items': [
          for (final entry in watchStates.entries) {'item_id': entry.key, 'state': entry.value},
        ],
        'next_cursor': null,
      });
    }
    if (path.startsWith('/artwork/')) {
      final id = Uri.decodeComponent(path.substring('/artwork/'.length));
      return http.Response.bytes(artworkById[id] ?? artworkBytes, 200, headers: const {'content-type': 'image/png'});
    }

    final streamMatch = RegExp(r'^/stream/([^/]+)$').firstMatch(path);
    if (streamMatch != null) {
      final versionId = Uri.decodeComponent(streamMatch.group(1)!);
      final bytes = versionBytes[versionId];
      if (bytes == null) return _json(_error('library.not_found'), status: 404);
      return _streamResponse(request, bytes);
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
      'watch_state_ownership': watchStateOwnership,
      'stream_sessions': watchState,
    },
    'auth': {
      'methods': ['password'],
      'setup_required': setupRequired,
    },
  };

  /// Shared by `/auth/refresh`, `/auth/login` and `/auth/setup` — all three
  /// end the same way: mint a fresh pair, bump [refreshCount] (the counter
  /// `at-N`/the authenticated-route check reads).
  Map<String, dynamic> _mintTokenPair() {
    refreshCount++;
    return {
      'access_token': 'at-$refreshCount',
      'refresh_token': 'rt-${refreshCount + 1}',
      'token_type': 'bearer',
      'expires_in_ms': 900000,
    };
  }

  /// `GET /stream/{version_id}`'s response, matching the frozen protocol's
  /// range rules: `If-Range` present -> ignore Range, full 200 (the weak
  /// ETag can never support it); a well-formed single range -> 206; a
  /// well-formed single range starting past the end -> 416; anything else
  /// (absent, malformed, or multi-range Range) -> full 200, the documented
  /// fallback for "a range this server won't parse".
  http.Response _streamResponse(http.Request request, List<int> bytes) {
    final etag = 'W/"${sha256.convert(bytes).toString().substring(0, 16)}"';
    final total = bytes.length;
    final rangeHeader = request.headers['Range'];
    if (rangeHeader != null && request.headers['If-Range'] == null) {
      try {
        final range = _parseSingleByteRange(rangeHeader, total);
        if (range != null) {
          return http.Response.bytes(
            bytes.sublist(range.start, range.end + 1),
            206,
            headers: {
              'accept-ranges': 'bytes',
              'etag': etag,
              'content-range': 'bytes ${range.start}-${range.end}/$total',
              'content-type': 'application/octet-stream',
            },
          );
        }
      } on _RangeNotSatisfiable {
        return http.Response(
          jsonEncode(_error('playback.range_not_satisfiable')),
          416,
          headers: {'content-type': 'application/json', 'content-range': 'bytes */$total'},
        );
      }
    }
    return http.Response.bytes(
      bytes,
      200,
      headers: {'accept-ranges': 'bytes', 'etag': etag, 'content-type': 'application/octet-stream'},
    );
  }

  static final _byteRangePattern = RegExp(r'^bytes=(\d*)-(\d*)$');

  /// `null` for "not a well-formed single range" (absent, malformed, or
  /// `bytes=0-10,20-30`-style multi-range) — the caller's cue to fall back
  /// to a full 200. Throws [_RangeNotSatisfiable] for a well-formed single
  /// range whose start is at or past [total] — the one case that is a 416,
  /// not a fallback.
  ({int start, int end})? _parseSingleByteRange(String header, int total) {
    final match = _byteRangePattern.firstMatch(header.trim());
    if (match == null) return null;
    final startText = match.group(1)!;
    final endText = match.group(2)!;
    if (startText.isEmpty && endText.isEmpty) return null;
    int start;
    int end;
    if (startText.isEmpty) {
      // Suffix range: the last N bytes.
      final suffixLength = int.parse(endText);
      start = (total - suffixLength).clamp(0, total);
      end = total - 1;
    } else {
      start = int.parse(startText);
      end = endText.isEmpty ? total - 1 : int.parse(endText).clamp(0, total - 1);
    }
    if (start >= total) throw const _RangeNotSatisfiable();
    return (start: start, end: end);
  }

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

/// How the fake answers `/auth/refresh`.
///
/// The four in the middle are the ones that matter for classification: none of
/// them proves the session is gone, and all four used to raise "session
/// expired" anyway.
enum PleyaFakeRefreshOutcome {
  /// Normal: mint a new pair and rotate.
  rotate,

  /// 429 with `auth.rate_limited`.
  rateLimited,

  /// 503 from the server itself.
  serverError,

  /// 200 whose body is not the protocol envelope.
  notTheContract,

  /// 401 without a protocol envelope, so not Pleya speaking.
  bareUnauthorized,

  /// 401 with `auth.invalid_token`: Pleya's own verdict.
  rejected,

  /// 401 with `auth.refresh_token_reused`.
  reused,
}

/// A one-shot fault `POST /__verify/fail_next` queues — see
/// [PleyaFakeServer.queueFailure].
class _QueuedFailure {
  const _QueuedFailure({this.pathPrefix, required this.status, required this.errorCode});

  final String? pathPrefix;
  final int status;
  final String errorCode;
}

/// A well-formed single Range request whose start is at or past the
/// content length — the one Range outcome that is a 416, not a fallback
/// to a full 200. See [PleyaFakeServer._parseSingleByteRange].
class _RangeNotSatisfiable implements Exception {
  const _RangeNotSatisfiable();
}
