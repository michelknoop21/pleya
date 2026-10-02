part of '../../jellyfin_client.dart';

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

  Future<ServerUser> createUser({required String name, String? password}) async {
    assertCanAdministerServer();
    final hasPassword = password != null && password.isNotEmpty;
    // Never a role above member: neither server makes a new user admin.
    final response = await _http.post(
      '/Users/New',
      body: {'Name': name, if (!connection.isEmby && hasPassword) 'Password': password},
    );
    throwIfHttpError(response);
    final dto = response.data;
    if (dto is! Map<String, dynamic> || dto['Id'] is! String) throw _adminError('Unexpected create-user response');
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
      // Both servers give a new user every library. Close that before the
      // account can be used; the caller grants what was asked for next.
      await setUserLibraryAccess(id, allLibraries: false);
    } catch (e, st) {
      await _removeHalfCreatedUser(id, name, e);
      Error.throwWithStackTrace(e, st);
    }
    return ServerUser(id: id, name: dto['Name'] as String? ?? name, role: ServerUserRole.member, allLibraries: false);
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
    return ServerUser(
      id: dto['Id'] as String,
      name: dto['Name'] as String? ?? '',
      role: policy['IsAdministrator'] == true ? ServerUserRole.admin : ServerUserRole.member,
      disabled: policy['IsDisabled'] == true,
      allLibraries: policy['EnableAllFolders'] == true,
      libraryIds: guidToId == null ? folders.toList() : folders.map((g) => guidToId[g]).whereType<String>().toList(),
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
}
