part of 'assistant_tools.dart';

/// Smart search over every library, rows on Home and collections, all from one query shape.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run.
class AssistantCatalogServices {
  const AssistantCatalogServices({required this.rowLoader, this.saveRow});

  /// The loader Home's own rows use: a `CatalogHomeCustomRowLoader` built the
  /// way `HomeCustomRowsProvider` builds it. A search without free text or a
  /// person runs through it, so what Big P shows is what the row will show.
  final HomeCustomRowLoader rowLoader;

  /// `HomeLayoutProvider.saveCustomRow` of the active profile. Null keeps
  /// `create_home_row` out of the run.
  final Future<void> Function(HomeCustomRow row)? saveRow;
}

/// One title a search found. [group] is set when the unified catalog merged
/// the title across servers; [item] is then its representative source.
typedef AssistantMediaGridEntry = ({MediaItem item, UnifiedMediaGroup? group});

/// Titles for the UI to draw as a Pleya grid.
class AssistantMediaGrid extends AssistantDisplay {
  const AssistantMediaGrid(this.entries);
  final List<AssistantMediaGridEntry> entries;
}

/// One search_catalog answer, kept for the rest of the run. Later tools work
/// from this, never from filters the model repeats.
class _CatalogQuery {
  _CatalogQuery(this.entries, this.row);
  final List<AssistantMediaGridEntry> entries;

  /// The query as a Home row, or null when it uses something a row cannot
  /// hold: free text, a person, a minimum rating, rating or random order, or
  /// no kind.
  final HomeCustomRow? row;

  /// Every concrete item behind [entries], across servers.
  Iterable<MediaItem> get sources =>
      entries.expand((e) => e.group == null ? [e.item] : e.group!.sources.map((s) => s.item));
}

/// Per run: a context lives exactly as long as one run.
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
  final sort = args['sort'] ?? 'title';
  if (sort is! String || !{..._rowSorts.keys, 'rating', 'random'}.contains(sort)) {
    throw const AssistantToolError('invalid_sort');
  }
  final limit = _int(args, 'limit', 1, 50) ?? 20;
  final rowShaped = text == null && person == null && minRating == null && _rowSorts.containsKey(sort);

  final entries = <AssistantMediaGridEntry>[];
  if (text == null && person == null) {
    // The Home-row path: the row's own filter model, loader and merge.
    final watch = inProgress
        ? UnifiedWatchFilter.inProgress
        : (unwatched ? UnifiedWatchFilter.unwatched : UnifiedWatchFilter.all);
    HomeCustomRow? row;
    for (final k in kind == null ? const [MediaKind.movie, MediaKind.show] : [kind]) {
      row = HomeCustomRow(
        id: '',
        kind: k,
        preferences: UnifiedCatalogPreferences(
          sort: _rowSorts[sort] ?? UnifiedCatalogSort.titleAsc,
          filters: UnifiedCatalogFilterSelection(genres: genres, years: years, watchState: watch),
        ),
      );
      // ponytail: rating/random order and a minimum rating only see the first
      // 100 titles; a rating sort in the catalog contract lifts that ceiling.
      final content = await ctx.catalog!.rowLoader.load(row, limit: rowShaped ? limit : 100);
      entries.addAll([for (final g in content.groups) (item: g.representativeSource.item, group: g)]);
    }
    if (minRating != null) entries.removeWhere((e) => (e.item.rating ?? -1) < minRating);
    // A single kind keeps the catalog's order; two kinds need one order.
    if (!rowShaped || kind == null) _order(entries, sort);
    return _CatalogQuery(entries.take(limit).toList(), rowShaped && kind != null ? row : null);
  }

  // Free text or a person: the servers' own search, the calls the search
  // screen makes, with the structured filters applied to the hits.
  final textKey = text?.toLowerCase();
  for (final id in ctx.userServers) {
    final client = ctx.userClient(id);
    if (client == null) continue;
    try {
      final List<MediaItem> hits;
      if (person != null) {
        if (client is! PersonSearchClient) continue;
        final people = await (client as PersonSearchClient).searchPeople(person, limit: 1);
        hits = people.isEmpty ? const [] : await client.fetchPersonMedia(people.first.id);
      } else {
        hits = await client.searchItems(text!, limit: 50);
      }
      for (final item in hits) {
        if (item.kind != MediaKind.movie && item.kind != MediaKind.show) continue;
        if (kind != null && item.kind != kind) continue;
        if (person != null && textKey != null && !(item.title ?? '').toLowerCase().contains(textKey)) continue;
        if (years.isNotEmpty && !years.contains(item.year)) continue;
        if (minRating != null && (item.rating ?? -1) < minRating) continue;
        if (unwatched && item.isWatched) continue;
        if (inProgress && !item.hasActiveProgress) continue;
        final itemGenres = {for (final g in item.genres ?? const <String>[]) g.toLowerCase()};
        if (genres.isNotEmpty && !genres.any((g) => itemGenres.contains(g.toLowerCase()))) continue;
        entries.add((item: item.serverId == null ? item.copyWith(serverId: id.value) : item, group: null));
      }
    } catch (e) {
      // One server failing leaves the others' answer standing.
      appLogger.w('Assistant: catalog search failed on one server', error: e.runtimeType);
    }
  }
  _order(entries, sort);
  return _CatalogQuery(entries.take(limit).toList(), null);
}

