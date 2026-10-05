part of 'assistant_tools.dart';

/// Conservative routing before the model can issue an immediate admin call.
bool assistantNeedsLibraryDoctorScope(String prompt) {
  if (assistantIsMissingEpisodeDiagnosis(prompt)) return true;
  final text = prompt.toLowerCase();
  if (RegExp(
    r'(diagnos\w*|check|inspect|controleer|onderzoek).*(episode|aflever|season|seizoen|metadata|edition|editie|subtitle|ondertitel|duplicate|duplicat|dubbel)|'
    r'(missing|ontbre\w*|missen|geen|zonder|without|no\b|incomplete|onvolledig\w*|inconsistent|conflict\w*|incorrect|wrong|verkeerd\w*|slecht\w*).*(subtitle|ondertitel|metadata)|'
    r'(subtitle|ondertitel|metadata).*(missing|ontbre\w*|missen|geen|zonder|without|no\b|incomplete|onvolledig\w*|inconsistent|conflict\w*|incorrect|wrong|verkeerd\w*|slecht\w*)|'
    r'(duplicate|duplicat|dubbel).*(movie|film|title|titel|show|serie)|'
    r'(movie|film|title|titel|show|serie).*(duplicate|duplicat|dubbel)|'
    r'\bmist\b.*\bseizoen\b|'
    r'\baflevering\b.*\bniet tussen\b|'
    r'\bklopt\b.*\bmetadata\b|'
    r'(duplicate|duplicat|dubbel).*(version|versie)|'
    r'(missing|ontbrekende|ontbreken|missen).*(episode|aflever)|'
    r'(episode|aflever).*(missing|ontbre|missen)',
  ).hasMatch(text)) {
    return true;
  }
  return RegExp(
    r'library doctor|bibliotheekdokter|diagnos\w*.*(library|libraries|bibliothe)|'
    r'(library|libraries|bibliothe).*diagnos|'
    r'(check|inspect|controleer|onderzoek).*(library|libraries|bibliothe)|'
    r'(missing|ontbrekende|ontbreken|gaps|gaten|dubbel|duplicate).*(library|libraries|bibliothe)|'
    r'(library|libraries|bibliothe).*(missing|ontbre|gaps|gaten|dubbel|duplicate)',
  ).hasMatch(text);
}

final _doctorProposals = Expando<Map<String, _DoctorProposal>>('libraryDoctorProposals');

final List<AssistantTool> _libraryDoctorTools = [
  AssistantTool(
    name: 'diagnose_library',
    description:
        'Library Doctor: read this profile\'s visible movie/series libraries. '
        'Report concrete metadata differences, copies/editions, Dutch subtitle evidence and numbered gaps. '
        'Only missing_aired is proved absent; unknown and partial coverage never prove absence. '
        'No repairs. Supported actions are proposals requiring a Pleya confirmation. '
        'Use their exact doctor_option_id with the named existing tool; no other administration.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {
      'server_id': {'type': 'string'},
      'library_id': {'type': 'string'},
      'item_id': {'type': 'string'},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 40},
    },
    serves: (ctx, _) => ctx.catalog?.rowLoader is CatalogHomeCustomRowLoader,
    run: (ctx, _, args) => _diagnoseLibrary(ctx, args),
  ),
];

/// A bounded diagnosis, and the exact source snapshot its facts refer to.
class _DoctorScan {
  _DoctorScan(this.ctx, this.loader, this.roots)
    : visible = _doctorVisible(loader),
      clients = {for (final root in roots) root.serverId: ctx.userClient(root.serverId)},
      seerr = ctx.requests?.client();
  final AssistantToolContext ctx;
  final CatalogHomeCustomRowLoader loader;
  final List<CatalogLibrary> roots;
  final Set<String> visible;
  final Map<ServerId, MediaServerClient?> clients;
  final SeerrClient? seerr;
  final abort = AbortController();
  final elapsed = Stopwatch()..start();
  final reasons = <String>{};
  final coverage = <Map<String, Object?>>[];
  int calls = 0;
  int checked = 0;
  bool expectedRead = false;

  void check() {
    if (ctx.cancelled) throw const AssistantToolError('cancelled');
    if (ctx.catalog!.activeProfileId() != ctx.catalog!.profileId) {
      throw const AssistantToolError('profile_changed');
    }
    if (!_setSame(visible, _doctorVisible(loader)) ||
        clients.entries.any((e) => !identical(ctx.userClient(e.key), e.value)) ||
        (expectedRead && !identical(ctx.requests?.client(), seerr))) {
      throw const AssistantToolError('catalog_changed');
    }
  }

