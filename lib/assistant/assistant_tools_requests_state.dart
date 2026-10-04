part of 'assistant_tools.dart';

// Fresh, bounded request evidence. These helpers serve both existing request
// entry points and the read-only status tool; nothing runs in the background.
void _requestContextLive(AssistantToolContext ctx) {
  if (ctx.cancelled) throw const AssistantToolError('cancelled');
  final catalog = ctx.catalog;
  if (catalog != null && catalog.activeProfileId() != catalog.profileId) {
    throw const AssistantToolError('not_allowed');
  }
}

void _requestLive(AssistantToolContext ctx, SeerrClient client) {
  _requestContextLive(ctx);
  if (ctx.requests?.client() != client ||
      (_shownRequestClients[ctx] != null && _shownRequestClients[ctx] != client) ||
      (_shownRequestUsers[ctx] != null && _shownRequestUsers[ctx] != client.session.userId)) {
    throw const AssistantToolError('not_allowed');
  }
}

Future<T> _requestRead<T>(AssistantToolContext ctx, SeerrClient client, Future<T> Function() read) async {
  _requestLive(ctx, client);
  final value = await _seerrCall(
    () => ctx.cancel == null
        ? read()
        : Future.any<T>([read(), ctx.cancel!.trigger.then<T>((_) => throw const AssistantToolError('cancelled'))]),
  );
  _requestLive(ctx, client);
  return value;
}

/// Seerr's 1 is a real no-request state; a field we could not decode is not.
String _observedRequestStatus(Object? raw) => switch (raw) {
  1 => 'not_requested',
  2 => 'pending',
  3 => 'processing',
  4 => 'partially_available',
  5 => 'available',
  _ => 'unknown',
};

String _observedRequestLifecycle(Object? raw) => switch (raw) {
  1 => 'pending',
  2 => 'approved',
  3 => 'declined',
  4 => 'failed',
  5 => 'completed',
  _ => 'unknown',
};

class _RequestState {
  const _RequestState(this.media, this.fourK, this.status, this.seasons, this.requestStatuses);
  final SeerrMedia media;
  final bool fourK;
  final String status;
  final Map<int, String>? seasons;
  final List<String>? requestStatuses;

  Map<String, Object?> get data => {
    'seerr_id': '${media.mediaType}:${media.tmdbId}',
    'title': clipText(media.title),
    'status': status,
    'four_k': fourK,
    'request_statuses': requestStatuses ?? const ['unknown'],
    if (!media.isMovie)
      'seasons': [
        for (final n in (seasons?.keys.toList() ?? <int>[])..sort()) {'season': n, 'status': seasons![n]},
      ],
    if (!media.isMovie && seasons == null) 'season_coverage': 'unknown',
  };
}

Future<_RequestState> _readRequestState(
  AssistantToolContext ctx,
  SeerrClient client,
  SeerrMedia shown,
  bool fourK,
) async {
  final detail = await _requestRead(
    ctx,
    client,
    () => shown.isMovie ? client.getMovie(shown.tmdbId) : client.getTv(shown.tmdbId),
  );
  if (detail['id'] != shown.tmdbId || (detail[shown.isMovie ? 'title' : 'name'] is! String)) {
    throw const AssistantToolError('request_status_unknown');
  }
  final media = SeerrMedia.fromDetail(detail, mediaType: shown.mediaType);
  final info = detail['mediaInfo'];
  // Overseerr's detail mapper omits mediaInfo when no Media record exists.
  // Once a record exists, a missing/invalid field is unverified evidence.
  final status = info == null
      ? 'not_requested'
      : info is Map
      ? _observedRequestStatus(info[fourK ? 'status4k' : 'status'])
      : 'unknown';
  Map<int, String>? seasons;
  if (!shown.isMovie && detail['seasons'] is List) {
    final known = <int>{};
    var valid = true;
    for (final row in detail['seasons'] as List) {
      if (row is! Map || row['seasonNumber'] is! int || (row['seasonNumber'] as int) < 0) {
        valid = false;
        break;
      }
      final n = row['seasonNumber'] as int;
      if (n > 0 && !known.add(n)) valid = false;
    }
    if (valid && (info == null || (info is Map && info['seasons'] is List))) {
      seasons = {for (final n in known) n: 'not_requested'};
      final seen = <int>{};
      for (final row in info is Map ? info['seasons'] as List : const []) {
        if (row is! Map || row['seasonNumber'] is! int || !seen.add(row['seasonNumber'] as int)) {
          seasons = null;
          break;
        }
        final n = row['seasonNumber'] as int;
        if (known.contains(n)) seasons![n] = _observedRequestStatus(row[fourK ? 'status4k' : 'status']);
      }
    }
  }
  final List<String>? requestStatuses;
  if (info == null) {
    requestStatuses = const [];
  } else if (info is Map && info['requests'] is List) {
    requestStatuses = [
      for (final row in info['requests'] as List)
        if (row is! Map || row['is4k'] is! bool)
          'unknown'
        else if (row['is4k'] == fourK)
          _observedRequestLifecycle(row['status']),
    ];
  } else {
    requestStatuses = null;
  }
  return _RequestState(media, fourK, status, seasons, requestStatuses);
}

