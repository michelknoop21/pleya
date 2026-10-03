import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_named_titles.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/services/multi_server_manager.dart';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

AssistantTitleMatch _match(String title) =>
    AssistantTitleMatch(matchId: title, title: title, kind: 'movie', confidence: 'high', targets: const []);

/// Films and series Big P names get a card from Pleya, not from the model.
void main() {
  test('titles between « » come first; list items with a year when the marks are missing', () {
    expect(assistantNamedTitles('Kijk «Interstellar» (2014) of «Gravity».'), [
      (title: 'Interstellar', year: 2014),
      (title: 'Gravity', year: null),
    ]);
    expect(assistantNamedTitles('Tips:\n- Interstellar (2014)\n2. **Gravity** (2013)\n- Scan gestart'), [
      (title: 'Interstellar', year: 2014),
      (title: 'Gravity', year: 2013),
    ]);
    expect(assistantNamedTitles('Ik heb de scan gestart.'), isEmpty);
    expect(assistantNamedTitles('«A» «B» «C» «D» «E» «F» «a»'), hasLength(5));
  });

  test('a named title without a card gets one, exact titles only, already shown ones skipped', () async {
    final asked = <Map<String, Object?>>[];
    final findTitle = AssistantTool(
      name: 'find_title',
      description: 'find',
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (ctx, _, args) async {
        asked.add(args);
        return AssistantToolResult(
          const {},
          display: AssistantTitleMatches(ctx, [_match('Interstellar'), _match('Gravity')]),
        );
      },
    );
    var calls = 0;
    final model = AssistantModelClient(
      AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan:11434', model: 'm'),
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Probeer «Interstellar» (2014).'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final steps = <AssistantStep>[];
    final result = await AssistantRun(
      model: model,
      context: AssistantToolContext(servers: MultiServerManager()),
      confirm: (_) async => null,
      entitlement: const _Entitled(),
      tools: [findTitle],
      onStep: steps.add,
    ).ask('Een goede ruimtefilm?');

    expect(calls, 1, reason: 'the lookup is Pleya\'s own, not another model turn');
    expect(asked.single['candidates'], [
      {'title': 'Interstellar', 'year': 2014},
    ]);
    final cards = result.displays.single as AssistantTitleMatches;
    expect([for (final m in cards.matches) m.title], ['Interstellar'], reason: 'Gravity was not named');
    expect(steps.last.display, same(cards), reason: 'the panel shows it as it does any tool display');
  });
}
