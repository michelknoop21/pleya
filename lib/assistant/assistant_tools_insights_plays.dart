part of 'assistant_tools.dart';

// The period readers of watch_stats, one per backend. Each returns that
// server's plays with the source's own account key; see assistant_tools_insights_watch.dart
// for how they are combined.

Future<_ServerPlays> _tautulliPlays(ServerId id, TautulliClient tautulli, int days) async {
  final after = _day(DateTime.now().subtract(Duration(days: days - 1)));
  final entries = <TautulliHistoryEntry>[];
  var capped = false;
  while (true) {
    final page = await tautulli.history(
      after: after,
      length: _historyPage,
      start: entries.length,
      // Grouped: consecutive plays of one item by one person are one view.
      grouping: true,
      orderColumn: 'date',
      orderDir: 'desc',
    );
    entries.addAll(page.entries);
    if (page.entries.length < _historyPage) break;
    if (entries.length >= _historyCap) {
      capped = true;
      break;
    }
  }
  return (
    plays: [
      // Music and live TV are not what "most watched" asks about.
      for (final e in entries)
        if (e.mediaType == 'movie' || e.mediaType == 'episode')
          (
            server: id.value,
            titleKey: _titleKey(e.mediaType == 'episode', _historyTitle(e)),
            title: clipText(_historyTitle(e)),
            userKey: e.userId != null ? 'id${e.userId}' : 'name${e.user ?? e.displayName}',
            user: clipText(e.displayName, 40),
            seconds: e.playSeconds ?? 0,
            named: true,
            // Tautulli reports plex.tv ids, global to the service.
            account: e.userId != null ? AssistantAccountKey(AssistantAccountProvider.plexTv, '${e.userId}') : null,
          ),
    ],
    hours: true,
    extra: <String, Object>{if (capped) 'capped_at_plays': _historyCap},
  );
}

/// Plex's own play log, for a server without a working Tautulli. One row per
/// completed view; no durations.
/// Null when the server does not answer within [_compareDeadline].
Future<_ServerPlays?> _plexPlays(ServerId id, PlexClient plex, String token, int days) async {
  final history = await _Budget(
    _compareDeadline,
  ).race(plex.fetchServerHistory(since: _periodStart(days), authToken: token, cap: _historyCap));
  if (history == null) return null;
  return (
    plays: [
      for (final p in history.plays)
        (
          server: id.value,
          titleKey: _titleKey(p.showTitle != null, p.showTitle ?? p.title),
          title: clipText(p.showTitle ?? p.title),
          userKey: 'id${p.accountId}',
          // Same fallback label as fetchItemWatchers when /accounts is silent.
          user: clipText(p.userName ?? 'User ${p.accountId}', 40),
          seconds: 0,
          named: p.userName != null,
          // The Plex server's own account numbering, valid on that server only.
          account: AssistantAccountKey(AssistantAccountProvider.plexServer, '${p.accountId}', serverId: id.value),
        ),
    ],
    hours: false,
    extra: <String, Object>{if (history.capped) 'capped_at_plays': _historyCap},
  );
}

/// Jellyfin and Emby keep no play log, only each user's last-played date per
/// item. Reads every user's recent finished plays (bounded per user and in
/// users, inside [_compareDeadline]) and keeps those in the period.
Future<_ServerPlays> _jellyfinPlays(ServerId id, JellyfinClient client, int days) async {
  final budget = _Budget(_compareDeadline);
  final from = _periodStart(days);
  final users = await budget.race(client.listUsers());
  var partial = users == null;
  var userCapped = false;
  final plays = <_Play>[];
  for (final user in (users ?? const <ServerUser>[]).take(_playsUserCap)) {
    final items = await budget.race(client.listPlayedItemsOf(user.id, limit: _playsPerUser));
    if (items == null) {
      partial = true;
      break;
    }
    // Newest first: a full read that still ends inside the period was cut off.
    if (items.length >= _playsPerUser && !items.last.lastPlayed.isBefore(from)) userCapped = true;
    for (final item in items) {
      if (item.lastPlayed.isBefore(from)) continue;
      plays.add((
        server: id.value,
        titleKey: _titleKey(item.seriesId != null, item.seriesName ?? item.title),
        title: clipText(item.seriesName ?? item.title),
        userKey: user.id,
        user: clipText(user.name, 40),
        seconds: 0,
        named: true,
        account: AssistantAccountKey(
          client.connection.isEmby ? AssistantAccountProvider.emby : AssistantAccountProvider.jellyfin,
          user.id,
          serverId: id.value,
        ),
      ));
    }
  }
  return (
    plays: plays,
    hours: false,
    extra: <String, Object>{
      if ((users?.length ?? 0) > _playsUserCap) 'capped_at_users': _playsUserCap,
      if (userCapped) 'capped_at_plays_per_user': _playsPerUser,
      if (partial) 'partial': true,
    },
  );
}

/// Pleya Server keeps, like Jellyfin, one watch state per user per item, so a
/// period is the same reading: each finished title once per user, at its last
/// touch. Null when the server predates `GET /watch-history` (DEC-143): any
/// 404 there means the route is missing, not that nobody watched.
Future<_ServerPlays?> _pleyaPlays(ServerId id, PleyaServerClient ps, int days) async {
  final from = _periodStart(days);
  final ({List<PleyaWatchedTitle> items, bool truncated}) history;
  try {
    history = await ps.watchHistory(days);
  } on MediaServerHttpException catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
  return (
    plays: [
      for (final w in history.items)
        if (!w.updatedAt.isBefore(from))
          (
            server: id.value,
            titleKey: _titleKey(w.seriesId != null, w.seriesTitle ?? w.title),
            title: clipText(w.seriesTitle ?? w.title),
            userKey: w.userId,
            user: clipText(w.userName, 40),
            seconds: 0,
            named: true,
            account: AssistantAccountKey(AssistantAccountProvider.pleyaServer, w.userId, serverId: id.value),
          ),
    ],
    hours: false,
    extra: <String, Object>{if (history.truncated) 'capped_at_plays': 1000},
  );
}