/// Ask Seerr again after confirmation, rather than trusting cached privileges.
Future<void> _requestRights(AssistantToolContext ctx, SeerrClient client, SeerrMedia media, bool fourK) async {
  final previousUser = client.session.userId;
  final me = await _requestRead(ctx, client, client.getMe);
  final permissions = me['permissions'];
  if (me['id'] is! int ||
      (me['id'] as int) < 1 ||
      (previousUser != null && me['id'] != previousUser) ||
      permissions is! int ||
      permissions < 0) {
    throw const AssistantToolError('not_allowed');
  }
  _shownRequestUsers[ctx] ??= me['id'] as int;
  _requestLive(ctx, client);
  // Overseerr allows the umbrella OR the matching per-type request flag.
  final permitted = fourK
      ? SeerrPermission.canRequest4k(permissions, isMovie: media.isMovie)
      : SeerrPermission.has(permissions, SeerrPermission.request | (media.isMovie ? 262144 : 524288));
  if (!permitted) throw AssistantToolError(fourK ? '4k_not_allowed' : 'not_allowed');
}

/// Current-profile visible library copies, using the same identity/search
/// primitives as ordinary results. Failed or unavailable sources prove no absence.
typedef _RequestLibraryEvidence = ({
  List<AssistantTitleTarget> targets,
  Set<String> knownLibraries,
  Set<String> visibleLibraries,
  bool qualityUncertain,
  Map<ServerId, MediaServerClient> clients,
});

