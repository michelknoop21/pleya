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

bool _servesRequests(AssistantToolContext ctx, ServerId _) => ctx.requests?.client() != null;

SeerrClient _seerr(AssistantToolContext ctx) =>
    ctx.requests?.client() ?? (throw const AssistantToolError('requests_not_available'));

/// Seerr's own failures as codes; the server's message text never reaches the model.
Future<T> _seerrCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on SeerrException catch (e) {
    if (e.isAuth || e.isForbidden) throw const AssistantToolError('not_allowed');
    if (e.isNetwork) throw const AssistantToolError('requests_not_available');
    rethrow;
  }
}

String _requestStatus(SeerrMediaStatus status) => switch (status) {
  SeerrMediaStatus.available => 'available',
  SeerrMediaStatus.partiallyAvailable => 'partially_available',
  SeerrMediaStatus.pending || SeerrMediaStatus.processing => 'requested',
  SeerrMediaStatus.unknown => 'not_requested',
};

/// `mediaInfo.status`, or `status4k` for the 4K copy, which Overseerr tracks
/// separately on the media and on each season.
SeerrMediaStatus _infoStatus(Object? info, bool fourK) {
  final value = info is Map ? info[fourK ? 'status4k' : 'status'] : null;
  return SeerrMediaStatus.fromValue(value is num ? value.toInt() : null);
}

/// Season number to status, specials left out, as the request sheet does.
Map<int, SeerrMediaStatus> _seasonStatuses(Map<String, dynamic> detail, bool fourK) {
  final seasons = SeerrSeason.listFromDetail(detail);
  if (!fourK) return {for (final s in seasons) s.seasonNumber: s.status};
  final info = detail['mediaInfo'];
  final known = <int, SeerrMediaStatus>{
    if (info is Map && info['seasons'] is List)
      for (final s in info['seasons'] as List)
        if (s is Map && s['seasonNumber'] is num) (s['seasonNumber'] as num).toInt(): _infoStatus(s, true),
  };
  return {for (final s in seasons) s.seasonNumber: known[s.seasonNumber] ?? SeerrMediaStatus.unknown};
}

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
      final candidates = _candidates(args);
      // Ten results at most in all, at least two per candidate.
      final perCandidate = (10 ~/ candidates.length).clamp(2, 8);
      final found = <SeerrMedia>[];
      // Three searches at a time, as the aggregation service does.
      for (var start = 0; start < candidates.length; start += 3) {
        final pages = await Future.wait([
          for (final c in candidates.skip(start).take(3)) _seerrCall(() => client.search(c.title)),
        ]);
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
      return _requestOptions(ctx, client, found);
    },
  ),
  AssistantTool(
    name: 'discover_request_titles',
    description:
        'Browse the request service (Seerr) when the user describes a kind of film or series but no title '
        'comes to mind. Genres are TMDB genre names. Filters the service cannot apply come back in '
        'ignored_filters; say so instead of pretending they were used. Returns at most 10 titles with a '
        'seerr_id for request_title.',
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
    },
    required: const ['kind'],
    serves: _servesRequests,
    run: (ctx, _, args) async {
      final client = _seerr(ctx);
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

      // The API documents date ranges, keywords and original language on
      // /discover; SeerrClient only passes genre and sortBy through yet.
      final ignored = <Map<String, Object?>>[
        if (yearFrom != null) {'filter': 'year_from', 'reason': 'not_supported'},
        if (yearTo != null) {'filter': 'year_to', 'reason': 'not_supported'},
        if (keywords.isNotEmpty) {'filter': 'keywords', 'reason': 'not_supported'},
        if (language != null) {'filter': 'original_language', 'reason': 'not_supported'},
      ];

      int? genre;
      List<String>? knownGenres;
      if (genreNames.isNotEmpty) {
        final all = await _seerrCall(() => movies ? client.getMovieGenres() : client.getTvGenres());
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
            ? client.discoverMovies(genre: genre, sortBy: sortBy)
            : client.discoverTv(genre: genre, sortBy: sortBy),
      );
      final result = _requestOptions(ctx, client, page.items.take(10));
      return AssistantToolResult({
        ...result.data,
        if (ignored.isNotEmpty) 'ignored_filters': ignored,
        'known_genres': ?knownGenres,
      }, display: result.display);
    },
  ),
  AssistantTool(
    name: 'request_title',
    description:
        'Ask the request service to add a title found with find_request_title or discover_request_titles. '
        'The user confirms in Pleya. For a series, seasons lists season numbers; leave it out for every season '
        'not yet requested. four_k only where can_request_4k was true. Use seerr_id exactly as it was returned.',
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
