part of 'assistant_tools.dart';

/// Asking for a title that is not in any library, through Seerr (Overseerr or
/// Jellyseerr).
///
/// Two tools on purpose. Finding is a read any profile with a Seerr session
/// may do; requesting is visible to the household and takes server disk, so
/// it waits for a Pleya card. The split is also the allow-list: only a title
/// `find_request_title` or `discover_request_titles` showed in this run can
/// be requested, by the model or by the user picking an option card.
///
/// Wired into [AssistantToolContext] by the UI layer; a null service keeps
/// these tools out of the run.
class AssistantRequestServices {
  const AssistantRequestServices({required this.client});

  /// The active profile's Seerr client, read live (`SeerrProvider.client`).
  /// Null after a disconnect: the tools stop serving and a waiting card is
  /// refused. Rights stay with Seerr: its session permissions gate 4K, and
  /// the server answers 403 for anything else this profile may not do.
  final SeerrClient? Function() client;
}

/// Seerr has no media-server id. The card and the authority re-check get this;
/// [_servesRequests] ignores it.
final _seerrServerId = ServerId('seerr');

/// Titles shown per run, keyed `movie:<tmdbId>` / `tv:<tmdbId>` (TMDB ids
/// collide between films and series). Keyed on the run's context, so it
/// lives exactly as long as the run.
final _shownRequestTitles = Expando<Map<String, SeerrMedia>>('shownRequestTitles');
final _shownRequestClients = Expando<SeerrClient>('shownRequestClients');
final _shownRequestUsers = Expando<int>('shownRequestUsers');

bool _servesRequests(AssistantToolContext ctx, ServerId _) => ctx.requests?.client() != null;

SeerrClient _seerr(AssistantToolContext ctx) =>
    ctx.requests?.client() ?? (throw const AssistantToolError('requests_not_available'));

/// Seerr's own failures as codes; the server's message text never reaches the model.
Future<T> _seerrCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on SeerrException catch (e) {
    if (e.isAuth || e.isForbidden) throw const AssistantToolError('not_allowed');
    throw const AssistantToolError('requests_not_available');
  }
}

String _requestStatus(SeerrMediaStatus status) => switch (status) {
  SeerrMediaStatus.available => 'available',
  SeerrMediaStatus.partiallyAvailable => 'partially_available',
  SeerrMediaStatus.pending || SeerrMediaStatus.processing => 'requested',
  SeerrMediaStatus.unknown => 'not_requested',
};

List<int>? _seasonNumbers(Map<String, Object?> args) {
  final value = args['seasons'];
  if (value == null) return null;
  if (value is! List || value.isEmpty || value.any((n) => n is! int || n < 1)) {
    throw const AssistantToolError('invalid_seasons');
  }
  return value.cast<int>().toSet().toList();
}