  Future<T> read<T>(Future<T> Function() operation) async {
    check();
    if (calls >= 100) throw const AssistantToolError('diagnosis_call_limit');
    final remaining = const Duration(seconds: 15) - elapsed.elapsed;
    if (remaining <= Duration.zero) throw const AssistantToolError('diagnosis_deadline');
    calls++;
    final value = await Future.any<T>([
      operation(),
      if (ctx.cancel != null) ctx.cancel!.trigger.then<T>((_) => throw const AssistantToolError('cancelled')),
    ]).timeout(remaining);
    check();
    return value;
  }

  Future<T?> attempt<T>(Future<T> Function() operation) async {
    try {
      return await read(operation);
    } on AssistantToolError catch (e) {
      if (const {'cancelled', 'profile_changed', 'catalog_changed'}.contains(e.code)) rethrow;
      reasons.add(e.code);
    } on TimeoutException {
      check();
      reasons.add('diagnosis_deadline');
      abort.abort();
    } catch (_) {
      check();
      reasons.add('read_failed');
    }
    return null;
  }

  Future<({List<MediaItem> items, bool complete})> pages(
    String scope,
    int limit,
    Future<LibraryPage<MediaItem>> Function(int offset, int size) fetch,
    bool Function(MediaItem) valid,
  ) async {
    final items = <MediaItem>[];
    final seen = <String>{};
    int? total;
    var offset = 0;
    var complete = false;
    for (var pageIndex = 0; pageIndex < 4 && offset < limit; pageIndex++) {
      final size = min(50, limit - offset);
      final page = await attempt(() => fetch(offset, size));
      if (page == null) break;
      if (page.offset != offset ||
          page.totalCount < 0 ||
          (total != null && total != page.totalCount) ||
          page.items.length > size) {
        reasons.add('inconsistent_page');
        break;
      }
      total = page.totalCount;
      var invalid = false;
      for (final item in page.items) {
        if (!seen.add(item.id) || !valid(item)) {
          invalid = true;
          reasons.add('invalid_or_repeated_item');
        } else {
          items.add(item);
        }
      }
      offset += page.items.length;
      if (invalid || offset > total) break;
      if (offset == total) {
        complete = true;
        break;
      }
      if (page.items.isEmpty) {
        reasons.add('incomplete_page');
        break;
      }
    }
    if (!complete) reasons.add('partial_enumeration');
    coverage.add({'scope': scope, 'checked': items.length, 'reported_total': total, 'complete': complete});
    return (items: items, complete: complete);
  }
}

Set<String> _doctorVisible(CatalogHomeCustomRowLoader loader) => {
  for (final kind in const [MediaKind.movie, MediaKind.show])
    for (final root in loader.librariesFor(kind)) buildGlobalKey(root.serverId, root.libraryId),
};

bool _doctorItemScope(MediaItem item, CatalogLibrary root, {MediaItem? source, String? parent}) {
  final explicitRoot = item.backend == MediaBackend.jellyfin ? (item.raw?['ParentLibraryId']) : item.libraryId;
  return item.id.isNotEmpty &&
      item.backend == root.backend &&
      (item.serverId == null || item.serverId == root.serverId.value) &&
      (!(item.raw?.containsKey('ParentLibraryId') ?? false) || explicitRoot is String && explicitRoot.isNotEmpty) &&
      (explicitRoot == null || explicitRoot == root.libraryId) &&
      (source == null || item.id == source.id && item.kind == source.kind) &&
      (parent == null || item.parentId == parent);
}

