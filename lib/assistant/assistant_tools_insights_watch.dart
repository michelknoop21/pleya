part of 'assistant_tools.dart';

// What watch_stats reads per backend (Tautulli, Plex itself, Jellyfin/Emby,
// Pleya Server) and how the servers fold into one answer.

/// A server's plays for a period. [hours] is false where the server reports
/// no durations.
typedef _ServerPlays = ({List<_Play> plays, bool hours, Map<String, Object> extra});

/// Administered servers that can answer right now: a paired Tautulli, or a
/// backend that reports activity itself.
List<ServerId> _watchServers(AssistantToolContext ctx) => [
  for (final id in ctx.administeredServers)
    if (ctx.adminClient(id) case final client?)
      if (ctx.insights?.tautulliFor(id) != null ||
          client is PlexClient ||
          client is JellyfinClient ||
          client is PleyaServerClient)
        id,
];

/// Repeat calls in one run answer the model but add no second card.
final _watchShown = Expando<Set<String>>();

AssistantDisplay? _onceInRun(AssistantToolContext ctx, String key, AssistantDisplay display) =>
    (_watchShown[ctx] ??= {}).add(key) ? display : null;

/// The owner token Plex's history and session routes need, as the detail
/// screen's "Watched by" row uses it.
String? _plexOwnerToken(AssistantToolContext ctx, ServerId id) {
  final token = ctx.servers.getPlexServer(id)?.accessToken;
  return token == null || token.isEmpty ? null : token;
}

/// Each server read in parallel; a server that fails or has no source is
/// null, so one bad server never sinks the others.
Future<List<(ServerId, T?)>> _perServer<T>(AssistantToolContext ctx, Future<T?> Function(ServerId id) read) =>
    Future.wait([
      for (final id in _watchServers(ctx))
        read(id).then<(ServerId, T?)>(
          (v) => (id, v),
          onError: (Object e, StackTrace st) {
            appLogger.d('watch_stats: ${ctx.servers.getClient(id)?.backend.name} could not answer', error: e);
            return (id, null);
          },
        ),
    ]);

Map<String, Object?> _unavailableEntry(AssistantToolContext ctx, ServerId id) => {
  'server': clipText(ctx.serverName(id)),
  'backend': ?ctx.servers.getClient(id)?.backend.name,
};

String _servedLabel(AssistantToolContext ctx, List<ServerId> answered, List<ServerId> unavailable) =>
    (answered.isEmpty ? unavailable : answered).map(ctx.serverName).join(', ');

// ---------------------------------------------------------------- now

Future<List<JellyfinActiveSession>?> _streamsOn(AssistantToolContext ctx, ServerId id) async {
  // Tautulli answers only for the Plex server it monitors.
  if (ctx.insights?.tautulliFor(id) case final tautulli?) {
    final now = await const NowWatchingService().resolve(tautulli);
    if (now != null) {
      return [
        for (final s in now.sessions)
          (
            userName: s.userName,
            title: s.title,
            episode: s.subtitle,
            progressPercent: s.progressPercent,
            paused: s.isPaused,
            transcoding: s.isTranscoding,
            device: s.playerLabel,
          ),
      ];
    }
    // Tautulli down or behind a login page: Plex itself still knows.
  }
  return switch (ctx.adminClient(id)) {
    final JellyfinClient jf => jf.listActiveSessions(),
    final PleyaServerClient ps => ps.streamSessions(),
    final PlexClient plex => switch (_plexOwnerToken(ctx, id)) {
      final token? => plex.fetchActiveStreams(authToken: token),
      null => null,
    },
    _ => null,
  };
}

