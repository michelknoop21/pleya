part of 'assistant_tools.dart';

// What watch_stats reads per backend: Tautulli, Jellyfin/Emby, Pleya Server.

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A series counts as one title, named by Tautulli's `grandparent_title`.
String _historyTitle(TautulliHistoryEntry e) {
  final show = e.grandparentTitle;
  if (e.mediaType == 'episode' && show != null && show.isNotEmpty) return show;
  return e.fullTitle ?? '';
}

Future<AssistantToolResult> _watchedNow(AssistantToolContext ctx, ServerId id, TautulliClient tautulli) async {
  final name = ctx.serverName(id);
  final now = await const NowWatchingService().resolve(tautulli);
  if (now == null) throw const AssistantToolError('source_unavailable');
  final sessions = now.sessions.take(20).toList();
  return AssistantToolResult({
    'server': clipText(name),
    'sessions': [
      for (final s in sessions)
        {
          'user': clipText(s.userName, 40),
          'title': clipText(s.title),
          if (s.subtitle != null) 'episode': clipText(s.subtitle),
          'progress_percent': s.progressPercent,
          'paused': s.isPaused,
          'transcoding': s.isTranscoding,
          if (s.playerLabel != null) 'player': clipText(s.playerLabel, 40),
        },
    ],
  }, display: AssistantWatchStats(serverName: name, sessions: sessions));
}

/// Streams from Jellyfin, Emby or Pleya Server (one record shape). Ids are
/// positional: no server session id is passed on. Paused and transcoding are
/// left out where the server does not report them.
AssistantToolResult _streamsNow(AssistantToolContext ctx, ServerId id, List<JellyfinActiveSession> streams) {
  final name = ctx.serverName(id);
  final shown = streams.take(20).toList();
  return AssistantToolResult(
    {
      'server': clipText(name),
      'sessions': [
        for (final s in shown)
          {
            'user': clipText(s.userName, 40),
            'title': clipText(s.title),
            if (s.episode != null) 'episode': clipText(s.episode),
            'progress_percent': s.progressPercent,
            'paused': ?s.paused,
            'transcoding': ?s.transcoding,
            if (s.device != null) 'player': clipText(s.device, 40),
          },
      ],
    },
    display: AssistantWatchStats(
      serverName: name,
      sessions: [
        for (final (i, s) in shown.indexed)
          WatchSession(
            id: '$i',
            userName: s.userName,
            title: s.title,
            subtitle: s.episode,
            progressPercent: s.progressPercent,
            isPaused: s.paused ?? false,
            delivery: s.transcoding == true ? StreamDelivery.transcode : StreamDelivery.directPlay,
            playerLabel: s.device,
          ),
      ],
    ),
  );
}

Future<AssistantToolResult> _watchedPeriod(
  AssistantToolContext ctx,
  ServerId id,
  TautulliClient tautulli,
  int days,
) async {
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

  return _periodResult(
    ctx.serverName(id),
    days,
    [
      // Music and live TV are not what "most watched" asks about.
      for (final e in entries)
        if (e.mediaType == 'movie' || e.mediaType == 'episode')
          (
            titleKey: e.mediaType == 'episode' ? 'g${e.grandparentRatingKey}' : 'r${e.ratingKey}',
            title: clipText(_historyTitle(e)),
            userKey: e.userId != null ? 'id${e.userId}' : 'name${e.user ?? e.displayName}',
            user: clipText(e.displayName, 40),
            seconds: e.playSeconds ?? 0,
          ),
    ],
    extra: {if (capped) 'capped_at_plays': _historyCap},
  );
}

/// Jellyfin and Emby keep no play log, only each user's last-played date per
/// item. Reads every user's recent finished plays (bounded per user and in
/// users, inside [_compareDeadline]) and keeps those in the period.
Future<AssistantToolResult> _jellyfinPeriod(
  AssistantToolContext ctx,
  ServerId id,
  JellyfinClient client,
  int days,
) async {
  final budget = _Budget(_compareDeadline);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day - (days - 1));
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
        titleKey: item.seriesId != null ? 's${item.seriesId}' : 'i${item.id}',
        title: clipText(item.seriesName ?? item.title),
        userKey: user.id,
        user: clipText(user.name, 40),
        seconds: 0,
      ));
    }
  }
  return _periodResult(
    ctx.serverName(id),
    days,
    plays,
    hours: false,
    extra: {
      if ((users?.length ?? 0) > _playsUserCap) 'capped_at_users': _playsUserCap,
      if (userCapped) 'capped_at_plays_per_user': _playsPerUser,
      if (partial) 'partial': true,
    },
  );
}

/// Top titles (a series counts once, under its name) and top users.
AssistantToolResult _periodResult(
  String name,
  int days,
  List<_Play> plays, {
  bool hours = true,
  Map<String, Object> extra = const {},
}) {
  final titles = <String, ({String title, int plays, Set<String> viewers})>{};
  final users = <String, ({String name, int plays, int seconds})>{};
  for (final p in plays) {
    final t = titles[p.titleKey];
    titles[p.titleKey] = (title: t?.title ?? p.title, plays: (t?.plays ?? 0) + 1, viewers: {...?t?.viewers, p.user});
    final u = users[p.userKey];
    users[p.userKey] = (name: u?.name ?? p.user, plays: (u?.plays ?? 0) + 1, seconds: (u?.seconds ?? 0) + p.seconds);
  }
  final topTitles = [
    for (final t in titles.values.toList()..sort((a, b) => b.plays.compareTo(a.plays)))
      (title: t.title, plays: t.plays, viewers: t.viewers.toList()),
  ];
  final topUsers = [
    for (final u in users.values.toList()..sort((a, b) => b.plays.compareTo(a.plays)))
      (name: u.name, plays: u.plays, seconds: u.seconds),
  ];
  return AssistantToolResult({
    'server': clipText(name),
    'days': days,
    'plays': plays.length,
    'top_titles': [
      for (final t in topTitles.take(10)) {'title': t.title, 'plays': t.plays, 'viewers': t.viewers.take(5).toList()},
    ],
    'top_users': [
      for (final u in topUsers.take(10))
        {'user': u.name, 'plays': u.plays, if (hours) 'hours': (u.seconds / 3600).round()},
    ],
    ...extra,
  }, display: AssistantWatchStats(serverName: name, days: days, titles: topTitles, users: topUsers));
}
