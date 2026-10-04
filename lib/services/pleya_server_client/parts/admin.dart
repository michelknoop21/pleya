part of '../../pleya_server_client.dart';

/// One running stream from `GET /stream-sessions`, in the same record shape
/// as `JellyfinActiveSession` so a reader can treat both alike. The wire has
/// no pause, transcode or episode fields; those stay null. The session id is
/// left out on purpose.
typedef PleyaActiveStream = ({
  String userName,
  String title,
  String? episode,
  int progressPercent,
  bool? paused,
  bool? transcoding,
  String? device,
});

/// One user's finished film or episode from `GET /watch-history`: the last
/// touch per user per item, not a play log. [seriesId] and [seriesTitle] are
/// set for an episode only.
typedef PleyaWatchedTitle = ({
  String userId,
  String userName,
  String itemId,
  String title,
  String? seriesId,
  String? seriesTitle,
  DateTime updatedAt,
});

/// Reads a `WatchHistory` body. A row without a readable `updated_at` is
/// dropped: it cannot be placed in a period.
({List<PleyaWatchedTitle> items, bool truncated}) pleyaWatchHistoryFromJson(Map<String, dynamic> json) {
  final items = json['items'];
  return (
    items: <PleyaWatchedTitle>[
      if (items is List)
        for (final w in items.whereType<Map<String, dynamic>>())
          if (DateTime.tryParse(w['updated_at'] as String? ?? '') case final at?)
            (
              userId: w['user_id'] as String? ?? '',
              userName: w['username'] as String? ?? '',
              itemId: w['item_id'] as String? ?? '',
              title: w['item_title'] as String? ?? '',
              seriesId: w['series_id'] as String?,
              seriesTitle: w['series_title'] as String?,
              updatedAt: at,
            ),
    ],
    truncated: json['truncated'] == true,
  );
}

