part of 'assistant_tools.dart';

const _cohortCandidateCap = 40;
const _cohortParticipantCap = 8;

/// User ids this run offered as an ambiguous choice. The choice is the
/// user's: the model cannot answer its own question, so a later call in the
/// same run that resolves to one of them, by id, name or alias, gets the
/// clarification again. A new run (a new context) starts clean.
final _offeredParticipants = Expando<Set<String>>('offeredParticipants');

final List<AssistantTool> _recommendationTools = [
  AssistantTool(
    name: 'recommend_together',
    description:
        'Find titles from this profile\'s visible catalog that every named participant can access and has explicitly not watched. '
        'Strict cohort evidence is supported only for the current authorized Jellyfin administrator. '
        'Names resolve local Pleya profile labels to verified server identities, otherwise uniquely match server users; ambiguity returns authorized choices for conversational clarification: ask the user, a choice offered in this turn stays unresolved until they answer. '
        'The current server user is always included; me names that same identity. Explicit user_ids must be verified against the fresh authorized user list. '
        'Unknown access, watch state or requested metadata excludes a title. A title with several copies on the server counts once and needs that proof for every copy. Series completion aggregates cannot prove zero child progress, so strict unseen series are unavailable. Results are a bounded sample, ordered by rating then stable identity. '
        'Explain coverage and facts as returned; never invent tastes, history overlap or unwatched status from absent history.',
    risk: AssistantToolRisk.read,
    properties: const {
      'participants': {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 1,
        'maxItems': _cohortParticipantCap,
      },
      'user_ids': {
        'type': 'array',
        'items': {'type': 'string'},
        'maxItems': _cohortParticipantCap,
      },
      ...AssistantStrictFilters.properties,
      'limit': {'type': 'integer'},
    },
    serves: (ctx, id) => ctx.catalog != null && ctx.userClient(id) != null,
    run: _recommendTogether,
  ),
];

