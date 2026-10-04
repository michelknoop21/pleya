part of 'assistant_tools.dart';

// What is popular, and what is like a title: Seerr first, the user's own TMDB
// key without it. The result is shown as find_title's cards.

const _discoverLimit = 12;

SeerrMedia? _fromTmdb(Map<String, dynamic> r, TmdbKind kind) {
  final id = r['id'];
  if (id is! int) return null;
  final date = '${r['release_date'] ?? r['first_air_date'] ?? ''}';
  return SeerrMedia(
    tmdbId: id,
    mediaType: kind.path,
    title: '${r['title'] ?? r['name'] ?? ''}',
    year: date.length >= 4 ? date.substring(0, 4) : null,
    posterPath: r['poster_path'] as String?,
    overview: r['overview'] as String?,
    status: SeerrMediaStatus.unknown,
  );
}

/// Seerr's answer as codes, TMDB's failure as an unavailable source. A
/// rejected TMDB key is remembered for the ask, as the facts chain does.
Future<T> _source<T>(AssistantToolContext ctx, Future<T> Function() call) async {
  try {
    return await _seerrCall(call);
  } on TmdbAuthException {
    ctx.titleFacts?.rejectTmdbKey();
    throw const AssistantToolError('tmdb_key_rejected');
  } on TmdbException {
    throw const AssistantToolError('source_unavailable');
  }
}

/// Without a TMDB client: `tmdb_key_rejected` when the key was turned down.
AssistantToolError _noTmdb(AssistantToolContext ctx, String code) =>
    AssistantToolError((ctx.titleFacts?.tmdbKeyRejected ?? false) ? 'tmdb_key_rejected' : code);

/// Tries Seerr, then TMDB; `no_source` when neither is there.
Future<List<SeerrMedia>> _fromSources(
  AssistantToolContext ctx,
  Future<List<SeerrMedia>> Function(SeerrClient seerr) viaSeerr,
  Future<List<SeerrMedia>> Function(TmdbClient tmdb) viaTmdb,
) async {
  final seerr = ctx.requests?.client();
  if (seerr != null) {
    try {
      return await _source(ctx, () => viaSeerr(seerr));
    } on AssistantToolError catch (e) {
      if (e.code == 'not_allowed' || ctx.titleFacts?.tmdb() == null) rethrow;
    }
  }
  final tmdb = ctx.titleFacts?.tmdb();
  if (tmdb == null) throw _noTmdb(ctx, 'no_source');
  return _source(ctx, () => viaTmdb(tmdb));
}

/// Dedupes, drops [skip] and cuts to the limit, links the library and shows
/// the cards.
Future<AssistantToolResult> _discoverResult(
  AssistantToolContext ctx,
  Iterable<SeerrMedia> found,
  int? age, {
  int? skip,
}) async {
  final unique = <String, SeerrMedia>{};
  for (final m in found) {
    if (m.tmdbId != skip && m.title.isNotEmpty) unique.putIfAbsent('${m.mediaType}:${m.tmdbId}', () => m);
  }
  final matches = [
    for (final m in unique.values.take(_discoverLimit))
      FindMatch(
          m.title,
          year: int.tryParse(m.year ?? ''),
          kind: m.isMovie ? MediaKind.movie : MediaKind.show,
          sources: const [FindSource.seerr],
        )
        ..ids = ExternalIds(tmdb: m.tmdbId)
        ..seerr = ctx.requests?.client() == null ? null : m,
  ];
  await assistantLinkLibrary(ctx, matches);
  final cards = await _titleCards(ctx, matches, age, listing: true);
  return AssistantToolResult({'titles': cards.rows, ...cards.note}, display: AssistantTitleMatches(ctx, cards.display));
}

/// Offered wherever the facts service is wired, so a missing source is
/// explained (`no_source`) instead of the tool being silently absent.
bool _servesDiscover(AssistantToolContext ctx, ServerId _) => ctx.titleFacts != null || ctx.requests?.client() != null;