final List<AssistantTool> _requestTools = [
  AssistantTool(
    name: 'find_request_title',
    description:
        'Search the request service (Seerr) for films or series that are not in a library yet. '
        'When the user describes a film instead of naming it, propose up to 5 likely titles from the '
        'description and look them all up in this one call. Returns a seerr_id per title for request_title, '
        'and whether it is already available or requested. The user sees the results as option cards.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'titles': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 5,
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': ['movie', 'series'],
            },
            'year': {'type': 'integer'},
          },
          'required': ['title'],
          'additionalProperties': false,
        },
      },
    },
    required: const ['titles'],
    serves: _servesRequests,
    run: (ctx, _, args) async {
      final client = _seerr(ctx);
      _requestLive(ctx, client);
      final candidates = _candidates(args);
      final age = await _kidsAge(ctx);
      // Ten results at most in all, at least two per candidate.
      final perCandidate = (10 ~/ candidates.length).clamp(2, 8);
      final found = <SeerrMedia>[];
      // Three searches at a time, as the aggregation service does.
      for (var start = 0; start < candidates.length; start += 3) {
        final pages = await Future.wait([
          for (final c in candidates.skip(start).take(3)) _seerrCall(() => client.search(c.title)),
        ]);
        _requestLive(ctx, client);
        for (final (i, page) in pages.indexed) {
          final c = candidates[start + i];
          found.addAll(
            page.items
                .where(
                  (m) =>
                      (c.kind == null || m.isMovie == (c.kind == 'movie')) && (c.year == null || m.year == '${c.year}'),
                )
                .take(perCandidate),
          );
        }
      }
      return _requestOptions(ctx, client, found, age);
    },
  ),
  AssistantTool(
    name: 'discover_request_titles',
    description:
        'Browse the request service (Seerr) when the user describes a kind of film or series but no title '
        'comes to mind. Genres are TMDB genre names; keywords are TMDB keywords for the subject, in English '
        '("space", "time travel"), the first one TMDB knows is applied. Filters the service cannot apply come back in '
        'ignored_filters; say so instead of pretending they were used. Returns at most 10 titles with a '
        'seerr_id for request_title, ranked best first (well-known before less known; give the first N the user asked for).',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'kind': {
        'type': 'string',
        'enum': ['movie', 'series'],
      },
      'genres': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'year_from': {'type': 'integer'},
      'year_to': {'type': 'integer'},
      'keywords': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'original_language': {'type': 'string', 'description': 'ISO 639-1 code'},
      'sort': {
        'type': 'string',
        'enum': ['popularity', 'rating'],
      },
      'niche': _nicheProperty,
    },
    required: const ['kind'],
    serves: _servesRequests,
    run: (ctx, _, args) async {
      final client = _seerr(ctx);
      _requestLive(ctx, client);
      final kind = args['kind'];
      if (kind != 'movie' && kind != 'series') throw const AssistantToolError('invalid_kind');
      final movies = kind == 'movie';
      final sort = args['sort'];
      if (sort != null && sort != 'popularity' && sort != 'rating') throw const AssistantToolError('invalid_sort');
      final genreNames = _strings(args, 'genres');
      final keywords = _strings(args, 'keywords');
      final language = args['original_language'];
      if (language != null && (language is! String || !RegExp(r'^[a-z]{2}$').hasMatch(language))) {
        throw const AssistantToolError('invalid_original_language');
      }
      final yearFrom = _yearArg(args, 'year_from');
      final yearTo = _yearArg(args, 'year_to');
      final age = await _kidsAge(ctx);

      // The API documents date ranges and original language on /discover;
      // SeerrClient only passes genre, keywords and sortBy through yet. The
      // language is filtered here, on the page Seerr returns.
      final ignored = <Map<String, Object?>>[
        if (yearFrom != null) {'filter': 'year_from', 'reason': 'not_supported'},
        if (yearTo != null) {'filter': 'year_to', 'reason': 'not_supported'},
      ];

      // The subject ("space") as a TMDB keyword id; without it discover is
      // only the popular titles of a genre. One keyword: several AND together.
      int? keyword;
      for (final name in keywords) {
        final value = clipText(name, 40);
        if (keyword != null) {
          ignored.add({'filter': 'keywords', 'value': value, 'reason': 'one_keyword_only'});
          continue;
        }
        final found = await _seerrCall(() => client.searchKeyword(name));
        final match = found.where((k) => k.name.toLowerCase() == name.toLowerCase()).firstOrNull ?? found.firstOrNull;
        if (match == null) {
          ignored.add({'filter': 'keywords', 'value': value, 'reason': 'unknown_keyword'});
        } else {
          keyword = match.id;
        }
      }

      int? genre;
      List<String>? knownGenres;
      if (genreNames.isNotEmpty) {
        final all = await _seerrCall(() => movies ? client.getMovieGenres() : client.getTvGenres());
        _requestLive(ctx, client);
        for (final name in genreNames) {
          final match = all.where((g) => g.name.toLowerCase() == name.toLowerCase()).firstOrNull;
          final value = clipText(name, 40);
          if (match == null) {
            ignored.add({'filter': 'genres', 'value': value, 'reason': 'unknown_genre'});
            knownGenres ??= [for (final g in all.take(40)) clipText(g.name, 40)];
          } else if (genre == null) {
            genre = match.id;
          } else if (match.id != genre) {
            ignored.add({'filter': 'genres', 'value': value, 'reason': 'one_genre_only'});
          }
        }
      }

      final sortBy = sort == 'rating' ? 'vote_average.desc' : 'popularity.desc';
      final page = await _seerrCall(
        () => movies
            ? client.discoverMovies(genre: genre, sortBy: sortBy, keywords: [?keyword])
            : client.discoverTv(genre: genre, sortBy: sortBy, keywords: [?keyword]),
      );
      // The asked language, or the niche the user asked for, keeps Seerr's
      // order; otherwise the well-known titles first (see rankSuggestions).
      final picks = rankSuggestions(
        language != null ? page.items.where((m) => m.originalLanguage == language) : page.items,
        niche: language != null || _niche(ctx, args),
      ).take(10);
      // Seerr's discover takes no original language, so only this page was
      // filtered: say so, the model must not claim the full catalog.
      if (language != null) {
        ignored.add({'filter': 'original_language', 'value': language, 'reason': 'first_page_only'});
      }
      final result = await _requestOptions(ctx, client, picks, age);
      return AssistantToolResult({
        ...result.data,
        if (ignored.isNotEmpty) 'ignored_filters': ignored,
        'known_genres': ?knownGenres,
      }, display: result.display);
    },
  ),
  AssistantTool(
    name: 'request_status',
    description:
        'Read or explicitly refresh the current Seerr status of a title shown in this task. '
        'Use seerr_id exactly as returned by find_title/find_request_title/discover_request_titles. '
        'Keeps standard and 4K copies and individual seasons separate. Unknown means unverified, not missing. '
        'No monitoring or automatic retry; a later question first finds the title again.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'seerr_id': {'type': 'string'},
      'four_k': {'type': 'boolean'},
    },
    required: const ['seerr_id'],
    serves: _servesRequests,
    run: (ctx, _, args) async {
      final shown =
          _shownRequestTitles[ctx]?[_string(args, 'seerr_id')] ?? (throw const AssistantToolError('unknown_seerr_id'));
      final client = _seerr(ctx);
      final state = await _readRequestState(ctx, client, shown, _bool(args, 'four_k'));
      return AssistantToolResult(state.data);
    },
  ),
  AssistantTool(
    name: 'request_title',
    description:
        'Request a missing title found with find_title, find_request_title or discover_request_titles, in the same task. '
        'The user confirms in Pleya. For a series, seasons lists season numbers; leave it out for every season '
        'not yet requested. An available library copy opens normally without a request. '
        'four_k only where can_request_4k was true. Use seerr_id exactly as returned. '
        'Never retry an uncertain write automatically; read request_status first and obtain a new confirmation.',
    risk: AssistantToolRisk.sensitive,
    needsServer: false,
    properties: const {
      'seerr_id': {'type': 'string'},
      'seasons': {
        'type': 'array',
        'items': {'type': 'integer'},
      },
      'four_k': {'type': 'boolean'},
    },
    required: const ['seerr_id'],
    serves: _servesRequests,
    run: (ctx, _, args) async {
      final shown =
          _shownRequestTitles[ctx]?[_string(args, 'seerr_id')] ?? (throw const AssistantToolError('unknown_seerr_id'));
      return _requestCard(ctx, shown, fourK: _bool(args, 'four_k'), wanted: _seasonNumbers(args));
    },
  ),
];
