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
    required this.missingTotal,
    required this.capped,
    this.partial = false,
  });
  final ServerId serverId;
  final String serverName;
  final ServerId otherServerId;
  final String otherServerName;
  final MediaKind kind;

  /// Items on [serverId], sorted by title; the first [_missingShown] only.
  final List<MediaItem> missing;

  /// How many titles are missing in all, [missing] may hold fewer.
  final int missingTotal;

  /// True when a side hit the per-server cap; [missing] may then hold titles
  /// the other server does have beyond the cap.
  final bool capped;

  /// True when the time budget ran out: only part of a library was read, or
  /// some titles were matched without their external ids.
  final bool partial;
}

/// Who watches what on one server: Tautulli for Plex, the server itself for
/// Jellyfin, Emby and (streams only) Pleya Server.
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

  /// False when the server has no source for the asked scope.
  final bool available;
}

const _compareCap = 5000;
const _comparePage = 200;
const _compareDeadline = Duration(seconds: 60);
const _lookupCap = 300;
const _missingShown = 500;
const _historyPage = 500;
const _historyCap = 5000;
const _playsUserCap = 50;
const _playsPerUser = 200;

/// One play for the period aggregate, already clipped. [userKey] is the
/// account, so two people who clip to one display name stay two users.
typedef _Play = ({String titleKey, String title, String userKey, String user, int seconds});

/// The wall-clock budget of one tool call. [race] answers null once it is
/// spent, so a slow server ends the reading instead of the whole tool.
class _Budget {
  _Budget(Duration limit) {
    _spentAt = Future<void>.delayed(limit, () => spent = true);
  }

  late final Future<void> _spentAt;
  bool spent = false;

  Future<T?> race<T>(Future<T> work) {
    if (!spent) return Future.any<T?>([work, _spentAt.then((_) => null)]);
    work.ignore();
    return Future<T?>.value();
  }
}

/// Pleya Server and local folders are never merged by the unified grouping
/// (DEC-063): every title would look missing, so they are not compared.
bool _comparable(AssistantToolContext ctx, ServerId id) => switch (ctx.adminClient(id)?.backend) {
  MediaBackend.plex || MediaBackend.jellyfin => true,
  _ => false,
};

/// Every item of [kind] in the libraries of that kind, page by page, until
/// the cap or the [budget] runs out.
Future<({List<MediaItem> items, bool capped, bool partial})> _wholeKind(
  AssistantToolContext ctx,
  ServerId id,
  MediaKind kind,
  _Budget budget,
) async {
  final client = ctx.adminClient(id) ?? (throw const AssistantToolError('server_not_available'));
  final items = <MediaItem>[];
  final seen = <String>{};
  final libraries = await budget.race(ctx.libraries(id));
  if (libraries == null) return (items: items, capped: false, partial: true);
  for (final library in libraries) {
    if (library.kind != kind) continue;
    var offset = 0;
    while (true) {
      if (items.length >= _compareCap) return (items: items.take(_compareCap).toList(), capped: true, partial: false);
      if (budget.spent) return (items: items, capped: false, partial: true);
      final page = await budget.race(
        client
            .fetchLibraryPagedContent(
              library.id,
              query: LibraryQuery(kind: kind, offset: offset, limit: _comparePage),
              libraryKind: kind,
            )
            .timeout(const Duration(seconds: 20)),
      );
      if (page == null) return (items: items, capped: false, partial: true);
      for (final item in page.items) {
        // Collections ride along on Plex; an item without a server cannot be
        // grouped (same rule as the unified catalog).
        if (item.kind != kind || (item.serverId?.isEmpty ?? true)) continue;
        if (seen.add(item.globalKey)) items.add(item);
      }
      offset += page.items.length;
      // Only a short page ends the library: a full page of collections or
      // repeats adds nothing new and still is not the end. The budget bounds
      // a backend that ignores the offset.
      if (page.items.length < _comparePage) break;
    }
  }
  return (items: items, capped: false, partial: false);
}

