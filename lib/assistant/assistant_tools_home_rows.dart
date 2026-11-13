part of 'assistant_tools.dart';

// The rows this profile saved on Home (BP-12t2): see them, rename one,
// remove one. A row is only accepted by the ref this run showed for it, and
// a change runs after a yes on the card, against the row as it is then.

/// `r1`, `r2`, ... to the row as it was listed, per run.
final _shownHomeRows = Expando<Map<String, HomeCustomRow>>('shownHomeRows');

bool _servesHomeRows(AssistantToolContext ctx, ServerId _) => ctx.catalog?.rows != null;

AssistantCatalogServices _homeRowsCatalog(AssistantToolContext ctx) {
  final catalog = ctx.catalog;
  if (catalog?.rows == null) throw const AssistantToolError('catalog_unavailable');
  if (catalog!.activeProfileId() != catalog.profileId) throw const AssistantToolError('profile_changed');
  return catalog;
}

HomeCustomRow _shownHomeRow(AssistantToolContext ctx, Map<String, Object?> args) =>
    _shownHomeRows[ctx]?[_string(args, 'row_id')] ?? (throw const AssistantToolError('unknown_row_id'));

/// The row as it is now, or a refusal when it went or changed since it was
/// listed: the card showed the old one.
HomeCustomRow _currentHomeRow(AssistantCatalogServices catalog, HomeCustomRow listed) {
  if (catalog.activeProfileId() != catalog.profileId) throw const AssistantToolError('profile_changed');
  final now = catalog.rows!().where((row) => row.id == listed.id).firstOrNull;
  if (now == null) throw const AssistantToolError('row_gone');
  if (now != listed) throw const AssistantToolError('row_changed');
  return now;
}

String _homeRowName(HomeCustomRow row) => clipText(row.name.isEmpty ? row.id : row.name, 64);

final List<AssistantTool> _homeRowTools = [
  AssistantTool(
    name: 'list_home_rows',
    description: 'Saved rows on this profile\'s Home, each with a row_id. Built-in rows are not listed.',
    risk: AssistantToolRisk.read,
    needsServer: false,
    properties: const {},
    serves: _servesHomeRows,
    run: (ctx, _, args) async {
      final catalog = _homeRowsCatalog(ctx);
      final shown = _shownHomeRows[ctx] ??= {};
      final rows = catalog.rows!();
      return AssistantToolResult({
        'rows': [
          for (final (i, row) in rows.indexed)
            () {
              final ref = 'r${i + 1}';
              shown[ref] = row;
              return {
                'row_id': ref,
                'title': _homeRowName(row),
                'kind': row.kind == MediaKind.movie ? 'movie' : 'show',
              };
            }(),
        ],
      });
    },
  ),
  AssistantTool(
    name: 'rename_home_row',
    description: 'Rename a saved Home row by row_id from list_home_rows. The user confirms in Pleya.',
    risk: AssistantToolRisk.mutation,
    needsServer: false,
    properties: const {
      'row_id': {'type': 'string'},
      'title': {'type': 'string'},
    },
    required: const ['row_id', 'title'],
    serves: (ctx, id) => _servesHomeRows(ctx, id) && ctx.catalog?.saveRow != null,
    run: (ctx, _, args) async {
      final catalog = _homeRowsCatalog(ctx);
      final save = catalog.saveRow ?? (throw const AssistantToolError('catalog_unavailable'));
      final listed = _shownHomeRow(ctx, args);
      final title = _label(args, 'title');
      final row = _currentHomeRow(catalog, listed);
      if (row.name == title) return AssistantToolResult({'status': 'already_named', 'title': title, 'done': false});
      return AssistantPendingAction(
        kind: AssistantActionKind.renameHomeRow,
        serverId: ctx.userServers.firstOrNull ?? (throw const AssistantToolError('no_servers')),
        serverName: '',
        subject: _homeRowName(row),
        items: [title],
        execute: ({password}) async {
          final now = _currentHomeRow(catalog, listed);
          await save(HomeCustomRow(id: now.id, kind: now.kind, name: title, preferences: now.preferences));
          return {'status': 'row_renamed', 'title': title, 'was': _homeRowName(now)};
        },
      );
    },
  ),
  AssistantTool(
    name: 'remove_home_row',
    description:
        'Remove a saved Home row by row_id from list_home_rows; its titles stay in the library. The user '
        'confirms in Pleya.',
    risk: AssistantToolRisk.mutation,
    needsServer: false,
    properties: const {
      'row_id': {'type': 'string'},
    },
    required: const ['row_id'],
    serves: (ctx, id) => _servesHomeRows(ctx, id) && ctx.catalog?.removeRow != null,
    run: (ctx, _, args) async {
      final catalog = _homeRowsCatalog(ctx);
      final remove = catalog.removeRow ?? (throw const AssistantToolError('catalog_unavailable'));
      final listed = _shownHomeRow(ctx, args);
      final row = _currentHomeRow(catalog, listed);
      return AssistantPendingAction(
        kind: AssistantActionKind.removeHomeRow,
        serverId: ctx.userServers.firstOrNull ?? (throw const AssistantToolError('no_servers')),
        serverName: '',
        subject: _homeRowName(row),
        execute: ({password}) async {
          final now = _currentHomeRow(catalog, listed);
          await remove(now.id);
          return {'status': 'row_removed', 'title': _homeRowName(now)};
        },
      );
    },
  ),
];
