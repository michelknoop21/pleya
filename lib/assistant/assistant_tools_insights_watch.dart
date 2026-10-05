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
Future<AssistantToolResult> _watchedNow(AssistantToolContext ctx, {Set<String> excluded = const {}}) async {
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
      for (final s in streams ?? const <JellyfinActiveSession>[])
        if (!excluded.contains(s.userName.trim().toLowerCase())) (server: ctx.serverName(id), s: s),
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

/// Top titles and users over every server that answered. A title is one
/// entry by identity ([_titleKey]); a person is one entry by account key: a
/// plex.tv id joins servers, every other id is its server's own, and a name is
/// never evidence, so same-named accounts stay separate.
Future<AssistantToolResult> _watchedPeriod(
  AssistantToolContext ctx,
  int days, {
  String? media,
  Set<String> excluded = const {},
  bool others = false,
}) async {
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
  var plays = [
    for (final r in served)
      for (final p in r.plays)
        if ((media == null || p.titleKey.startsWith('show:') == (media == 'show')) &&
            !excluded.contains(p.user.trim().toLowerCase()))
          p,
  ];
  // "The others" is decided on account keys. A play whose person cannot be told
  // apart from the asker is left out and reported, never folded back in.
  var leftOut = const <_Play>[];
  if (others) {
    final split = othersOf(plays, keyOf: (p) => p.account, me: ctx.currentUser);
    plays = split.others;
    leftOut = split.leftOut;
  }
  final hours = served.isNotEmpty && served.every((r) => r.hours);
  // A server that ran out of time, or whose history hit the cap, may miss
  // plays: the card says so rather than ranking as if complete.
  final partial = served.any(
    (r) => r.extra['partial'] == true || r.extra.keys.any((k) => k.startsWith('capped_at_plays')),
  );

  // A title is one entry when its sources are the same title: the same server's
  // own plays, or another server's only on a match (see assistantMediaMatch).
  // A merge on the title alone is a guess and is said so, never ranked as complete.
  final clusters = clusterByMediaKey(
    plays,
    keyOf: (p) => AssistantMediaKey(bucket: p.titleKey, year: p.year, ids: p.ids ?? const ExternalIds()),
    serverOf: (p) => p.server,
  );
  final users = <String, ({String name, int plays, int seconds})>{};
  // One person per account key. Only a key that is global (a plex.tv id) joins
  // servers; every other id is its server's own. A name or a nickname is
  // never evidence, so two same-named accounts stay two rows.
  String person(_Play p) => p.account?.toString() ?? '${p.server}|${p.userKey}';
  for (final p in plays) {
    final key = person(p);
    final u = users[key];
    users[key] = (name: u?.name ?? p.user, plays: (u?.plays ?? 0) + 1, seconds: (u?.seconds ?? 0) + p.seconds);
  }
  final titles = [
    for (final c in clusters)
      (
        title: c.members.first.title,
        plays: c.members.length,
        viewers: {for (final p in c.members) p.user},
        servers: {for (final s in c.servers) ServerId(s)},
        show: c.members.first.titleKey.startsWith('show:'),
        proof: c.crossServer ? c.weakest : null,
      ),
  ];
  final guessed = titles.where((t) => t.proof == AssistantMediaProof.titleOnly).length;
  final ranked = titles..sort((a, b) => b.plays.compareTo(a.plays));
  // The titles the card shows open their library copy, as a found title does.
  final targets = await Future.wait([
    for (final t in ranked.take(_watchTargets)) _watchTarget(ctx, t.title, t.show, t.servers),
  ]);
  final topTitles = [
    for (final (i, t) in ranked.indexed)
      (
        title: t.title,
        plays: t.plays,
        viewers: t.viewers.toList(),
        show: t.show,
        target: i < targets.length ? targets[i] : null,
      ),
  ];
  final topUsers = users.values.toList()..sort((a, b) => b.plays.compareTo(a.plays));
  return AssistantToolResult(
    {
      'servers': [for (final id in answered) clipText(ctx.serverName(id))],
      'days': days,
      'plays': plays.length,
      'top_titles': [
        for (final t in ranked.take(10))
          {
            'title': t.title,
            'plays': t.plays,
            'viewers': t.viewers.take(5).toList(),
            // Plays from several servers joined into this entry, and how firmly.
            if (t.proof != null) 'merged_across_servers': t.proof!.name,
          },
      ],
      if (guessed > 0) 'merged_on_title_only': guessed,
      'top_users': [
        for (final u in topUsers.take(10))
          {'user': u.name, 'plays': u.plays, if (hours) 'hours': (u.seconds / 3600).round()},
      ],
      if (others) 'audience': 'others',
      if (leftOut.isNotEmpty)
        'left_out': {
          'plays': leftOut.length,
          'servers': ({for (final p in leftOut) ctx.serverName(ServerId(p.server))}).toList(),
          'reason': 'cannot tell these accounts apart from the asker',
        },
      if (unavailable.isNotEmpty) 'unavailable': [for (final id in unavailable) _unavailableEntry(ctx, id)],
      for (final r in served) ...r.extra,
    },
    display: _onceInRun(
      ctx,
      'period/$days/${media ?? 'all'}/${others ? 'others' : 'all'}/${(excluded.toList()..sort()).join(',')}',
      AssistantWatchStats(
        serverName: _servedLabel(ctx, answered, unavailable),
        days: days,
        // Plays left out of "the others", or titles joined across servers on
        // their name alone, make the ranking unproven too.
        partial: partial || leftOut.isNotEmpty || guessed > 0,
        titles: topTitles,
        users: topUsers,
        unavailable: [for (final id in unavailable) ctx.serverName(id)],
      ),
    ),
  );
}

const _watchTargets = 5;

/// The library copy of a watched title on one of the [servers] it was played
/// on: the one item with the same title key and kind, outside Home's hidden
/// libraries, or null. A history row has no item id that every backend
/// keeps, so the title is looked up; two copies with that title (Dune 1984
/// and 2021) are ambiguous and open nothing rather than the wrong film. The
/// servers are asked at once, each for at most five seconds in all.
Future<AssistantTitleTarget?> _watchTarget(
  AssistantToolContext ctx,
  String title,
  bool show,
  Set<ServerId> servers,
) async {
  final want = _titleKey(show, title);
  Future<AssistantTitleTarget?> on(ServerId id) async {
    final client = ctx.userClient(id);
    if (client == null || ctx.cancelled) return null;
    final found = await client.searchItems(clipText(title, 100), limit: 10);
    if (ctx.cancelled) return null;
    final same = [
      for (final item in filterHiddenLibraryItems(found, await _hiddenLibraryKeys(ctx, id)))
        if (item.kind == (show ? MediaKind.show : MediaKind.movie) && _titleKey(show, item.title ?? '') == want) item,
    ];
    if (same.length != 1) return null;
    final item = same.single;
    final scoped = (item.serverId?.isEmpty ?? true) ? item.copyWith(serverId: id.value) : item;
    return (serverId: id, serverName: ctx.serverName(id), item: scoped);
  }

  Future<AssistantTitleTarget?> bounded(ServerId id) =>
      on(id).timeout(const Duration(seconds: 5), onTimeout: () => null).catchError((Object _) => null);

  final found = [
    for (final t in await Future.wait([for (final id in servers) bounded(id)])) ?t,
  ];
  return found.firstOrNull;
}