Future<AssistantToolOutcome> _recommendTogether(
  AssistantToolContext ctx,
  ServerId? serverId,
  Map<String, Object?> args,
) async {
  final id = serverId!;
  final catalog = ctx.catalog ?? (throw const AssistantToolError('catalog_unavailable'));
  final filters = AssistantStrictFilters.parse(args);
  final limit = _int(args, 'limit', 1, 20) ?? 10;
  final names = _strings(args, 'participants');
  final explicitIds = _strings(args, 'user_ids');
  if (names.length + explicitIds.length < 1 ||
      names.length + explicitIds.length > _cohortParticipantCap ||
      [...names, ...explicitIds].any((s) => s.trim().isEmpty || s.length > 64))
    throw const AssistantToolError('invalid_participants');
  final client = ctx.adminClient(id);
  if (client is! JellyfinClient || client.connection.isEmby) {
    return const AssistantToolResult({
      'status': 'unsupported_strict_cohort',
      'coverage': 'No reliable item access and explicit unwatched evidence for every participant on this backend.',
      'results': <Object>[],
    });
  }
  final requesterId = client.connection.userId;
  final candidateLibraries = <String, MediaKind>{};
  void checkCurrent() {
    if (ctx.cancelled) throw const AssistantToolError('cancelled');
    if (catalog.activeProfileId() != catalog.profileId) throw const AssistantToolError('profile_changed');
    if (!identical(ctx.adminClient(id), client) || client.connection.userId != requesterId)
      throw const AssistantToolError('not_allowed');
    if (catalog.rowLoader case final CatalogHomeCustomRowLoader loader) {
      for (final entry in candidateLibraries.entries) {
        if (!loader
            .librariesFor(entry.value)
            .any((library) => library.serverId == id && library.libraryId == entry.key))
          throw const AssistantToolError('catalog_changed');
      }
    }
  }

  checkCurrent();
  await client.assertRecommendationAdministrator(abort: ctx.cancel, checkCurrent: checkCurrent);
  final users = await client.listUsers();
  checkCurrent();
  final requester = users.where((u) => client.sameUserId(u.id, client.connection.userId)).firstOrNull;
  if (requester == null) throw const AssistantToolError('current_user_unknown');
  final profiles = await catalog.participantProfiles?.call(id) ?? const <ProfileServerIdentity>[];
  checkCurrent();
  final selected = <String, ServerUser>{requester.id: requester};
  final offeredBefore = {...?_offeredParticipants[ctx]};
  final people = resolvePeople(
    names: names,
    users: users,
    profiles: profiles,
    sameUserId: client.sameUserId,
    requesterUserId: client.connection.userId,
    initial: selected,
  );
  selected
    ..clear()
    ..addAll(people.selected);
  final ambiguous = <Map<String, Object?>>[];
  for (final entry in people.ambiguous) {
    (_offeredParticipants[ctx] ??= {}).addAll(entry.choices.map((u) => u.id));
    ambiguous.add({
      'name': clipText(entry.name, 64),
      'choices': [
        for (final u in entry.choices) {'user_id': u.id, 'name': clipText(u.name, 64), 'server_id': id.value},
      ],
    });
  }
  final missing = [for (final name in people.missing) clipText(name, 64)];
  for (final userId in explicitIds) {
    final match = users.where((u) => client.sameUserId(u.id, userId)).firstOrNull;
    if (match == null) throw const AssistantToolError('unknown_user_id');
    selected[match.id] = match;
  }
  if (selected.length > _cohortParticipantCap) throw const AssistantToolError('invalid_participants');
  await client.assertRecommendationAdministrator(abort: ctx.cancel, checkCurrent: checkCurrent);
  // Keep every cohort result in this run tied to its original authority.
  // A later recommendation must not replace an earlier result's source checks.
  final priorCheck = ctx.recommendationCheck;
  ctx.recommendationCheck = () {
    priorCheck?.call();
    checkCurrent();
  };
  final unanswered = [
    for (final u in selected.values)
      if (u.id != requester.id && offeredBefore.contains(u.id)) clipText(u.name, 64),
  ];
  if (ambiguous.isNotEmpty || missing.isNotEmpty || unanswered.isNotEmpty)
    return AssistantToolResult({
      'status': 'participant_clarification',
      'ambiguous': ambiguous,
      'not_found': missing,
      if (unanswered.isNotEmpty) 'ask_the_user_which': unanswered,
      'results': <Object>[],
    });
  // Proof is per title, not per copy: one film in "Films" and "Films 4K" is
  // one title with two copies, and a copy someone watched, may not open or
  // Pleya cannot read rules the title out. [titles] holds each title's copies.
  final candidates = <String, ({MediaItem item, String libraryId})>{};
  final titles = <List<String>>[];
  var partial = false;
  var sampled = false;
  var unknown = 0;
  var denied = 0;
  var watched = 0;
  var filtered = 0;
  for (final kind in filters.kind == null ? [MediaKind.movie, MediaKind.show] : [filters.kind!]) {
    final content = await catalog.rowLoader.load(
      // The 40 slots go to this server's titles the requester has not
      // watched; the exact reads below still prove it per participant.
      HomeCustomRow(
        id: '',
        kind: kind,
        preferences: UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched, serverIds: {id.value}),
        ),
      ),
      limit: _cohortCandidateCap,
    );
    checkCurrent();
    partial |= content.isPartial;
    sampled |= !content.isExact;
    final visible = switch (catalog.rowLoader) {
      final CatalogHomeCustomRowLoader loader => {
        for (final library in loader.librariesFor(kind))
          if (library.serverId == id) library.libraryId,
      },
      _ => null,
    };
    for (final group in content.groups) {
      final copies = [
        for (final source in group.sources)
          if (source.serverId == id && source.item.kind == kind) source,
      ];
      if (copies.isEmpty) continue;
      // A copy outside the visible libraries is never read, so nothing
      // proves it unwatched: the title goes.
      if (copies.any((c) => c.libraryId == null || !(visible?.contains(c.libraryId) ?? true))) {
        unknown++;
        continue;
      }
      // A title is read with all its copies or not at all.
      final fresh = {
        for (final c in copies)
          if (!candidates.containsKey(c.item.id)) c.item.id,
      };
      if (candidates.length + fresh.length > _cohortCandidateCap) {
        sampled = true;
        continue;
      }
      for (final c in copies) {
        candidateLibraries[c.libraryId!] = kind;
        candidates[c.item.id] = (item: c.item, libraryId: c.libraryId!);
      }
      titles.add([for (final c in copies) c.item.id]);
    }
  }
  final titleCount = titles.length + unknown;
  final evidence = <String, Map<String, ParticipantItemEvidence>>{};

  /// True when [title] stays in: every copy allowed and unwatched for every
  /// user in [users], and a copy that meets the filters. Counts why not.
  bool proven(List<String> title, Iterable<ServerUser> users) {
    final observations = [
      for (final copy in title)
        for (final user in users) evidence[user.id]?[copy] ?? const ParticipantItemEvidence(),
    ];
    if (observations.any((e) => e.access == ParticipantAccess.denied)) {
      denied++;
    } else if (observations.any((e) => e.watch == ParticipantWatchState.watched)) {
      watched++;
    } else if (observations.any(
      (e) => e.access != ParticipantAccess.allowed || e.watch != ParticipantWatchState.unwatched,
    )) {
      unknown++;
    } else if (_cohortCopy(title, evidence[requester.id], filters) == null) {
      filtered++;
    } else {
      return true;
    }
    return false;
  }

  evidence[requester.id] = await client.readParticipantEvidence(
    requester.id,
    {for (final entry in candidates.entries) entry.key: entry.value.libraryId},
    abort: ctx.cancel,
    checkCurrent: checkCurrent,
  );
  checkCurrent();
  titles.retainWhere((title) => proven(title, [requester]));
  final eligibleLibraries = {
    for (final title in titles)
      for (final copy in title) copy: candidates[copy]!.libraryId,
  };
  final others = selected.values.where((u) => u.id != requester.id).toList();
  for (final user in others) {
    evidence[user.id] = await client.readParticipantEvidence(
      user.id,
      eligibleLibraries,
      abort: ctx.cancel,
      checkCurrent: checkCurrent,
    );
    checkCurrent();
  }
  // One result per title, however many copies it has.
  final matches = <MediaItem>[
    for (final title in titles)
      if (others.isEmpty || proven(title, others)) _cohortCopy(title, evidence[requester.id], filters)!,
  ];
  matches.sort((a, b) {
    final rating = (b.rating ?? -1).compareTo(a.rating ?? -1);
    return rating != 0 ? rating : a.globalKey.compareTo(b.globalKey);
  });
  await client.assertRecommendationAdministrator(abort: ctx.cancel, checkCurrent: checkCurrent);
  checkCurrent();
  // Library preferences are live too: a hidden source cannot leak after an
  // outstanding participant request finishes.
  if (catalog.rowLoader case final CatalogHomeCustomRowLoader loader) {
    matches.removeWhere(
      (match) => !loader
          .librariesFor(match.kind)
          .any((library) => library.serverId == id && library.libraryId == match.libraryId),
    );
  }
  final shown = matches.take(limit).toList();
  for (final match in shown) ctx.showItem(id, match.id);
  return AssistantToolResult({
    'status': 'strict_cohort_results',
    'can_become_home_row': false,
    'home_row_unavailable_reason': 'Participant access and watch evidence cannot be replayed by a saved Home row.',
    'server_id': id.value,
    'profile_aliases': people.aliases,
    'identity_scope': 'server_user_shared_bindings_share_one_history',
    'participants': [
      for (final u in selected.values) {'user_id': u.id, 'name': clipText(u.name, 64)},
    ],
    // Asked for series: the strict "nobody watched it" proof does not exist for
    // them, so an empty list is the tool's limit and not a lack of titles.
    if (filters.kind == MediaKind.show) 'series_unsupported': true,
    'coverage': {
      'candidates_checked': titleCount,
      'copies_read': candidates.length,
      'candidate_cap': _cohortCandidateCap,
      'series_unseen_supported': false,
      'sampled': sampled,
      'partial': partial,
      'excluded_unknown': unknown,
      'excluded_no_access': denied,
      'excluded_watched': watched,
      'excluded_metadata': filtered,
      'scope': 'requester_unwatched_titles_in_current_profile_visible_catalog_on_selected_server',
    },
    'results': [
      for (final match in shown)
        {
          'item_id': match.id,
          'server_id': id.value,
          'title': clipText(match.title),
          'year': match.year,
          'reasons': {
            'access_proved_for': selected.keys.toList(),
            'unwatched_proved_for': selected.keys.toList(),
            ...filters.facts(match),
          },
        },
    ],
  }, display: AssistantMediaGrid([for (final match in shown) (item: match, group: null)]));
}

/// The copy of [title] the result names: the first whose metadata the
/// requester's read returned and that meets [filters]. Null when none does.
MediaItem? _cohortCopy(
  List<String> title,
  Map<String, ParticipantItemEvidence>? requesterEvidence,
  AssistantStrictFilters filters,
) => title.map((copy) => requesterEvidence?[copy]?.item).nonNulls.where(filters.matches).firstOrNull;
