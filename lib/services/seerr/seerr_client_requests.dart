part of 'seerr_client.dart';

/// Request endpoints (`/request`, `/service/*`) for [SeerrClient], kept in a
/// part so they share the client's private transport.
extension SeerrClientRequests on SeerrClient {
  /// `POST /request`. [seasons] is only sent for TV; pass a list of season
  /// numbers. Advanced (admin) options are optional.
  Future<void> createRequest({
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
    final resp = await _send(() => _http.post('/request', body: body, headers: _authHeaders()));
    _throwIfError(resp);
  }

  /// `GET /request/count`. Feeds the counts next to the filter tabs. Returns
  /// zeros when the server does not answer, so the tabs degrade to plain labels
  /// instead of the screen failing over a decoration.
  Future<({int total, int pending, int approved, int available, int processing})> getRequestCounts() async {
    const empty = (total: 0, pending: 0, approved: 0, available: 0, processing: 0);
    try {
      final resp = await _send(() => _http.get('/request/count', headers: _authHeaders()));
      final data = resp.data;
      if (data is! Map) return empty;
      return (
        total: SeerrClient._int(data['total']) ?? 0,
        pending: SeerrClient._int(data['pending']) ?? 0,
        approved: SeerrClient._int(data['approved']) ?? 0,
        available: SeerrClient._int(data['available']) ?? 0,
        processing: SeerrClient._int(data['processing']) ?? 0,
      );
    } catch (_) {
      return empty;
    }
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
    if (data is! Map) return (items: const <SeerrRequest>[], totalPages: 1);
    final results = data['results'];
    final items = <SeerrRequest>[];
    if (results is List) {
      for (final r in results) {
        if (r is Map) {
          final req = SeerrRequest.tryFromJson(r.cast<String, dynamic>());
          if (req != null) items.add(req);
        }
      }
    }
    final pageInfo = data['pageInfo'];
    final totalPages = pageInfo is Map ? SeerrClient._int(pageInfo['pages']) ?? 1 : 1;
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

  Future<void> updateRequest(int id, {List<int>? seasons, bool? is4k}) async {
    final body = <String, dynamic>{'seasons': ?seasons, 'is4k': ?is4k};
    final resp = await _send(() => _http.put('/request/$id', body: body, headers: _authHeaders()));
    _throwIfError(resp);
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
