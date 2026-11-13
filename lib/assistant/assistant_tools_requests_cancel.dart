part of 'assistant_tools.dart';

// Cancelling a request (BP-12t1). The same rule as the requests list
// ([SeerrRequestRights]): only the viewer's own request, and only while it is
// still pending. A manager may delete more on the server; Big P does not.

typedef _OwnRequests = ({List<int> cancellable, List<int> seasons, String? blocked});

const _OwnRequests _unreadableRequests = (cancellable: <int>[], seasons: <int>[], blocked: 'request_status_unknown');

/// The viewer's own pending requests for [shown] in the asked quality, read
/// fresh, with the seasons they cover. [blocked] says why there is nothing to
/// cancel: `not_requested`, `other_quality` (only the other quality has one),
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
  if (info == null) return (cancellable: const <int>[], seasons: const <int>[], blocked: 'not_requested');
  if (info is! Map || info['requests'] is! List) return _unreadableRequests;
  final mine = <int>[];
  final seasons = <int>{};
  var others = false, settled = false, otherQuality = false;
  for (final row in info['requests'] as List) {
    // A row this build cannot read proves nothing about whose it is.
    if (row is! Map || row['is4k'] is! bool || row['id'] is! int || row['status'] is! int) {
      return _unreadableRequests;
    }
    final by = row['requestedBy'];
    if (by is! Map || by['id'] is! int) return _unreadableRequests;
    final own = by['id'] == myId;
    if (row['is4k'] != fourK) {
      if (own && row['status'] == 1) otherQuality = true;
      continue;
    }
    if (!own) {
      others = true;
    } else if (row['status'] != 1) {
      settled = true;
    } else {
      mine.add(row['id'] as int);
      if (shown.isMovie) continue;
      // The card names the seasons that go, so they have to be readable.
      final covered = row['seasons'];
      if (covered is! List || covered.isEmpty) return _unreadableRequests;
      for (final season in covered) {
        if (season is! Map || season['seasonNumber'] is! int) return _unreadableRequests;
        seasons.add(season['seasonNumber'] as int);
      }
    }
  }
  if (mine.isNotEmpty) return (cancellable: mine..sort(), seasons: seasons.toList()..sort(), blocked: null);
  return (
    cancellable: const <int>[],
    seasons: const <int>[],
    blocked: settled
        ? 'not_pending'
        : others
        ? 'not_yours'
        : otherQuality
        ? 'other_quality'
        : 'not_requested',
  );
}

bool _sameInts(List<int> a, List<int> b) => a.length == b.length && a.every(b.contains);

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
    // A children's profile does not learn that someone else asked for a
    // title: request_status is closed to it for the same reason.
    final status = found.blocked == 'not_yours' && ctx.ageGate == AssistantAgeGate.kidsProfile
        ? 'not_requested'
        : found.blocked;
    return AssistantToolResult({'status': status, 'title': subject, 'done': false, if (fourK) 'four_k': true});
  }
  final ids = List<int>.unmodifiable(found.cancellable);
  final seasons = List<int>.unmodifiable(found.seasons);
  final key = '${shown.mediaType}:${shown.tmdbId}';
  return AssistantPendingAction(
    kind: AssistantActionKind.cancelRequest,
    serverId: _seerrServerId,
    serverName: clipText(Uri.tryParse(client.session.baseUrl)?.host ?? 'Seerr', 64),
    subject: subject,
    // Everything one yes takes away: every season of every own pending request.
    items: [
      for (final n in seasons) t.seerr.season(number: n),
      if (fourK) '4K',
    ],
    execute: ({password}) async {
      _requestLive(ctx, client);
      // What the card showed has to be what is still there: a request that
      // was approved in the meantime is no longer the viewer's to cancel.
      final fresh = await _ownPendingRequests(ctx, client, shown, fourK);
      if (fresh.blocked != null) return {'status': fresh.blocked, 'title': subject, 'done': false};
      if (!_sameInts(fresh.cancellable, ids) || !_sameInts(fresh.seasons, seasons)) {
        return {'error': 'request_changed', 'done': false};
      }
      var removed = 0;
      for (final id in ids) {
        try {
          await client.deleteRequest(id);
          removed++;
        } on SeerrException catch (e) {
          _requestLive(ctx, client);
          final refused = e.isAuth || e.isForbidden;
          // Nothing went yet: a plain refusal. Otherwise the model has to
          // hear how many did go, whatever stopped the rest.
          if (refused && removed == 0) throw const AssistantToolError('not_allowed');
          return {
            // The service may have taken a delete whose answer was lost.
            'error': refused
                ? 'not_allowed'
                : e.isNetwork || (e.statusCode ?? 0) >= 500
                ? 'cancel_outcome_unknown'
                : 'cancel_failed',
            'cancelled_requests': removed,
            'of_requests': ids.length,
            'done': false,
          };
        }
        _requestLive(ctx, client);
      }
      final base = <String, Object?>{
        'cancelled': true,
        'title': subject,
        if (seasons.isNotEmpty) 'seasons': seasons,
        if (fourK) 'four_k': true,
      };
      String status;
      Map<String, Object?> extra = const {};
      try {
        status = (await _readRequestState(ctx, client, shown, fourK)).status;
      } on AssistantToolError catch (e) {
        _requestLive(ctx, client);
        status = 'unknown';
        extra = {'status_error': e.code};
      }
      // The option cards carry the standard quality: a card built before the
      // cancel would still say "requested". Someone else's request may remain; a
      // status that could not be read changes no card.
      if (!fourK) {
        ctx.requestedSeerrIds.remove(key);
        final card = switch (status) {
          'pending' || 'processing' => 'requested',
          'unknown' => null,
          _ => status,
        };
        if (card != null) ctx.cancelledSeerrIds[key] = card;
      }
      return {...base, 'status': status, ...extra};
    },
  );
}
