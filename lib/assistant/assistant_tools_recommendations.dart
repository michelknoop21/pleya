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
        'Unknown access, watch state or requested metadata excludes a title. Series completion aggregates cannot prove zero child progress, so strict unseen series are unavailable. Results are a bounded sample, ordered by rating then stable identity. '
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
  final aliases = <String, String>{};
  final ambiguous = <Map<String, Object?>>[];
  final missing = <String>[];
  for (final name in names) {
    final matchingProfiles = profiles
        .where((p) => p.displayName.trim().toLowerCase() == name.trim().toLowerCase())
        .toList();
    final aliasIds = {for (final p in matchingProfiles) ...p.userIds};
    final matches = users
        .where(
          (u) => name.trim().toLowerCase() == 'me'
              ? client.sameUserId(u.id, client.connection.userId)
              : matchingProfiles.isNotEmpty
              ? aliasIds.any((alias) => client.sameUserId(alias, u.id))
              : u.name.trim().toLowerCase() == name.trim().toLowerCase(),
        )
        .toList();
    if (matches.length == 1 && matchingProfiles.length <= 1) {
      selected[matches.single.id] = matches.single;
      if (matchingProfiles.isNotEmpty) aliases[name] = matches.single.id;
    } else if (matches.isEmpty) {
      missing.add(clipText(name, 64));
    } else {
      (_offeredParticipants[ctx] ??= {}).addAll(matches.map((u) => u.id));
      ambiguous.add({
        'name': clipText(name, 64),
        'choices': [
          for (final u in matches) {'user_id': u.id, 'name': clipText(u.name, 64), 'server_id': id.value},
        ],
      });
    }
  }
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
  final candidates = <String, ({MediaItem item, String libraryId})>{};
  var partial = false;
  var sampled = false;
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
    for (final group in content.groups) {
      for (final source in group.sources) {
        if (source.serverId != id || source.item.kind != kind || source.libraryId == null) continue;
        if (catalog.rowLoader case final CatalogHomeCustomRowLoader loader) {
          if (!loader
              .librariesFor(kind)
              .any((library) => library.serverId == id && library.libraryId == source.libraryId))
            continue;
        }
        if (candidates.length == _cohortCandidateCap && !candidates.containsKey(source.item.id)) {
          sampled = true;
          continue;
        }
        candidateLibraries[source.libraryId!] = kind;
        candidates[source.item.id] = (item: source.item, libraryId: source.libraryId!);
      }
    }
  }
  final libraries = {for (final entry in candidates.entries) entry.key: entry.value.libraryId};
  final requesterEvidence = await client.readParticipantEvidence(
    requester.id,
    libraries,
    abort: ctx.cancel,
    checkCurrent: checkCurrent,
  );
  checkCurrent();
  final evidence = <String, Map<String, ParticipantItemEvidence>>{requester.id: requesterEvidence};
  final candidateCount = candidates.length;
  var unknown = 0;
  var denied = 0;
  var watched = 0;
  var filtered = 0;
  candidates.removeWhere((key, _) {
    final observation = requesterEvidence[key] ?? const ParticipantItemEvidence();
    if (observation.access == ParticipantAccess.denied) {
      denied++;
      return true;
    }
    if (observation.watch == ParticipantWatchState.watched) {
      watched++;
      return true;
    }
    if (observation.access != ParticipantAccess.allowed || observation.watch != ParticipantWatchState.unwatched) {
      unknown++;
      return true;
    }
    if (observation.item == null || !filters.matches(observation.item!)) {
      filtered++;
      return true;
    }
    return false;
  });
  final eligibleLibraries = {for (final entry in candidates.entries) entry.key: entry.value.libraryId};
  for (final user in selected.values.where((u) => u.id != requester.id)) {
    evidence[user.id] = await client.readParticipantEvidence(
      user.id,
      eligibleLibraries,
      abort: ctx.cancel,
      checkCurrent: checkCurrent,
    );
    checkCurrent();
  }
  final matches = <MediaItem>[];
  for (final entry in candidates.entries) {
    final observations = [
      for (final user in selected.values) evidence[user.id]?[entry.key] ?? const ParticipantItemEvidence(),
    ];
    if (observations.any((e) => e.access == ParticipantAccess.denied)) {
      denied++;
      continue;
    }
    if (observations.any((e) => e.watch == ParticipantWatchState.watched)) {
      watched++;
      continue;
    }
    if (observations.any((e) => e.access != ParticipantAccess.allowed || e.watch != ParticipantWatchState.unwatched)) {
      unknown++;
      continue;
    }
    final item = observations.first.item;
    if (item == null || !filters.matches(item)) {
      filtered++;
      continue;
    }
    matches.add(item);
  }
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
    'profile_aliases': aliases,
    'identity_scope': 'server_user_shared_bindings_share_one_history',
    'participants': [
      for (final u in selected.values) {'user_id': u.id, 'name': clipText(u.name, 64)},
    ],
    'coverage': {
      'candidates_checked': candidateCount,
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
