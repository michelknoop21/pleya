import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/multi_server_manager.dart';

// Every read path of a run answers to the rights stamp, not only _execute:
// the named-titles lookup, and what an earlier read left in the context (BP-04b).

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

AssistantModelClient _model(List<Map<String, Object?>> script, {void Function(int turn)? onTurn}) {
  var turn = 0;
  return AssistantModelClient(
    AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan:11434', model: 'm'),
    httpClient: MockClient((_) async {
      onTurn?.call(turn);
      final step = turn < script.length ? script[turn] : null;
      turn++;
      final message = step == null
          ? {'role': 'assistant', 'content': 'Klaar.'}
          : step.containsKey('say')
          ? {'role': 'assistant', 'content': step['say']}
          : {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c$turn',
                  'type': 'function',
                  'function': {'name': step['call'], 'arguments': '{}'},
                },
              ],
            };
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': message},
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }),
  );
}

AssistantTool _read(String name, Future<AssistantToolOutcome> Function(AssistantToolContext ctx) run) => AssistantTool(
  name: name,
  description: name,
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (ctx, _, _) => run(ctx),
);

AssistantTitleMatches _card(AssistantToolContext ctx) => AssistantTitleMatches(ctx, [
  AssistantTitleMatch(
    matchId: 'Interstellar',
    title: 'Interstellar',
    kind: 'movie',
    confidence: 'high',
    targets: [
      (
        serverId: ServerId('w'),
        serverName: 'W',
        item: MediaItem(id: 'i', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Interstellar'),
      ),
    ],
  ),
]);

void main() {
  test('a named-titles lookup whose rights moved while it ran leaves no card', () async {
    var epoch = 0;
    var bump = false;
    final findTitle = _read('find_title', (ctx) async {
      if (bump) epoch++;
      return AssistantToolResult(const {}, display: _card(ctx));
    });
    Future<AssistantRunResult> ask() => AssistantRun(
      model: _model([
        {'say': 'Probeer «Interstellar» (2014).'},
      ]),
      context: AssistantToolContext(servers: MultiServerManager()),
      confirm: (_) async => null,
      entitlement: const _Entitled(),
      tools: [findTitle],
      rightsEpoch: () => epoch,
    ).ask('Een goede ruimtefilm?');

    expect((await ask()).displays, isNotEmpty, reason: 'unchanged rights: the card is shown');
    bump = true;
    expect((await ask()).displays, isEmpty, reason: 'rights moved during the lookup: no card from that read');
  });

  test('what an earlier read left is dropped when the rights moved between two calls', () async {
    var epoch = 0;
    String? second;
    final first = _read('first', (ctx) async {
      ctx.showItem(ServerId('a'), 'i1');
      return const AssistantToolResult({'ok': true});
    });
    final next = _read('second', (ctx) async {
      try {
        ctx.requireShownItem(ServerId('a'), 'i1');
        second = 'still shown';
      } on AssistantToolError catch (e) {
        second = e.code;
      }
      return const AssistantToolResult({'ok': true});
    });
    Future<void> ask({required bool move}) async {
      second = null;
      epoch = 0;
      await AssistantRun(
        // The rights move while the model decides on its second call.
        model: _model([
          {'call': 'first'},
          {'call': 'second'},
        ], onTurn: (turn) => epoch = move && turn == 1 ? 1 : 0),
        context: AssistantToolContext(servers: MultiServerManager()),
        confirm: (_) async => null,
        entitlement: const _Entitled(),
        tools: [first, next],
        rightsEpoch: () => epoch,
      ).ask('Doe iets.');
    }

    await ask(move: false);
    expect(second, 'still shown', reason: 'unchanged rights: no false clear');
    await ask(move: true);
    expect(second, 'unknown_item_id');
  });

  test('the named-titles lookup starts from empty caches when the rights moved before it', () async {
    String? seen;
    Future<AssistantRunResult> ask({required bool move}) {
      var epoch = 0;
      seen = null;
      final first = _read('first', (ctx) async {
        ctx.showItem(ServerId('a'), 'i1');
        return const AssistantToolResult({'ok': true});
      });
      final findTitle = _read('find_title', (ctx) async {
        try {
          ctx.requireShownItem(ServerId('a'), 'i1');
          seen = 'still shown';
        } on AssistantToolError catch (e) {
          seen = e.code;
        }
        return AssistantToolResult(const {}, display: _card(ctx));
      });
      return AssistantRun(
        // The rights move while the final answer is written, before the lookup.
        model: _model([
          {'call': 'first'},
          {'say': 'Probeer «Interstellar» (2014).'},
        ], onTurn: (turn) => epoch = move && turn == 1 ? 1 : 0),
        context: AssistantToolContext(servers: MultiServerManager()),
        confirm: (_) async => null,
        entitlement: const _Entitled(),
        tools: [first, findTitle],
        rightsEpoch: () => epoch,
      ).ask('Een goede ruimtefilm?');
    }

    var result = await ask(move: false);
    expect(seen, 'still shown', reason: 'unchanged rights: no false clear');
    result = await ask(move: true);
    expect(seen, 'unknown_item_id');
    expect(result.displays, isNotEmpty, reason: 'the forget does not cost the card the lookup builds');
  });
}