final List<AssistantTool> _discoverTools = [
  AssistantTool(
    name: 'trending_titles',
    description:
        'What is popular right now: trending films and series, from the request service (Seerr) or, without it, '
        'from TMDB with the user\'s own key. Returns up to 12 titles, each in the library (item_id, server_id) or '
        'with a seerr_id for request_title. When it fails with no_source, say the user can connect Seerr or '
        'enter a TMDB key under Settings > Big P; with tmdb_key_rejected, that TMDB turned down the key there.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'kind': {
        'type': 'string',
        'enum': ['movie', 'tv', 'all'],
      },
      ..._forKids,
    },
    required: const [],
    serves: _servesDiscover,
    run: (ctx, _, args) async {
      final kind = args['kind'] ?? 'all';
      if (kind != 'movie' && kind != 'tv' && kind != 'all') throw const AssistantToolError('invalid_kind');
      final age = await _kidsAge(ctx, args);
      final found = await _fromSources(
        ctx,
        (seerr) async => [
          for (final m in (await seerr.discoverTrending()).items)
            if (kind == 'all' || m.mediaType == kind) m,
        ],
        (tmdb) async => [
          for (final k in TmdbKind.values)
            if (kind == 'all' || kind == k.path)
              for (final r in await tmdb.trending(k)) ?_fromTmdb(r, k),
        ],
      );
      return _discoverResult(ctx, found, age);
    },
  ),
  AssistantTool(
    name: 'similar_titles',
    description:
        'Titles like one the user names ("something like Dark"). Finds the title first, in the library or in '
        'Seerr or TMDB, then returns up to 12 similar and recommended titles, each in the library (item_id, '
        'server_id) or with a seerr_id for request_title. Fails with title_not_found, no_source or '
        'tmdb_key_rejected (TMDB turned down the key under Settings > Big P).',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'title': {'type': 'string'},
      'year': {'type': 'integer'},
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show'],
      },
      ..._forKids,
    },
    required: const ['title'],
    serves: _servesDiscover,
    run: (ctx, _, args) async {
      final title = clipText(_string(args, 'title'), 100);
      final year = _int(args, 'year', 1870, 2100);
      final kind = _findKind(args['kind']);
      if (kind == MediaKind.episode) throw const AssistantToolError('invalid_kind');
      final age = await _kidsAge(ctx, args);
      final (:id, :isMovie) = await _resolveSource(ctx, title, year, kind);
      final found = await _fromSources(
        ctx,
        (seerr) async => [
          ...(await seerr.getRecommendations(tmdbId: id, isMovie: isMovie)).items,
          ...(await seerr.getSimilar(tmdbId: id, isMovie: isMovie)).items,
        ],
        (tmdb) async {
          final k = isMovie ? TmdbKind.movie : TmdbKind.tv;
          return [
            for (final r in [...await tmdb.recommendations(k, id), ...await tmdb.similar(k, id)]) ?_fromTmdb(r, k),
          ];
        },
      );
      return _discoverResult(ctx, found, age, skip: id);
    },
  ),
];

/// The TMDB id of the title the user named: the library and Seerr through
/// find_title's own route, TMDB's search when those know no id.
Future<({int id, bool isMovie})> _resolveSource(
  AssistantToolContext ctx,
  String title,
  int? year,
  MediaKind? kind,
) async {
  final found = await findTitles(
    ctx,
    FindQuery(candidates: [(title: title, year: year, kind: kind)], kind: kind, variants: [title]),
  );
  final key = titleKey(title);
  final named = found.matches.where(
    (m) => m.titles.any((t) => titleKey(t) == key) && (m.seerr?.tmdbId ?? m.ids.tmdb) != null,
  );
  if (named.firstOrNull case final m?) {
    return (id: m.seerr?.tmdbId ?? m.ids.tmdb!, isMovie: (m.kind ?? kind) != MediaKind.show);
  }
  final tmdb = ctx.titleFacts?.tmdb();
  if (tmdb == null) throw _noTmdb(ctx, ctx.requests?.client() == null ? 'no_source' : 'title_not_found');
  for (final r in await _source(ctx, () => tmdb.searchMulti(title, year: year))) {
    final type = r['media_type'];
    if ((type != 'movie' && type != 'tv') || r['id'] is! int) continue;
    if (kind != null && (type == 'movie') != (kind == MediaKind.movie)) continue;
    return (id: r['id'] as int, isMovie: type == 'movie');
  }
  throw const AssistantToolError('title_not_found');
}