Future<AssistantToolOutcome> _diagnoseLibrary(AssistantToolContext ctx, Map<String, Object?> args) async {
  ctx.libraryDoctorMode = true;
  ctx.libraryDoctorActions.clear();
  _doctorProposals[ctx] = {};
  final catalog = ctx.catalog ?? (throw const AssistantToolError('catalog_unavailable'));
  final loader = catalog.rowLoader;
  if (loader is! CatalogHomeCustomRowLoader) throw const AssistantToolError('catalog_unavailable');
  final limit = _int(args, 'limit', 1, 40) ?? 20;
  final server = args.containsKey('server_id') ? _string(args, 'server_id') : null;
  final library = args.containsKey('library_id') ? _string(args, 'library_id') : null;
  final itemId = args.containsKey('item_id') ? _string(args, 'item_id') : null;
  if ((library != null || itemId != null) && server == null) throw const AssistantToolError('missing_server_id');
  if (itemId != null) ctx.requireShownItem(ServerId(server!), itemId);
  final roots = [
    for (final kind in const [MediaKind.movie, MediaKind.show])
      for (final root in loader.librariesFor(kind))
        if ((server == null || root.serverId.value == server) && (library == null || root.libraryId == library)) root,
  ];
  if (roots.isEmpty) throw const AssistantToolError('unknown_visible_library');
  final scan = _DoctorScan(ctx, loader, roots);
  scan.check();
  ctx.libraryDoctorCheck = scan.check;
  if (ctx.cancel != null) unawaited(ctx.cancel!.trigger.then((_) => scan.abort.abort()));
  final facts = <Map<String, Object?>>[];
  final hydrated = <MediaItem>[];
  final proposals = <Map<String, Object?>>[];
  try {
    if (roots.length > 8) scan.reasons.add('library_limit');
    for (final root in roots.take(8)) {
      final client = scan.clients[root.serverId];
      if (client == null) {
        scan.reasons.add('server_unavailable');
        continue;
      }
      final kind = loader.librariesFor(MediaKind.movie).contains(root) ? MediaKind.movie : MediaKind.show;
      final remaining = limit - hydrated.length;
      if (remaining <= 0) {
        scan.reasons.add('item_limit');
        break;
      }
      final rows = await scan.pages(
        buildGlobalKey(root.serverId, root.libraryId),
        remaining,
        (offset, size) => client.fetchLibraryPagedContent(
          root.libraryId,
          query: LibraryQuery(kind: kind, offset: offset, limit: size),
          libraryKind: kind,
          abort: scan.abort,
        ),
        (item) => _doctorItemScope(item, root) && item.kind == kind,
      );
      for (final row in rows.items.where((item) => itemId == null || item.id == itemId)) {
        final item = await scan.attempt(() => client.fetchItem(row.id));
        scan.checked++;
        // The row's current root query proves membership. If Jellyfin's
        // hydrated DTO omits the root, retain that proof only while its parent
        // agrees with the queried row; a move during hydration stays unknown.
        if (item == null ||
            !_doctorItemScope(item, root, source: row) ||
            (item.backend == MediaBackend.jellyfin &&
                item.raw?['ParentLibraryId'] == null &&
                item.parentId != row.parentId)) {
          scan.reasons.add('unavailable_metadata');
          continue;
        }
        final scoped = item.copyWith(serverId: root.serverId.value, libraryId: root.libraryId);
        hydrated.add(scoped);
        final missing = [
          if (item.title?.trim().isNotEmpty != true) 'title',
          if (item.year == null) 'year',
          if (item.summary?.trim().isNotEmpty != true) 'summary',
          if (item.thumbPath?.isNotEmpty != true) 'poster',
        ];
        final fact = <String, Object?>{
          'item_id': item.id,
          'server_id': root.serverId.value,
          'library_id': root.libraryId,
          'title': clipText(item.title),
          'missing_metadata': missing,
          'versions': _doctorVersions(item),
        };
        if (item.kind == MediaKind.show) {
          fact['seasons'] = await _doctorSeasons(scan, root, scoped, rows.complete);
        }
        facts.add(fact);
        scan.check();
        ctx.showItem(root.serverId, item.id);
        // Concrete facts may offer existing jobs; no diagnosis ever invokes one.
        final supportsMembershipProof = client is JellyfinClient || client is PlexClient;
        if (supportsMembershipProof &&
            missing.isNotEmpty &&
            ctx.admin<ItemMetadataRefreshClient>(root.serverId) != null) {
          proposals.add(_doctorPropose(ctx, scan, root, scoped, AssistantActionKind.refreshMetadata));
        }
        final seasons = fact['seasons'];
        if (supportsMembershipProof &&
            seasons is List &&
            seasons.any((s) => s is Map && (s['missing_aired'] as List).isNotEmpty) &&
            ctx.admin<LibraryScanClient>(root.serverId) != null &&
            !proposals.any(
              (p) =>
                  p['tool'] == 'scan_library' &&
                  p['server_id'] == root.serverId.value &&
                  p['library_id'] == root.libraryId,
            )) {
          proposals.add(_doctorPropose(ctx, scan, root, scoped, AssistantActionKind.scanLibrary));
        }
      }
    }
    if (itemId != null && !hydrated.any((i) => i.id == itemId)) {
      throw const AssistantToolError('item_not_in_checked_scope');
    }
    final groups = await scan.attempt(() => _doctorGroups(scan, hydrated));
    scan.check();
    final data = <String, Object?>{
      'items': facts,
      'groups': [
        for (final group in groups ?? const <UnifiedMediaGroup>[])
          {
            'title': clipText(group.representativeSource.item.title),
            'source_count': group.sources.length,
            'duplicate_status': 'not_proven',
            'metadata_differences': _doctorDifferences(group),
            'sources': [
              for (final source in group.sources)
                {
                  'server_id': source.serverId.value,
                  'item_id': source.item.id,
                  'edition': clipText(source.item.editionTitle),
                },
            ],
          },
      ],
      'actions': proposals,
      'partial': scan.reasons.isNotEmpty,
      'coverage': {
        'items_checked': scan.checked,
        'read_operations': scan.calls,
        'pages': scan.coverage,
        'limits': scan.reasons.toList(),
        'item_limit': limit,
        'library_limit': 8,
        'page_limit': 4,
      },
    };
    ctx.libraryDoctorAnswer = (language) => _doctorAnswer(data, language);
    return AssistantToolResult(data);
  } finally {
    scan.abort.abort();
  }
}

