part of 'assistant_tools.dart';

// The query behind search_catalog, create_home_row and create_collection.

/// One search_catalog answer, kept for the rest of the run. Later tools work
/// from this, never from filters the model repeats.
class _CatalogQuery {
  _CatalogQuery(
    this.groups,
    this.row, {
    this.partial = false,
    this.sampled = false,
    this.serversLeftOut = const [],
    this.genreUnverified = const {},
  });
  final List<UnifiedMediaGroup> groups;

  /// The query as a Home row, or null when it uses something a row cannot
  /// hold: free text, a person, a minimum rating, rating or random order, or
  /// no kind.
  final HomeCustomRow? row;

  /// A server or library did not answer, or could not run this search.
  final bool partial;

  /// Rating or random order, or a minimum rating, judged on the first 100
  /// titles only: the catalog has no rating order to ask for.
  final bool sampled;

  /// Servers left out because they cannot run a requested filter.
  final List<String> serversLeftOut;

  /// Group ids kept although no source carried genre data to check.
  final Set<String> genreUnverified;

  List<AssistantMediaGridEntry> get entries => [for (final g in groups) (item: g.representativeSource.item, group: g)];

  /// Every concrete source behind [groups], across servers.
  Iterable<UnifiedMediaSource> get sources => groups.expand((g) => g.sources);
}

/// Per ask: AssistantRun hands every ask a fresh context.
final _catalogQueries = Expando<Map<String, _CatalogQuery>>('assistantCatalogQueries');

_CatalogQuery _requireQuery(AssistantToolContext ctx, Map<String, Object?> args) =>
    _catalogQueries[ctx]?[_string(args, 'query_id')] ?? (throw const AssistantToolError('unknown_query_id'));

int? _int(Map<String, Object?> args, String key, int min, int max) {
  final value = args[key];
  if (value == null) return null;
  if (value is! num || value != value.roundToDouble() || value < min || value > max) {
    throw AssistantToolError('invalid_$key');
  }
  return value.toInt();
}

String? _optionalText(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value == null || (value is String && value.trim().isEmpty)) return null;
  if (value is! String) throw AssistantToolError('invalid_$key');
  return clipText(value, 100);
}

/// A label Pleya stores and shows as-is: the same rule as a user name.
String _label(Map<String, Object?> args, String key) {
  final value = _string(args, key);
  if (value.length > 64 || RegExp(r'[\p{Cc}\p{Cf}/\\]', unicode: true).hasMatch(value)) {
    throw AssistantToolError('invalid_$key');
  }
  return value;
}

/// Where a collection can be made: administered, and the owner rule the
/// clients themselves enforce (`assertCanManageServerMetadata`).
MediaServerClient? _collectionClient(AssistantToolContext ctx, ServerId id) {
  final client = ctx.adminClient(id);
  if (client == null || !ctx.servers.canManageServerMetadata(id)) return null;
  return client.backend == MediaBackend.plex || client.backend == MediaBackend.jellyfin ? client : null;
}

const _rowSorts = {
  'added': UnifiedCatalogSort.recentlyAdded,
  'released': UnifiedCatalogSort.newestRelease,
  'title': UnifiedCatalogSort.titleAsc,
};

