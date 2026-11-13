part of 'assistant_tools.dart';

// The rows this profile saved on Home (BP-12t2): see them, rename one,
// remove one. A row is only accepted by the ref this run showed for it, and
// a change runs after a yes on the card, against the row as it is then.

/// `r1`, `r2`, ... to the row as it was last listed, per run.
final _shownHomeRows = Expando<Map<String, HomeCustomRow>>('shownHomeRows');

/// The ref each row got, by the row's own id. A row keeps its ref for the
/// whole run and no ref is handed out twice: a row made in between moves the
/// positions, and a ref the model still holds must not come to mean another
/// row.
final _homeRowRefs = Expando<Map<String, String>>('homeRowRefs');

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

/// The row as Home calls it: its own name, or the label of its filter when
/// it was never named. Never the internal id, which nobody can check on a card.
String _homeRowName(HomeCustomRow row) {
  final label = clipText(homeCustomRowLabel(row), 64).trim();
  if (label.isNotEmpty) return label;
  // A filter that reads as nothing still needs a line on the card.
  return row.kind == MediaKind.movie ? t.unifiedCatalog.discovery.allMovies : t.unifiedCatalog.discovery.allSeries;
}

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
      final refs = _homeRowRefs[ctx] ??= {};
      final rows = catalog.rows!();
      return AssistantToolResult({
        // The order they were made in, newest first: not the order on Home.
        'order': 'newest_first',
        'rows': [
          for (final row in rows)
            () {
              final ref = refs[row.id] ??= 'r${refs.length + 1}';
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
      // Against what the user sees: an unnamed row that reads "Action" is
      // not renamed to "Action" on a card that says "Action → Action".
      if (_homeRowName(row) == title) {
        return AssistantToolResult({'status': 'already_named', 'title': title, 'done': false});
      }
      final ref = _string(args, 'row_id');
      return AssistantPendingAction(
        kind: AssistantActionKind.renameHomeRow,
        serverId: ctx.userServers.firstOrNull ?? (throw const AssistantToolError('no_servers')),
        serverName: '',
        // Old and new name together: the card has one line for the subject,
        // and its list is headed "titles", which a new name is not.
        subject: '${_homeRowName(row)} → $title',
        execute: ({password}) async {
          final now = _currentHomeRow(catalog, listed);
          final renamed = HomeCustomRow(id: now.id, kind: now.kind, name: title, preferences: now.preferences);
          await save(renamed);
          // The ref now means the row as this run left it: a second change to
          // the same row must not trip over the first.
          _shownHomeRows[ctx]?[ref] = renamed;
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
