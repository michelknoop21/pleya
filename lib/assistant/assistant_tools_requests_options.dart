part of 'assistant_tools.dart';

// Request options for the UI and the confirmation card a pick turns into.

/// One title Big P found, as the UI draws it on an option card. Built from
/// Seerr data; the full [overview] stays here and never reaches the model.
class AssistantRequestOption {
  const AssistantRequestOption({
    required this.seerrId,
    required this.title,
    required this.kind,
    required this.posterUrl,
    required this.overview,
    required this.status,
    this.year,
  });

  /// Pass to [assistantRequestFromOption] when the user picks this card.
  final String seerrId;
  final String title;
  final int? year;

  /// `movie` or `series`.
  final String kind;

  /// Full TMDB poster URL as the Aanvragen screens build it; empty when Seerr has none.
  final String posterUrl;
  final String overview;

  /// `available`, `partially_available`, `requested` or `not_requested`.
  final String status;
}

/// Options from `find_request_title` or `discover_request_titles`. [context]
/// is the ask that showed them: hand it back to [assistantRequestFromOption],
/// which only accepts ids this context showed.
class AssistantRequestOptions extends AssistantDisplay {
  const AssistantRequestOptions(this.context, this.options);
  final AssistantToolContext context;
  final List<AssistantRequestOption> options;
}

/// Registers [found] in the run's allow-list and returns what the model gets
/// and what the UI shows. The model sees a short overview clip so it can
/// match a description; the card gets a longer one.
AssistantToolResult _requestOptions(AssistantToolContext ctx, SeerrClient client, Iterable<SeerrMedia> found) {
  _requestLive(ctx, client);
  _shownRequestClients[ctx] ??= client;
  if (client.session.userId case final user?) _shownRequestUsers[ctx] ??= user;
  final shown = _shownRequestTitles[ctx] ??= {};
  final permissions = client.session.permissions;
  final rows = <Map<String, Object?>>[];
  final options = <AssistantRequestOption>[];
  for (final m in found) {
    final id = '${m.mediaType}:${m.tmdbId}';
    if (rows.any((r) => r['seerr_id'] == id)) continue;
    shown[id] = m;
    final title = clipText(m.title);
    final year = int.tryParse(m.year ?? '');
    final kind = m.isMovie ? 'movie' : 'series';
    final status = _requestStatus(m.status);
    rows.add({
      'seerr_id': id,
      'title': title,
      'year': ?year,
      'kind': kind,
      'status': status,
      'can_request_4k': SeerrPermission.canRequest4k(permissions, isMovie: m.isMovie),
      if (clipText(m.overview, 120) case final o when o.isNotEmpty) 'overview': o,
    });
    options.add(
      AssistantRequestOption(
        seerrId: id,
        title: title,
        year: year,
        kind: kind,
        posterUrl: m.posterUrl,
        overview: clipText(m.overview, 300),
        status: status,
      ),
    );
  }
  return AssistantToolResult({'titles': rows}, display: AssistantRequestOptions(ctx, options));
}

typedef _Candidate = ({String title, String? kind, int? year});

List<_Candidate> _candidates(Map<String, Object?> args) {
  final value = args['titles'];
  if (value is! List || value.isEmpty || value.length > 5) throw const AssistantToolError('invalid_titles');
  return [
    for (final c in value)
      if (c is! Map) throw const AssistantToolError('invalid_titles') else _candidate(c.cast<String, Object?>()),
  ];
}

_Candidate _candidate(Map<String, Object?> c) {
  final kind = c['kind'];
  if (kind != null && kind != 'movie' && kind != 'series') throw const AssistantToolError('invalid_kind');
  final year = c['year'];
  if (year != null && year is! int) throw const AssistantToolError('invalid_year');
  return (title: clipText(_string(c, 'title'), 100), kind: kind as String?, year: year as int?);
}

int? _yearArg(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value == null) return null;
  if (value is! int || value < 1870 || value > 2100) throw AssistantToolError('invalid_$key');
  return value;
}

