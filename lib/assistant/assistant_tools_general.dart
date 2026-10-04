part of 'assistant_tools.dart';

/// Reads every profile may use: servers, libraries, finding a title.
final List<AssistantTool> _generalTools = [
  AssistantTool(
    name: 'list_servers',
    description: 'Media servers of this profile, whether each is online, and whether this profile administers it.',
    risk: AssistantToolRisk.read,
    properties: const {},
    needsServer: false,
    serves: (_, _) => true,
    run: (ctx, _, _) async => AssistantToolResult({
      'servers': [
        for (final id in ctx.userServers)
          {
            'server_id': id.value,
            'name': clipText(ctx.serverName(id)),
            'backend': ctx.servers.getClient(id)?.backend.name,
            'online': ctx.userClient(id) != null,
            'administer': ctx.administeredServers.contains(id),
          },
      ],
    }),
  ),
  AssistantTool(
    name: 'list_libraries',
    description: 'Libraries on one server.',
    risk: AssistantToolRisk.read,
    properties: const {},
    serves: (ctx, id) => ctx.userClient(id) != null,
    run: (ctx, id, _) async => AssistantToolResult({
      'libraries': [
        for (final l in await ctx.libraries(id!))
          {
            'library_id': l.id,
            'title': clipText(l.title),
            'kind': l.kind.name,
            // Lets "which library was scanned longest ago" be answered.
            if (l.updatedAt != null)
              'updated_at': DateTime.fromMillisecondsSinceEpoch(l.updatedAt! * 1000, isUtc: true).toIso8601String(),
          },
      ],
    }),
  ),
  AssistantTool(
    name: 'find_media',
    description: 'Search a server for films, series or albums by title, to get an item_id.',
    risk: AssistantToolRisk.read,
    properties: const {
      'query': {'type': 'string'},
    },
    required: const ['query'],
    serves: (ctx, id) => ctx.userClient(id) != null,
    run: (ctx, id, args) async {
      final query = _string(args, 'query');
      final age = await _kidsAge(ctx);
      final client = ctx.userClient(id!)!;
      // Home's hidden libraries stay out, as in the app's own search.
      final items = filterHiddenLibraryItems([
        for (final i in await client.searchItems(clipText(query, 100), limit: 10))
          (i.serverId?.isEmpty ?? true) ? i.copyWith(serverId: id.value) : i,
      ], await _hiddenLibraryKeys(ctx, id));
      const kinds = {
        MediaKind.movie,
        MediaKind.show,
        MediaKind.season,
        MediaKind.episode,
        MediaKind.album,
        MediaKind.artist,
      };
      final gated = await _gateTitles(ctx, items.where((i) => kinds.contains(i.kind)).take(10).toList(), _itemRef, age);
      return AssistantToolResult(
        {
          'items': [
            for (final (item, facts) in gated.kept)
              () {
                ctx.showItem(id, item.id);
                return {
                  'item_id': item.id,
                  'title': clipText(item.title),
                  if (item.grandparentTitle != null) 'series': clipText(item.grandparentTitle),
                  if (item.year != null) 'year': item.year,
                  'kind': item.kind.name,
                  ..._factsField(facts, gated.region),
                };
              }(),
          ],
          ...gated.note,
          // Films and series it found are cards to open, not names in prose.
        },
        display: AssistantMediaGrid(
          [
            for (final (item, _) in gated.kept)
              if (item.kind == MediaKind.movie || item.kind == MediaKind.show) (item: item, group: null),
          ],
          facts: {for (final (item, facts) in gated.kept) item.globalKey: ?facts},
        ),
      );
    },
  ),
];