List<Map<String, Object?>> _doctorVersions(MediaItem item) => [
  for (final version in item.mediaVersions ?? [])
    {
      'version_id': version.id,
      'name': clipText(version.name),
      'edition': clipText(item.editionTitle),
      'resolution': version.videoResolution,
      'dutch_subtitles': _doctorDutch(item, version.id),
    },
  if (item.mediaVersions?.isNotEmpty != true) {'dutch_subtitles': 'unknown'},
];

bool _doctorDutchLanguage(Object? language) =>
    language is String && const {'nl', 'nld', 'dut', 'dutch', 'nederlands'}.contains(language.trim().toLowerCase());

String _doctorDutch(MediaItem item, String versionId) {
  final versions = item.mediaVersions ?? [];
  for (final version in versions.where((v) => v.id == versionId)) {
    if (version.parts
        .expand((p) => p.streams)
        .any((s) => s.kind == MediaStreamKind.subtitle && _doctorDutchLanguage(s.languageCode))) {
      return 'present';
    }
  }
  // Raw Jellyfin DTOs retain whether streams were omitted, plus unsupported
  // tracks. Other backends cannot prove completeness from the mapped list.
  if (item.backend != MediaBackend.jellyfin) return 'unknown';
  final sources = item.raw?['MediaSources'];
  if (sources is! List) return 'unknown';
  final matches = sources.where((s) => s is Map && s['Id'] == versionId).toList();
  if (matches.length != 1) return 'unknown';
  final streams = (matches.single as Map)['MediaStreams'];
  if (streams is! List ||
      streams.any((s) {
        if (s is! Map) return true;
        final type = s['Type'];
        return type is! String || !const {'Video', 'Audio', 'Subtitle', 'Attachment', 'Data'}.contains(type);
      })) {
    return 'unknown';
  }
  var unknown = false;
  for (final stream in streams.cast<Map>()) {
    if (stream['Type'] != 'Subtitle') continue;
    if (_doctorDutchLanguage(stream['Language'])) return 'present';
    final language = stream['Language'];
    // Absence needs interpretable languages, not merely non-Dutch strings.
    if (language is! String ||
        !const {
          'en',
          'eng',
          'english',
          'fr',
          'fra',
          'fre',
          'de',
          'deu',
          'ger',
          'es',
          'spa',
          'it',
          'ita',
          'pt',
          'por',
          'ja',
          'jpn',
          'ko',
          'kor',
          'zh',
          'zho',
          'chi',
          'ar',
          'ara',
          'ru',
          'rus',
          'sv',
          'swe',
          'da',
          'dan',
          'no',
          'nor',
          'fi',
          'fin',
          'pl',
          'pol',
          'tr',
          'tur',
          'uk',
          'ukr',
          'cs',
          'ces',
          'cze',
          'hu',
          'hun',
          'he',
          'heb',
          'ro',
          'ron',
          'rum',
          'el',
          'ell',
          'gre',
        }.contains(language.trim().toLowerCase())) {
      unknown = true;
    }
  }
  return unknown ? 'unknown' : 'absent';
}