/// The card for [shown], built from a fresh Seerr answer. Shared by
/// `request_title` and [assistantRequestFromOption], so both paths show and
/// send exactly the same thing.
Future<AssistantToolOutcome> _requestCard(
  AssistantToolContext ctx,
  SeerrMedia shown, {
  required bool fourK,
  List<int>? wanted,
}) async {
  final client = _seerr(ctx);
  _requestLive(ctx, client);
  if (shown.isMovie && wanted != null) throw const AssistantToolError('invalid_seasons');
  if (fourK && !SeerrPermission.canRequest4k(client.session.permissions, isMovie: shown.isMovie)) {
    throw const AssistantToolError('4k_not_allowed');
  }
  final state = await _readRequestState(ctx, client, shown, fourK);
  final title = clipText(state.media.title);
  final subject = state.media.year == null ? title : '$title (${state.media.year})';
  final selection = _requestSelection(state, wanted);
  if (selection.covered != null && selection.covered != 'already_available') {
    return AssistantToolResult({'status': selection.covered, 'title': subject, if (fourK) 'four_k': true});
  }
  try {
    final copies = await _requestLibraryCopies(ctx, client, state.media, fourK: fourK);
    final available = await _libraryRequestedCopies(ctx, client, state.media, copies, fourK);
    if (available.targets.isNotEmpty) {
      return _availableRequestResult(ctx, state.media, available, fourK);
    }
  } on AssistantToolError catch (e) {
    if (selection.covered != 'already_available' || e.code != 'library_availability_unknown') rethrow;
    _requestLive(ctx, client);
    return AssistantToolResult({
      'status': selection.covered,
      'title': subject,
      if (fourK) 'four_k': true,
      'library_availability': 'unknown',
    });
  }
  if (selection.covered != null) {
    return AssistantToolResult({'status': selection.covered, 'title': subject, if (fourK) 'four_k': true});
  }
  await _requestRights(ctx, client, shown, fourK);
  final seasons = selection.seasons == null ? null : List<int>.unmodifiable(selection.seasons!);
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
      _requestLive(ctx, client);
      final fresh = await _readRequestState(ctx, client, shown, fourK);
      final checked = _requestSelection(fresh, seasons);
      if (checked.covered != null) return {'status': checked.covered, 'title': subject, 'done': false};
      if (seasons != null && checked.seasons!.length != seasons.length) {
        return {'error': 'request_coverage_changed', 'done': false};
      }
      final copies = await _requestLibraryCopies(ctx, client, fresh.media, fourK: fourK);
      final available = await _libraryRequestedCopies(ctx, client, fresh.media, copies, fourK);
      if (_visibleRequestCopies(ctx, client, available, shown.isMovie ? MediaKind.movie : MediaKind.show).isNotEmpty) {
        return {'status': 'already_available', 'title': subject, 'done': false};
      }
      await _requestRights(ctx, client, shown, fourK);
      _requestLibraryEvidenceLive(ctx, client, copies, shown.isMovie ? MediaKind.movie : MediaKind.show);
      final Map<String, dynamic> response;
      try {
        response = await client.createRequest(
          mediaType: shown.mediaType,
          tmdbId: shown.tmdbId,
          seasons: seasons,
          is4k: fourK,
        );
      } on SeerrException catch (e) {
        _requestLive(ctx, client);
        if (e.isAuth || e.isForbidden) throw const AssistantToolError('not_allowed');
        if (e.statusCode == 409) {
          return {'status': 'already_requested', 'title': subject, 'done': false};
        }
        // The service may have accepted a write whose response was lost.
        // A new request always starts with another fresh read and confirmation.
        return {
          'error': e.isNetwork || (e.statusCode ?? 0) >= 500 ? 'request_outcome_unknown' : 'request_failed',
          'done': false,
        };
      }
      _requestLive(ctx, client);
      final base = <String, Object?>{
        'accepted': true,
        'title': subject,
        'seasons': ?seasons,
        if (fourK) 'four_k': true,
        'request_status': _observedRequestLifecycle(response['status']),
      };
      try {
        final observed = await _readRequestState(ctx, client, shown, fourK);
        return {
          ...base,
          'status': observed.status == 'pending' ? 'requested' : observed.status,
          if (!shown.isMovie) 'season_statuses': observed.data['seasons'],
        };
      } on AssistantToolError catch (e) {
        _requestLive(ctx, client);
        return {...base, 'status': 'unknown', 'status_error': e.code};
      }
    },
  );
}

/// The user picked an option card: the same card `request_title` builds, no
/// model involved. Only an id [ctx] showed is accepted, so pass
/// [AssistantRequestOptions.context]. A refusal comes back as
/// `AssistantToolResult({'error': code})`; an [AssistantPendingAction] goes
/// through the same confirmation as a model-made one (re-check entitlement
/// and `ctx.requests?.client()` before running it).
Future<AssistantToolOutcome> assistantRequestFromOption(
  AssistantToolContext ctx,
  String seerrId, {
  bool fourK = false,
  List<int>? seasons,
}) async {
  try {
    final shown = _shownRequestTitles[ctx]?[seerrId] ?? (throw const AssistantToolError('unknown_seerr_id'));
    return await _requestCard(ctx, shown, fourK: fourK, wanted: _seasonNumbers({'seasons': seasons}));
  } on AssistantToolError catch (e) {
    return AssistantToolResult({'error': e.code});
  }
}
