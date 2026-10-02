part of 'assistant_tools.dart';

/// Admin insight across servers: what is missing where, what is being watched.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run. Rights never come from here: both tools act
/// only on servers the profile administers ([AssistantToolContext.adminClient]).
class AssistantInsightServices {
  const AssistantInsightServices({required this.tautulliFor});

  /// The paired Tautulli for [serverId], or null when that server has none.
  /// Hand in `TautulliProvider.clientForServer`: it answers only for the server
  /// Tautulli monitors, so a rating key never resolves on the wrong server.
  final TautulliClient? Function(ServerId serverId) tautulliFor;
}

/// Titles on [serverName] that [otherServerName] lacks, for the UI.
class AssistantServerComparison extends AssistantDisplay {
  const AssistantServerComparison({
    required this.serverId,
    required this.serverName,
    required this.otherServerId,
    required this.otherServerName,
    required this.kind,
    required this.missing,
    required this.capped,
  });
  final ServerId serverId;
  final String serverName;
  final ServerId otherServerId;
  final String otherServerName;
  final MediaKind kind;

  /// Items on [serverId], sorted by title.
  final List<MediaItem> missing;

  /// True when a side hit the per-server cap; [missing] may then hold titles
  /// the other server does have beyond the cap.
  final bool capped;
}

/// Who watches what on one server, from its Tautulli.
class AssistantWatchStats extends AssistantDisplay {
  const AssistantWatchStats({
    required this.serverName,
    this.days,
    this.sessions = const [],
    this.titles = const [],
    this.users = const [],
    this.available = true,
  });
  final String serverName;

  /// Null for "now".
  final int? days;
  final List<WatchSession> sessions;
  final List<({String title, int plays, List<String> viewers})> titles;
  final List<({String name, int plays, int seconds})> users;

  /// False when the server has no history source (no Tautulli, or not Plex).
  final bool available;
}

const _compareCap = 5000;
const _comparePage = 200;
const _historyPage = 500;
const _historyCap = 5000;

/// Pleya Server and local folders are never merged by the unified grouping
/// (DEC-063): every title would look missing, so they are not compared.
bool _comparable(AssistantToolContext ctx, ServerId id) => switch (ctx.adminClient(id)?.backend) {
  MediaBackend.plex || MediaBackend.jellyfin => true,
  _ => false,
};

/// Every item of [kind] in the libraries of that kind, page by page.
Future<({List<MediaItem> items, bool capped})> _wholeKind(AssistantToolContext ctx, ServerId id, MediaKind kind) async {
  final client = ctx.adminClient(id) ?? (throw const AssistantToolError('server_not_available'));
  final items = <MediaItem>[];
  final seen = <String>{};
  for (final library in await ctx.libraries(id)) {
    if (library.kind != kind) continue;
    var offset = 0;
    while (true) {
      if (items.length >= _compareCap) return (items: items.take(_compareCap).toList(), capped: true);
      final page = await client
          .fetchLibraryPagedContent(
            library.id,
            query: LibraryQuery(kind: kind, offset: offset, limit: _comparePage),
            libraryKind: kind,
          )
          .timeout(const Duration(seconds: 20));
      var added = 0;
      for (final item in page.items) {
        // Collections ride along on Plex; an item without a server cannot be
        // grouped (same rule as the unified catalog).
        if (item.kind != kind || (item.serverId?.isEmpty ?? true)) continue;
        if (seen.add(item.globalKey)) {
          items.add(item);
          added++;
        }
      }
      offset += page.items.length;
      // A short page ends the library; a page with nothing new is a backend
      // ignoring the offset, not an endless library.
      if (page.items.length < _comparePage || added == 0) break;
    }
  }
  return (items: items, capped: false);
}