/// Streams on every server. Ids are positional: no server session id is
/// passed on. Paused and transcoding are left out where a server does not say.
Future<AssistantToolResult> _watchedNow(AssistantToolContext ctx) async {
  final read = await _perServer(ctx, (id) => _streamsOn(ctx, id));
  final answered = [
    for (final (id, s) in read)
      if (s != null) id,
  ];
  final unavailable = [
    for (final (id, s) in read)
      if (s == null) id,
  ];
  final shown = [
    for (final (id, streams) in read)
      for (final s in streams ?? const <JellyfinActiveSession>[]) (server: ctx.serverName(id), s: s),
  ].take(20).toList();
  return AssistantToolResult(
    {
      'servers': [for (final id in answered) clipText(ctx.serverName(id))],
      'sessions': [
        for (final (:server, :s) in shown)
          {
            'server': clipText(server),
            'user': clipText(s.userName, 40),
            'title': clipText(s.title),
            if (s.episode != null) 'episode': clipText(s.episode),
            'progress_percent': s.progressPercent,
            'paused': ?s.paused,
            'transcoding': ?s.transcoding,
            if (s.device != null) 'player': clipText(s.device, 40),
          },
      ],
      if (unavailable.isNotEmpty) 'unavailable': [for (final id in unavailable) _unavailableEntry(ctx, id)],
    },
    display: _onceInRun(
      ctx,
      'now',
      AssistantWatchStats(
        serverName: _servedLabel(ctx, answered, unavailable),
        unavailable: [for (final id in unavailable) ctx.serverName(id)],
        sessions: [
          for (final (i, (:server, :s)) in shown.indexed)
            WatchSession(
              id: '$i',
              userName: s.userName,
              // Several servers in one card: say where each stream runs.
              title: answered.length > 1 ? '${s.title} · $server' : s.title,
              subtitle: s.episode,
              progressPercent: s.progressPercent,
              isPaused: s.paused ?? false,
              delivery: s.transcoding == true ? StreamDelivery.transcode : StreamDelivery.directPlay,
              playerLabel: s.device,
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- period

/// The unified catalog's identity at title level (its bucket rules): kind
/// plus normalized title.
// ponytail: no watch source carries a guid or a year, so two different films
// sharing a title merge here; add guid/year once the history rows carry them.
String _titleKey(bool series, String title) =>
    (series ? CanonicalMediaIdentity.show(title: title) : CanonicalMediaIdentity.movie(title: title)).bucketKey ??
    '${series ? 'show' : 'movie'}:raw:$title';

DateTime _periodStart(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (days - 1));
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A series counts as one title, named by Tautulli's `grandparent_title`.
String _historyTitle(TautulliHistoryEntry e) {
  final show = e.grandparentTitle;
  if (e.mediaType == 'episode' && show != null && show.isNotEmpty) return show;
  return e.fullTitle ?? '';
}

Future<_ServerPlays?> _playsOn(AssistantToolContext ctx, ServerId id, int days) async {
  if (ctx.insights?.tautulliFor(id) case final tautulli?) {
    try {
      return await _tautulliPlays(id, tautulli, days);
    } catch (e) {
      // Not answering for this server after all, or behind Cloudflare Access.
      appLogger.d('watch_stats: Tautulli history unavailable, asking the server', error: e);
    }
  }
  return switch (ctx.adminClient(id)) {
    final JellyfinClient jf => _jellyfinPlays(id, jf, days),
    final PleyaServerClient ps => _pleyaPlays(id, ps, days),
    final PlexClient plex => switch (_plexOwnerToken(ctx, id)) {
      final token? => _plexPlays(id, plex, token, days),
      null => null,
    },
    _ => null,
  };
}

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
          ),
    ],
    hours: false,
    extra: <String, Object>{if (history.truncated) 'capped_at_plays': 1000},
  );
}

/// Top titles and users over every server that answered. A title is one
/// entry by identity ([_titleKey]); a person is one entry by name across
/// servers, while two accounts on one server that share a name stay two.
Future<AssistantToolResult> _watchedPeriod(AssistantToolContext ctx, int days) async {
  final read = await _perServer(ctx, (id) => _playsOn(ctx, id, days));
  final answered = [
    for (final (id, r) in read)
      if (r != null) id,
  ];
  final unavailable = [
    for (final (id, r) in read)
      if (r == null) id,
  ];
  final served = [for (final (_, r) in read) ?r];
  final plays = [for (final r in served) ...r.plays];
  final hours = served.isNotEmpty && served.every((r) => r.hours);

  final titles = <String, ({String title, int plays, Set<String> viewers})>{};
  final users = <String, ({String name, int plays, int seconds})>{};
  final personOf = <String, String>{};
  final serversOfPerson = <String, Set<String>>{};
  String person(_Play p) => personOf['${p.server}|${p.userKey}'] ??= () {
    // An unnamed account ("User 7") is that server's own: never merged by label.
    if (!p.named) return '${p.server}|${p.userKey}';
    for (var i = 0; ; i++) {
      final key = '${p.user.toLowerCase()}#$i';
      if ((serversOfPerson[key] ??= {}).add(p.server)) return key;
    }
  }();
  for (final p in plays) {
    final t = titles[p.titleKey];
    titles[p.titleKey] = (title: t?.title ?? p.title, plays: (t?.plays ?? 0) + 1, viewers: {...?t?.viewers, p.user});
    final key = person(p);
    final u = users[key];
    users[key] = (name: u?.name ?? p.user, plays: (u?.plays ?? 0) + 1, seconds: (u?.seconds ?? 0) + p.seconds);
  }
  final topTitles = [
    for (final t in titles.values.toList()..sort((a, b) => b.plays.compareTo(a.plays)))
      (title: t.title, plays: t.plays, viewers: t.viewers.toList()),
  ];
  final topUsers = users.values.toList()..sort((a, b) => b.plays.compareTo(a.plays));
  return AssistantToolResult(
    {
      'servers': [for (final id in answered) clipText(ctx.serverName(id))],
      'days': days,
      'plays': plays.length,
      'top_titles': [
        for (final t in topTitles.take(10)) {'title': t.title, 'plays': t.plays, 'viewers': t.viewers.take(5).toList()},
      ],
      'top_users': [
        for (final u in topUsers.take(10))
          {'user': u.name, 'plays': u.plays, if (hours) 'hours': (u.seconds / 3600).round()},
      ],
      if (unavailable.isNotEmpty) 'unavailable': [for (final id in unavailable) _unavailableEntry(ctx, id)],
      for (final r in served) ...r.extra,
    },
    display: _onceInRun(
      ctx,
      'period/$days',
      AssistantWatchStats(
        serverName: _servedLabel(ctx, answered, unavailable),
        days: days,
        titles: topTitles,
        users: topUsers,
        unavailable: [for (final id in unavailable) ctx.serverName(id)],
      ),
    ),
  );
}
