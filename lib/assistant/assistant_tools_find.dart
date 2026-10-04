part of 'assistant_tools.dart';

// Finding a title from a description, in the profile's own unified library
// and in Seerr at once. The route itself lives in `assistant_find_route.dart`;
// this part parses the model's interpretation, registers what it shows in the
// run's allow-lists and builds the display.

/// A library copy the UI can open.
typedef AssistantTitleTarget = ({ServerId serverId, String serverName, MediaItem item});

/// One found title as the UI draws it: where it can be played, and the
/// request option when Seerr knows it.
class AssistantTitleMatch {
  const AssistantTitleMatch({
    required this.matchId,
    required this.title,
    required this.kind,
    required this.confidence,
    required this.targets,
    this.year,
    this.request,
    this.series,
    this.season,
    this.episode,
    this.snippet = '',
    this.facts,
  });
  final String matchId;
  final String title;
  final int? year;

  /// `movie`, `show` or `episode`.
  final String kind;

  /// `high`, `medium` or `low`.
  final String confidence;
  final List<AssistantTitleTarget> targets;

  /// For [assistantRequestFromOption]; for an episode, its series.
  final AssistantRequestOption? request;
  final String? series;
  final int? season;
  final int? episode;

  /// The plot text the title was matched on, clipped; may be empty.
  final String snippet;

  /// Age rating, genres, runtime and services, when looked up.
  final TitleFacts? facts;
}

class AssistantTitleMatches extends AssistantDisplay {
  const AssistantTitleMatches(this.context, this.matches);

  /// Hand back to [assistantRequestFromOption] with a match's request.
  final AssistantToolContext context;
  final List<AssistantTitleMatch> matches;
}

const _findKinds = {'movie': MediaKind.movie, 'show': MediaKind.show, 'episode': MediaKind.episode};

/// A catalogue id where a title belongs: tt0133093, tmdb:603, 5+ digits.
/// The model never supplies ids; such a "title" is dropped, not searched.
final _idLike = RegExp(r'^(tt\d{5,}|(tmdb|imdb|tvdb)\W*\d+|\d{5,})$', caseSensitive: false);

MediaKind? _findKind(Object? value) =>
    value == null ? null : (_findKinds[value] ?? (throw const AssistantToolError('invalid_kind')));

FindQuery _findQuery(Map<String, Object?> args) {
  final raw = args['candidates'] ?? const [];
  if (raw is! List || raw.length > 5) throw const AssistantToolError('invalid_candidates');
  final candidates = <FindCandidate>[];
  for (final c in raw) {
    if (c is! Map) throw const AssistantToolError('invalid_candidates');
    final title = clipText(_string(c.cast<String, Object?>(), 'title'), 100);
    if (_idLike.hasMatch(title)) continue;
    final year = c['year'];
    if (year != null && (year is! int || year < 1870 || year > 2100)) throw const AssistantToolError('invalid_year');
    // Only title, year and kind are read: an id field the model adds is ignored.
    candidates.add((title: title, year: year as int?, kind: _findKind(c['kind'])));
  }
  final series = _optionalText(args, 'series');
  return FindQuery(
    candidates: candidates,
    kind: _findKind(args['kind']),
    variants: [for (final v in _strings(args, 'variants').take(8)) clipText(v, 100)],
    series: series == null || _idLike.hasMatch(series) ? null : series,
    season: _int(args, 'season', 0, 200),
    episode: _int(args, 'episode', 1, 2000),
    subject: _bool(args, 'subject'),
  );
}

String _sourceName(FindSource s) => switch (s) {
  FindSource.model => 'model',
  FindSource.libraryPlot => 'library_plot',
  FindSource.wikipedia => 'wikipedia',
  FindSource.web => 'web',
  FindSource.library => 'library',
  FindSource.seerr => 'seerr',
};

final List<AssistantTool> _findTools = [
  AssistantTool(
    name: 'find_title',
    description:
        'Find a film, series or episode the user describes but cannot name, or titles about a subject or theme '
        '("a film about space"). Interpret the question once: up to 5 candidate titles you suspect (title, year, '
        'kind; never ids), the kind, and 2-8 search phrases: first the subject itself in English, then in Dutch '
        '(for space: "space", "ruimte"), then short phrases a plot summary would contain ("astronauts in a '
        'spacecraft", "astronauten in een ruimteschip"). For an episode give the series and any season or episode '
        'number. Searches the plot summaries of this profile\'s libraries, Wikipedia and Seerr, and the web only '
        'when that is not enough. Returns up to 8 matches, up to 20 library titles when subject is true, with a confidence, where they can be played (item_id, server_id) and a '
        'seerr_id for request_title. Say so when confidence is low or partial is set.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'candidates': {
        'type': 'array',
        'maxItems': 5,
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'year': {'type': 'integer'},
            'kind': {
              'type': 'string',
              'enum': ['movie', 'show', 'episode'],
            },
          },
          'required': ['title'],
          'additionalProperties': false,
        },
      },
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show', 'episode'],
      },
      'variants': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 8,
        'items': {'type': 'string'},
      },
      'series': {'type': 'string'},
      'season': {'type': 'integer'},
      'episode': {'type': 'integer'},
      'subject': {
        'type': 'boolean',
        'description':
            'true when the user wants films about a topic (a list), false or absent when looking for one '
            'specific title',
      },
      ..._forKids,
    },
    required: const ['variants'],
    // A visible server that is online now, or Seerr.
    serves: (ctx, _) => ctx.userServers.any((id) => ctx.userClient(id) != null) || ctx.requests?.client() != null,
    run: (ctx, _, args) async {
      _requestContextLive(ctx);
      final client = ctx.requests?.client();
      final query = _findQuery(args);
      final age = await _kidsAge(ctx, args);
      final result = await findTitles(ctx, query);
      _requestContextLive(ctx);
      if (ctx.requests?.client() != client) throw const AssistantToolError('not_allowed');
      final cards = await _titleCards(ctx, result.matches, age);
      return AssistantToolResult({
        'matches': cards.rows,
        ...cards.note,
        if (result.partial) 'partial': true,
        if (result.webSearched) 'web_searched': true,
      }, display: AssistantTitleMatches(ctx, cards.display));
    },
  ),
];