/// The unified catalog's identity pipeline (canonical bucket, strong tokens,
/// grouping) over both sides; a group without a source on [other] is missing.
///
/// Jellyfin items carry no stable guid, so asking the resolver about every
/// shared title would cost one item fetch per Jellyfin title. A lookup is
/// only spent where the title+year fallback cannot decide: a server holding
/// two items in one bucket (C19), or no year. At most [_lookupCap] of those;
/// the rest stay guid-only.
Future<({List<MediaItem> missing, bool lookupsCapped})> _missingOn(
  AssistantToolContext ctx,
  List<MediaItem> items,
  ServerId other,
  _Budget budget,
) async {
  final perServer = <String, Map<String, int>>{};
  for (final item in items) {
    final key = canonicalIdentityOf(item)?.bucketKey;
    if (key == null) continue;
    final counts = perServer.putIfAbsent(key, () => {});
    counts[item.serverId!] = (counts[item.serverId!] ?? 0) + 1;
  }
  var lookups = 0;
  var lookupsCapped = false;
  ExternalIdTarget? targetFor(MediaItem item, CanonicalMediaIdentity? identity) {
    if (normalizeStableGuid(item.guid) != null) return null;
    final counts = perServer[identity?.bucketKey];
    if (counts == null || counts.values.fold(0, (a, b) => a + b) < 2) return null;
    if (identity!.year != null && counts.values.every((n) => n == 1)) return null;
    if (lookups >= _lookupCap) {
      lookupsCapped = true;
      return null;
    }
    lookups++;
    return (serverId: item.serverId!, targetId: item.id);
  }

  final resolver = UnifiedIdentityResolver(
    fetchExternalIds: (serverId, targetId) async {
      final client = ctx.adminClient(ServerId(serverId));
      if (client == null || budget.spent) throw StateError('no lookup');
      return await budget.race(client.fetchExternalIds(targetId).timeout(const Duration(seconds: 10))) ??
          (throw StateError('budget spent'));
    },
  );
  final evidence = await resolver.resolveEvidence([
    for (final item in items)
      if (canonicalIdentityOf(item) case final identity)
        ResolvableItem(
          item: item,
          identity: identity,
          scope: (identity ?? CanonicalMediaIdentity.opaque()).granularity.name,
          externalIdTarget: targetFor(item, identity),
        ),
  ]);
  final groups = groupUnifiedMediaSources([
    for (var i = 0; i < items.length; i++)
      GroupingCandidate(source: UnifiedMediaSource.fromItem(items[i]), evidence: evidence[i]),
  ]);
  final missing = [
    for (final group in groups)
      if (!group.sources.any((s) => s.serverId == other)) group.sources.first.item,
  ]..sort((a, b) => (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()));
  return (missing: missing, lookupsCapped: lookupsCapped);
}

final List<AssistantTool> _insightTools = [
  AssistantTool(
    name: 'compare_servers',
    description:
        'Films or series on server_id that other_server_id does not have, matched by identity across servers. '
        'One call compares exactly one pair of servers; for more servers, call once per pair. '
        'partial: true means the time budget ran out and the list is incomplete. '
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
      final budget = _Budget(_compareDeadline);
      final mine = await _wholeKind(ctx, id, kind, budget);
      final theirs = await _wholeKind(ctx, other, kind, budget);
      final (:missing, :lookupsCapped) = await _missingOn(ctx, [...mine.items, ...theirs.items], other, budget);
      final shown = missing.take(_missingShown).toList();
      for (final item in shown) {
        ctx.showItem(id, item.id);
      }
      final capped = mine.capped || theirs.capped;
      final partial = mine.partial || theirs.partial || budget.spent;
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
          if (lookupsCapped) 'identity_lookups_capped_at': _lookupCap,
          if (partial) 'partial': true,
        },
        display: AssistantServerComparison(
          serverId: id,
          serverName: ctx.serverName(id),
          otherServerId: other,
          otherServerName: ctx.serverName(other),
          kind: kind,
          missing: shown,
          missingTotal: missing.length,
          capped: capped,
          partial: partial,
        ),
      );
    },
  ),
  AssistantTool(
    name: 'watch_stats',
    description:
        'What is being watched on a server and by whom: scope "now" for current streams, "period" for the most '
        'watched titles and most active users over the last days (1-31). One server per call; to cover several '
        'servers, call once per server. On Jellyfin and Emby a period counts each title once per user, at its '
        'last play (the server keeps no play log), and only finished titles; on Pleya Server only "now" is '
        'available.',
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
      // Tautulli answers only for the Plex server it monitors.
      final tautulli = ctx.insights!.tautulliFor(id!);
      if (tautulli != null) {
        return scope == 'now' ? _watchedNow(ctx, id, tautulli) : _watchedPeriod(ctx, id, tautulli, days);
      }
      switch (ctx.adminClient(id)) {
        case final JellyfinClient jf:
          return scope == 'now'
              ? _streamsNow(ctx, id, await jf.listActiveSessions())
              : _jellyfinPeriod(ctx, id, jf, days);
        case final PleyaServerClient ps when scope == 'now':
          return _streamsNow(ctx, id, await ps.streamSessions());
      }
      final name = ctx.serverName(id);
      return AssistantToolResult({
        'server': clipText(name),
        // Plex without Tautulli, or Pleya Server history (it keeps none).
        scope == 'now' ? 'now_unavailable_for' : 'history_unavailable_for': [clipText(name)],
      }, display: AssistantWatchStats(serverName: name, days: scope == 'now' ? null : days, available: false));
    },
  ),
];
