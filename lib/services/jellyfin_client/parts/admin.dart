part of '../../jellyfin_client.dart';

/// One stream on the server as an admin sees it. Carries no session id,
/// token or address: only what an admin reads off a "now playing" list. Null
/// [paused]/[transcoding] means the server did not say.
typedef JellyfinActiveSession = ({
  String userName,
  String title,
  String? episode,
  int progressPercent,
  bool? paused,
  bool? transcoding,
  String? device,
});

/// One finished film or episode of one user, with the server's single
/// last-played date for it (a replay moves the date, it adds no row).
/// [year] and [ids] describe a film; an episode's own year and ids are not
/// its series', so they stay null there.
typedef JellyfinPlayedItem = ({
  String id,
  String title,
  String? seriesId,
  String? seriesName,
  DateTime lastPlayed,
  int? year,
  ExternalIds? ids,
});

/// Server administration ([ServerUserAdministration], [RetryableJobsClient],
/// library scans, item refresh) for Jellyfin and Emby.
///
/// The two servers share these endpoints; they differ in the user list
/// (`/Users/Query` on Emby), password handling on create, the refresh body
/// Emby requires, and the folder id a policy carries. Jellyfin's
/// `EnabledFolders` holds the CollectionFolder id, the same id
/// `/Users/{id}/Views` gives the app as `MediaLibrary.id`. Emby's holds the
/// folder `Guid` from `/Library/SelectableMediaFolders`, so ids are translated
/// both ways there. An app id that maps to no server folder fails closed.
mixin _JellyfinAdminMethods {
  JellyfinConnection get connection;
  FailoverHttpClient get _http;
  void assertCanAdministerServer();

  bool get supportsServerAdministration => true;

  bool get createUserRequiresPassword => false;

  /// A metadata-only refresh: finds new and removed files without touching
  /// existing metadata. Emby only walks children with `Recursive`.
  Future<void> scanLibrary(String libraryId) async {
    assertCanAdministerServer();
    final response = await _http.post(
      '/Items/${adminPathSegment(libraryId)}/Refresh',
      queryParameters: {
        if (connection.isEmby) 'Recursive': 'true',
        'metadataRefreshMode': 'Default',
        'imageRefreshMode': 'Default',
        'replaceAllMetadata': 'false',
        'replaceAllImages': 'false',
      },
      body: _embyRefreshBody,
    );
    throwIfHttpError(response);
  }

  Future<void> refreshItemMetadata(String itemId) async {
    assertCanAdministerServer();
    final response = await _http.post(
      '/Items/${adminPathSegment(itemId)}/Refresh',
      queryParameters: {
        if (connection.isEmby) 'Recursive': 'true',
        'metadataRefreshMode': 'FullRefresh',
        'imageRefreshMode': 'Default',
        'replaceAllMetadata': 'false',
        'replaceAllImages': 'false',
      },
      body: _embyRefreshBody,
    );
    throwIfHttpError(response);
  }

  /// Emby requires a `BaseRefreshRequest` body; Jellyfin takes none.
  Map<String, dynamic>? get _embyRefreshBody => connection.isEmby ? const <String, dynamic>{} : null;

  Future<List<ServerJob>> listJobs() async {
    assertCanAdministerServer();
    final response = await _http.get('/ScheduledTasks');
    throwIfHttpError(response);
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .where((task) => task['IsHidden'] != true && task['Id'] is String)
        .map(_jobFromTask)
        .toList();
  }

  Future<void> cancelJob(String jobId) async {
    assertCanAdministerServer();
    final response = await _http.delete('/ScheduledTasks/Running/${adminPathSegment(jobId)}');
    throwIfHttpError(response);
  }

  Future<void> retryJob(String jobId) async {
    assertCanAdministerServer();
    final response = await _http.post('/ScheduledTasks/Running/${adminPathSegment(jobId)}');
    throwIfHttpError(response);
  }

  ServerJob _jobFromTask(Map<String, dynamic> task) {
    final last = task['LastExecutionResult'];
    final result = last is Map<String, dynamic> ? last : const <String, dynamic>{};
    final state = switch (task['State']) {
      'Running' || 'Cancelling' => ServerJobState.running,
      'Idle' => switch (result['Status']) {
        'Completed' => ServerJobState.succeeded,
        'Failed' || 'Aborted' => ServerJobState.failed,
        'Cancelled' => ServerJobState.cancelled,
        _ => ServerJobState.unknown,
      },
      _ => ServerJobState.unknown,
    };
    final percent = task['CurrentProgressPercentage'];
    final endedAt = result['EndTimeUtc'];
    return ServerJob(
      id: task['Id'] as String,
      title: task['Name'] as String? ?? task['Id'] as String,
      state: state,
      progress: state == ServerJobState.running && percent is num ? (percent / 100).clamp(0.0, 1.0).toDouble() : null,
      error: result['ErrorMessage'] as String?,
      updatedAt: endedAt is String ? DateTime.tryParse(endedAt) : null,
      cancellable: task['State'] == 'Running',
      retryable: task['State'] == 'Idle',
    );
  }

  Future<List<ServerUser>> listUsers() async {
    assertCanAdministerServer();
    final response = await _http.get(connection.isEmby ? '/Users/Query' : '/Users');
    throwIfHttpError(response);
    final data = response.data;
    final items = connection.isEmby ? (data is Map<String, dynamic> ? data['Items'] : null) : data;
    if (items is! List) return const [];
    final users = items.whereType<Map<String, dynamic>>().where((u) => u['Id'] is String).toList();
    // Emby policies carry folder Guids; translate back to app ids once.
    final guidToId = connection.isEmby && users.isNotEmpty ? await _embyGuidToLibraryId() : null;
    return users.map((u) => _userFromDto(u, guidToId)).toList();
  }

  bool get canChangeLibraryAccess => true;

  Future<ServerUser> createUser({
    required String name,
    String? password,
    bool allLibraries = false,
    List<String> libraryIds = const [],
  }) async {
    assertCanAdministerServer();
    final hasPassword = password != null && password.isNotEmpty;
    // An unknown library stops the create before there is a user to undo.
    if (!allLibraries) await _policyFolderIds(libraryIds);
    // Never a role above member: neither server makes a new user admin.
    final response = await _http.post(
      '/Users/New',
      body: {'Name': name, if (!connection.isEmby && hasPassword) 'Password': password},
    );
    throwIfHttpError(response);
    final dto = response.data;
    if (dto is! Map<String, dynamic> || dto['Id'] is! String) {
      // A 2xx means the user exists, with every library. Names are unique,
      // so find it by name and take it away again.
      final created = (await listUsers()).where((u) => u.name == name).firstOrNull;
      if (created != null) await _removeHalfCreatedUser(created.id, name, 'unexpected create-user response');
      throw _adminError('Unexpected create-user response');
    }
    final id = dto['Id'] as String;
    try {
      if (connection.isEmby && hasPassword) {
        // Emby's CreateUserByName has no password field.
        final pw = await _http.post(
          '/Users/${adminPathSegment(id)}/Password',
          body: {'Id': id, 'NewPw': password, 'ResetPassword': false},
        );
        throwIfHttpError(pw);
      }
      // Both servers give a new user every library. The requested access
      // replaces that in the same policy write; if it fails the user goes,
      // because an account that sees everything is the unsafe side.
      await setUserLibraryAccess(id, allLibraries: allLibraries, libraryIds: libraryIds);
    } catch (e, st) {
      await _removeHalfCreatedUser(id, name, e);
      Error.throwWithStackTrace(e, st);
    }
    return ServerUser(
      id: id,
      name: dto['Name'] as String? ?? name,
      role: ServerUserRole.member,
      allLibraries: allLibraries,
      libraryIds: allLibraries ? const [] : libraryIds,
    );
  }

  /// Undo a create whose setup failed, so no open or passwordless account is
  /// left behind. A failed undo is its own error: the account still exists.
  Future<void> _removeHalfCreatedUser(String id, String name, Object cause) async {
    try {
      throwIfHttpError(await _http.delete('/Users/${adminPathSegment(id)}'));
    } catch (_) {
      throw _adminError('User "$name" was created, its setup failed ($cause) and it could not be removed');
    }
  }

  /// `/Users/{id}/Policy` replaces the whole policy, so the current one is
  /// read first and posted back with only the folder fields changed.
  Future<void> setUserLibraryAccess(
    String userId, {
    required bool allLibraries,
    List<String> libraryIds = const [],
  }) async {
    assertCanAdministerServer();
    final folders = allLibraries ? const <String>[] : await _policyFolderIds(libraryIds);
    final response = await _http.get('/Users/${adminPathSegment(userId)}');
    throwIfHttpError(response);
    final dto = response.data;
    final current = dto is Map<String, dynamic> ? dto['Policy'] : null;
    if (current is! Map<String, dynamic>) throw _adminError('User $userId has no policy');
    final policy = Map<String, dynamic>.of(current)
      ..['EnableAllFolders'] = allLibraries
      ..['EnabledFolders'] = folders;
    // Jellyfin ignores EnabledFolders while BlockedMediaFolders is non-empty.
    if (!connection.isEmby) policy['BlockedMediaFolders'] = const <String>[];
    assertCanAdministerServer();
    final update = await _http.post('/Users/${adminPathSegment(userId)}/Policy', body: policy);
    throwIfHttpError(update);
  }

  Future<void> deleteUser(String userId) async {
    assertCanAdministerServer();
    final response = await _http.delete('/Users/${adminPathSegment(userId)}');
    throwIfHttpError(response);
  }

  ServerUser _userFromDto(Map<String, dynamic> dto, Map<String, String>? guidToId) {
    final p = dto['Policy'];
    final policy = p is Map<String, dynamic> ? p : const <String, dynamic>{};
    final folders = (policy['EnabledFolders'] as List?)?.whereType<String>() ?? const <String>[];
    // An Emby folder Guid that maps to no library would vanish from the list;
    // replacing access from that list would then drop the grant. Unknown
    // beats incomplete.
    final unmapped = guidToId != null && folders.any((g) => !guidToId.containsKey(g));
    return ServerUser(
      id: dto['Id'] as String,
      name: dto['Name'] as String? ?? '',
      role: policy['IsAdministrator'] == true ? ServerUserRole.admin : ServerUserRole.member,
      disabled: policy['IsDisabled'] == true,
      allLibraries: policy['EnableAllFolders'] == true,
      libraryIds: guidToId == null ? folders.toList() : folders.map((g) => guidToId[g]).whereType<String>().toList(),
      libraryAccessKnown: !unmapped,
    );
  }

  /// App library ids to the ids a policy's `EnabledFolders` takes. Throws
  /// before any write when one of them is not a library on this server.
  Future<List<String>> _policyFolderIds(List<String> libraryIds) async {
    if (libraryIds.isEmpty) return const [];
    final Map<String, String> byAppId;
    if (connection.isEmby) {
      byAppId = {for (final e in (await _embyGuidToLibraryId()).entries) _folderKey(e.value): e.key};
    } else {
      final response = await _http.get('/Library/VirtualFolders');
      throwIfHttpError(response);
      final data = response.data;
      byAppId = {
        if (data is List)
          for (final f in data.whereType<Map<String, dynamic>>())
            if (f['ItemId'] is String) _folderKey(f['ItemId'] as String): f['ItemId'] as String,
      };
    }
    return [
      for (final id in libraryIds) byAppId[_folderKey(id)] ?? (throw _adminError('Library $id is not on this server')),
    ];
  }

  /// Guids may arrive with or without dashes; compare them in one form.
  String _folderKey(String id) => id.replaceAll('-', '').toLowerCase();

  /// Emby folder `Guid` to the folder `Id` the app uses as library id.
  Future<Map<String, String>> _embyGuidToLibraryId() async {
    final response = await _http.get('/Library/SelectableMediaFolders');
    throwIfHttpError(response);
    final data = response.data;
    return {
      if (data is List)
        for (final f in data.whereType<Map<String, dynamic>>())
          if (f['Guid'] is String && f['Id'] is String) f['Guid'] as String: f['Id'] as String,
    };
  }

  MediaServerHttpException _adminError(String message) =>
      MediaServerHttpException(type: MediaServerHttpErrorType.unknown, message: message);

  /// Everything playing on the server right now, every user's: an admin's
  /// `GET /Sessions` is not limited to its own. Same route and `SessionInfo`
  /// shape on Emby. Sessions without a `NowPlayingItem` are idle clients.
  Future<List<JellyfinActiveSession>> listActiveSessions() async {
    assertCanAdministerServer();
    final response = await _http.get('/Sessions');
    throwIfHttpError(response);
    final data = response.data;
    return [
      if (data is List)
        for (final s in data.whereType<Map<String, dynamic>>())
          if (s['NowPlayingItem'] case final Map<String, dynamic> item) _activeSession(s, item),
    ];
  }

  JellyfinActiveSession _activeSession(Map<String, dynamic> s, Map<String, dynamic> item) {
    final state = s['PlayState'] is Map<String, dynamic> ? s['PlayState'] as Map<String, dynamic> : const {};
    final position = state['PositionTicks'];
    final runtime = item['RunTimeTicks'];
    final isEpisode = item['Type'] == 'Episode';
    final season = item['ParentIndexNumber'], number = item['IndexNumber'];
    final name = item['Name'] as String?;
    final device = [?s['DeviceName'] as String?, ?s['Client'] as String?].join(' · ');
    return (
      userName: s['UserName'] as String? ?? '',
      title: (isEpisode ? item['SeriesName'] as String? : null) ?? name ?? '',
      episode: isEpisode ? [if (season is int && number is int) 'S$season · E$number', ?name].join(' ') : null,
      progressPercent: position is num && runtime is num && runtime > 0
          ? (position * 100 / runtime).round().clamp(0, 100).toInt()
          : 0,
      paused: state['IsPaused'] as bool?,
      transcoding: state['PlayMethod'] is String ? state['PlayMethod'] == 'Transcode' : null,
      device: device.isEmpty ? null : device,
    );
  }

  /// Films and episodes [userId] has finished, most recently played first,
  /// at most [limit]. Jellyfin scopes `/Items` by `userId`; Emby's `/Items`
  /// has no user parameter, so it takes `/Users/{id}/Items`.
  Future<List<JellyfinPlayedItem>> listPlayedItemsOf(String userId, {int limit = 200}) async {
    assertCanAdministerServer();
    final response = await _http.get(
      connection.isEmby ? '/Users/${adminPathSegment(userId)}/Items' : '/Items',
      queryParameters: {
        if (!connection.isEmby) 'userId': userId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Episode',
        'Filters': 'IsPlayed',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Limit': limit.toString(),
        'Fields': 'ProviderIds',
        'EnableUserData': 'true',
        'EnableImages': 'false',
      },
    );
    throwIfHttpError(response);
    final data = response.data;
    final items = data is Map<String, dynamic> ? data['Items'] : null;
    return [
      if (items is List)
        for (final i in items.whereType<Map<String, dynamic>>())
          if ((i['UserData'] is Map ? i['UserData']['LastPlayedDate'] : null) case final String played?)
            if (DateTime.tryParse(played) case final at? when i['Id'] is String)
              (
                id: i['Id'] as String,
                title: i['Name'] as String? ?? '',
                seriesId: i['Type'] == 'Episode' ? i['SeriesId'] as String? : null,
                seriesName: i['Type'] == 'Episode' ? i['SeriesName'] as String? : null,
                lastPlayed: at,
                year: i['Type'] == 'Movie' && i['ProductionYear'] is int ? i['ProductionYear'] as int : null,
                ids: i['Type'] == 'Movie' && i['ProviderIds'] is Map<String, dynamic>
                    ? ExternalIds.fromJellyfinProviderIds(i['ProviderIds'] as Map<String, dynamic>)
                    : null,
              ),
    ];
  }
}