/// The unified catalog's identity pipeline (canonical bucket, strong tokens,
/// grouping) over both sides; a group without a source on [other] is missing.
Future<List<MediaItem>> _missingOn(AssistantToolContext ctx, List<MediaItem> items, ServerId other) async {
  final resolver = UnifiedIdentityResolver(
    fetchExternalIds: (serverId, targetId) =>
        (ctx.adminClient(ServerId(serverId)) ?? (throw StateError('server gone'))).fetchExternalIds(targetId),
  );
  final evidence = await resolver.resolveEvidence([
    for (final item in items)
      ResolvableItem(
        item: item,
        identity: canonicalIdentityOf(item),
        scope: (canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque()).granularity.name,
        // ponytail: a stable guid already is proof, so only guid-less items in
        // a colliding bucket cost a request; thousands of shared titles would
        // otherwise mean thousands of calls. Cross-backend pairs then merge on
        // title+year without a conflicting id, like the catalog's fallback.
        externalIdTarget: normalizeStableGuid(item.guid) == null ? (serverId: item.serverId!, targetId: item.id) : null,
      ),
  ]);
  final groups = groupUnifiedMediaSources([
    for (var i = 0; i < items.length; i++)
      GroupingCandidate(source: UnifiedMediaSource.fromItem(items[i]), evidence: evidence[i]),
  ]);
  return [
    for (final group in groups)
      if (!group.sources.any((s) => s.serverId == other)) group.sources.first.item,
  ]..sort((a, b) => (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()));
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A series counts as one title: Tautulli's full title is `Series - Episode`.
String _historyTitle(TautulliHistoryEntry e) {
  final full = e.fullTitle ?? '';
  if (e.mediaType != 'episode') return full;
  final cut = full.indexOf(' - ');
  // ponytail: a series name containing " - " is cut short; the history row
  // carries no grandparent_title in our model.
  return cut > 0 ? full.substring(0, cut) : full;
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

Future<AssistantToolResult> _watchedPeriod(
  AssistantToolContext ctx,
  ServerId id,
  TautulliClient tautulli,
  int days,
) async {
  final name = ctx.serverName(id);
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

  final titles = <String, ({String title, int plays, Set<String> viewers})>{};
  final users = <String, ({int plays, int seconds})>{};
  for (final e in entries) {
    final key = e.mediaType == 'episode' ? 'g${e.grandparentRatingKey}' : 'r${e.ratingKey}';
    final viewer = clipText(e.displayName, 40);
    final t = titles[key];
    titles[key] = (
      title: t?.title ?? clipText(_historyTitle(e)),
      plays: (t?.plays ?? 0) + 1,
      viewers: {...?t?.viewers, viewer},
    );
    final u = users[viewer];
    users[viewer] = (plays: (u?.plays ?? 0) + 1, seconds: (u?.seconds ?? 0) + (e.playSeconds ?? 0));
  }
  final topTitles = [
    for (final t in titles.values.toList()..sort((a, b) => b.plays.compareTo(a.plays)))
      (title: t.title, plays: t.plays, viewers: t.viewers.toList()),
  ];
  final topUsers = [
    for (final u in users.entries.toList()..sort((a, b) => b.value.plays.compareTo(a.value.plays)))
      (name: u.key, plays: u.value.plays, seconds: u.value.seconds),
  ];
  return AssistantToolResult({
    'server': clipText(name),
    'days': days,
    'plays': entries.length,
    'top_titles': [
      for (final t in topTitles.take(10)) {'title': t.title, 'plays': t.plays, 'viewers': t.viewers.take(5).toList()},
    ],
    'top_users': [
      for (final u in topUsers.take(10)) {'user': u.name, 'plays': u.plays, 'hours': (u.seconds / 3600).round()},
    ],
    if (capped) 'capped_at_plays': _historyCap,
  }, display: AssistantWatchStats(serverName: name, days: days, titles: topTitles, users: topUsers));
}

final List<AssistantTool> _insightTools = [
  AssistantTool(
    name: 'compare_servers',
    description:
        'Films or series on server_id that other_server_id does not have, matched by identity across servers. '
        '$_serverIdNote',
    risk: AssistantToolRisk.read,
    properties: const {
      'other_server_id': {'type': 'string', 'description': 'Another server_id from the same list.'},
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show'],
      },
    },
    required: const ['other_server_id', 'kind'],
    serves: (ctx, id) =>
        ctx.insights != null &&
        _comparable(ctx, id) &&
        ctx.administeredServers.any((other) => other != id && _comparable(ctx, other)),
    run: (ctx, id, args) async {
      final other = ServerId.tryParse(_string(args, 'other_server_id'));
      if (other == null || other == id! || !ctx.administeredServers.contains(other) || !_comparable(ctx, other)) {
        throw const AssistantToolError('server_not_available');
      }
      final kind = switch (_string(args, 'kind')) {
        'movie' => MediaKind.movie,
        'show' => MediaKind.show,
        _ => throw const AssistantToolError('invalid_kind'),
      };
      final mine = await _wholeKind(ctx, id, kind);
      final theirs = await _wholeKind(ctx, other, kind);
      final missing = await _missingOn(ctx, [...mine.items, ...theirs.items], other);
      for (final item in missing) {
        ctx.showItem(id, item.id);
      }
      final capped = mine.capped || theirs.capped;
      return AssistantToolResult(
        {
          'server': clipText(ctx.serverName(id)),
          'other_server': clipText(ctx.serverName(other)),
          'kind': kind.name,
          'count_on_server': mine.items.length,
          'count_on_other': theirs.items.length,
          'missing_count': missing.length,
          'examples': [
            for (final item in missing.take(20))
              {'item_id': item.id, 'title': clipText(item.title), if (item.year != null) 'year': item.year},
          ],
          if (capped) 'capped_at_items_per_server': _compareCap,
        },
        display: AssistantServerComparison(
          serverId: id,
          serverName: ctx.serverName(id),
          otherServerId: other,
          otherServerName: ctx.serverName(other),
          kind: kind,
          missing: missing,
          capped: capped,
        ),
      );
    },
  ),
  AssistantTool(
    name: 'watch_stats',
    description:
        'What is being watched on a server and by whom: scope "now" for current streams, "period" for the most '
        'watched titles and most active users over the last days (1-31).',
    risk: AssistantToolRisk.read,
    properties: const {
      'scope': {
        'type': 'string',
        'enum': ['now', 'period'],
      },
      'days': {'type': 'integer', 'minimum': 1, 'maximum': 31},
    },
    required: const ['scope'],
    serves: (ctx, id) => ctx.insights != null && ctx.adminClient(id) != null,
    run: (ctx, id, args) async {
      final scope = _string(args, 'scope');
      if (scope != 'now' && scope != 'period') throw const AssistantToolError('invalid_scope');
      final days = switch (args['days']) {
        null => 7,
        final int d when d >= 1 && d <= 31 => d,
        _ => throw const AssistantToolError('invalid_days'),
      };
      final tautulli = ctx.insights!.tautulliFor(id!);
      if (tautulli == null) {
        final name = ctx.serverName(id);
        return AssistantToolResult({
          'server': clipText(name),
          // Tautulli is the only source; Jellyfin and Pleya Server have none.
          scope == 'now' ? 'now_unavailable_for' : 'history_unavailable_for': [clipText(name)],
        }, display: AssistantWatchStats(serverName: name, days: scope == 'now' ? null : days, available: false));
      }
      return scope == 'now' ? _watchedNow(ctx, id, tautulli) : _watchedPeriod(ctx, id, tautulli, days);
    },
  ),
];
