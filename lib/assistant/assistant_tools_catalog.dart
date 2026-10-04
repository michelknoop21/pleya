part of 'assistant_tools.dart';

/// Smart search over every library, rows on Home and collections, all from one query shape.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run.
class AssistantCatalogServices {
  const AssistantCatalogServices({
    required this.rowLoader,
    required this.profileId,
    required this.activeProfileId,
    this.saveRow,
  });

  /// The loader Home's own rows use: a `CatalogHomeCustomRowLoader` built the
  /// way `HomeCustomRowsProvider` builds it. A search without free text or a
  /// person runs through it, so what Big P shows is what the row will show.
  final HomeCustomRowLoader rowLoader;

  /// `HomeLayoutProvider.saveCustomRow` of the profile [profileId]. Null keeps
  /// `create_home_row` out of the run.
  final Future<void> Function(HomeCustomRow row)? saveRow;

  /// The profile [saveRow] writes to.
  final String profileId;

  /// The profile active right now. A row card is refused once this differs
  /// from [profileId], so a switch between card and confirm saves nothing.
  final String Function() activeProfileId;
}

/// One title a search found. [group] is set when the unified catalog merged
/// the title across servers; [item] is then its representative source.
typedef AssistantMediaGridEntry = ({MediaItem item, UnifiedMediaGroup? group});

/// Titles for the UI to draw as a Pleya grid.
class AssistantMediaGrid extends AssistantDisplay {
  const AssistantMediaGrid(this.entries, {this.facts = const {}});
  final List<AssistantMediaGridEntry> entries;

  /// Facts per item id, for the titles that were looked up.
  final Map<String, TitleFacts> facts;
}

final List<AssistantTool> _catalogTools = [
  AssistantTool(
    name: 'search_catalog',
    description:
        'Search films and series on all servers of this profile by text, kind, genres, years, minimum rating '
        '(0-10), watch state or an actor (person). text matches titles, not what a title is about: for a '
        'subject, theme or plot use find_title. Returns a query_id for create_home_row and create_collection. '
        'Flags to pass on to the user: partial (a server did not answer), sampled (rating/random order or '
        'min_rating judged on the first 100 titles only), servers_left_out (servers that cannot run the '
        'filters, so their titles are not in the list), genre_unverified (titles kept without genre data).',
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
      ..._forKids,
    },
    needsServer: false,
    serves: (ctx, _) => ctx.catalog != null,
    run: (ctx, _, args) async {
      if (ctx.catalog == null) throw const AssistantToolError('catalog_unavailable');
      final age = await _kidsAge(ctx, args);
      final query = await _search(ctx, args);
      final queries = _catalogQueries[ctx] ??= {};
      final queryId = 'q${queries.length + 1}';
      queries[queryId] = query;
      final results = <Map<String, Object?>>[];
      final gated = await _gateTitles(
        ctx,
        query.groups.take(15).toList(),
        (g) => _itemRef(g.representativeSource.item.copyWith(serverId: g.representativeSource.serverId.value)),
        age,
      );
      final facts = <String, TitleFacts>{};
      for (final (g, f) in gated.kept) {
        // The source's own server id: always set, unlike the item's.
        final source = g.representativeSource;
        final item = source.item;
        final serverId = source.serverId;
        ctx.showItem(serverId, item.id);
        if (f != null) facts[item.id] = f;
        results.add({
          'item_id': item.id,
          'title': clipText(item.title),
          if (item.year != null) 'year': item.year,
          'kind': item.kind.name,
          'server_id': serverId.value,
          if (query.genreUnverified.contains(g.groupId)) 'genre_unverified': true,
          ..._factsField(f, gated.region),
        });
      }
      // For children only the titles that passed; the rest of the grid is unchecked.
      final kept = {for (final (g, _) in gated.kept) g.representativeSource.item.id};
      final entries = age == null ? query.entries : query.entries.where((e) => kept.contains(e.item.id)).toList();
      return AssistantToolResult({
        'query_id': queryId,
        'count': query.groups.length,
        'can_become_home_row': query.row != null,
        if (query.partial) 'partial': true,
        if (query.sampled) 'sampled': true,
        if (query.serversLeftOut.isNotEmpty) 'servers_left_out': query.serversLeftOut,
        if (query.genreUnverified.isNotEmpty) 'genre_unverified': query.genreUnverified.length,
        ...gated.note,
        'results': results,
      }, display: AssistantMediaGrid(entries, facts: facts));
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
      final catalog = ctx.catalog;
      final save = catalog?.saveRow ?? (throw const AssistantToolError('catalog_unavailable'));
      final profileId = catalog!.profileId;
      if (catalog.activeProfileId() != profileId) throw const AssistantToolError('profile_changed');
      final query = _requireQuery(ctx, args);
      final title = _label(args, 'title');
      final row = query.row ?? (throw const AssistantToolError('query_not_row_compatible'));
      // A Home row belongs to the profile, not to a server. The run checks
      // `serves` again against this id, which holds for any profile server.
      final serverId = ctx.userServers.firstOrNull ?? (throw const AssistantToolError('no_servers'));
      final preview = query.entries.take(8).toList();
      return AssistantPendingAction(
        kind: AssistantActionKind.createHomeRow,
        serverId: serverId,
        serverName: '',
        subject: title,
        items: _titles(preview.map((e) => e.item), 8),
        preview: AssistantMediaGrid(preview),
        execute: ({password}) async {
          if (catalog.activeProfileId() != profileId) throw const AssistantToolError('profile_changed');
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
      final client = _collectionClient(ctx, id!) ?? (throw const AssistantToolError('server_not_available'));
      final onServer = [
        for (final source in query.sources)
          if (source.serverId == id) source,
      ];
      var chosen = onServer;
      MediaLibrary? library;
      if (client.backend == MediaBackend.plex) {
        // A Plex collection lives in one library section: the one holding
        // most of the titles. Jellyfin's BoxSets belong to no library.
        final byLibrary = <String, List<UnifiedMediaSource>>{};
        for (final source in onServer) {
          if (source.libraryId case final libraryId?) (byLibrary[libraryId] ??= []).add(source);
        }
        if (byLibrary.isEmpty) throw const AssistantToolError('no_items_on_server');
        chosen = byLibrary.values.reduce((a, b) => b.length > a.length ? b : a);
        library = await ctx.library(id, chosen.first.libraryId!);
      }
      if (chosen.isEmpty) throw const AssistantToolError('no_items_on_server');
      final items = [for (final s in chosen) s.item];
      final elsewhere = onServer.length - items.length;
      // The card counts titles of the whole result, as the user saw them.
      final included = query.groups.where((g) => g.sources.any(chosen.contains)).length;
      return AssistantPendingAction(
        kind: AssistantActionKind.createCollection,
        serverId: id,
        serverName: ctx.serverName(id),
        // Built by Pleya: the card says how many of the result's titles go in.
        subject: included == query.groups.length ? name : '$name ($included/${query.groups.length})',
        libraryNames: [?library?.title],
        items: _titles(items, 30),
        execute: ({password}) async {
          final client = _collectionClient(ctx, id) ?? (throw const AssistantToolError('server_not_available'));
          final collectionId = await client.createCollection(
            libraryId: library?.id ?? '',
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