Future<_RequestLibraryEvidence> _requestLibraryCopies(
  AssistantToolContext ctx,
  SeerrClient seerr,
  SeerrMedia media, {
  bool fourK = false,
}) async {
  final loader = ctx.catalog?.rowLoader;
  if (ctx.userServers.isNotEmpty && loader is! CatalogHomeCustomRowLoader) {
    throw const AssistantToolError('library_availability_unknown');
  }
  if (loader is! CatalogHomeCustomRowLoader) {
    return (
      targets: const <AssistantTitleTarget>[],
      knownLibraries: const <String>{},
      visibleLibraries: const <String>{},
      qualityUncertain: false,
      clients: const <ServerId, MediaServerClient>{},
    );
  }
  final kind = media.isMovie ? MediaKind.movie : MediaKind.show;
  final identity = MediaIdentity(
    externalIds: ExternalIds(tmdb: media.tmdbId),
    title: media.title,
    year: int.tryParse(media.year ?? ''),
    kind: kind,
  );
  final visibleLibraries = {for (final l in loader.librariesFor(kind)) buildGlobalKey(l.serverId, l.libraryId)};
  var qualityUncertain = false;
  final targets = <AssistantTitleTarget>[];
  final checkedClients = <ServerId, MediaServerClient>{};
  final knownLibraries = <String>{};
  for (final id in ctx.userServers) {
    if (!loader.librariesFor(kind).any((l) => l.serverId == id)) continue;
    final client = ctx.userClient(id);
    if (client == null) throw const AssistantToolError('library_availability_unknown');
    checkedClients[id] = client;
    try {
      var hits = await _requestRead(ctx, seerr, () async {
        return isIdentityEligibleBackend(client.backend)
            ? client.findAllByIdentity(identity)
            : Future.value(<MediaItem>[]);
      });
      if (ctx.userClient(id) != client) throw const AssistantToolError('not_allowed');
      final all = await _requestRead(ctx, seerr, client.fetchLibraries);
      if (ctx.userClient(id) != client) throw const AssistantToolError('not_allowed');
      knownLibraries.addAll(all.map((l) => l.globalKey));
      final visible = {for (final l in loader.librariesFor(kind)) buildGlobalKey(l.serverId, l.libraryId)};
      final hidden = {
        for (final l in all)
          if (l.kind == kind && !visible.contains(l.globalKey)) l.globalKey,
      };
      hits = visibleMatchesFromServer(
        hits,
        id,
        hidden,
      ).where((item) => item.libraryId != null && visible.contains(buildGlobalKey(id, item.libraryId!))).toList();
      // Identity lookups may be capped or ambiguous. A scoped title page
      // certifies absence/quality only when every matching row was observed.
      if (hits.isEmpty || fourK) {
        final candidates = <({MediaItem item, ExternalIds ids})>[];
        for (final library in loader.librariesFor(kind).where((l) => l.serverId == id)) {
          final query = LibraryQuery(kind: kind, search: media.title, limit: 100);
          final page = await _requestRead(
            ctx,
            seerr,
            () => switch (client) {
              PlexClient() => client.fetchLibraryContent(library.libraryId, query, requireTotalCount: true),
              JellyfinClient() => client.fetchLibraryPagedContent(
                library.libraryId,
                query: query,
                libraryKind: kind,
                requireTotalCount: true,
              ),
              _ => client.fetchLibraryPagedContent(library.libraryId, query: query, libraryKind: kind),
            },
          );
          if (ctx.userClient(id) != client) throw const AssistantToolError('not_allowed');
          if (page.offset != 0 ||
              page.totalCount < 0 ||
              page.totalCount != page.items.length ||
              page.items.length >= 100) {
            throw const AssistantToolError('library_availability_unknown');
          }
          for (final item in page.items) {
            // A conflicting top scope is never permission proof. Validate it
            // before another metadata read, and retain the queried provenance.
            if (item.libraryId != null && item.libraryId != library.libraryId) {
              throw const AssistantToolError('library_availability_unknown');
            }
            final ids = isIdentityEligibleBackend(client.backend)
                ? await _requestRead(ctx, seerr, () => client.fetchExternalIds(item.id))
                : const ExternalIds();
            if (ctx.userClient(id) != client) throw const AssistantToolError('not_allowed');
            candidates.add(
              MediaIdentity.candidate(item.libraryId == null ? item.copyWith(libraryId: library.libraryId) : item, ids),
            );
          }
        }
        final complete = identity.pickAllMatches(candidates);
        if (fourK &&
            candidates.any(
              (candidate) =>
                  candidate.ids.tmdb == null &&
                  !complete.any((item) => item.id == candidate.item.id) &&
                  identity.pickAllMatches([candidate]).isNotEmpty,
            )) {
          qualityUncertain = true;
        }
        if (complete.isEmpty && candidates.any((candidate) => identity.pickAllMatches([candidate]).isNotEmpty)) {
          throw const AssistantToolError('library_availability_unknown');
        }
        hits = {
          for (final item in [...hits, ...complete]) item.id: item,
        }.values.toList();
      }
      for (final item in visibleMatchesFromServer(hits, id, hidden)) {
        if (item.kind != kind) continue;
        targets.add((serverId: id, serverName: ctx.serverName(id), item: item.copyWith(serverId: id.value)));
      }
    } on AssistantToolError {
      rethrow;
    } catch (_) {
      throw const AssistantToolError('library_availability_unknown');
    }
  }
  final evidence = (
    targets: targets,
    knownLibraries: knownLibraries,
    visibleLibraries: visibleLibraries,
    qualityUncertain: qualityUncertain,
    clients: checkedClients,
  );
  _requestLibraryEvidenceLive(ctx, seerr, evidence, kind);
  return (
    targets: _visibleRequestCopies(ctx, seerr, evidence, kind),
    knownLibraries: knownLibraries,
    visibleLibraries: visibleLibraries,
    qualityUncertain: qualityUncertain,
    clients: checkedClients,
  );
}

void _requestLibraryEvidenceLive(
  AssistantToolContext ctx,
  SeerrClient seerr,
  _RequestLibraryEvidence evidence,
  MediaKind kind,
) {
  _visibleRequestCopies(ctx, seerr, evidence, kind);
  final loader = ctx.catalog?.rowLoader;
  final visible = {
    if (loader is CatalogHomeCustomRowLoader)
      for (final l in loader.librariesFor(kind)) buildGlobalKey(l.serverId, l.libraryId),
  };
  if (visible.length != evidence.visibleLibraries.length || !visible.containsAll(evidence.visibleLibraries)) {
    throw const AssistantToolError('not_allowed');
  }
}

List<AssistantTitleTarget> _visibleRequestCopies(
  AssistantToolContext ctx,
  SeerrClient seerr,
  _RequestLibraryEvidence evidence,
  MediaKind kind,
) {
  _requestLive(ctx, seerr);
  if (evidence.clients.entries.any((entry) => ctx.userClient(entry.key) != entry.value)) {
    throw const AssistantToolError('not_allowed');
  }
  final loader = ctx.catalog?.rowLoader;
  final visibleNow = {
    if (loader is CatalogHomeCustomRowLoader)
      for (final l in loader.librariesFor(kind)) buildGlobalKey(l.serverId, l.libraryId),
  };
  return evidence.targets.where((target) {
    final library = target.item.libraryId;
    if (library == null) return false;
    final key = buildGlobalKey(target.serverId, library);
    return visibleNow.contains(key);
  }).toList();
}

