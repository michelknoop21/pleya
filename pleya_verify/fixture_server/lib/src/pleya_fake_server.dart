import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixture_clock.dart';
import 'memory_fake_store.dart';
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

  /// Whether `/info` advertises `filters` and the library routes honour the
  /// filter parameters and `/libraries/{id}/facets`. Off by default: a server
  /// that predates the capability ignores the parameters, and a test that does
  /// not opt in proves what the client does against one.
  bool filtersCapability = false;

  /// Whether `/info` advertises `playback_plan` and `POST /playback/plan`
  /// answers. [planVersionId] is the version the planner picks when the request
  /// names none, [planDeliveryMode] the mode it reports, and a non-null
  /// [planFailureStatus] makes the route fail with that status. Every request
  /// body lands in [planRequests].
  bool playbackPlanCapability = false;

  /// S20: favorites, ratings and remembered tracks. The fake keeps them per
  /// item id and records each call so a test can read what the app sent.
  bool personalCapability = false;

  /// Household activity (protocol chapter 14b). [itemActivityByItem] holds the
  /// wire entries per item id, [itemActivityRequests] every path that was
  /// asked, also without the flag, and [itemActivityFailureStatus] makes the
  /// route fail with that status.
  bool itemActivityCapability = false;
  final Map<String, List<Map<String, dynamic>>> itemActivityByItem = {};
  final List<String> itemActivityRequests = [];
  int? itemActivityFailureStatus;

  /// BP-08b is opt-in so existing fixtures retain their old-server behavior.
  bool assistantMemoryCapability = false;
  final Map<String, String> _memoryAccessUsers = {};
  final Map<String, String> _memoryRefreshUsers = {};
  final Map<String, String> _memoryRoles = {};
  final Map<String, MemoryFakeStore> _memoryStores = {};

  /// Test-account registration, never a production API or a profile-name link.
  void addMemoryAccount({required String username, required String password, String role = 'member'}) {
    _credentials[username] = password;
    _memoryRoles[username] = role;
  }

  void setMemoryRole(String username, String role) => _memoryRoles[username] = role;

  String _memoryUserId(String username) {
    final hash = sha256.convert(utf8.encode('memory-user/$username')).toString();
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-4${hash.substring(13, 16)}-8${hash.substring(17, 20)}-${hash.substring(20, 32)}';
  }

  /// S23: the server offers downloads. A download reads `preparing` for
  /// [downloadPrepareRounds] polls, then `ready` with [downloadSha256], or
  /// `failed` when [downloadFails] is set. [downloadRequests] records each
  /// `POST /downloads` body.
  bool downloadsCapability = false;
  int downloadPrepareRounds = 0;
  bool downloadFails = false;
  String downloadSha256 = 'a' * 64;
  final List<Map<String, dynamic>> downloadRequests = [];
  final Map<String, int> _downloadPolls = {};
  final Set<String> favoriteIds = {};
  final Map<String, int> ratingsByItem = {};
  final Map<String, Map<String, dynamic>> trackPreferences = {};
  String planVersionId = 'version-1';
  String planDeliveryMode = 'direct_play';
  int? planFailureStatus;
  final List<Map<String, dynamic>> planRequests = [];

  /// Calls on `/playback/sessions/{id}` and below, as `METHOD path`.
  final List<String> sessionCalls = [];

  /// While set, `POST /watch-state` answers with this status and an error
  /// envelope, without recording the event. Reads (the 5xx regression of
  /// backlog 24.3) need a write that fails fast, not a timeout.
  int? watchStateFailureStatus;

  /// Whether `/info` advertises `users` and `administration` and `/users/me`
  /// answers with the signed-in account as `owner`. Off by default: every
  /// scenario that does not opt in keeps the role-less session it always had,
  /// which is the non-owner state `tvos.authority.non-owner` proves.
  ///
  /// Only the identity is served. The administration routes themselves
  /// (`/users`, `/jobs`, `/audit`) are not, so this carries a scenario as far
  /// as the app offering an administrative action, not through sending one.
  bool usersCapability = false;

  /// The background jobs `GET /jobs` lists once [usersCapability] is on, newest
  /// first, in the server's own JSON. Empty by default; `server.admin-jobs.v1`
  /// seeds one failed job.
  final List<Map<String, dynamic>> adminJobs = [];

  /// Library ids a `POST /libraries/{id}/scan` was sent for, in order.
  final List<String> scanRequests = [];

  /// Job ids a `POST /jobs/{id}/retry` was sent for, in order.
  final List<String> retryRequests = [];

  /// A retried job reads as running until `GET /jobs` has been asked this many
  /// times since the retry, then as succeeded. Four lets a watch (two seconds apart) see "running"
  /// before the end; a job seen running is the watch's own, whatever the clock
  /// on the device says about the fixture's fixed timestamps.
  int retryRunningReads = 4;
  final Map<String, int> _retryReads = {};

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

  /// Artwork ids that can be rendered at any requested width, keyed to a
  /// generator taking that width. A fixture registers one when the point of
  /// the run is *what size was asked for*; everything else keeps serving its
  /// fixed bytes from [artworkById].
  final Map<String, List<int> Function(int width)> resizableArtwork = {};

  /// What a real server cannot say over the protocol yet, per item or person
  /// id: scores, reviews, portraits, a logo, extras, rows and tracks. Served at
  /// `GET /verify/detail/{id}`, a route only a Verify build of the app asks for
  /// (`lib/services/pleya_server_client/parts/verify_detail.dart`). It stays out
  /// of the item itself so every item answer remains what the contract says.
  final Map<String, Map<String, dynamic>> verifyDetail = {};

  /// Trakt's answers, by path: `movies/{id}/comments/likes`, `search/tmdb/{id}`.
  /// Served at `GET /verify/trakt/{path}`, where a Verify build reads them.
  final Map<String, Object> verifyTrakt = {};

  /// version id -> playable bytes, auto-populated by [addItem] for every
  /// version it creates. `GET /stream/{version_id}` serves from here.
  final Map<String, List<int>> versionBytes = {};

  /// `"<kind>/<slug>"` -> the id [applyNamedFixture] generated for it.
  ///
  /// Fixture ids are `sha256(fixture/kind/slug)` truncations: stable, but
  /// not something a scenario author can write down. A step like
  /// `fixture_mutate: {op: add_episode, parent_id: …}` needs the season's
  /// real id, so the seeder publishes what it made and `/__verify/state`
  /// hands it to the runner. Recomputing the hash on the runner side would
  /// work until the day the formula changes on one side only.
  final Map<String, String> seededIds = {};

  /// Item ids on the Pleya Verify kijklijst, newest first, answered at
  /// `/verify/watchlist`. Empty unless `watchlist.studio.v1` is seeded, and
  /// only ever read by a `PLEYA_VERIFY` build: a real Pleya Server has no such
  /// route, so a production client never asks.
  final List<String> verifyWatchlistIds = [];

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

  /// How many of the next requests that carry a `cursor` get a 400
  /// `library.cursor_invalid`, as a real server answers a cursor from before an
  /// update. A request without a cursor is never refused, so a client that
  /// starts over from the top is let through.
  int rejectCursorRequests = 0;

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

  /// Empties the media catalog and nothing else — no credentials, no
  /// session, no counters, no clock.
  ///
  /// Seeding a named fixture needs exactly this, and used to call [reset]
  /// instead. That made step order silently load-bearing: a scenario doing
  /// `sign_in` and then `seed` had its just-created session wiped by the
  /// seed, and every later authenticated step failed with an error about a
  /// dead session that pointed nowhere near the seed step that killed it.
  /// Nothing in the scenario grammar forbids that order, so the fixture is
  /// the right place to stop being order-sensitive.
  void resetCatalog() {
    items.clear();
    libraries.clear();
    libraryItems.clear();
    children.clear();
    hubs.updateAll((_, __) => []);
    searchResults.clear();
    artworkById.clear();
    versionBytes.clear();
    seededIds.clear();
    verifyWatchlistIds.clear();
    verifyDetail.clear();
    verifyTrakt.clear();
  }

  /// Clears every mutable field back to a fresh instance's state. Used by
  /// the `/__verify/reset` control-plane route between scenario runs.
  void reset() {
    resetCatalog();
    watchEvents.clear();
    watchStates.clear();
    ownedByThisSession = true;
    filtersCapability = false;
    playbackPlanCapability = false;
    personalCapability = false;
    itemActivityCapability = false;
    itemActivityByItem.clear();
    itemActivityRequests.clear();
    itemActivityFailureStatus = null;
    assistantMemoryCapability = false;
    _memoryAccessUsers.clear();
    _memoryRefreshUsers.clear();
    _memoryRoles.clear();
    _memoryStores.clear();
    downloadsCapability = false;
    downloadPrepareRounds = 0;
    downloadFails = false;
    downloadRequests.clear();
    _downloadPolls.clear();
    favoriteIds.clear();
    ratingsByItem.clear();
    trackPreferences.clear();
    planVersionId = 'version-1';
    planDeliveryMode = 'direct_play';
    planFailureStatus = null;
    planRequests.clear();
    sessionCalls.clear();
    watchStateFailureStatus = null;
    usersCapability = false;
    adminJobs.clear();
    scanRequests.clear();
    retryRequests.clear();
    retryRunningReads = 4;
    _retryReads.clear();
    requests.clear();
    refreshCount = 0;
    rejectCurrentAccessTokens = false;
    unreachable = false;
    refreshOutcome = PleyaFakeRefreshOutcome.rotate;
    setupRequired = _initialSetupRequired;
    _credentials.clear();
    clock.resetToStart();
    _queuedFailure = null;
    _queuedLatency = Duration.zero;
    _queuedLatencyCount = 0;
  }

  /// The administration routes the assistant's scan and restart tools use, shaped
  /// by the contract: the job page, a job's retry (200 with the Job) and a
  /// library's scan (202 with the Scan). The job id a watch could follow is not
  /// in a scan's answer, as on the real server.
  http.Response? _adminRoute(String path, String method) {
    if (path == '/jobs' && method == 'GET') {
      for (final job in adminJobs) {
        final reads = _retryReads[job['id']];
        if (reads == null) continue;
        _retryReads[job['id'] as String] = reads + 1;
        if (reads + 1 > retryRunningReads && job['state'] == 'running') {
          job
            ..['state'] = 'succeeded'
            ..['finished_at'] = clock.now.toIso8601String();
        }
      }
      return _json({'items': adminJobs, 'next_cursor': null});
    }
    final retry = RegExp(r'^/jobs/([^/]+)/retry$').firstMatch(path);
    if (retry != null && method == 'POST') {
      final job = adminJobs.where((job) => job['id'] == retry.group(1)).firstOrNull;
      if (job == null) return _json(_error('job.not_found'), status: 404);
      retryRequests.add(job['id'] as String);
      job
        ..['state'] = 'running'
        ..['attempts'] = (job['attempts'] as int? ?? 0) + 1
        ..['run_at'] = clock.now.toIso8601String()
        ..['created_at'] = clock.now.toIso8601String()
        ..['finished_at'] = null
        ..['last_error'] = null;
      _retryReads[job['id'] as String] = 0;
      return _json(job);
    }
    final scan = RegExp(r'^/libraries/([^/]+)/scan$').firstMatch(path);
    if (scan != null && method == 'POST') {
      scanRequests.add(scan.group(1)!);
      // The Scan the server starts. It carries a scan id, not a job id to follow.
      return _json({
        'id': 'scan-${scanRequests.length}',
        'library_id': scan.group(1),
        'trigger': 'manual',
        'state': 'running',
        'started_at': clock.now.toIso8601String(),
        'finished_at': null,
        'files_seen': 0,
        'files_new': 0,
        'files_renamed': 0,
        'files_changed': 0,
        'files_probed': 0,
        'files_missing': 0,
        'bytes_hashed': 0,
        'items_created': 0,
        'versions_created': 0,
        'error_count': 0,
        'last_error': null,
        'current_path': null,
      }, status: 202);
    }
    return null;
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

    /// The wide backdrop, which is a different artwork from the poster and the
    /// only one `MediaItem.billboardArt` will draw sharp on a hero. Left null
    /// by every fixture that predates the hero artwork audit, which is why the
    /// Home hero rendered its blurred poster-fill fallback there.
    String? backdropId,
    String? edition,
    Map<String, dynamic>? userState,
    String addedAt = '2026-06-18T21:34:02Z',
    List<String>? genres,
    String? contentRating,
  }) {
    final item = <String, dynamic>{
      'id': id,
      'kind': kind,
      'title': title,
      'sort_title': title,
      'year': year,
      'genres': ?genres,
      'content_rating': ?contentRating,
      'added_at': addedAt,
      'duration_ms': durationMs,
      'parent_id': parentId,
      'index': index,
      'child_count': childCount,
      'episode_count': episodeCount,
      'watched_episode_count': watchedEpisodeCount,
      'artwork': {'poster_id': posterId, 'backdrop_id': backdropId},
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

  /// Adds a playable film to [libraryId] and puts it at the front of
  /// `recently_added`, the way a real server lists the newest first.
  /// `POST /__verify/add_movie`'s implementation, the mutation
  /// `tvos.home.recently-added-refresh` needs. Returns the new id, or `null`
  /// when [libraryId] is unknown (the control plane turns that into 404).
  String? addMovie({required String libraryId, String? title}) {
    final library = libraries.where((l) => l['id'] == libraryId).firstOrNull;
    if (library == null) return null;
    // Counted, not timestamped: the fixture clock is frozen, so two films
    // added in one scenario would otherwise share an id.
    final id = '$libraryId/added-movie-${(libraryItems[libraryId]?.length ?? 0) + 1}';
    addItem(
      id: id,
      kind: 'movie',
      title: title ?? 'Added Movie',
      libraryId: libraryId,
      year: clock.now.year,
      durationMs: 5400000,
      addedAt: clock.now.toIso8601String(),
      posterId: id,
    );
    artworkById[id] = artworkBytes;
    hubs['recently_added']!.insert(0, id);
    library['item_count'] = ((library['item_count'] as int?) ?? 0) + 1;
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

    if (rejectCursorRequests > 0 && query.containsKey('cursor')) {
      rejectCursorRequests--;
      return _json(_error('library.cursor_invalid'), status: 400);
    }

    if (path == '/info') return _json(_info());
    if (path == '/auth/login') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final username = body['username'] as String?;
      final password = body['password'] as String?;
      if (username == null || _credentials[username] != password) {
        return _json(_error('auth.invalid_credentials'), status: 401);
      }
      return _json(_mintTokenPair(username: username));
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
      _memoryRoles[username] = 'owner';
      return _json(_mintTokenPair(username: username));
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
      if (assistantMemoryCapability) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final username = _memoryRefreshUsers.remove(body['refresh_token']);
        if (username == null) return _json(_error('auth.invalid_token'), status: 401);
        return _json(_mintTokenPair(username: username));
      }
      return _json(_mintTokenPair());
    }
    // Trakt is read with an app key and no account, so these answer without a
    // token: a client that sends one is the bug the scenario would miss.
    if (path.startsWith('/verify/trakt/')) {
      if (request.headers.containsKey('Authorization')) return _json(_error('auth.invalid_token'), status: 401);
      final body = verifyTrakt[path.substring('/verify/trakt/'.length)];
      return body == null ? _json(_error('library.not_found'), status: 404) : _json(body);
    }
    final bearer = request.headers['Authorization'];
    final memoryUsername = _memoryAccessUsers[bearer];
    final expected = rejectCurrentAccessTokens ? null : 'Bearer at-$refreshCount';
    final authorized =
        !rejectCurrentAccessTokens && (assistantMemoryCapability ? memoryUsername != null : bearer == expected);
    if (!authorized) {
      return _json(_error('auth.invalid_token'), status: 401);
    }
    if (path == '/server') {
      return _json(const {'id': 'srv-1', 'name': 'Zolder', 'version': '0.2.0', 'started_at': '2026-08-18T19:25:33Z'});
    }
    if (path == '/libraries') return _json({'items': libraries});
    if (usersCapability) {
      final admin = _adminRoute(path, request.method);
      if (admin != null) return admin;
    }
    if (usersCapability && path == '/users/me' && request.method == 'GET') {
      if (assistantMemoryCapability && memoryUsername != null) {
        return _json({
          'id': _memoryUserId(memoryUsername),
          'username': memoryUsername,
          'role': _memoryRoles[memoryUsername] ?? 'member',
        });
      }
      // The old fixtures keep their original single owner identity.
      return _json({'id': 'user-owner', 'username': _credentials.keys.firstOrNull ?? 'owner', 'role': 'owner'});
    }
    if (assistantMemoryCapability && (path == '/users/me/memory' || path == '/users/me/memory/clear')) {
      if (memoryUsername == null || !{'owner', 'admin', 'member'}.contains(_memoryRoles[memoryUsername] ?? 'member')) {
        return _json(_error('memory.not_permitted'), status: 403);
      }
      final subject = _memoryUserId(memoryUsername);
      final store = _memoryStores.putIfAbsent(subject, () => MemoryFakeStore(subject, () => clock.now));
      return store.handle(request, clear: path.endsWith('/clear'));
    }

    if (path == '/auth/stream-token') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({'stream_token': 'st-for-${body['version_id']}', 'expires_at': '2026-08-21T21:09:11Z'});
    }

    if (path == '/playback/plan' && request.method == 'POST' && playbackPlanCapability) {
      final failure = planFailureStatus;
      if (failure != null) return _json(_error('playback.not_playable'), status: failure);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      planRequests.add(body);
      final versionId = (body['version_id'] as String?) ?? planVersionId;
      final reason = {
        'code': planDeliveryMode == 'direct_play' ? 'direct.supported' : 'container.unsupported',
        'params': <String, dynamic>{},
      };
      final direct = planDeliveryMode == 'direct_play';
      // A mode the client does not know still comes with a session, like a
      // newer server would send it.
      return _json({
        'item_id': body['item_id'],
        'version_id': versionId,
        'delivery_mode': planDeliveryMode,
        'stream_url': direct ? '/pleya/v1/stream/$versionId' : '/pleya/v1/playback/sessions/sess-1/index.m3u8',
        'container': direct ? 'original' : 'hls',
        'video': {'action': 'copy'},
        'audio': {'action': 'copy'},
        'seekable': direct,
        'session_id': direct ? null : 'sess-1',
        'reason': reason,
        'reasons': [reason],
      });
    }

    if (path.startsWith('/playback/sessions/') && playbackPlanCapability) {
      sessionCalls.add('${request.method} $path');
      return http.Response('', 204);
    }

    final activityMatch = RegExp(r'^/items/([^/]+)/activity$').firstMatch(path);
    if (activityMatch != null) {
      itemActivityRequests.add(path);
      final failure = itemActivityCapability ? itemActivityFailureStatus : 404;
      if (failure != null) return _json(_error('library.not_found'), status: failure);
      return _json({'items': itemActivityByItem[activityMatch.group(1)] ?? const []});
    }

    if (personalCapability) {
      final personal = _personal(request, path);
      if (personal != null) return personal;
    }
    if (downloadsCapability && path.startsWith('/downloads')) return _downloads(request, path);

    if (path == '/watch-state' && request.method == 'POST') {
      final failure = watchStateFailureStatus;
      if (failure != null) return _json(_error('server.internal'), status: failure);
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
    if (path == '/verify/watchlist') return _json({'item_ids': verifyWatchlistIds});
    if (path.startsWith('/verify/detail/')) {
      final detail = verifyDetail[Uri.decodeComponent(path.substring('/verify/detail/'.length))];
      return detail == null ? _json(_error('library.not_found'), status: 404) : _json(detail);
    }
    if (path.startsWith('/artwork/')) {
      final id = Uri.decodeComponent(path.substring('/artwork/'.length));
      // A resizable artwork honours `?width=`, the way a real server does.
      // Without this the fixture answered every width with the same bytes, so
      // "was the request big enough" was unobservable end to end and the hero
      // audit could only reason about it from the URL.
      final recipe = resizableArtwork[id];
      final asked = int.tryParse(query['width'] ?? '');
      if (recipe != null && asked != null && asked > 0) {
        return http.Response.bytes(recipe(asked.clamp(16, 4096)), 200, headers: const {'content-type': 'image/png'});
      }
      final bytes = artworkById[id] ?? artworkBytes;
      return http.Response.bytes(bytes, 200, headers: {'content-type': _imageContentType(bytes)});
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
      final narrowed = filtersCapability ? _filtered(ids, request.url.queryParametersAll) : ids;
      return _json(_page(_sorted(narrowed, query['sort']), query));
    }

    final facetsMatch = RegExp(r'^/libraries/([^/]+)/facets$').firstMatch(path);
    if (facetsMatch != null && filtersCapability) {
      final ids = libraryItems[Uri.decodeComponent(facetsMatch.group(1)!)];
      if (ids == null) return _json(_error('library.not_found'), status: 404);
      return _json(_facets(ids));
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

  /// The subset of the filter parameters this fixture can answer from the data
  /// it holds: genre, year, a year range, content rating and the three watch
  /// states. Audio language and resolution have no data in the fixture and are
  /// not applied; a scenario that sends them proves the request, not the answer.
  List<String> _filtered(List<String> ids, Map<String, List<String>> params) {
    final genres = [for (final g in params['genre'] ?? const <String>[]) g.toLowerCase()];
    final years = {for (final y in params['year'] ?? const <String>[]) int.tryParse(y)};
    final ratings = [for (final r in params['content_rating'] ?? const <String>[]) r.toLowerCase()];
    final from = int.tryParse(params['year_from']?.first ?? '');
    final to = int.tryParse(params['year_to']?.first ?? '');
    final watch = params['watch']?.first;
    return [
      for (final id in ids)
        if (_matches(items[id]!, genres: genres, years: years, ratings: ratings, from: from, to: to, watch: watch)) id,
    ];
  }

  bool _matches(
    Map<String, dynamic> item, {
    required List<String> genres,
    required Set<int?> years,
    required List<String> ratings,
    required int? from,
    required int? to,
    required String? watch,
  }) {
    final itemGenres = [for (final g in (item['genres'] as List?) ?? const []) (g as String).toLowerCase()];
    if (genres.isNotEmpty && !genres.any(itemGenres.contains)) return false;
    final year = item['year'] as int?;
    if (years.isNotEmpty && !years.contains(year)) return false;
    if (from != null && (year == null || year < from)) return false;
    if (to != null && (year == null || year > to)) return false;
    final rating = (item['content_rating'] as String?)?.toLowerCase();
    if (ratings.isNotEmpty && !ratings.contains(rating)) return false;
    if (watch != null) {
      final state = watchStates[item['id']] ?? (item['user_state'] as Map<String, dynamic>?);
      final watched = state?['watched'] == true;
      final started = ((state?['position_ms'] as int?) ?? 0) > 0;
      final ok = switch (watch) {
        'unwatched' => !watched,
        'in_progress' => !watched && started,
        'watched' => watched,
        _ => true,
      };
      if (!ok) return false;
    }
    return true;
  }

  Map<String, dynamic> _facets(List<String> ids) {
    List<Map<String, dynamic>> count(Iterable<String> values, {bool numericDesc = false}) {
      final tally = <String, int>{};
      for (final v in values) {
        tally[v] = (tally[v] ?? 0) + 1;
      }
      final keys = tally.keys.toList()
        ..sort(numericDesc ? (a, b) => int.parse(b).compareTo(int.parse(a)) : (a, b) => tally[b]!.compareTo(tally[a]!));
      return [
        for (final k in keys) {'value': k, 'count': tally[k]},
      ];
    }

    final rows = [for (final id in ids) items[id]!];
    var unwatched = 0, inProgress = 0, watched = 0;
    for (final item in rows) {
      final state = watchStates[item['id']] ?? (item['user_state'] as Map<String, dynamic>?);
      final isWatched = state?['watched'] == true;
      if (isWatched) {
        watched++;
      } else {
        unwatched++;
        if (((state?['position_ms'] as int?) ?? 0) > 0) inProgress++;
      }
    }
    return {
      'genres': count([for (final r in rows) ...((r['genres'] as List?) ?? const []).cast<String>()]),
      'years': count([
        for (final r in rows)
          if (r['year'] != null) '${r['year']}',
      ], numericDesc: true),
      'content_ratings': count([
        for (final r in rows)
          if (r['content_rating'] != null) r['content_rating'] as String,
      ]),
      'audio_languages': <Map<String, dynamic>>[],
      'resolutions': <Map<String, dynamic>>[],
      'watch': {'unwatched': unwatched, 'in_progress': inProgress, 'watched': watched},
    };
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
      'users': usersCapability,
      'administration': usersCapability,
      if (assistantMemoryCapability) 'assistant_memory': true,
      'watch_state_ownership': watchStateOwnership,
      'stream_sessions': watchState,
      if (filtersCapability) 'filters': true,
      if (playbackPlanCapability) 'playback_plan': true,
      if (downloadsCapability) 'downloads': true,
      if (personalCapability) ...{'history': true, 'favorites': true, 'ratings': true, 'track_preferences': true},
      if (itemActivityCapability) 'item_activity': true,
    },
    'auth': {
      'methods': ['password'],
      'setup_required': setupRequired,
    },
  };

  /// Shared by `/auth/refresh`, `/auth/login` and `/auth/setup` — all three
  /// end the same way: mint a fresh pair, bump [refreshCount] (the counter
  /// `at-N`/the authenticated-route check reads).
  Map<String, dynamic> _mintTokenPair({String? username}) {
    refreshCount++;
    if (assistantMemoryCapability && username != null) {
      _memoryAccessUsers['Bearer at-$refreshCount'] = username;
      _memoryRefreshUsers['rt-${refreshCount + 1}'] = username;
    }
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
    // Both "past the end" and "reversed" (bytes=5-2) are not satisfiable.
    // Without this, a reversal of exactly 1 (bytes=2-1) computed an empty
    // sublist silently (start == end+1, which satisfies sublist's start<=end
    // requirement trivially) and a larger reversal (bytes=5-2) threw an
    // uncaught RangeError instead of the documented 416.
    if (start >= total || start > end) throw const _RangeNotSatisfiable();
    return (start: start, end: end);
  }

  /// `image/jpeg` for the studio art (a JPEG starts with FF D8), `image/png`
  /// for everything the fixtures generate.
  static String _imageContentType(List<int> bytes) =>
      bytes.length > 1 && bytes[0] == 0xFF && bytes[1] == 0xD8 ? 'image/jpeg' : 'image/png';

  Map<String, dynamic> _error(String code) => {
    'error': {'code': code, 'message': code, 'retryable': false},
  };

  http.Response? _personal(http.Request request, String path) {
    final id = path.split('/').last;
    if (path.startsWith('/favorites/')) {
      if (request.method == 'PUT') favoriteIds.add(id);
      if (request.method == 'DELETE') favoriteIds.remove(id);
      return http.Response('', 204);
    }
    if (path.startsWith('/ratings/')) {
      if (request.method == 'PUT') {
        ratingsByItem[id] = (jsonDecode(request.body) as Map<String, dynamic>)['rating'] as int;
      }
      if (request.method == 'DELETE') ratingsByItem.remove(id);
      return http.Response('', 204);
    }
    if (path.startsWith('/track-preferences/')) {
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        trackPreferences[id] = {'source_item_id': id, 'updated_at': '2026-10-20T20:00:00Z', ...body};
      }
      if (request.method == 'DELETE') {
        trackPreferences.remove(id);
        return http.Response('', 204);
      }
      final stored = trackPreferences[id];
      return _json({
        'source_item_id': stored?['source_item_id'],
        'audio_language': stored?['audio_language'],
        'subtitle_language': stored?['subtitle_language'],
        'subtitle_mode': stored?['subtitle_mode'],
        'updated_at': stored?['updated_at'],
      });
    }
    return null;
  }

  http.Response _downloads(http.Request request, String path) {
    Map<String, dynamic> wire(String id, String status) => {
      'id': id,
      'item_id': 'movie-1',
      'version_id': 'version-1',
      'status': status,
      'size_bytes': status == 'ready' ? 1024 : null,
      'sha256': status == 'ready' ? downloadSha256 : null,
      'file_url': '/pleya/v1/downloads/$id/file',
      'created_at': '2026-10-23T09:15:00Z',
    };
    if (path == '/downloads' && request.method == 'POST') {
      downloadRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _json(wire('dl-1', 'preparing'), status: 201);
    }
    if (request.method == 'DELETE') return http.Response('', 204);
    final id = path.split('/').last;
    final polls = _downloadPolls[id] = (_downloadPolls[id] ?? 0) + 1;
    if (downloadFails) return _json(wire(id, 'failed'));
    return _json(wire(id, polls > downloadPrepareRounds ? 'ready' : 'preparing'));
  }

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
