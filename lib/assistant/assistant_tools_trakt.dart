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
  final servers = [for (final id in ctx.userServers) (id: id, client: ctx.servers.getClient(id))];
  // A server that cannot answer a catalogue-identity lookup at all (Pleya
  // Server, a local folder, one without a client) may hold the title: a miss
  // is then never "not found".
  final blind = servers.any((s) => s.client == null || !isIdentityEligibleBackend(s.client!.backend));
  final asked = [
    for (final s in servers)
      if (s.client case final client? when isIdentityEligibleBackend(client.backend))
        // A server whose hidden libraries could not be read is not asked: a
        // hit there could be one the profile hides.
        if (ctx.servers.isServerOnline(s.id) && hiddenByServer.containsKey(s.id.value)) (id: s.id, client: client),
  ];
  final found = <MediaItem>[];
  var answered = 0;
  for (var i = 0; i < asked.length; i += 3) {
    if (ctx.cancelled) break;
    final results = await Future.wait([
      for (final s in asked.skip(i).take(3)) _askTraktServer(s.client, identity, title.title),
    ]);
    for (final (n, r) in results.indexed) {
      final id = asked[i + n].id;
      if (!r.answered) continue;
      answered++;
      for (final item in visibleMatchesFromServer(r.items, id, hiddenByServer[id.value] ?? const {})) {
        found.add(item.serverId == id.value ? item : item.copyWith(serverId: id.value));
      }
    }
  }
  if (found.isNotEmpty) return (status: _TraktLibraryStatus.inLibrary, items: found);
  final complete = !blind && answered > 0 && answered == servers.length;
  return (status: complete ? _TraktLibraryStatus.notFound : _TraktLibraryStatus.notChecked, items: const <MediaItem>[]);
}

/// How many search hits a server's title search holds back at most (Plex and
/// Jellyfin cap it at 20): a miss that came from a full page proves nothing.
const _traktSearchCap = 20;

/// One server's answer for [identity]. An empty answer counts only when the
/// plain title search was not full: a common title ("It", "Heat") can sit
/// beyond the first page, and then the server has not really been asked.
Future<({bool answered, List<MediaItem> items})> _askTraktServer(
  MediaServerClient client,
  MediaIdentity identity,
  String title,
) async {
  try {
    final matches = await client.findAllByIdentity(identity);
    if (matches.isNotEmpty) return (answered: true, items: matches);
    final probe = await client.searchItems(title, limit: _traktSearchCap);
    return (answered: probe.length < _traktSearchCap, items: const <MediaItem>[]);
  } on Object {
    return (answered: false, items: const <MediaItem>[]);
  }
}

final List<AssistantTool> _traktTools = [
  AssistantTool(
    name: 'trakt_watchlist',
    description:
        'The user\'s own Trakt watchlist, set against their libraries: "what is on my Trakt watchlist", "which of my '
        'watchlist titles can I watch here". Returns the newest entries, each with library_status: in_library '
        '(item_id and server_id, open or play it), not_found_in_library (every server of the profile answered, each could be asked '
        'by identity, and none has it: say so and offer a request) or not_checked (a server did not answer, or it was not looked up: say it is '
        'not confirmed, never that it is missing). Titles are matched by external id first and by title and year '
        'only when the ids say nothing; a library with titles in another language can miss a match. Fails with '
        'trakt_not_connected (say the user can link Trakt under Settings > Trackers), '
        'trakt_personalization_off (Trakt is linked but personal features are switched off in Settings), '
        'trakt_not_available (not on this profile) or trakt_unreachable. '
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
      if (trakt?.blocked() case final reason?) throw AssistantToolError(reason);
      if (trakt == null) throw const AssistantToolError('trakt_not_connected');
      final kind = args['kind'] ?? 'all';
      if (kind != 'movie' && kind != 'show' && kind != 'all') throw const AssistantToolError('invalid_kind');
      final listed = await trakt.watchlist();
      if (listed == null) throw const AssistantToolError('trakt_unreachable');
      // The profile or the switch can change while Trakt answers.
      if (trakt.blocked() case final reason?) throw AssistantToolError(reason);
      // The kind filter comes before the cap, so a few newer films do not push
      // every series out of "my series".
      final ofKind = [
        for (final t in listed)
          if (kind == 'all' || (kind == 'show') == t.isShow) t,
      ];
      final wanted = ofKind.take(_traktWatchlistShown).toList();
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
        'listed_on_trakt': ofKind.length,
        'looked_up': lookups.where((l) => l.status != _TraktLibraryStatus.notChecked).length,
      }, display: shown.isEmpty ? null : AssistantMediaGrid([for (final item in shown) (item: item, group: null)]));
    },
  ),
];
