import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/watchlist_actions.dart';

import 'eval/big_p_eval_fixtures.dart';
import 'eval/big_p_eval_world.dart';

// The kijklijst through Big P (BP-12t3), tool by tool, against the eval
// world's in-memory list.

AssistantTool _tool(String name) => assistantTools.firstWhere((t) => t.name == name);
final _zolder = ServerId('zolder');

Matcher _refuses(String code) => throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', code));

Future<List<Map>> _list(AssistantToolContext ctx, [Map<String, Object?> args = const {}]) async {
  final result = await _tool('my_watchlist').run(ctx, null, args) as AssistantToolResult;
  return (jsonDecode(jsonEncode(result.data['entries'])) as List).cast<Map>();
}

void main() {
  late EvalWatchlist list;
  late AssistantToolContext ctx;

  setUp(() {
    list = EvalWatchlist(['Dune', 'Arrival']);
    ctx = evalContext(kids: false, world: EvalWorld(watchlist: list));
  });

  test('lists the titles with a ref each and says unknown where nothing was looked up', () async {
    final rows = await _list(ctx);
    expect(rows.map((r) => r['entry_id']), ['w1', 'w2']);
    expect(rows.map((r) => r['title']), ['Dune', 'Arrival']);
    expect(rows.map((r) => r['in_library']), ['unknown', 'unknown']);
    expect(await _list(ctx, {'kind': 'show'}), isEmpty);
    await expectLater(_tool('my_watchlist').run(ctx, null, {'kind': 'episode'}), _refuses('invalid_kind'));
  });

  test('a ref keeps its title after an add moved the list', () async {
    await _list(ctx);
    ctx.showItem(_zolder, 'm02');
    final card = await _tool('add_to_watchlist').run(ctx, _zolder, {'item_id': 'm02'}) as AssistantPendingAction;
    expect(card.kind, AssistantActionKind.addToWatchlist);
    expect(card.subject, 'Finding Nemo (2003)');
    expect(list.entries, hasLength(2), reason: 'nothing changes before the yes');
    expect(await card.execute(), {'status': 'on_watchlist', 'title': 'Finding Nemo (2003)'});
    final rows = await _list(ctx);
    expect({for (final r in rows) r['title']: r['entry_id']}, {'Finding Nemo': 'w3', 'Dune': 'w1', 'Arrival': 'w2'});
    expect(rows.first['in_library'], isTrue);
  });

  test('an item this run never showed is refused', () async {
    await expectLater(_tool('add_to_watchlist').run(ctx, _zolder, {'item_id': 'm02'}), _refuses('unknown_item_id'));
  });

  test('remove takes the entry the ref named and nothing else', () async {
    await _list(ctx);
    final card = await _tool('remove_from_watchlist').run(ctx, null, {'entry_id': 'w2'}) as AssistantPendingAction;
    expect(card.kind, AssistantActionKind.removeFromWatchlist);
    expect(card.subject, 'Arrival');
    expect(await card.execute(), {'status': 'off_watchlist', 'title': 'Arrival'});
    expect(list.entries.map((e) => e.item.title), ['Dune']);
  });

  test('an unknown ref, and an entry that left the list meanwhile, are refused', () async {
    await expectLater(_tool('remove_from_watchlist').run(ctx, null, {'entry_id': 'w1'}), _refuses('unknown_entry_id'));
    await _list(ctx);
    final card = await _tool('remove_from_watchlist').run(ctx, null, {'entry_id': 'w1'}) as AssistantPendingAction;
    list.entries.removeAt(0);
    await expectLater(card.execute(), _refuses('not_on_watchlist'));
    await expectLater(_tool('remove_from_watchlist').run(ctx, null, {'entry_id': 'w1'}), _refuses('not_on_watchlist'));
  });

  test('a change that did not go through is an error with its reason, never a success', () async {
    await _list(ctx);
    ctx.showItem(_zolder, 'm02');
    for (final (outcome, code) in [
      (WatchlistOutcome.offlineRejected, 'device_offline'),
      (WatchlistOutcome.unsupported, 'watchlist_not_supported_for_title'),
      (WatchlistOutcome.failed, 'watchlist_failed'),
      (WatchlistOutcome.partiallyFailed, 'watchlist_partly_changed'),
    ]) {
      list.fail = outcome;
      final add = await _tool('add_to_watchlist').run(ctx, _zolder, {'item_id': 'm02'}) as AssistantPendingAction;
      expect(await add.execute(), {'error': code, 'done': false});
      final remove = await _tool('remove_from_watchlist').run(ctx, null, {'entry_id': 'w1'}) as AssistantPendingAction;
      expect(await remove.execute(), {'error': code, 'done': false});
    }
    expect(list.entries, hasLength(2));
  });

  test('without a list the tools are not on offer', () {
    final none = evalContext(kids: false);
    for (final name in ['my_watchlist', 'add_to_watchlist', 'remove_from_watchlist']) {
      expect(_tool(name).serves(none, _zolder), isFalse, reason: name);
      expect(_tool(name).serves(ctx, _zolder), isTrue, reason: name);
    }
  });
}
