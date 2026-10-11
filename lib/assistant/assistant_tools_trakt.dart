part of 'assistant_tools.dart';

// The asker's own Trakt watchlist, set against the profile's libraries. Read
// only, for the signed-in account of the active profile, never on a children's
// profile. A title the libraries were not asked about, or whose server did not
// answer, is "not_checked": only a complete answer says "not_found_in_library".

/// Titles listed per call, and how many of them are looked up in the
/// libraries (each costs one search per server).
const _traktWatchlistShown = 30;
const _traktWatchlistChecked = 12;

enum _TraktLibraryStatus { inLibrary, notFound, notChecked }

typedef _TraktLookup = ({_TraktLibraryStatus status, List<MediaItem> items});

/// Where [title] lives, by catalogue identity on every visible server that can
/// answer one. Complete only when each of those servers answered.
Future<_TraktLookup> _lookUpTraktTitle(
  AssistantToolContext ctx,
  TraktTitle title,
  Map<String, Set<String>> hiddenByServer,
) async {
  const unknown = (status: _TraktLibraryStatus.notChecked, items: <MediaItem>[]);
  final identity = MediaIdentity(
    externalIds: ExternalIds(imdb: title.ids.imdb, tmdb: title.ids.tmdb, tvdb: title.ids.tvdb),
    title: title.title,
    year: title.year,
    kind: title.isShow ? MediaKind.show : MediaKind.movie,
  );
  if (!identity.isSearchable) return unknown;
  final eligible = [
    for (final id in ctx.userServers)
      if (ctx.servers.getClient(id) case final client? when isIdentityEligibleBackend(client.backend))
        // A server whose hidden libraries could not be read is not asked: a
        // hit there could be one the profile hides.
        (serverId: id, client: client, online: hiddenByServer.containsKey(id.value)),
  ];
  if (eligible.isEmpty) return unknown;
  final found = <MediaItem>[];
  var answered = 0;
  await fanOutFindAllByIdentity(
    servers: [
      for (final s in eligible)
        if (s.online) s,
    ],
    identity: identity,
    maxConcurrent: 3,
    onBatch: (batch) {
      for (final r in batch) {
        if (!r.ok) continue;
        answered++;
        for (final item in visibleMatchesFromServer(
          r.matches,
          r.serverId,
          hiddenByServer[r.serverId.value] ?? const {},
        )) {
          found.add(item.serverId == r.serverId.value ? item : item.copyWith(serverId: r.serverId.value));
        }
      }
      return ctx.cancelled;
    },
  );
  if (found.isNotEmpty) return (status: _TraktLibraryStatus.inLibrary, items: found);
  return (
    status: answered == eligible.length ? _TraktLibraryStatus.notFound : _TraktLibraryStatus.notChecked,
    items: const <MediaItem>[],
  );
}

final List<AssistantTool> _traktTools = [
  AssistantTool(
    name: 'trakt_watchlist',
    description:
        'The user\'s own Trakt watchlist, set against their libraries: "what is on my Trakt watchlist", "which of my '
        'watchlist titles can I watch here". Returns the newest entries, each with library_status: in_library '
        '(item_id and server_id, open or play it), not_found_in_library (every server answered and none has it: '
        'say so and offer a request) or not_checked (a server did not answer, or it was not looked up: say it is '
        'not confirmed, never that it is missing). Titles are matched by external id first and by title and year '
        'only when the ids say nothing; a library with titles in another language can miss a match. Fails with '
        'trakt_not_connected (say the user can link Trakt under Settings > Trackers) or trakt_unreachable. '
        'Pass kind for films or series only.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show', 'all'],
      },
    },
    required: const [],
    serves: (ctx, _) => ctx.trakt != null,
    run: (ctx, _, args) async {
      final trakt = ctx.trakt;
      if (trakt == null || !trakt.available()) throw const AssistantToolError('trakt_not_connected');
      final kind = args['kind'] ?? 'all';
      if (kind != 'movie' && kind != 'show' && kind != 'all') throw const AssistantToolError('invalid_kind');
      final listed = await trakt.watchlist();
      if (listed == null) throw const AssistantToolError('trakt_unreachable');
      // The profile or the switch can change while Trakt answers.
      if (!trakt.available()) throw const AssistantToolError('trakt_not_connected');
      final wanted = [
        for (final t in listed)
          if (kind == 'all' || (kind == 'show') == t.isShow) t,
      ].take(_traktWatchlistShown).toList();
      // Without the catalog wiring the hidden libraries are unknown, and a
      // hit there must not be shown: nothing is looked up.
      final catalogKnown = ctx.catalog != null;
      final hiddenByServer = <String, Set<String>>{};
      if (catalogKnown) {
        for (final id in ctx.userServers) {
          if (!ctx.servers.isServerOnline(id)) continue;
          try {
            hiddenByServer[id.value] = await _hiddenLibraryKeys(ctx, id);
          } on Object {
            // Left out: the server then counts as not answered.
          }
        }
      }
      final lookups = <_TraktLookup>[];
      for (var i = 0; i < wanted.length; i += 4) {
        final chunk = wanted.skip(i).take(4).toList();
        lookups.addAll(
          await Future.wait([
            for (final (j, t) in chunk.indexed)
              if (catalogKnown && i + j < _traktWatchlistChecked)
                _lookUpTraktTitle(ctx, t, hiddenByServer)
              else
                Future.value((status: _TraktLibraryStatus.notChecked, items: const <MediaItem>[])),
          ]),
        );
        if (ctx.cancelled) break;
      }
      final rows = <Map<String, Object?>>[];
      final shown = <MediaItem>[];
      for (final (i, t) in wanted.indexed) {
        final lookup = i < lookups.length ? lookups[i] : (status: _TraktLibraryStatus.notChecked, items: <MediaItem>[]);
        final first = lookup.items.firstOrNull;
        if (first != null && first.serverId != null) {
          ctx.showItem(ServerId(first.serverId!), first.id);
          shown.add(first);
        }
        rows.add({
          'title': clipText(t.title),
          'year': ?t.year,
          'kind': t.isShow ? 'show' : 'movie',
          'library_status': switch (lookup.status) {
            _TraktLibraryStatus.inLibrary => 'in_library',
            _TraktLibraryStatus.notFound => 'not_found_in_library',
            _TraktLibraryStatus.notChecked => 'not_checked',
          },
          if (first != null && first.serverId != null) ...{
            'item_id': first.id,
            'server_id': first.serverId,
            'servers': {
              for (final item in lookup.items) clipText(ctx.serverName(ServerId(item.serverId!)), 40),
            }.toList(),
          },
        });
      }
      return AssistantToolResult({
        'titles': rows,
        'count': rows.length,
        'listed_on_trakt': listed.length,
        if (listed.length > rows.length || !catalogKnown)
          'looked_up': lookups.where((l) => l.status != _TraktLibraryStatus.notChecked).length,
      }, display: shown.isEmpty ? null : AssistantMediaGrid([for (final item in shown) (item: item, group: null)]));
    },
  ),
];