/// A found title as the facts chain looks it up: its library copy and its
/// TMDB id when Seerr or the server knew them.
TitleRef _matchRef(FindMatch m) => TitleRef(
  kind: _tmdbKind(m.kind ?? MediaKind.movie),
  title: m.title,
  year: m.year,
  tmdbId: m.seerr?.tmdbId ?? m.ids.tmdb,
  imdb: m.ids.imdb,
  tvdb: m.ids.tvdb,
  item: m.library.firstOrNull,
  serverId: m.library.firstOrNull?.serverId,
);

/// Rows for the model and cards for the UI from [matches]: library copies
/// registered as showable, request options registered for request_title,
/// facts attached and, with [age], the age gate applied. A [listing]
/// (trending, similar) has no confidence, sources or snippet to report.
Future<({List<Map<String, Object?>> rows, List<AssistantTitleMatch> display, Map<String, Object?> note})> _titleCards(
  AssistantToolContext ctx,
  List<FindMatch> matches,
  int? age, {
  bool listing = false,
}) async {
  final client = ctx.requests?.client();
  void live() => client == null ? _requestContextLive(ctx) : _requestLive(ctx, client);
  live();
  if (client != null) {
    _shownRequestClients[ctx] ??= client;
    if (client.session.userId case final user?) _shownRequestUsers[ctx] ??= user;
  }
  final shown = _shownRequestTitles[ctx] ??= {};
  final rows = <Map<String, Object?>>[];
  final display = <AssistantTitleMatch>[];
  final gated = await _gateTitles(ctx, matches, _matchRef, age);
  // The gate may look up facts; the profile or Seerr client can change meanwhile.
  live();
  for (final (i, (m, facts)) in gated.kept.indexed) {
    final id = 'm${i + 1}';
    final kind = (m.kind ?? MediaKind.movie).name;
    final confidence = listing ? 'high' : m.confidence;
    final snippet = listing ? '' : clipText(m.snippet, 160);
    final targets = <AssistantTitleTarget>[
      for (final item in m.library)
        (serverId: ServerId(item.serverId!), serverName: ctx.serverName(ServerId(item.serverId!)), item: item),
    ];
    for (final t in targets) {
      ctx.showItem(t.serverId, t.item.id);
    }
    AssistantRequestOption? request;
    if (m.seerr case final s? when client != null) {
      final seerrId = '${s.mediaType}:${s.tmdbId}';
      shown[seerrId] = s;
      request = AssistantRequestOption(
        seerrId: seerrId,
        title: clipText(s.title),
        year: int.tryParse(s.year ?? ''),
        kind: s.isMovie ? 'movie' : 'series',
        posterUrl: s.posterUrl,
        overview: clipText(s.overview, 300),
        status: _requestStatus(s.status),
        facts: facts,
      );
    }
    final first = targets.firstOrNull;
    rows.add({
      'match_id': id,
      'title': clipText(m.title),
      'year': ?m.year,
      'kind': kind,
      'in_library': targets.isNotEmpty,
      'servers': {for (final t in targets) clipText(t.serverName, 40)}.toList(),
      'seerr_status': ?request?.status,
      'seerr_id': ?request?.seerrId,
      if (!listing) ...{
        'confidence': confidence,
        'sources': [for (final s in m.sources) _sourceName(s)],
      },
      if (snippet.isNotEmpty) 'snippet': snippet,
      if (first != null) ...{'item_id': first.item.id, 'server_id': first.serverId.value},
      if (m.series != null) ...{'series': clipText(m.series), 'season': ?m.season, 'episode': ?m.episode},
      ..._factsField(facts, gated.region),
    });
    display.add(
      AssistantTitleMatch(
        matchId: id,
        title: clipText(m.title),
        year: m.year,
        kind: kind,
        confidence: confidence,
        targets: targets,
        request: request,
        series: m.series == null ? null : clipText(m.series),
        season: m.season,
        episode: m.episode,
        snippet: snippet,
        facts: facts,
      ),
    );
  }
  return (rows: rows, display: display, note: gated.note);
}