Map<String, Object?> _doctorDifferences(UnifiedMediaGroup group) {
  final values = <String, Set<Object>>{};
  for (final source in group.sources) {
    for (final entry in {
      'title': source.item.title,
      'year': source.item.year,
      'summary': source.item.summary,
      'content_rating': source.item.contentRating,
    }.entries) {
      final value = entry.value;
      if (value != null) (values[entry.key] ??= {}).add(value);
    }
  }
  return {
    for (final entry in values.entries)
      if (entry.value.length > 1)
        entry.key: [for (final value in entry.value) value is String ? clipText(value, 160) : value],
  };
}

Future<List<UnifiedMediaGroup>> _doctorGroups(_DoctorScan scan, List<MediaItem> items) async {
  final resolver = UnifiedIdentityResolver(
    fetchExternalIds: (server, id) => scan.read(() {
      final client = scan.clients[ServerId(server)] ?? (throw const AssistantToolError('catalog_changed'));
      return client.fetchExternalIds(id);
    }),
  );
  final evidence = await resolver.resolveEvidence([
    for (final item in items)
      ResolvableItem(
        item: item,
        identity: canonicalIdentityOf(item),
        scope: (canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque()).granularity.name,
        externalIdTarget: normalizeStableGuid(item.guid) == null ? (serverId: item.serverId!, targetId: item.id) : null,
      ),
  ]);
  scan.check();
  return groupUnifiedMediaSources([
    for (var i = 0; i < items.length; i++)
      GroupingCandidate(source: UnifiedMediaSource.fromItem(items[i]), evidence: evidence[i]),
  ]);
}

Future<List<Map<String, Object?>>> _doctorSeasons(
  _DoctorScan scan,
  CatalogLibrary root,
  MediaItem show,
  bool rootComplete,
) async {
  final client = scan.clients[root.serverId]!;
  final seasons = await scan.pages(
    'show:${show.id}',
    30,
    (offset, size) => client.fetchChildrenPage(show.id, start: offset, size: size, abort: scan.abort),
    (item) => _doctorItemScope(item, root, parent: show.id) && item.kind == MediaKind.season,
  );
  Map? expected;
  int? tmdb;
  if (scan.seerr != null) {
    scan.expectedRead = true;
    final ids = await scan.attempt(() => client.fetchExternalIds(show.id));
    tmdb = ids?.tmdb;
    if (tmdb != null && tmdb > 0) expected = await scan.attempt(() => scan.seerr!.getTv(tmdb!));
    if (expected?['id'] != tmdb) expected = null;
  }
  final facts = <Map<String, Object?>>[];
  final seasonNumbers = <int>{};
  final numberingUnique = seasons.items.every((s) => s.index != null && seasonNumbers.add(s.index!));
  for (final season in seasons.items.take(8)) {
    final number = season.index;
    final episodes = await scan.pages(
      'season:${season.id}',
      200,
      (offset, size) => client.fetchChildrenPage(season.id, start: offset, size: size, abort: scan.abort),
      (item) =>
          _doctorItemScope(item, root, parent: season.id) &&
          item.kind == MediaKind.episode &&
          (item.grandparentId == null || item.grandparentId == show.id),
    );
    final present = <int>{};
    var compatible = numberingUnique && number != null && number > 0;
    for (final episode in episodes.items) {
      final first = episode.index;
      final rawEnd = episode.backend == MediaBackend.jellyfin ? (episode.raw?['IndexNumberEnd']) : null;
      final last = rawEnd ?? first;
      if (first == null || first < 1 || last is! int || last < first || last > 1000 || episode.parentIndex != number) {
        compatible = false;
        continue;
      }
      for (var n = first; n <= last; n++) {
        if (!present.add(n)) compatible = false;
      }
    }
    final gaps = <int>[];
    if (compatible && present.isNotEmpty) {
      for (var n = 1; n <= present.reduce(max); n++) {
        if (!present.contains(n)) gaps.add(n);
      }
    }
    final missing = <int>[];
    var expectedKnown = false;
    final expectedSeasons = expected?['seasons'];
    final matching = expectedSeasons is List
        ? expectedSeasons.where((s) => s is Map && s['seasonNumber'] == number).toList()
        : const [];
    if (compatible && rootComplete && seasons.complete && episodes.complete && matching.length == 1 && tmdb != null) {
      final detail = await scan.attempt(() => scan.seerr!.getTvSeason(tmdb!, number!));
      final rows = detail?['episodes'];
      final count = (matching.single as Map)['episodeCount'];
      final dates = <int, DateTime>{};
      var valid =
          detail?['seasonNumber'] == number &&
          rows is List &&
          count is int &&
          count > 0 &&
          count <= 1000 &&
          rows.length == count;
      if (valid) {
        for (final row in rows) {
          final n = row is Map ? row['episodeNumber'] : null;
          final date = row is Map ? _doctorDate(row['airDate']) : null;
          if (row is! Map ||
              row['seasonNumber'] != number ||
              n is! int ||
              n < 1 ||
              n > count ||
              date == null ||
              dates.containsKey(n)) {
            valid = false;
            break;
          }
          dates[n] = date;
        }
        if (present.any((n) => !dates.containsKey(n))) valid = false;
        // At least one ordinary local episode must corroborate this numbering
        // scheme/date. A compound range alone cannot establish compatibility.
        var corroborated = false;
        for (final episode in episodes.items) {
          final end = episode.raw?['IndexNumberEnd'];
          if (end != null && end != episode.index) continue;
          final localDate = _doctorDate(episode.originallyAvailableAt);
          if (localDate == null || dates[episode.index] != localDate) {
            valid = false;
          } else {
            corroborated = true;
          }
        }
        valid = valid && corroborated;
      }
      if (valid) {
        expectedKnown = true;
        final today = DateTime.now().toUtc();
        for (final entry in dates.entries) {
          if (!present.contains(entry.key) && entry.value.isBefore(DateTime.utc(today.year, today.month, today.day))) {
            missing.add(entry.key);
          }
        }
      }
    }
    facts.add({
      'season': number,
      'numbering': number == 0
          ? 'specials'
          : compatible
          ? 'known'
          : 'unknown',
      'numbering_gaps': gaps,
      'missing_aired': missing,
      'expected': expectedKnown ? 'verified' : 'unknown',
      'complete': episodes.complete && seasons.complete && rootComplete,
    });
  }
  if (seasons.items.length > 8) scan.reasons.add('season_limit');
  final expectedSeasons = expected?['seasons'];
  if (expectedSeasons is List) {
    for (final season in expectedSeasons.take(30)) {
      final number = season is Map ? season['seasonNumber'] : null;
      if (number is int && number > 0 && !seasonNumbers.contains(number)) {
        facts.add({
          'season': number,
          'numbering': 'unknown',
          'numbering_gaps': <int>[],
          'missing_aired': <int>[],
          'expected': 'unknown',
          'complete': seasons.complete && rootComplete,
          'presence': 'not_in_checked_seasons',
        });
      }
    }
    if (expectedSeasons.length > 30) scan.reasons.add('expected_season_limit');
  }
  return facts;
}

