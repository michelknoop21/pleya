part of 'seerr_client.dart';

extension SeerrClientIssues on SeerrClient {
  bool get canManageIssues => SeerrPermission.has(session.permissions, SeerrPermission.manageIssues);
  bool get canViewAllIssues => canManageIssues || SeerrPermission.has(session.permissions, SeerrPermission.viewIssues);
  bool get canViewIssues =>
      canViewAllIssues ||
      (session.userId != null && SeerrPermission.has(session.permissions, SeerrPermission.createIssues));

  bool canReplyToIssue(SeerrIssue issue) =>
      canManageIssues ||
      (session.userId != null &&
          issue.creatorId == session.userId &&
          SeerrPermission.has(session.permissions, SeerrPermission.createIssues));

  Future<({List<SeerrIssue> items, bool hasMore})> getIssues({
    SeerrIssueStatus? status,
    bool ownOnly = true,
    int page = 1,
  }) async {
    final user = session.userId;
    final scoped = ownOnly || !canViewAllIssues;
    if (!canViewIssues || (scoped && user == null)) throw SeerrException.forbidden();
    const take = 20;
    final response = await _send(
      () => _http.get(
        '/issue',
        headers: _authHeaders(),
        queryParameters: {
          'take': take,
          'skip': (page - 1) * take,
          'sort': 'modified',
          if (status != null) 'filter': status.name,
          if (scoped) 'createdBy': user,
        },
      ),
    );
    final data = response.data;
    if (data is! Map || data['results'] is! List) throw const FormatException('Invalid Seerr issues response');
    if (session.userId != user || !canViewIssues || (!scoped && !canViewAllIssues)) {
      throw SeerrException.forbidden();
    }
    final results = data['results'] as List;
    final info = data['pageInfo'];
    final pages = info is Map ? SeerrClient._int(info['pages']) : null;
    return (
      items: [
        for (final row in results) ?_parseRow(row),
      ].where((issue) => (!scoped || issue.creatorId == user) && (status == null || issue.status == status)).toList(),
      hasMore: pages == null ? results.length == take : page < pages,
    );
  }

  /// One malformed row (unknown status, bad id) must not take the page down.
  SeerrIssue? _parseRow(Object? row) {
    if (row is! Map) return null;
    try {
      return SeerrIssue.fromJson(row.cast<String, dynamic>());
    } on FormatException catch (e) {
      appLogger.w('seerr: skipping an unreadable issue row: ${e.message}');
      return null;
    }
  }

  Future<SeerrIssue> getIssue(int id) async {
    if (!canViewIssues || id <= 0) throw SeerrException.forbidden();
    final user = session.userId;
    final data = await _detail('/issue/$id');
    final issue = SeerrIssue.fromJson(data);
    if (!canViewIssues ||
        issue.id != id ||
        session.userId != user ||
        (!canViewAllIssues && (user == null || issue.creatorId != user))) {
      throw SeerrException.forbidden();
    }
    return issue;
  }

  Future<void> replyToIssue(SeerrIssue issue, String message) async {
    if (!canReplyToIssue(issue)) throw SeerrException.forbidden();
    final text = message.trim();
    if (text.isEmpty) throw ArgumentError.value(message, 'message');
    final response = await _rawSend(
      () => _http.post('/issue/${issue.id}/comment', headers: _authHeaders(), body: {'message': text}),
    );
    _throwIfError(response);
  }

  Future<void> setIssueStatus(SeerrIssue issue, SeerrIssueStatus status) async {
    if (!canManageIssues) throw SeerrException.forbidden();
    final response = await _rawSend(() => _http.post('/issue/${issue.id}/${status.name}', headers: _authHeaders()));
    _throwIfError(response);
  }

  Future<({String? title, String? posterUrl})> issueMedia(SeerrIssue issue) async {
    final type = issue.mediaType;
    final id = issue.tmdbId;
    if (id == null || (type != 'tv' && type != 'movie')) return (title: null, posterUrl: null);
    final key = '$type:$id';
    if (!_displayCache.containsKey(key)) await _cacheDisplay(key, id, type == 'movie');
    final display = _displayCache[key];
    return (title: display?.title, posterUrl: SeerrConstants.tmdbPosterUrl(display?.posterPath));
  }
}
