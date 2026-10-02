part of 'assistant_tools.dart';

/// Asking for a title that is not in any library, through Seerr (Overseerr or
/// Jellyseerr).
///
/// Two tools on purpose. Finding is a read any profile with a Seerr session
/// may do; requesting is visible to the household and takes server disk, so
/// it waits for a Pleya card. The split is also the allow-list: only a title
/// `find_request_title` showed in this run can be requested.
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
        'Search the request service (Seerr) for a film or series that is not in a library yet. '
        'Returns a seerr_id per title for request_title, and whether it is already available or requested.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'query': {'type': 'string'},
      'kind': {
        'type': 'string',
        'enum': ['movie', 'series'],
      },
      'year': {'type': 'integer'},
    },
    required: const ['query'],
    serves: _servesRequests,
    run: (ctx, _, args) async {
      final client = _seerr(ctx);
      final query = clipText(_string(args, 'query'), 100);
      final kind = args['kind'];
      if (kind != null && kind != 'movie' && kind != 'series') throw const AssistantToolError('invalid_kind');
      final year = args['year'];
      if (year != null && year is! int) throw const AssistantToolError('invalid_year');
      final page = await _seerrCall(() => client.search(query));
      final shown = _shownRequestTitles[ctx] ??= {};
      final permissions = client.session.permissions;
      return AssistantToolResult({
        'titles': [
          for (final m
              in page.items
                  .where((m) => (kind == null || m.isMovie == (kind == 'movie')) && (year == null || m.year == '$year'))
                  .take(8))
            () {
              final id = '${m.mediaType}:${m.tmdbId}';
              shown[id] = m;
              return {
                'seerr_id': id,
                'title': clipText(m.title),
                'year': ?int.tryParse(m.year ?? ''),
                'kind': m.isMovie ? 'movie' : 'series',
                'status': _requestStatus(m.status),
                'can_request_4k': SeerrPermission.canRequest4k(permissions, isMovie: m.isMovie),
              };
            }(),
        ],
      });
    },
  ),
  AssistantTool(
    name: 'request_title',
    description:
        'Ask the request service to add a title found with find_request_title. The user confirms in Pleya. '
        'For a series, seasons lists season numbers; leave it out for every season not yet requested. '
        'four_k only where can_request_4k was true. $_serverIdNote',
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
      final client = _seerr(ctx);
      final fourK = _bool(args, 'four_k');
      if (fourK && !SeerrPermission.canRequest4k(client.session.permissions, isMovie: shown.isMovie)) {
        throw const AssistantToolError('4k_not_allowed');
      }
      final wanted = _seasonNumbers(args);
      if (shown.isMovie && wanted != null) throw const AssistantToolError('invalid_seasons');

      // Fresh from Seerr: the status may have moved since the search, and
      // the card is built from this answer, not from the model.
      final detail = await _seerrCall(() => shown.isMovie ? client.getMovie(shown.tmdbId) : client.getTv(shown.tmdbId));
      final media = SeerrMedia.fromDetail(detail, mediaType: shown.mediaType);
      final title = clipText(media.title.isEmpty ? shown.title : media.title);
      final subject = media.year == null ? title : '$title (${media.year})';

      List<int>? seasons;
      final List<SeerrMediaStatus> covered;
      if (shown.isMovie) {
        final status = _infoStatus(detail['mediaInfo'], fourK);
        covered = status == SeerrMediaStatus.unknown ? const [] : [status];
      } else {
        final all = _seasonStatuses(detail, fourK);
        if (wanted != null && wanted.any((n) => !all.containsKey(n))) throw const AssistantToolError('unknown_season');
        final asked = wanted ?? all.keys.toList();
        if (asked.isEmpty) throw const AssistantToolError('no_seasons');
        seasons = [
          for (final n in asked)
            if (all[n] == SeerrMediaStatus.unknown) n,
        ]..sort();
        covered = seasons.isEmpty ? [for (final n in asked) all[n]!] : const [];
      }
      if (covered.isNotEmpty) {
        return AssistantToolResult({
          'status': covered.every((s) => s.isAvailable) ? 'already_available' : 'already_requested',
          'title': subject,
          if (fourK) 'four_k': true,
        });
      }

      return AssistantPendingAction(
        kind: AssistantActionKind.requestTitle,
        serverId: _seerrServerId,
        serverName: clipText(Uri.tryParse(client.session.baseUrl)?.host ?? 'Seerr', 64),
        subject: subject,
        items: [
          for (final n in seasons ?? const <int>[]) t.seerr.season(number: n),
          if (fourK) '4K',
        ],
        execute: ({password}) async {
          // The card may have been open a while: after a disconnect or a
          // profile switch this request no longer belongs to this client.
          if (ctx.requests?.client() != client) throw const AssistantToolError('not_allowed');
          await _seerrCall(
            () => client.createRequest(mediaType: shown.mediaType, tmdbId: shown.tmdbId, seasons: seasons, is4k: fourK),
          );
          return {'status': 'requested', 'title': subject, 'seasons': ?seasons, if (fourK) 'four_k': true};
        },
      );
    },
  ),
];