/// Server administration: scans, jobs, users and library access.
///
/// Unlike the read paths elsewhere, nothing here answers null or empty on a
/// failed request. An admin action that did not happen must not look like one
/// that did, so every non-2xx answer throws: [MediaServerAuthException] for a
/// 401 or 403, [MediaServerHttpException] for the rest, with the protocol
/// error code as its message. A member reaching an admin route gets a 404
/// (`auth.user_not_found`), because the server hides its admin surface.
///
/// Every method asserts [ServerAuthorityGuard.assertCanAdministerServer]
/// before its first request.
///
/// A scan is a job of kind `scan_library`, so [listJobs] reads `GET /jobs`
/// alone: `GET /scans` lists the same work again with file counters, and a
/// second source would show every scan twice.
mixin _PleyaServerAdminMethods on _PleyaServerRequests
    implements LibraryScanClient, RetryableJobsClient, ServerUserAdministration {
  MediaServerHttpClient get _http;

  void assertCanAdministerServer();

  @override
  bool get supportsServerAdministration => wireCapabilities.administration;

  @override
  Future<void> scanLibrary(String libraryId) async {
    assertCanAdministerServer();
    await _adminSend('POST', '/libraries/${adminPathSegment(libraryId)}/scan');
  }

  /// The newest page of jobs.
  // ponytail: one page of 100; follow `next_cursor` when a screen needs history.
  @override
  Future<List<ServerJob>> listJobs() async {
    assertCanAdministerServer();
    final json = await _adminSend('GET', '/jobs', queryParameters: const {'limit': '100'});
    return [for (final job in PleyaJob.listFromJson(json ?? const {})) _job(job)];
  }

  @override
  Future<void> cancelJob(String jobId) async {
    assertCanAdministerServer();
    await _adminSend('POST', '/jobs/${adminPathSegment(jobId)}/cancel');
  }

  @override
  Future<void> retryJob(String jobId) async {
    assertCanAdministerServer();
    await _adminSend('POST', '/jobs/${adminPathSegment(jobId)}/retry');
  }

  /// Every account on the server.
  ///
  /// Owner and admin bypass library permissions on the server (DEC-119 §2), so
  /// they see all libraries. For member and restricted the protocol has no
  /// read of the grant list: `GET /users` carries no permissions and only
  /// `PUT /users/{id}/permissions` answers with them. Those users therefore
  /// come back with `allLibraries: false` and no ids, which means "unknown",
  /// not "none".
  @override
  Future<List<ServerUser>> listUsers() async {
    assertCanAdministerServer();
    final json = await _adminSend('GET', '/users');
    return [
      for (final user in pleyaUsersFromJson(json ?? const {}))
        ServerUser(
          id: user.id,
          name: user.username,
          role: _role(user.role),
          allLibraries: user.role == 'owner' || user.role == 'admin',
          // Owner and admin bypass grants. A member's grants have no read
          // route, so their access is unknown rather than empty.
          libraryAccessKnown: user.role == 'owner' || user.role == 'admin',
        ),
    ];
  }

  /// Who is streaming right now (`GET /stream-sessions`, admin class). The
  /// list is unpaged by design: the server caps sessions per user.
  Future<List<PleyaActiveStream>> streamSessions() async {
    assertCanAdministerServer();
    final json = await _adminSend('GET', '/stream-sessions');
    final items = json?['items'];
    return [
      if (items is List)
        for (final s in items.whereType<Map<String, dynamic>>())
          (
            userName: s['username'] as String? ?? '',
            title: s['item_title'] as String? ?? '',
            episode: null,
            progressPercent: switch ((s['position_ms'], s['duration_ms'])) {
              (final num p, final num d) when d > 0 => (p * 100 / d).round().clamp(0, 100).toInt(),
              _ => 0,
            },
            paused: null,
            transcoding: null,
            device: s['device_name'] as String?,
          ),
    ];
  }

  /// Finished titles per user whose watch state changed in the last [days]
  /// (`GET /watch-history`, admin class, DEC-143), newest first. The server
  /// caps the list at 1000 rows and says so with [truncated]. An older server
  /// without the route answers 404 `library.not_found`.
  Future<({List<PleyaWatchedTitle> items, bool truncated})> watchHistory(int days) async {
    assertCanAdministerServer();
    return pleyaWatchHistoryFromJson(
      await _adminSend('GET', '/watch-history', queryParameters: {'days': '$days'}) ?? const {},
    );
  }

  @override
  bool get createUserRequiresPassword => true;

  /// The server has no read route for a member's grants and its PUT replaces
  /// the whole list, so changing an existing user could drop a `download`
  /// grant nobody asked to touch. Until the protocol can read grants, only a
  /// new user (whose list is known to be empty) gets access set.
  @override
  bool get canChangeLibraryAccess => false;

  /// Always role `member`. The server refuses an owner outright and an admin
  /// is not something this path may create.
  @override
  Future<ServerUser> createUser({
    required String name,
    String? password,
    bool allLibraries = false,
    List<String> libraryIds = const [],
  }) async {
    assertCanAdministerServer();
    if (password == null || password.isEmpty) {
      throw ArgumentError.value(password, 'password', 'A Pleya Server account needs a password');
    }
    final json = await _adminSend('POST', '/users', body: {'username': name, 'password': password, 'role': 'member'});
    final created = PleyaUser.fromJson(json ?? const {});
    final user = ServerUser(id: created.id, name: created.username, role: _role(created.role), allLibraries: false);
    if (!allLibraries && libraryIds.isEmpty) return user;
    try {
      await _putGrants(user.id, allLibraries: allLibraries, libraryIds: libraryIds);
    } catch (e) {
      // The member exists and sees nothing, which is the safe side; the
      // caller reports the missing access instead of a failed create.
      throw ServerUserAccessNotGranted(user, e);
    }
    return ServerUser(
      id: user.id,
      name: user.name,
      role: user.role,
      allLibraries: false,
      libraryIds: allLibraries ? const [] : libraryIds,
      libraryAccessKnown: !allLibraries,
    );
  }

  @override
  Future<void> setUserLibraryAccess(
    String userId, {
    required bool allLibraries,
    List<String> libraryIds = const [],
  }) async {
    assertCanAdministerServer();
    throw UnsupportedError('Pleya Server cannot read existing grants; refusing to replace them');
  }

  /// `view` per library; for [allLibraries], one row per library that exists
  /// now (the server has no lasting "all" for a member). Only for a user whose
  /// grant list is known to be empty. `manage` is never sent.
  Future<void> _putGrants(String userId, {required bool allLibraries, required List<String> libraryIds}) async {
    final ids = allLibraries
        ? [
            for (final library in PleyaLibrary.listFromJson(await _adminSend('GET', '/libraries') ?? const {}))
              library.id,
          ]
        : libraryIds;
    assertCanAdministerServer();
    await _adminSend(
      'PUT',
      '/users/${adminPathSegment(userId)}/permissions',
      body: {
        'permissions': [
          for (final id in ids) {'library_id': id, 'permission': 'view'},
        ],
      },
    );
  }

  @override
  Future<void> deleteUser(String userId) async {
    assertCanAdministerServer();
    await _adminSend('DELETE', '/users/${adminPathSegment(userId)}');
  }

  static ServerUserRole _role(String role) => switch (role) {
    'owner' => ServerUserRole.owner,
    'admin' => ServerUserRole.admin,
    'member' => ServerUserRole.member,
    'restricted' => ServerUserRole.restricted,
    _ => ServerUserRole.unknown,
  };

  static ServerJob _job(PleyaJob job) {
    final state = switch (job.state) {
      'pending' => ServerJobState.queued,
      'running' => ServerJobState.running,
      'succeeded' => ServerJobState.succeeded,
      'failed' => ServerJobState.failed,
      'cancelled' => ServerJobState.cancelled,
      _ => ServerJobState.unknown,
    };
    final active = state == ServerJobState.queued || state == ServerJobState.running;
    final finished =
        state == ServerJobState.succeeded || state == ServerJobState.failed || state == ServerJobState.cancelled;
    return ServerJob(
      id: job.id,
      title: job.kind,
      state: state,
      libraryId: job.libraryId,
      error: job.lastError,
      updatedAt: job.finishedAt ?? job.createdAt,
      cancellable: active,
      // The server retries any job that is no longer pending or running.
      retryable: finished,
    );
  }

  /// Send an admin request and hand back its JSON object (null for a 202 or
  /// 204 without one). Retries once on a 401, like [_authorizedGet]; throws on
  /// anything else outside 2xx.
  Future<Map<String, dynamic>?> _adminSend(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
  }) async {
    Future<MediaServerResponse> send() async {
      final headers = await _session.authHeaders();
      final encoded = body == null ? null : jsonEncode(body);
      const timeout = MediaServerTimeouts.interactive;
      return switch (method) {
        'GET' => _http.get(path, queryParameters: queryParameters, headers: headers, timeout: timeout),
        'POST' => _http.post(path, body: encoded, headers: headers, timeout: timeout),
        'PUT' => _http.put(path, body: encoded, headers: headers, timeout: timeout),
        'DELETE' => _http.delete(path, headers: headers, timeout: timeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
    }

    var response = await send();
    if (response.statusCode == 401) {
      _session.invalidateAccessToken();
      response = await send();
    }
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final code = PleyaError.tryParse(response.data)?.code;
      appLogger.d('PleyaServerClient: $method $path -> $status ${code ?? ''}');
      if (status == 401 || status == 403) {
        throw MediaServerAuthException(code ?? 'HTTP $status', statusCode: status);
      }
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: status,
        responseData: response.data,
        message: code ?? 'HTTP $status',
      );
    }
    final data = response.data;
    return data is Map<String, dynamic> ? data : null;
  }
}