Future<_CatalogQuery> _search(AssistantToolContext ctx, Map<String, Object?> args) async {
  final text = _optionalText(args, 'text');
  final person = _optionalText(args, 'person');
  final kind = switch (args['kind']) {
    null => null,
    'movie' => MediaKind.movie,
    'show' => MediaKind.show,
    _ => throw const AssistantToolError('invalid_kind'),
  };
  final genres = {for (final g in _strings(args, 'genres').take(5)) clipText(g, 40)};
  final lastYear = DateTime.now().year + 2;
  final yearFrom = _int(args, 'year_from', 1880, lastYear);
  final yearTo = _int(args, 'year_to', 1880, lastYear);
  if (yearFrom != null && yearTo != null && yearFrom > yearTo) throw const AssistantToolError('invalid_year_to');
  final years = yearFrom == null && yearTo == null
      ? const <int>{}
      : {for (var y = yearFrom ?? 1880; y <= (yearTo ?? lastYear); y++) y};
  final minRating = switch (args['min_rating']) {
    null => null,
    final num r when r >= 0 && r <= 10 => r.toDouble(),
    _ => throw const AssistantToolError('invalid_min_rating'),
  };
  final unwatched = _bool(args, 'unwatched');
  final inProgress = _bool(args, 'in_progress');
  if (unwatched && inProgress) throw const AssistantToolError('invalid_in_progress');
  final askedSort = args['sort'];
  final sort = askedSort ?? 'title';
  if (sort is! String || !{..._rowSorts.keys, 'rating', 'random'}.contains(sort)) {
    throw const AssistantToolError('invalid_sort');
  }
  final limit = _int(args, 'limit', 1, 50) ?? 20;
  final rowShaped = text == null && person == null && minRating == null && _rowSorts.containsKey(sort);

  if (text == null && person == null) {
    // The Home-row path: the row's own filter model, loader and merge.
    final watch = inProgress
        ? UnifiedWatchFilter.inProgress
        : (unwatched ? UnifiedWatchFilter.unwatched : UnifiedWatchFilter.all);
    // The loader drops a filter for everyone as soon as one participating
    // backend cannot run it (`unifiedFilterCapabilitiesFor`). Rather than
    // show an unfiltered list as filtered, such servers stay out of the
    // query, and the answer names them.
    final capable = <String>{};
    final leftOut = <String>[];
    for (final id in ctx.userServers) {
      final backend = ctx.servers.getClient(id)?.backend;
      if (backend == null) continue;
      final caps = unifiedFilterCapabilitiesFor([backend]);
      if ((genres.isEmpty && years.isEmpty || caps.supportsMetadataFilters) && caps.supportsWatchState(watch)) {
        capable.add(id.value);
      } else {
        leftOut.add(clipText(ctx.serverName(id), 40));
      }
    }
    if (leftOut.isNotEmpty && capable.isEmpty) throw const AssistantToolError('filters_unsupported');
    final groups = <UnifiedMediaGroup>[];
    var partial = false;
    var sampled = false;
    HomeCustomRow? row;
    for (final k in kind == null ? const [MediaKind.movie, MediaKind.show] : [kind]) {
      row = HomeCustomRow(
        id: '',
        kind: k,
        preferences: UnifiedCatalogPreferences(
          sort: _rowSorts[sort] ?? UnifiedCatalogSort.titleAsc,
          filters: UnifiedCatalogFilterSelection(
            genres: genres,
            years: years,
            watchState: watch,
            serverIds: leftOut.isEmpty ? const {} : capable,
          ),
        ),
      );
      // ponytail: rating/random order and a minimum rating only see the first
      // 100 titles (flagged as sampled); a rating sort in the catalog contract
      // lifts that ceiling.
      final content = await ctx.catalog!.rowLoader.load(row, limit: rowShaped ? limit : 100);
      partial |= content.isPartial;
      sampled |= !rowShaped && !content.isExact;
      groups.addAll(content.groups);
    }
    if (minRating != null) groups.removeWhere((g) => (g.representativeSource.item.rating ?? -1) < minRating);
    // A single kind keeps the catalog's order; two kinds need one order.
    if (!rowShaped || kind == null) _order(groups, sort);
    return _CatalogQuery(
      groups.take(limit).toList(),
      rowShaped && kind != null ? row : null,
      partial: partial,
      sampled: sampled,
      serversLeftOut: leftOut,
    );
  }

  // Free text or a person: the servers' own search, the calls the search
  // screen makes, with the structured filters applied to the hits.
  final textKey = text?.toLowerCase();
  final found = <MediaItem>[];
  final genreChecked = <String>{};
  var partial = false;
  for (final id in ctx.userServers) {
    final client = ctx.userClient(id);
    if (client == null || (person != null && client is! PersonSearchClient)) {
      partial = true;
      continue;
    }
    try {
      final hidden = await _hiddenLibraryKeys(ctx, id);
      final List<MediaItem> hits;
      if (person != null) {
        final people = await (client as PersonSearchClient).searchPeople(person, limit: 1);
        hits = people.isEmpty ? const [] : await client.fetchPersonMedia(people.first.id);
      } else {
        hits = await client.searchItems(text!, limit: 50);
      }
      for (final hit in hits) {
        if (hit.kind != MediaKind.movie && hit.kind != MediaKind.show) continue;
        if (kind != null && hit.kind != kind) continue;
        if (person != null && textKey != null && !(hit.title ?? '').toLowerCase().contains(textKey)) continue;
        if (years.isNotEmpty && !years.contains(hit.year)) continue;
        if (minRating != null && (hit.rating ?? -1) < minRating) continue;
        if (unwatched && hit.isWatched) continue;
        if (inProgress && !hit.hasActiveProgress) continue;
        final item = (hit.serverId?.isEmpty ?? true) ? hit.copyWith(serverId: id.value) : hit;
        if (filterHiddenLibraryItems([item], hidden).isEmpty) continue;
        // Search hits often carry no genres (Jellyfin's never do): such a hit
        // stays in and is reported as unverified rather than dropped.
        final itemGenres = {for (final g in item.genres ?? const <String>[]) g.toLowerCase()};
        if (genres.isNotEmpty && itemGenres.isNotEmpty) {
          if (!genres.any((g) => itemGenres.contains(g.toLowerCase()))) continue;
          genreChecked.add(item.globalKey);
        }
        found.add(item);
      }
    } catch (e) {
      // One server failing leaves the others' answer standing.
      partial = true;
      appLogger.w('Assistant: catalog search failed on one server', error: e.runtimeType);
    }
  }
  final groups = await _merge(ctx, found);
  // No sort asked: the servers' relevance order stands.
  if (askedSort != null) _order(groups, sort);
  final kept = groups.take(limit).toList();
  return _CatalogQuery(
    kept,
    null,
    partial: partial,
    genreUnverified: genres.isEmpty
        ? const {}
        : {
            for (final g in kept)
              if (!g.sources.any((s) => genreChecked.contains(s.sourceKey))) g.groupId,
          },
  );
}

