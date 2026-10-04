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
    this.facts,
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

  /// Age rating, genres, runtime and services, when looked up.
  final TitleFacts? facts;
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
/// match a description; the card gets a longer one. With [age] only titles
/// the age gate allows for it are kept, and registered.
Future<AssistantToolResult> _requestOptions(
  AssistantToolContext ctx,
  SeerrClient client,
  Iterable<SeerrMedia> found,
  int? age,
) async {
  final unique = <String, SeerrMedia>{};
  for (final m in found) {
    unique.putIfAbsent('${m.mediaType}:${m.tmdbId}', () => m);
  }
  final gated = await _gateTitles(ctx, unique.values.toList(), _seerrRef, age);
  final shown = _shownRequestTitles[ctx] ??= {};
  final permissions = client.session.permissions;
  final rows = <Map<String, Object?>>[];
  final options = <AssistantRequestOption>[];
  for (final (m, facts) in gated.kept) {
    final id = '${m.mediaType}:${m.tmdbId}';
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
      ..._factsField(facts, gated.region),
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
        facts: facts,
      ),
    );
  }
  return AssistantToolResult({'titles': rows, ...gated.note}, display: AssistantRequestOptions(ctx, options));
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
  if (fourK && !SeerrPermission.canRequest4k(client.session.permissions, isMovie: shown.isMovie)) {
    throw const AssistantToolError('4k_not_allowed');
  }
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