void _order(List<AssistantMediaGridEntry> entries, String sort) {
  String titleKey(MediaItem i) => (i.titleSort ?? i.title ?? '').toLowerCase();
  String releaseKey(MediaItem i) => i.originallyAvailableAt ?? '${i.year ?? ''}';
  switch (sort) {
    case 'random':
      entries.shuffle(Random());
    case 'rating':
      entries.sort((a, b) => (b.item.rating ?? -1).compareTo(a.item.rating ?? -1));
    case 'added':
      entries.sort((a, b) => (b.item.addedAt ?? -1).compareTo(a.item.addedAt ?? -1));
    case 'released':
      entries.sort((a, b) => releaseKey(b.item).compareTo(releaseKey(a.item)));
    default:
      entries.sort((a, b) => titleKey(a.item).compareTo(titleKey(b.item)));
  }
}

List<String> _titles(Iterable<MediaItem> items, int max) => [for (final i in items.take(max)) clipText(i.title)];

final List<AssistantTool> _catalogTools = [
  AssistantTool(
    name: 'search_catalog',
    description:
        'Search films and series on all servers of this profile by text, kind, genres, years, minimum rating '
        '(0-10), watch state or a person (actor or director). Returns a query_id for create_home_row and '
        'create_collection.',
    risk: AssistantToolRisk.read,
    properties: const {
      'text': {'type': 'string'},
      'person': {'type': 'string'},
      'kind': {
        'type': 'string',
        'enum': ['movie', 'show'],
      },
      'genres': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'year_from': {'type': 'integer'},
      'year_to': {'type': 'integer'},
      'min_rating': {'type': 'number'},
      'unwatched': {'type': 'boolean'},
      'in_progress': {'type': 'boolean'},
      'sort': {
        'type': 'string',
        'enum': ['added', 'released', 'rating', 'title', 'random'],
      },
      'limit': {'type': 'integer'},
    },
    needsServer: false,
    serves: (ctx, _) => ctx.catalog != null,
    run: (ctx, _, args) async {
      if (ctx.catalog == null) throw const AssistantToolError('catalog_unavailable');
      final query = await _search(ctx, args);
      final queries = _catalogQueries[ctx] ??= {};
      final queryId = 'q${queries.length + 1}';
      queries[queryId] = query;
      return AssistantToolResult({
        'query_id': queryId,
        'count': query.entries.length,
        'can_become_home_row': query.row != null,
        'results': [
          for (final e in query.entries.take(15))
            () {
              final serverId = ServerId(e.item.serverId ?? '');
              ctx.showItem(serverId, e.item.id);
              return {
                'item_id': e.item.id,
                'title': clipText(e.item.title),
                if (e.item.year != null) 'year': e.item.year,
                'kind': e.item.kind.name,
                'server_id': serverId.value,
              };
            }(),
        ],
      }, display: AssistantMediaGrid(query.entries));
    },
  ),
  AssistantTool(
    name: 'create_home_row',
    description:
        'Add a search_catalog result with can_become_home_row as a row on this profile\'s Home. '
        'The user confirms in Pleya.',
    risk: AssistantToolRisk.mutation,
    properties: const {
      'query_id': {'type': 'string'},
      'title': {'type': 'string'},
    },
    required: const ['query_id', 'title'],
    needsServer: false,
    serves: (ctx, _) => ctx.catalog?.saveRow != null,
    run: (ctx, _, args) async {
      final save = ctx.catalog?.saveRow ?? (throw const AssistantToolError('catalog_unavailable'));
      final query = _requireQuery(ctx, args);
      final title = _label(args, 'title');
      final row = query.row ?? (throw const AssistantToolError('query_not_row_compatible'));
      final preview = query.entries.take(8).toList();
      return AssistantPendingAction(
        kind: AssistantActionKind.createHomeRow,
        // A Home row belongs to the profile, not to a server. The run checks
        // `serves` again against this id, which holds for any profile server.
        serverId: ctx.userServers.first,
        serverName: '',
        subject: title,
        items: _titles(preview.map((e) => e.item), 8),
        preview: AssistantMediaGrid(preview),
        execute: ({password}) async {
          await save(
            HomeCustomRow(id: HomeCustomRow.newId(), kind: row.kind, name: title, preferences: row.preferences),
          );
          return {'status': 'row_created', 'title': title};
        },
      );
    },
  ),
  AssistantTool(
    name: 'create_collection',
    description:
        'Create a collection on one server from the titles of a search_catalog result that are on that server. '
        'The user confirms in Pleya. $_serverIdNote',
    risk: AssistantToolRisk.sensitive,
    properties: const {
      'query_id': {'type': 'string'},
      'name': {'type': 'string'},
    },
    required: const ['query_id', 'name'],
    serves: (ctx, id) => ctx.catalog != null && _collectionClient(ctx, id) != null,
    run: (ctx, id, args) async {
      final query = _requireQuery(ctx, args);
      final name = _label(args, 'name');
      final onServer = [
        for (final item in query.sources)
          if (item.serverId == id!.value && item.libraryId != null) item,
      ];
      if (onServer.isEmpty) throw const AssistantToolError('no_items_on_server');
      // A collection lives in one library: the one holding most of the titles.
      final byLibrary = <String, List<MediaItem>>{};
      for (final item in onServer) {
        (byLibrary[item.libraryId!] ??= []).add(item);
      }
      final items = byLibrary.values.reduce((a, b) => b.length > a.length ? b : a);
      final library = await ctx.library(id!, items.first.libraryId!);
      final elsewhere = onServer.length - items.length;
      return AssistantPendingAction(
        kind: AssistantActionKind.createCollection,
        serverId: id,
        serverName: ctx.serverName(id),
        subject: name,
        libraryNames: [library.title],
        items: _titles(items, 30),
        execute: ({password}) async {
          final client = _collectionClient(ctx, id) ?? (throw const AssistantToolError('server_not_available'));
          final collectionId = await client.createCollection(
            libraryId: library.id,
            title: name,
            items: [items.first],
            itemKind: items.first.kind,
          );
          if (collectionId == null) throw const AssistantToolError('failed');
          // From here the collection exists: a failed add is reported as
          // exactly that, so nobody creates it twice.
          var added = true;
          try {
            added = await client.addToCollection(collectionId: collectionId, items: items.skip(1).toList());
          } catch (e) {
            appLogger.w('Assistant: collection created, adding items failed', error: e.runtimeType);
            added = false;
          }
          final notAdded = (added ? 0 : items.length - 1) + elsewhere;
          return {
            'status': 'created',
            'name': name,
            'items_added': items.length - (added ? 0 : items.length - 1),
            if (notAdded > 0) 'items_not_added': notAdded,
          };
        },
      );
    },
  ),
];