/// The same title on several servers becomes one entry: the unified
/// catalog's identity pipeline, which keeps the first hit's position.
/// The movie and series libraries of [id] that Home does not show this
/// profile (`librariesFor`: visible server, library not hidden), as
/// find_title reads them. Hits there are dropped with the app's own
/// predicate, which keeps a hit that names no library. Empty without a
/// catalog.
Future<Set<String>> _hiddenLibraryKeys(AssistantToolContext ctx, ServerId id) async {
  final loader = ctx.catalog?.rowLoader;
  if (loader is! CatalogHomeCustomRowLoader) return const {};
  final visible = {
    for (final kind in const [MediaKind.movie, MediaKind.show])
      for (final l in loader.librariesFor(kind)) buildGlobalKey(l.serverId, l.libraryId),
  };
  return {
    for (final l in await ctx.libraries(id))
      if ((l.kind == MediaKind.movie || l.kind == MediaKind.show) && !visible.contains(l.globalKey)) l.globalKey,
  };
}

Future<List<UnifiedMediaGroup>> _merge(AssistantToolContext ctx, List<MediaItem> items) async {
  final resolver = UnifiedIdentityResolver(
    fetchExternalIds: (serverId, targetId) =>
        (ctx.userClient(ServerId(serverId)) ?? (throw StateError('server gone'))).fetchExternalIds(targetId),
  );
  final evidence = await resolver.resolveEvidence([
    for (final item in items)
      ResolvableItem(
        item: item,
        identity: canonicalIdentityOf(item),
        scope: (canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque()).granularity.name,
        // A stable guid already is proof; only guid-less items in a colliding
        // bucket cost a request.
        externalIdTarget: normalizeStableGuid(item.guid) == null ? (serverId: item.serverId!, targetId: item.id) : null,
      ),
  ]);
  return groupUnifiedMediaSources([
    for (var i = 0; i < items.length; i++)
      GroupingCandidate(source: UnifiedMediaSource.fromItem(items[i]), evidence: evidence[i]),
  ]);
}

void _order(List<UnifiedMediaGroup> groups, String sort) {
  MediaItem rep(UnifiedMediaGroup g) => g.representativeSource.item;
  String titleKey(MediaItem i) => (i.titleSort ?? i.title ?? '').toLowerCase();
  String releaseKey(MediaItem i) => i.originallyAvailableAt ?? '${i.year ?? ''}';
  switch (sort) {
    case 'random':
      groups.shuffle(Random());
    case 'rating':
      groups.sort((a, b) => (rep(b).rating ?? -1).compareTo(rep(a).rating ?? -1));
    case 'added':
      groups.sort((a, b) => (rep(b).addedAt ?? -1).compareTo(rep(a).addedAt ?? -1));
    case 'released':
      groups.sort((a, b) => releaseKey(rep(b)).compareTo(releaseKey(rep(a))));
    default:
      groups.sort((a, b) => titleKey(rep(a)).compareTo(titleKey(rep(b))));
  }
}

List<String> _titles(Iterable<MediaItem> items, int max) => [for (final i in items.take(max)) clipText(i.title)];