DateTime? _doctorDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

class _DoctorProposal {
  const _DoctorProposal(this.scan, this.root, this.item, this.kind);
  final _DoctorScan scan;
  final CatalogLibrary root;
  final MediaItem item;
  final AssistantActionKind kind;
}

Map<String, Object?> _doctorPropose(
  AssistantToolContext ctx,
  _DoctorScan scan,
  CatalogLibrary root,
  MediaItem item,
  AssistantActionKind kind,
) {
  final token = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  final tool = kind == AssistantActionKind.scanLibrary ? 'scan_library' : 'refresh_metadata';
  (_doctorProposals[ctx] ??= {})[token] = _DoctorProposal(scan, root, item, kind);
  ctx.libraryDoctorActions.add(tool);
  return {
    'doctor_option_id': token,
    'tool': tool,
    'server_id': root.serverId.value,
    'library_id': root.libraryId,
    if (kind == AssistantActionKind.refreshMetadata) 'item_id': item.id,
    'subject': clipText(kind == AssistantActionKind.scanLibrary ? root.libraryTitle : item.title),
    'requires_confirmation': true,
  };
}

Future<AssistantPendingAction> _doctorPending(
  AssistantToolContext ctx,
  ServerId id,
  Map<String, Object?> args,
  AssistantActionKind kind,
) async {
  final token = _string(args, 'doctor_option_id');
  final proposal = _doctorProposals[ctx]?[token];
  if (proposal == null ||
      proposal.kind != kind ||
      proposal.root.serverId != id ||
      (args.containsKey('server_id') && args['server_id'] != id.value) ||
      (args.containsKey('tool') &&
          args['tool'] != (kind == AssistantActionKind.scanLibrary ? 'scan_library' : 'refresh_metadata')) ||
      (kind == AssistantActionKind.scanLibrary && args.containsKey('item_id')) ||
      (args.containsKey('library_id') && args['library_id'] != proposal.root.libraryId) ||
      (kind == AssistantActionKind.scanLibrary && args['library_id'] != proposal.root.libraryId) ||
      (kind == AssistantActionKind.refreshMetadata && args['item_id'] != proposal.item.id)) {
    throw const AssistantToolError('unknown_doctor_option');
  }
  final scan = proposal.scan;
  final root = proposal.root;
  Future<void> checkAction() async {
    final client = scan.clients[id]!;
    void checkAuthority() {
      scan.check();
      if (!identical(ctx.adminClient(id), client) ||
          (kind == AssistantActionKind.scanLibrary && ctx.admin<LibraryScanClient>(id) == null) ||
          (kind == AssistantActionKind.refreshMetadata && ctx.admin<ItemMetadataRefreshClient>(id) == null)) {
        throw const AssistantToolError('not_allowed');
      }
    }

    // Waiting for confirmation does not consume this separate fresh-read budget.
    // Both hydration and membership share it; neither can outlive cancellation.
    final elapsed = Stopwatch()..start();
    Future<T> fresh<T>(Future<T> Function() operation) async {
      checkAuthority();
      final remaining = const Duration(seconds: 8) - elapsed.elapsed;
      if (remaining <= Duration.zero) throw const AssistantToolError('diagnosis_deadline');
      final value = await Future.any<T>([
        operation(),
        if (ctx.cancel != null) ctx.cancel!.trigger.then<T>((_) => throw const AssistantToolError('cancelled')),
      ]).timeout(remaining);
      checkAuthority();
      return value;
    }

    final item = await fresh(() => client.fetchItem(proposal.item.id));
    if (item == null ||
        !_doctorItemScope(item, root, source: proposal.item) ||
        item.guid != proposal.item.guid ||
        item.title != proposal.item.title ||
        item.year != proposal.item.year) {
      throw const AssistantToolError('catalog_changed');
    }
    // Jellyfin's fresh DTO may contain only a nested ParentId. That is not
    // root authority. Requery the captured, still-visible root and fail closed
    // unless the bounded title candidate page is complete and contains this item.
    final query = LibraryQuery(kind: item.kind, search: item.title, limit: 200);
    final page = await fresh(
      () => switch (client) {
        JellyfinClient() => client.fetchLibraryPagedContent(
          root.libraryId,
          query: query,
          libraryKind: item.kind,
          requireTotalCount: true,
        ),
        PlexClient() => client.fetchLibraryContent(root.libraryId, query, requireTotalCount: true),
        _ => throw const AssistantToolError('library_membership_unknown'),
      },
    );
    if (page.offset != 0 ||
        page.totalCount != page.items.length ||
        page.items.length > 200 ||
        page.items.map((row) => row.id).toSet().length != page.items.length ||
        page.items.any((row) => !_doctorItemScope(row, root) || row.kind != item.kind) ||
        !page.items.any(
          (row) =>
              _doctorItemScope(row, root, source: item) &&
              row.guid == item.guid &&
              row.title == item.title &&
              row.year == item.year &&
              row.parentId == item.parentId,
        )) {
      throw const AssistantToolError('catalog_changed');
    }
    checkAuthority();
  }

  await checkAction();
  AssistantJobWatch? watch;
  return AssistantPendingAction(
    kind: kind,
    serverId: id,
    serverName: ctx.serverName(id),
    subject: clipText(kind == AssistantActionKind.scanLibrary ? root.libraryTitle : proposal.item.title),
    // Stamped when the scan is sent, not when the card is made: a scan that
    // ends while the card waits is not this one.
    jobAtRun: kind == AssistantActionKind.scanLibrary
        ? () => watch ??= AssistantJobWatch(serverId: id, startedAt: DateTime.now(), libraryId: root.libraryId)
        : null,
    execute: ({password}) async {
      if (_doctorProposals[ctx]?.remove(token) != proposal) throw const AssistantToolError('unknown_doctor_option');
      await checkAction();
      if (kind == AssistantActionKind.scanLibrary) {
        watch = AssistantJobWatch(serverId: id, startedAt: DateTime.now(), libraryId: root.libraryId);
        await ctx.admin<LibraryScanClient>(id)!.scanLibrary(root.libraryId);
      } else {
        await ctx.admin<ItemMetadataRefreshClient>(id)!.refreshItemMetadata(proposal.item.id);
      }
      return {'status': kind == AssistantActionKind.scanLibrary ? 'scan_started' : 'refresh_started'};
    },
  );
}