/// Strict cohort reads use the current credential only. Jellyfin's exact
/// GetItem route delegates to IsVisibleStandalone (parents, parental policy,
/// tags and collection-folder access), unlike the batch IDs query shortcut.
/// Verified against v10.11.0 UserLibraryController.GetItem,
/// LibraryManager.ItemIsVisible and BaseItem.IsVisibleStandaloneInternal.
extension JellyfinParticipantEvidence on JellyfinClient {
  Future<void> assertRecommendationAdministrator({
    AbortController? abort,
    required void Function() checkCurrent,
  }) async {
    checkCurrent();
    assertCanAdministerServer();
    if (connection.isEmby) throw _adminError('Strict cohort evidence is unavailable on Emby');
    final response = await _http.get('/Users/Me', abort: abort);
    checkCurrent();
    assertCanAdministerServer();
    throwIfHttpError(response);
    final dto = response.data;
    final policy = dto is Map<String, dynamic> ? dto['Policy'] : null;
    if (dto is! Map<String, dynamic> ||
        dto['Id'] is! String ||
        !sameUserId(dto['Id'] as String, connection.userId) ||
        policy is! Map<String, dynamic> ||
        policy['IsAdministrator'] != true ||
        policy['IsDisabled'] != false) {
      throw _adminError('Live administrator evidence unavailable');
    }
  }