AssistantToolResult _availableRequestResult(
  AssistantToolContext ctx,
  SeerrMedia media,
  _RequestLibraryEvidence evidence,
  bool fourK,
) {
  _requestLibraryEvidenceLive(ctx, _seerr(ctx), evidence, media.isMovie ? MediaKind.movie : MediaKind.show);
  final targets = _visibleRequestCopies(ctx, _seerr(ctx), evidence, media.isMovie ? MediaKind.movie : MediaKind.show);
  if (targets.isEmpty) throw const AssistantToolError('not_allowed');
  for (final target in targets) {
    ctx.showItem(target.serverId, target.item.id);
  }
  return AssistantToolResult(
    {'status': 'already_available', 'title': clipText(media.title), 'four_k': fourK, 'done': false},
    display: AssistantTitleMatches(ctx, [
      AssistantTitleMatch(
        matchId: 'available',
        title: clipText(media.title),
        year: int.tryParse(media.year ?? ''),
        kind: media.isMovie ? 'movie' : 'show',
        confidence: 'high',
        targets: targets,
      ),
    ]),
  );
}

({List<int>? seasons, String? covered}) _requestSelection(_RequestState state, List<int>? wanted) {
  final statuses = state.media.isMovie ? {0: state.status} : state.seasons;
  if (statuses == null) throw const AssistantToolError('request_status_unknown');
  if (wanted != null && wanted.any((n) => !statuses.containsKey(n))) throw const AssistantToolError('unknown_season');
  final asked = wanted ?? statuses.keys.toList();
  if (asked.isEmpty) throw const AssistantToolError('no_seasons');
  if (asked.any((n) => statuses[n] == 'unknown')) throw const AssistantToolError('request_status_unknown');
  final missing = [
    for (final n in asked)
      if (statuses[n] == 'not_requested') n,
  ]..sort();
  return (
    seasons: state.media.isMovie ? null : missing,
    covered: missing.isNotEmpty
        ? null
        : asked.every((n) => statuses[n] == 'available')
        ? 'already_available'
        : 'already_requested',
  );
}

Future<_RequestLibraryEvidence> _libraryRequestedCopies(
  AssistantToolContext ctx,
  SeerrClient client,
  SeerrMedia media,
  _RequestLibraryEvidence evidence,
  bool fourK,
) async {
  // A series result proves only that show exists, never that every season does.
  final copies = _visibleRequestCopies(ctx, client, evidence, media.isMovie ? MediaKind.movie : MediaKind.show);
  if (media.isMovie && fourK && copies.isEmpty && evidence.qualityUncertain) {
    throw const AssistantToolError('library_availability_unknown');
  }
  if (!media.isMovie || copies.isEmpty) {
    return (
      targets: const <AssistantTitleTarget>[],
      knownLibraries: evidence.knownLibraries,
      visibleLibraries: evidence.visibleLibraries,
      qualityUncertain: evidence.qualityUncertain,
      clients: evidence.clients,
    );
  }
  if (!fourK) {
    return (
      targets: copies,
      knownLibraries: evidence.knownLibraries,
      visibleLibraries: evidence.visibleLibraries,
      qualityUncertain: evidence.qualityUncertain,
      clients: evidence.clients,
    );
  }
  var unknown = evidence.qualityUncertain;
  final available = <AssistantTitleTarget>[];
  for (final copy in copies) {
    final source = ctx.userClient(copy.serverId);
    if (source == null) throw const AssistantToolError('library_availability_unknown');
    final item = copy.item.mediaVersions == null
        ? await _requestRead(ctx, client, () => source.fetchItem(copy.item.id))
        : copy.item;
    if (ctx.userClient(copy.serverId) != source) throw const AssistantToolError('not_allowed');
    final versions = item?.mediaVersions;
    if (versions == null || versions.isEmpty) {
      unknown = true;
      continue;
    }
    for (final version in versions) {
      final resolution = version.videoResolution?.toLowerCase();
      if ((version.height ?? 0) >= 2160 || resolution == '4k' || resolution == '2160') {
        available.add(copy);
        break;
      }
      if (version.height == null &&
          resolution != '1080' &&
          resolution != '720' &&
          resolution != 'sd' &&
          resolution != '480' &&
          resolution != '576') {
        unknown = true;
      }
    }
  }
  final observed = (
    targets: available,
    knownLibraries: evidence.knownLibraries,
    visibleLibraries: evidence.visibleLibraries,
    qualityUncertain: evidence.qualityUncertain,
    clients: evidence.clients,
  );
  final visible = _visibleRequestCopies(ctx, client, observed, MediaKind.movie);
  if (visible.isEmpty && unknown) throw const AssistantToolError('library_availability_unknown');
  return (
    targets: visible,
    knownLibraries: evidence.knownLibraries,
    visibleLibraries: evidence.visibleLibraries,
    qualityUncertain: evidence.qualityUncertain,
    clients: evidence.clients,
  );
}
