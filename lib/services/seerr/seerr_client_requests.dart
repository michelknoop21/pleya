part of 'seerr_client.dart';

/// Request endpoints (`/request`, `/service/*`) for [SeerrClient], kept in a
/// part so they share the client's private transport.
extension SeerrClientRequests on SeerrClient {
  /// `POST /request`. [seasons] is only sent for TV; pass a list of season
  /// numbers. Advanced (admin) options are optional.
  Future<Map<String, dynamic>> createRequest({
    required String mediaType,
    required int tmdbId,
    List<int>? seasons,
    bool is4k = false,
    int? serverId,
    int? profileId,
    String? rootFolder,
  }) async {
    final body = <String, dynamic>{
      'mediaType': mediaType,
      'mediaId': tmdbId,
      'is4k': is4k,
      if (mediaType == 'tv' && seasons != null) 'seasons': seasons,
      'serverId': ?serverId,
      'profileId': ?profileId,
      'rootFolder': ?rootFolder,
    };
    final MediaServerResponse resp;
    try {
      resp = await _send(() => _http.post('/request', body: body, headers: _authHeaders()));
    } on SeerrException catch (e) {
      // A 2xx response can be accepted even when its JSON body is unreadable.
      // Keep that evidence distinct from a response lost on the transport.
      if (e.isNetwork && e.statusCode != null && e.statusCode! >= 200 && e.statusCode! < 300) return const {};
      rethrow;
    }
    _throwIfError(resp);
    return resp.data is Map ? (resp.data as Map).cast<String, dynamic>() : const {};
  }

  /// `GET /request/count`. Null when the server does not answer or sends no
  /// object, so a caller can tell "not counted" from "none".
  ///
  /// The route takes no `requestedBy`: these are every user's requests.
  Future<SeerrRequestCounts?> getRequestCounts() async {
    try {
      final resp = await _send(() => _http.get('/request/count', headers: _authHeaders()));
      final data = resp.data;
      if (data is! Map) return null;
      return (
        total: SeerrClient._int(data['total']),
        pending: SeerrClient._int(data['pending']),
        approved: SeerrClient._int(data['approved']),
        available: SeerrClient._int(data['available']),
        processing: SeerrClient._int(data['processing']),
      );
    } catch (_) {
      return null;
    }
  }

  /// `GET /request/{id}`: one request as the server holds it now.
  Future<SeerrRequest?> getRequest(int id) async {
    final resp = await _send(() => _http.get('/request/$id', headers: _authHeaders()));
    final data = resp.data;
    return data is Map ? SeerrRequest.tryFromJson(data.cast<String, dynamic>()) : null;
  }

  /// `GET /request`. [filter] is one of all/pending/approved/processing/
  /// available/unavailable. [requestedBy] scopes to a user (own requests).
  Future<({List<SeerrRequest> items, int totalPages})> getRequests({
    String filter = 'all',
    int page = 1,
    int take = 20,
    int? requestedBy,
  }) async {
    final resp = await _send(
      () => _http.get(
        '/request',
        queryParameters: {
          'take': take,
          'skip': (page - 1) * take,
          'filter': filter,
          'sort': 'added',
          'requestedBy': ?requestedBy,
        },
        headers: _authHeaders(),
      ),
    );
    final data = resp.data;
    if (data is! Map || data['results'] is! List || data['pageInfo'] is! Map) {
      throw const SeerrException('unreadable request list');
    }
    final results = data['results'] as List;
    final rawPages = (data['pageInfo'] as Map)['pages'];
    final totalPages = rawPages is int ? rawPages : null;
    if (totalPages == null || totalPages < 0 || (totalPages == 0 && results.isNotEmpty)) {
      throw const SeerrException('unreadable request pagination');
    }
    final items = <SeerrRequest>[];
    final ids = <int>{};
    for (final row in results) {
      final request = row is Map ? SeerrRequest.tryFromJson(row.cast<String, dynamic>()) : null;
      // Dropping an unreadable neighbour or collapsing a duplicate would make
      // this list's apparent completeness false evidence of absence.
      if (request == null || request.id <= 0 || !ids.add(request.id))
        throw const SeerrException('unreadable request row');
      items.add(request);
    }
    return (items: items, totalPages: totalPages);
  }

  /// Fills in the title, year and artwork that `/request` does not return.
  ///
  /// Overseerr's request payload embeds the `media` row (tmdb id, availability,
  /// timestamps) and nothing that names the title, so a request list on its own
  /// can only say "movie" or "show". Its own web frontend resolves each row
  /// against `/movie/{id}` or `/tv/{id}`; this does the same, cached per title
  /// and a few at a time so a page of twenty does not open twenty sockets.
  ///
  /// Best effort by design: a lookup that fails leaves that row exactly as it
  /// came in. A request must still be listed, and still be cancellable, when
  /// the metadata service is having a bad day.
  Future<List<SeerrRequest>> hydrateRequests(List<SeerrRequest> items) async {
    final wanted = <String, ({int tmdbId, bool isMovie})>{};
    for (final r in items) {
      final tmdbId = r.tmdbId;
      if (tmdbId == null || !r.needsDisplayData) continue;
      final key = '${r.mediaType}:$tmdbId';
      if (_displayCache.containsKey(key)) continue;
      wanted[key] = (tmdbId: tmdbId, isMovie: r.mediaType != 'tv');
    }

    if (wanted.isNotEmpty) {
      const maxInFlight = 6;
      final entries = wanted.entries.toList();
      for (var i = 0; i < entries.length; i += maxInFlight) {
        final batch = entries.skip(i).take(maxInFlight);
        await Future.wait(batch.map((e) => _cacheDisplay(e.key, e.value.tmdbId, e.value.isMovie)));
      }
    }

    return [
      for (final r in items)
        if (r.tmdbId == null || !r.needsDisplayData)
          r
        else
          switch (_displayCache['${r.mediaType}:${r.tmdbId}']) {
            final d? => r.withDisplayData(
              title: d.title,
              year: d.year,
              posterPath: d.posterPath,
              backdropPath: d.backdropPath,
            ),
            null => r,
          },
    ];
  }