String _doctorAnswer(Map<String, Object?> data, String language) {
  final dutch = language == 'Dutch';
  final lines = <String>[
    dutch
        ? 'Bibliotheekdiagnose: ${(data['items'] as List).length} titels gecontroleerd.'
        : 'Library diagnosis: ${(data['items'] as List).length} titles checked.',
    if (data['partial'] == true)
      dutch
          ? 'Gedeeltelijke dekking; niet gecontroleerde gegevens blijven onbekend.'
          : 'Partial coverage; unchecked data remains unknown.',
  ];
  for (final item in (data['items'] as List).cast<Map>()) {
    final missing = (item['missing_metadata'] as List)
        .map((field) => _doctorFieldLabel(field as String, dutch))
        .join(', ');
    lines.add(
      '${item['title']}: ${dutch ? 'ontbrekende metadatavelden' : 'missing metadata fields'}: ${missing.isEmpty ? (dutch ? 'geen' : 'none') : missing}.',
    );
    for (final season in (item['seasons'] as List? ?? []).cast<Map>()) {
      final gaps = (season['numbering_gaps'] as List).join(', ');
      final absent = (season['missing_aired'] as List).join(', ');
      lines.add(
        '${dutch ? 'Seizoen' : 'Season'} ${season['season'] ?? (dutch ? 'onbekend' : 'unknown')}: ${dutch ? 'Nummergaten' : 'Numbering gaps'}: ${gaps.isEmpty ? (dutch ? 'geen vastgesteld' : 'none established') : gaps}. '
        '${dutch ? 'Bewezen ontbrekende uitgezonden afleveringen' : 'Proved missing aired episodes'}: ${absent.isEmpty ? (season['expected'] == 'verified' ? (dutch ? 'geen' : 'none') : (dutch ? 'onbekend' : 'unknown')) : absent}.',
      );
    }
    for (final version in (item['versions'] as List).cast<Map>()) {
      final state = version['dutch_subtitles'];
      final label = dutch
          ? switch (state) {
              'present' => 'aanwezig',
              'absent' => 'afwezig',
              _ => 'onbekend',
            }
          : state;
      lines.add(
        '${dutch ? 'Versie' : 'Version'}${version['name'] is String && (version['name'] as String).isNotEmpty ? ' ${version['name']}' : ''}: ${dutch ? 'Nederlandse ondertitels' : 'Dutch subtitles'} $label.',
      );
    }
  }
  if ((data['groups'] as List).any((g) => (g as Map)['source_count'] as int > 1)) {
    lines.add(
      dutch
          ? 'Meerdere kopieën/edities gevonden; duplicaten zijn niet bewezen.'
          : 'Multiple copies/editions found; duplicates are not proved.',
    );
  }
  for (final group in (data['groups'] as List).cast<Map>()) {
    for (final entry in (group['metadata_differences'] as Map).entries) {
      lines.add(
        '${group['title']}: ${dutch ? 'verschillende waarden voor' : 'different values for'} ${_doctorFieldLabel(entry.key as String, dutch)}: ${(entry.value as List).join(' / ')}.',
      );
    }
  }
  if ((data['actions'] as List).isNotEmpty) {
    for (final action in (data['actions'] as List).cast<Map>()) {
      final scan = action['tool'] == 'scan_library';
      final label = dutch
          ? (scan ? 'Bibliotheekscan' : 'Metadata vernieuwen')
          : (scan ? 'Library scan' : 'Metadata refresh');
      lines.add(
        '$label: ${action['subject']} (${dutch ? 'voorstel, bevestiging vereist' : 'proposal, confirmation required'}).',
      );
    }
    lines.add(
      dutch
          ? 'Beschikbare serveracties zijn voorstellen en vereisen bevestiging; een oplossing is niet gegarandeerd.'
          : 'Available server actions are proposals requiring confirmation; a repair is not guaranteed.',
    );
  }
  return lines.join('\n');
}

String _doctorFieldLabel(String field, bool dutch) => dutch
    ? switch (field) {
        'title' => 'titel',
        'year' => 'jaar',
        'summary' => 'samenvatting',
        'poster' => 'poster',
        'content_rating' => 'leeftijdsclassificatie',
        _ => field,
      }
    : field == 'content_rating'
    ? 'content rating'
    : field;
