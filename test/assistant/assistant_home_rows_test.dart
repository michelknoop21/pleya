import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';

import 'assistant_find_fakes.dart';

// The saved Home rows through Big P (BP-12t2), against a store that behaves
// like HomeLayoutProvider: a new row goes to the front, an edit keeps its
// place.

HomeCustomRow _row(String id, String name, {Set<String> genres = const {}}) => HomeCustomRow(
  id: id,
  kind: MediaKind.movie,
  name: name,
  preferences: UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(genres: genres)),
);

AssistantTool _tool(String name) => assistantTools.firstWhere((t) => t.name == name);

class _World {
  _World(this.rows, {bool withServer = true}) {
    addTearDown(manager.dispose);
    if (withServer) manager.debugRegisterClientForTesting(FakeServer('zolder'));
    manager.setVisibleServerIds(null);
  }
  final List<HomeCustomRow> rows;
  final manager = MultiServerManager();
  String active = 'p';

  late final ctx = AssistantToolContext(
    servers: manager,
    catalog: AssistantCatalogServices(
      rowLoader: CatalogHomeCustomRowLoader(
        libraries: () => const [],
        isServerVisible: manager.isServerVisible,
        hiddenLibraryKeys: () => const {},
        clientFor: manager.getClient,
      ),
      profileId: 'p',
      activeProfileId: () => active,
      saveRow: (row) async {
        final at = rows.indexWhere((r) => r.id == row.id);
        at >= 0 ? rows[at] = row : rows.insert(0, row);
      },
      rows: () => List.unmodifiable(rows),
      removeRow: (id) async => rows.removeWhere((r) => r.id == id),
    ),
  );

  Future<List<Map>> list() async {
    final result = await _tool('list_home_rows').run(ctx, null, const {}) as AssistantToolResult;
    return (jsonDecode(jsonEncode(result.data['rows'])) as List).cast<Map>();
  }

  Future<AssistantToolOutcome> rename(String ref, String title) =>
      _tool('rename_home_row').run(ctx, null, {'row_id': ref, 'title': title});
  Future<AssistantToolOutcome> remove(String ref) => _tool('remove_home_row').run(ctx, null, {'row_id': ref});
}

Matcher _refuses(String code) => throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', code));

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  test('lists the saved rows with a ref each, an unnamed row by the label Home gives it', () async {
    final w = _World([
      _row('lq8z3k2p0a', '', genres: {'Action'}),
      _row('b', 'Kerstfilms'),
    ]);
    final rows = await w.list();
    expect(rows.map((r) => r['row_id']), ['r1', 'r2']);
    expect(rows.map((r) => r['title']), ['Action', 'Kerstfilms']);
    expect(jsonEncode(rows), isNot(contains('lq8z3k2p0a')), reason: 'no internal id reaches the model');
  });

  test('a ref keeps meaning the same row after a new row moved the positions', () async {
    final w = _World([_row('a', 'A'), _row('b', 'B')]);
    await w.list();
    w.rows.insert(0, _row('c', 'C'));
    final again = await w.list();
    expect({for (final r in again) r['title']: r['row_id']}, {'C': 'r3', 'A': 'r1', 'B': 'r2'});
    final card = await w.remove('r1') as AssistantPendingAction;
    expect(card.subject, 'A');
    await card.execute();
    expect(w.rows.map((r) => r.name), ['C', 'B']);
  });

  test('rename shows old and new name on the card and keeps the row in place', () async {
    final w = _World([_row('a', 'A'), _row('b', 'Kerstfilms'), _row('c', 'C')]);
    await w.list();
    final card = await w.rename('r2', 'Feestdagen') as AssistantPendingAction;
    expect(card.kind, AssistantActionKind.renameHomeRow);
    expect(card.subject, 'Kerstfilms → Feestdagen');
    expect(card.items, isEmpty);
    expect(w.rows[1].name, 'Kerstfilms', reason: 'nothing changes before the yes');
    expect(await card.execute(), {'status': 'row_renamed', 'title': 'Feestdagen', 'was': 'Kerstfilms'});
    expect(w.rows.map((r) => r.name), ['A', 'Feestdagen', 'C']);
  });

  test('the name it already has needs no card', () async {
    final w = _World([_row('a', 'A')]);
    await w.list();
    final result = await w.rename('r1', 'A') as AssistantToolResult;
    expect(result.data, {'status': 'already_named', 'title': 'A', 'done': false});
  });

  test('a ref this run never listed, and a title with a control character, are refused', () async {
    final w = _World([_row('a', 'A')]);
    await expectLater(w.remove('r1'), _refuses('unknown_row_id'));
    await w.list();
    await expectLater(w.remove('a'), _refuses('unknown_row_id'));
    await expectLater(w.rename('r1', 'x\u0007y'), _refuses('invalid_title'));
  });

  test('a row that changed or went while the card was open is left alone', () async {
    final w = _World([_row('a', 'A'), _row('b', 'B')]);
    await w.list();
    final rename = await w.rename('r1', 'Nieuw') as AssistantPendingAction;
    final remove = await w.remove('r2') as AssistantPendingAction;
    w.rows[0] = _row('a', 'Elders hernoemd');
    w.rows.removeAt(1);
    await expectLater(rename.execute(), _refuses('row_changed'));
    await expectLater(remove.execute(), _refuses('row_gone'));
    expect(w.rows.single.name, 'Elders hernoemd');
  });

  test('another profile becoming active stops listing, the card and the yes', () async {
    final w = _World([_row('a', 'A')]);
    await w.list();
    final card = await w.remove('r1') as AssistantPendingAction;
    w.active = 'q';
    await expectLater(card.execute(), _refuses('profile_changed'));
    await expectLater(w.list(), _refuses('profile_changed'));
    await expectLater(w.remove('r1'), _refuses('profile_changed'));
    expect(w.rows, hasLength(1));
  });

  test('the tools are only on offer with the services they need', () {
    final w = _World([]);
    final id = w.ctx.userServers.first;
    expect(_tool('list_home_rows').serves(w.ctx, id), isTrue);
    final bare = AssistantToolContext(
      servers: w.manager,
      catalog: AssistantCatalogServices(
        rowLoader: w.ctx.catalog!.rowLoader,
        profileId: 'p',
        activeProfileId: () => 'p',
        rows: () => const [],
      ),
    );
    expect(_tool('list_home_rows').serves(bare, id), isTrue);
    expect(_tool('rename_home_row').serves(bare, id), isFalse);
    expect(_tool('remove_home_row').serves(bare, id), isFalse);
    final none = AssistantToolContext(servers: w.manager);
    expect(_tool('list_home_rows').serves(none, id), isFalse);
  });
}