  Future<void> _cacheDisplay(String key, int tmdbId, bool isMovie) {
    final running = _displayInFlight[key];
    if (running != null) return running;
    // Block body, not an arrow: `remove` hands back the very future being
    // awaited here, and whenComplete waits on a returned future -- so an arrow
    // makes this wait on itself and never completes.
    final future = _fetchDisplay(key, tmdbId, isMovie).whenComplete(() {
      _displayInFlight.remove(key);
    });
    _displayInFlight[key] = future;
    return future;
  }

  Future<void> _fetchDisplay(String key, int tmdbId, bool isMovie) async {
    try {
      final json = isMovie ? await getMovie(tmdbId) : await getTv(tmdbId);
      final media = SeerrMedia.fromDetail(json, mediaType: isMovie ? 'movie' : 'tv');
      _displayCache[key] = _SeerrMediaDisplay(
        title: media.title.isEmpty ? null : media.title,
        year: media.year,
        posterPath: media.posterPath,
        backdropPath: media.backdropPath,
      );
    } catch (e) {
      // One unreachable title must not take the list down with it.
      appLogger.d('seerr: could not resolve $key for the request list: $e');
    }
  }

  /// `PUT /request/{id}`. Returns false when the server accepted the call but
  /// saved nothing (202, no season left to request).
  ///
  /// The route only acts on a `mediaType` of movie or tv, and it assigns the
  /// target fields from the body whether they are there or not. So every call
  /// names the type and passes the target of [current] back, unless [target]
  /// replaces it.
  /// `is4k` and `userId` are deliberately absent: the route ignores the first,
  /// and the second would move the request to another user.
  Future<bool> updateRequest(SeerrRequest current, {List<int>? seasons, SeerrRequestTarget? target}) async {
    if (!current.isReliableReadback || !current.targetKnown || !current.advancedKnown) {
      throw const SeerrException('unreadable stored request');
    }
    final isTv = current.mediaType == 'tv';
    final body = <String, dynamic>{
      'mediaType': isTv ? 'tv' : 'movie',
      // A given target replaces all three together: a profile or folder of the
      // previous server means nothing on another one.
      'serverId': ?(target == null ? current.serverId : target.serverId),
      'profileId': ?(target == null ? current.profileId : target.profileId),
      'rootFolder': ?(target == null ? current.rootFolder : target.rootFolder),
      'tags': ?current.tags,
      if (isTv) 'languageProfileId': ?current.languageProfileId,
      if (isTv) 'seasons': [...(seasons ?? current.seasons)]..sort(),
    };
    final resp = await _send(() => _http.put('/request/${current.id}', body: body, headers: _authHeaders()));
    _throwIfError(resp);
    return resp.statusCode != 202;
  }

  Future<void> deleteRequest(int id) async {
    final resp = await _send(() => _http.delete('/request/$id', headers: _authHeaders()));
    _throwIfError(resp);
  }

  Future<void> approveRequest(int id) async {
    final resp = await _send(() => _http.post('/request/$id/approve', headers: _authHeaders()));
    _throwIfError(resp);
  }

  Future<void> declineRequest(int id) async {
    final resp = await _send(() => _http.post('/request/$id/decline', headers: _authHeaders()));
    _throwIfError(resp);
  }

  Future<List<SeerrServiceServer>> getRadarrServers() => _serviceServers('/service/radarr');
  Future<List<SeerrServiceServer>> getSonarrServers() => _serviceServers('/service/sonarr');

  Future<List<SeerrServiceServer>> _serviceServers(String path) async {
    final resp = await _send(() => _http.get(path, headers: _authHeaders()));
    return SeerrServiceServer.listFrom(resp.data);
  }

  /// Quality profiles and root folders for one Radarr/Sonarr server.
  ///
  /// The list endpoints above only name the servers; the profiles a user
  /// created in Radarr or Sonarr live behind this per-server call, which is why
  /// the request sheet could never offer them.
  Future<SeerrServiceServerDetail> getRadarrServerDetail(int serverId) =>
      _serviceServerDetail('/service/radarr', serverId);
  Future<SeerrServiceServerDetail> getSonarrServerDetail(int serverId) =>
      _serviceServerDetail('/service/sonarr', serverId);

  Future<SeerrServiceServerDetail> _serviceServerDetail(String path, int serverId) async {
    final resp = await _send(() => _http.get('$path/$serverId', headers: _authHeaders()));
    final data = resp.data;
    if (data is! Map) return const SeerrServiceServerDetail();
    return SeerrServiceServerDetail.fromJson(data.cast<String, dynamic>());
  }
}

/// Cached display fields for one title, keyed by `mediaType:tmdbId`.
class _SeerrMediaDisplay {
  const _SeerrMediaDisplay({this.title, this.year, this.posterPath, this.backdropPath});

  final String? title;
  final String? year;
  final String? posterPath;
  final String? backdropPath;
}
