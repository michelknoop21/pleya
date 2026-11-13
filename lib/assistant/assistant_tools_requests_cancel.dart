part of 'assistant_tools.dart';

// Cancelling a request (BP-12t1). The same rule as the requests list
// ([SeerrRequestRights]): only the viewer's own request, and only while it is
// still pending. A manager may delete more on the server; Big P does not.

typedef _OwnRequests = ({List<int> cancellable, String? blocked});

/// The viewer's own pending requests for [shown] in the asked quality, read
/// fresh. [blocked] says why there is nothing to cancel: `not_requested`,
/// `not_yours`, `not_pending` or `request_status_unknown`.
Future<_OwnRequests> _ownPendingRequests(
  AssistantToolContext ctx,
  SeerrClient client,
  SeerrMedia shown,
  bool fourK,
) async {
  final previousUser = client.session.userId;
  final me = await _requestRead(ctx, client, client.getMe);
  final myId = me['id'];
  if (myId is! int || myId < 1 || (previousUser != null && myId != previousUser)) {
    throw const AssistantToolError('not_allowed');
  }
  _shownRequestUsers[ctx] ??= myId;
  _requestLive(ctx, client);
  final detail = await _requestRead(
    ctx,
    client,
    () => shown.isMovie ? client.getMovie(shown.tmdbId) : client.getTv(shown.tmdbId),
  );
  if (detail['id'] != shown.tmdbId) throw const AssistantToolError('request_status_unknown');
  final info = detail['mediaInfo'];
  if (info == null) return (cancellable: const <int>[], blocked: 'not_requested');
  if (info is! Map || info['requests'] is! List) {
    return (cancellable: const <int>[], blocked: 'request_status_unknown');
  }
  final mine = <int>[];
  var others = false, settled = false;
  for (final row in info['requests'] as List) {
    // A row this build cannot read proves nothing about whose it is.
    if (row is! Map || row['is4k'] is! bool || row['id'] is! int || row['status'] is! int) {
      return (cancellable: const <int>[], blocked: 'request_status_unknown');
    }
    if (row['is4k'] != fourK) continue;
    final by = row['requestedBy'];
    final own = by is Map && by['id'] == myId;
    if (!own) {
      others = true;
    } else if (row['status'] == 1) {
      mine.add(row['id'] as int);
    } else {
      settled = true;
    }
  }
  if (mine.isNotEmpty) return (cancellable: mine..sort(), blocked: null);
  return (
    cancellable: const <int>[],
    blocked: settled
        ? 'not_pending'
        : others
        ? 'not_yours'
        : 'not_requested',
  );
}

Future<AssistantToolOutcome> _cancelRequestCard(
  AssistantToolContext ctx,
  SeerrMedia shown, {
  required bool fourK,
}) async {
  final client = _seerr(ctx);
  _requestLive(ctx, client);
  final title = clipText(shown.title);
  final subject = shown.year == null ? title : '$title (${shown.year})';
  final found = await _ownPendingRequests(ctx, client, shown, fourK);
  if (found.blocked != null) {
    return AssistantToolResult({'status': found.blocked, 'title': subject, 'done': false, if (fourK) 'four_k': true});
  }
  final ids = List<int>.unmodifiable(found.cancellable);
  return AssistantPendingAction(
    kind: AssistantActionKind.cancelRequest,
    serverId: _seerrServerId,
    serverName: clipText(Uri.tryParse(client.session.baseUrl)?.host ?? 'Seerr', 64),
    subject: subject,
    items: [if (fourK) '4K'],
    execute: ({password}) async {
      _requestLive(ctx, client);
      // What the card showed has to be what is still there: a request that
      // was approved in the meantime is no longer the viewer's to cancel.
      final fresh = await _ownPendingRequests(ctx, client, shown, fourK);
      if (fresh.blocked != null) return {'status': fresh.blocked, 'title': subject, 'done': false};
      if (fresh.cancellable.length != ids.length || !fresh.cancellable.every(ids.contains)) {
        return {'error': 'request_changed', 'done': false};
      }
      var removed = 0;
      for (final id in ids) {
        try {
          await client.deleteRequest(id);
          removed++;
        } on SeerrException catch (e) {
          _requestLive(ctx, client);
          if (e.isAuth || e.isForbidden) throw const AssistantToolError('not_allowed');
          // The service may have taken a delete whose answer was lost.
          return {
            'error': e.isNetwork || (e.statusCode ?? 0) >= 500 ? 'cancel_outcome_unknown' : 'cancel_failed',
            'cancelled_requests': removed,
            'done': false,
          };
        }
        _requestLive(ctx, client);
      }
      ctx.requestedSeerrIds.remove('${shown.mediaType}:${shown.tmdbId}');
      final base = <String, Object?>{'cancelled': true, 'title': subject, if (fourK) 'four_k': true};
      try {
        final observed = await _readRequestState(ctx, client, shown, fourK);
        return {...base, 'status': observed.status};
      } on AssistantToolError catch (e) {
        _requestLive(ctx, client);
        return {...base, 'status': 'unknown', 'status_error': e.code};
      }
    },
  );
}
