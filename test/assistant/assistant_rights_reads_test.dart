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

AssistantModelClient _model(List<Map<String, Object?>> script) {
  var turn = 0;
  return AssistantModelClient(
    AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan:11434', model: 'm'),
    httpClient: MockClient((_) async {
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

void main() {
  test('a named-titles lookup whose rights moved while it ran leaves no card', () async {
    var epoch = 0;
    final findTitle = _read('find_title', (ctx) async {
      epoch++;
      return AssistantToolResult(
        const {},
        display: AssistantTitleMatches(ctx, [
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
        ]),
      );
    });
    Future<AssistantRunResult> ask({required bool moves}) {
      epoch = 0;
      return AssistantRun(
        model: _model([
          {'say': 'Probeer «Interstellar» (2014).'},
        ]),
        context: AssistantToolContext(servers: MultiServerManager()),
        confirm: (_) async => null,
        entitlement: const _Entitled(),
        tools: [findTitle],
        // Stamped before and after the lookup; moves with it when asked to.
        rightsEpoch: () => moves ? epoch : 0,
      ).ask('Een goede ruimtefilm?');
    }

    expect((await ask(moves: false)).displays, isNotEmpty, reason: 'unchanged rights: the card is shown');
    expect((await ask(moves: true)).displays, isEmpty, reason: 'rights moved: no card from that read');
  });

  test('what an earlier read showed cannot be acted on once the rights have moved', () async {
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
    final ctx = AssistantToolContext(servers: MultiServerManager());
    Future<void> ask({required bool move}) async {
      second = null;
      epoch = 0;
      final result = AssistantRun(
        model: _model([
          {'call': 'first'},
          {'call': 'second'},
        ]),
        context: ctx,
        confirm: (_) async => null,
        entitlement: const _Entitled(),
        tools: [first, next],
        // The second call begins under a different epoch than the first.
        rightsEpoch: () => move ? epoch++ ~/ 2 : 0,
      );
      await result.ask('Doe iets.');
    }

    await ask(move: false);
    expect(second, 'still shown');
    await ask(move: true);
    expect(second, 'unknown_item_id');
  });
}
