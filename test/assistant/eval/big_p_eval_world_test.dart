import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';

import 'big_p_eval_fixtures.dart';
import 'big_p_eval_world.dart';

// The builders of big_p_eval_world, each read through the real tool that a
// case will use, so a case never rests on a fixture that silently serves
// nothing (BP-11a2).

Future<Map<String, Object?>> _run(AssistantToolContext ctx, String name, [Map<String, Object?> args = const {}]) async {
  final tool = assistantTools.firstWhere((t) => t.name == name);
  return ((await tool.run(ctx, null, args)) as AssistantToolResult).data;
}

void main() {
  test('the plain fixture offers none of the extra sources', () {
    final names = assistantTools
        .where((t) => t.serves(evalContext(kids: false), ServerId('zolder')))
        .map((t) => t.name)
        .toSet();
    expect(names, isNot(contains('trakt_watchlist')));
    expect(names, isNot(contains('find_request_title')));
    expect(names, isNot(contains('recall_memory')));
    expect(names, isNot(contains('my_watching')));
  });

  test('the second profile watched other titles than the first', () async {
    final michel = evalContext(kids: false, world: const EvalWorld(profile: evalMichel));
    final sanne = evalContext(kids: false, world: const EvalWorld(profile: evalSanne));
    expect(michel.personal!.userName, 'Michel');
    expect(sanne.personal!.userName, 'Sanne');
    final a = await michel.personal!.everSeen();
    final b = await sanne.personal!.everSeen();
    expect(a.intersection(b), isEmpty, reason: 'no overlap, so a mix-up shows');
    expect(evalSanne.seenIds.every((id) => evalTitles.any((t) => t.id == id)), isTrue);
    expect(evalSanne.pickIds.every((id) => !evalSanne.seenIds.contains(id)), isTrue);
  });

  test('the offline server is registered, visible and not online', () async {
    final ctx = evalContext(kids: false, world: const EvalWorld(offlineServer: true));
    final servers = (await _run(ctx, 'list_servers'))['servers'] as List;
    expect(servers, hasLength(2));
    expect(ctx.servers.isServerOnline(ctx.userServers.first), isTrue);
    expect([for (final s in ctx.userServers) ctx.servers.isServerOnline(s)], containsAll([true, false]));
  });

  test('Trakt serves its watchlist, or the reason it cannot', () async {
    final ok = evalContext(kids: false, world: EvalWorld(trakt: evalTrakt()));
    final data = await _run(ok, 'trakt_watchlist');
    expect(data.toString(), allOf(contains('Coco'), contains('Primer')));
    final blocked = evalContext(
      kids: false,
      world: EvalWorld(trakt: evalTrakt(blockedBy: 'trakt_not_linked')),
    );
    await expectLater(_run(blocked, 'trakt_watchlist'), throwsA(predicate((e) => '$e'.contains('trakt_not_linked'))));
  });

  test('Seerr finds a title that is not in the library', () async {
    final seerr = evalSeerr();
    final ctx = evalContext(kids: false, world: EvalWorld(seerr: seerr));
    final data = await _run(ctx, 'find_request_title', {
      'titles': [
        {'title': 'Severance'},
      ],
    });
    expect(data.toString(), contains('Severance'));
    expect(seerr.paths, contains('search:Severance'));
  });

  test('memory is per profile', () async {
    final memory = await EvalMemory.open(michelFacts: ['houdt van komedies'], sanneFacts: ['kijkt geen horror']);
    expect(await memory.michel.values(), ['houdt van komedies']);
    expect(await memory.sanne.values(), ['kijkt geen horror']);
    final ctx = evalContext(kids: false, world: EvalWorld(memory: memory))
      ..memoryTurn = AssistantMemoryTurn(enabled: true);
    expect((await _run(ctx, 'recall_memory')).toString(), allOf(contains('komedies'), isNot(contains('horror'))));
  });
}
