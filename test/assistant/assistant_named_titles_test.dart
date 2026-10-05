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
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/multi_server_manager.dart';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

AssistantTitleMatch _match(String title, {bool inLibrary = false}) => AssistantTitleMatch(
  matchId: title,
  title: title,
  kind: 'movie',
  confidence: 'high',
  targets: [
    if (inLibrary)
      (
        serverId: ServerId('w'),
        serverName: 'W',
        item: MediaItem(id: title, backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: title),
      ),
  ],
);

/// Films and series Big P names get a card from Pleya, not from the model.
void main() {
  test('Big P\'s words carry no em or en dashes', () {
    expect(assistantPlainDashes('Bluey \u2014 20 plays'), 'Bluey, 20 plays');
    expect(assistantPlainDashes('Bluey\u2014the show'), 'Bluey, the show');
    expect(assistantPlainDashes('Gideuh \u2013 34 plays'), 'Gideuh, 34 plays');
    expect(assistantPlainDashes('2018\u20132020'), '2018-2020');
    expect(assistantPlainDashes('Done \u2014.'), 'Done.');
    expect(assistantPlainDashes('Nothing to change.'), 'Nothing to change.');
    // Bullets stay lines, ranges stay ranges, no stray commas.
    expect(assistantPlainDashes('Picks:\n\u2014 A\n\u2014 B'), 'Picks:\n- A\n- B');
    expect(assistantPlainDashes('(2019 \u2013 2021)'), '(2019-2021)');
    expect(assistantPlainDashes('A\u2014\u2014B'), 'A, B');
    expect(assistantPlainDashes('Note: \u2014 x'), 'Note: x');
  });

  test('"Bluey (2018)" on a card and «Bluey» (2018) in the answer are one title', () {
    final card = (key: assistantTitleKey('Bluey (2018)'), year: 2018);
    expect(assistantSameTitle(card, assistantTitleKey('Bluey'), 2018), isTrue);
    expect(assistantTitleKey('Dune (1984)'), assistantTitleKey('Dune'));
    // A title that is a number stays a number.
    expect(assistantTitleKey('2012'), '2012');
  });

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
    expect(assistantNamedTitles('«Dune» (1984) en «Dune» (2021)'), [
      (title: 'Dune', year: 1984),
      (title: 'Dune', year: 2021),
    ], reason: 'a remake is its own title');
    expect(assistantNamedTitles('«Gravity» (0000)'), [
      (title: 'Gravity', year: null),
    ], reason: 'a year find_title would refuse is dropped, not the title');
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
          display: AssistantTitleMatches(ctx, [
            _match('Interstellar', inLibrary: true),
            _match('Gravity', inLibrary: true),
            _match('Interstellar'),
          ]),
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
    expect(
      cards.matches,
      hasLength(1),
      reason: 'Gravity was not named; a card with nothing to open or request is dropped',
    );
    expect(cards.matches.single.targets, isNotEmpty);
    expect(steps.last.display, same(cards), reason: 'the panel shows it as it does any tool display');
  });

  test('a find_media grid that led to an action leaves no card; one that did not stays', () async {
    final dune = MediaItem(id: 'd1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Dune');
    AssistantTool tool(
      String name,
      AssistantDisplay? Function(AssistantToolContext) display, {
      AssistantActionRecord? record,
    }) => AssistantTool(
      name: name,
      description: name,
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (ctx, _, _) async => AssistantToolResult(const {'ok': true}, display: display(ctx), record: record),
    );
    final tools = [
      tool('find_media', (_) => AssistantMediaGrid([(item: dune, group: null)])),
      tool(
        'refresh_metadata',
        (_) => null,
        record: const AssistantActionRecord(
          kind: AssistantActionKind.refreshMetadata,
          serverName: 'W',
          subject: 'Dune',
        ),
      ),
      // A read that names the item is no action: the grid stays.
      tool('find_subtitles', (_) => null),
    ];
    Future<AssistantRunResult> run(List<Map<String, Object?>> calls) {
      var turn = 0;
      final model = AssistantModelClient(
        AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan:11434', model: 'm'),
        httpClient: MockClient((_) async {
          final message = turn < calls.length
              ? {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'c$turn',
                      'type': 'function',
                      'function': {'name': calls[turn]['name'], 'arguments': jsonEncode(calls[turn]['args'])},
                    },
                  ],
                }
              : {'role': 'assistant', 'content': 'Klaar.'};
          turn++;
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
      return AssistantRun(
        model: model,
        context: AssistantToolContext(servers: MultiServerManager()),
        confirm: (_) async => null,
        entitlement: const _Entitled(),
        tools: tools,
      ).ask('x');
    }

    final acted = await run([
      {
        'name': 'find_media',
        'args': {'query': 'Dune'},
      },
      {
        'name': 'refresh_metadata',
        'args': {'item_id': 'd1'},
      },
    ]);
    expect(acted.displays, isEmpty, reason: 'the lookup led to the action');

    final found = await run([
      {
        'name': 'find_media',
        'args': {'query': 'Dune'},
      },
      {
        'name': 'find_subtitles',
        'args': {'item_id': 'd1'},
      },
    ]);
    expect(found.displays.single, isA<AssistantMediaGrid>());
  });
}