  Future<Map<String, ParticipantItemEvidence>> readParticipantEvidence(
    String userId,
    Map<String, String> itemLibraries, {
    AbortController? abort,
    required void Function() checkCurrent,
  }) async {
    await assertRecommendationAdministrator(abort: abort, checkCurrent: checkCurrent);
    final response = await _http.get('/Users/${adminPathSegment(userId)}', abort: abort);
    checkCurrent();
    assertCanAdministerServer();
    throwIfHttpError(response);
    final dto = response.data;
    final p = dto is Map<String, dynamic> ? dto['Policy'] : null;
    if (dto is! Map<String, dynamic> ||
        dto['Id'] is! String ||
        !sameUserId(dto['Id'] as String, userId) ||
        p is! Map<String, dynamic> ||
        p['IsDisabled'] is! bool ||
        p['EnableAllFolders'] is! bool ||
        p['EnabledFolders'] is! List ||
        (p['EnabledFolders'] as List).any((v) => v is! String)) {
      return {for (final id in itemLibraries.keys) id: const ParticipantItemEvidence()};
    }
    final enabled = (p['EnabledFolders'] as List).cast<String>().map(_folderKey).toSet();
    final evidence = <String, ParticipantItemEvidence>{};
    Future<void> readItem(MapEntry<String, String> entry) async {
      checkCurrent();
      assertCanAdministerServer();
      if (p['IsDisabled'] == true || (p['EnableAllFolders'] == false && !enabled.contains(_folderKey(entry.value)))) {
        evidence[entry.key] = const ParticipantItemEvidence(access: ParticipantAccess.denied);
        return;
      }
      final result = await _http.get(
        '/Items/${adminPathSegment(entry.key)}',
        queryParameters: {'userId': userId},
        abort: abort,
      );
      checkCurrent();
      assertCanAdministerServer();
      if (result.statusCode == 404) {
        // Denied or removed: neither is eligible. Do not turn an error into
        // an unwatched claim.
        evidence[entry.key] = const ParticipantItemEvidence(access: ParticipantAccess.denied);
        return;
      }
      throwIfHttpError(result);
      final data = result.data;
      if (data is! Map<String, dynamic> ||
          _folderKey(data['Id'] is String ? data['Id'] as String : '') != _folderKey(entry.key)) {
        evidence[entry.key] = const ParticipantItemEvidence();
        return;
      }
      final exactTopLibrary = data['ParentLibraryId'];
      // Only an absent top-library identity may inherit the catalog's
      // proved recursive query scope. ParentId can be an intermediate folder
      // and is not evidence of the top library. Explicit conflicts or malformed
      // top identities invalidate the source before any companion reads.
      if (exactTopLibrary != null &&
          (exactTopLibrary is! String ||
              exactTopLibrary.isEmpty ||
              _folderKey(exactTopLibrary) != _folderKey(entry.value))) {
        evidence[entry.key] = const ParticipantItemEvidence();
        return;
      }
      final userData = data['UserData'];
      final played = userData is Map<String, dynamic> ? userData['Played'] : null;
      final progress = userData is Map<String, dynamic> ? userData['PlaybackPositionTicks'] : null;
      final playCount = userData is Map<String, dynamic> ? userData['PlayCount'] : null;
      final started = (progress is num && progress > 0) || (playCount is num && playCount > 0);
      final malformedProgress = progress != null && (progress is! num || !progress.isFinite || progress < 0);
      final malformedCount =
          playCount != null &&
          (playCount is! num || !playCount.isFinite || playCount < 0 || playCount != playCount.roundToDouble());
      var watch = played is! bool || malformedProgress || malformedCount
          ? ParticipantWatchState.unknown
          : (played || started ? ParticipantWatchState.watched : ParticipantWatchState.unwatched);
      if (data['Type'] == 'Series' && watch != ParticipantWatchState.watched) {
        // Folder.FillUserDataDtoValues (Jellyfin v10.11.0, 1600-1635)
        // aggregates completed children, not started child progress. Even
        // percentage zero/all children unplayed cannot prove genuinely unseen.
        // A positive valid percentage proves some completed children; zero,
        // absent or malformed aggregate evidence cannot prove unseen series.
        final percentage = userData is Map<String, dynamic> ? userData['PlayedPercentage'] : null;
        watch = percentage is num && percentage.isFinite && percentage > 0 && percentage <= 100
            ? ParticipantWatchState.watched
            : ParticipantWatchState.unknown;
      }
      final item = JellyfinMappers.mediaItem(data, serverId: serverId, serverName: serverName, absolutizer: null);
      evidence[entry.key] = ParticipantItemEvidence(
        access: ParticipantAccess.allowed,
        watch: watch,
        item: item?.copyWith(libraryId: exactTopLibrary as String? ?? entry.value),
      );
    }

    final entries = itemLibraries.entries.toList();
    // Three exact reads at most, no persistent queue or executor. HTTP gets
    // the ask's abort signal; every completion checks the live context.
    for (var start = 0; start < entries.length; start += 3) {
      checkCurrent();
      await Future.wait(entries.skip(start).take(3).map(readItem));
      checkCurrent();
    }
    // A role change while a request was outstanding invalidates the whole
    // read. No participant data leaves the caller after revocation.
    await assertRecommendationAdministrator(abort: abort, checkCurrent: checkCurrent);
    return evidence;
  }

  /// Jellyfin writes one GUID with or without dashes, in either case.
  bool sameUserId(String a, String b) => _folderKey(a) == _folderKey(b);
}
