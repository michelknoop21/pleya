import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_named_titles.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';

import 'assistant_find_fakes.dart';

// The closing answer on a children's profile: a turned-down title in plain
// prose, the ages card only for an answer that names titles, and child task
// titles that are not the model's.

const _hp = 'Harry Potter and the Deathly Hallows: Part 2';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Facts extends TitleFactsService {
  _Facts() : super(cache: TitleFactsCache());
  static const byTitle = {
    _hp: TitleFacts(certifications: {'NL': '12', 'US': 'PG-13'}, genres: ['Fantasy']),
    'Toy Story': TitleFacts(certifications: {'NL': 'AL', 'US': 'G'}, genres: ['Animation']),
  };
  @override
  Future<List<TitleFacts>> factsFor(List<TitleRef> refs) async => [
    for (final r in refs) byTitle[r.title] ?? const TitleFacts(),
  ];
}

class _Server extends FakeServer {
  _Server(super.id, {super.libraries});
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
}

AssistantToolContext _ctx({List<int> ages = const [8]}) {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(
    _Server(
      'w',
      libraries: {
        'films': [fakeItem('hp', _hp, year: 2011), fakeItem('ts', 'Toy Story', year: 1995)],
      },
    ),
  );
  m.setVisibleServerIds(null);
  return AssistantToolContext(
    servers: m,
    catalog: AssistantCatalogServices(
      rowLoader: CatalogHomeCustomRowLoader(
        libraries: () => [fakeLib('w', 'films')],
        isServerVisible: m.isServerVisible,
        hiddenLibraryKeys: () => const {},
        clientFor: m.getClient,
      ),
      profileId: 'p',
      activeProfileId: () => 'p',
    ),
    titleFacts: _Facts(),
    kidsAges: () async => ages,
    kidsProfile: () async => true,
    region: () => 'NL',
  );
}

Map<String, Object?> _reply(Object step, int n) => step is String
    ? {'role': 'assistant', 'content': step}
    : {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'c$n',
            'type': 'function',
            'function': {'name': (step as Map)['name'], 'arguments': jsonEncode(step['args'])},
          },
        ],
      };

/// [pick] chooses the reply from the tool names offered and the call count.
({AssistantModelClient model, List<List<Map<String, Object?>>> sent}) _model(
  Object Function(List<String> tools, int n) pick,
) {
  final sent = <List<Map<String, Object?>>>[];
  final model = AssistantModelClient(
    const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      sent.add((body['messages'] as List).cast());
      final tools = [
        for (final t in (body['tools'] as List? ?? const [])) ((t as Map)['function'] as Map)['name'] as String,
      ];
      return jsonResponse({
        'choices': [
          {'message': _reply(pick(tools, sent.length), sent.length)},
        ],
      });
    }),
  );
  return (model: model, sent: sent);
}

({AssistantModelClient model, List<List<Map<String, Object?>>> sent}) _script(List<Object> script) =>
    _model((_, n) => script[n - 1]);

Future<AssistantRunResult> _ask(AssistantModelClient model, AssistantToolContext ctx, String prompt) =>
    AssistantRun(model: model, context: ctx, confirm: (_) async => null, entitlement: const _Entitled()).ask(prompt);

/// find_title for [titles]: the gate passes Toy Story and turns down the 12+ film.
Map<String, Object?> _find(List<String> titles) => {
  'name': 'find_title',
  'args': {
    'candidates': [
      for (final t in titles) {'title': t},
    ],
    'variants': titles,
  },
};

List<String> _cards(AssistantRunResult r) => [
  for (final d in r.displays.whereType<AssistantTitleMatches>())
    for (final m in d.matches) m.title,
];

AssistantController _controller(AssistantModelClient model, AssistantToolContext ctx) {
  final c = AssistantController(
    buildContext: (_) => ctx,
    entitlement: const _Entitled(),
    loadConfig: () async =>
        const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
    modelFor: (_) => model,
    languageName: () => 'Dutch',
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  const prompt = 'Een film voor de kinderen?';

  group('a turned-down title in the answer text', () {
    test('R2: named in prose without « » or year, it gets the correction round', () async {
      final m = _script([
        _find([_hp]),
        'Probeer eens $_hp, die is heel spannend.',
        'Kijk «Toy Story» (1995).',
      ]);
      final r = await _ask(m.model, _ctx(), prompt);
      expect(m.sent, hasLength(3), reason: 'one correction round');
      expect(m.sent[2].last['content'], contains('«$_hp» (NL 12)'));
      expect(r.text, 'Kijk «Toy Story» (1995).');
      expect(r.ageFilterNotice, isFalse);
    });

    test('the main title without its subtitle, in lower case, still counts', () async {
      final m = _script([
        _find([_hp]),
        'harry potter and the deathly hallows is spannend.',
        'Kijk «Toy Story» (1995).',
      ]);
      final r = await _ask(m.model, _ctx(), prompt);
      expect(m.sent, hasLength(3), reason: 'one correction round');
      expect(r.text, 'Kijk «Toy Story» (1995).');
    });

    test('a model that keeps the title: Pleya\'s own line replaces the text, no card names it', () async {
      final m = _script([
        _find([_hp]),
        'Probeer $_hp.',
        'Toch $_hp, echt waar.',
        'nooit gevraagd',
      ]);
      final r = await _ask(m.model, _ctx(), prompt);
      expect(m.sent, hasLength(3), reason: 'no second correction');
      expect(r.text, isEmpty);
      expect(r.ageFilterNotice, isTrue);
      expect(_cards(r), isNot(contains(_hp)));

      final c = _controller(
        _script([
          _find([_hp]),
          'Probeer $_hp.',
          'Toch «$_hp» (2011).',
        ]).model,
        _ctx(),
      );
      await c.submit(prompt);
      expect(c.answer, t.assistant.kids.noFit);
      expect(c.answer, isNot(contains('Harry')));
      expect(c.ageFilterNotice, isTrue);
      expect([
        for (final d in c.displays.whereType<AssistantTitleMatches>())
          for (final m in d.matches) m.title,
      ], isNot(contains(_hp)));
    });

    test('negative control: Toy Story passed and never replaces the text, also next to a turned-down title', () async {
      final m = _script([
        _find([_hp, 'Toy Story']),
        'Toy Story is een leuke film voor jullie.',
      ]);
      final r = await _ask(m.model, _ctx(), prompt);
      expect(m.sent, hasLength(2), reason: 'no correction');
      expect(r.text, 'Toy Story is een leuke film voor jullie.');
      expect(r.ageFilterNotice, isFalse);
    });
  });

  test('plain words fold accents and drop marks; a short main title is no match on its own', () {
    expect(assistantPlainWords('«Amélie» (2001)!'), 'amelie 2001');
    expect(assistantTitleWords(_hp), [
      'harry potter and the deathly hallows part 2',
      'harry potter and the deathly hallows',
    ]);
    expect(assistantTitleWords('Up: Carl\'s Date'), ['up carl s date']);
    expect(assistantTitleWords('Spider-Man - Homecoming'), ['spider man homecoming', 'spider man']);
  });

  group('a children\'s profile without ages', () {
    test('R1: a question without titles is answered normally', () async {
      final m = _script([
        {'name': 'list_servers', 'args': <String, Object?>{}},
        'Je server w is online.',
      ]);
      final r = await _ask(m.model, _ctx(ages: const []), 'Wat is mijn serverstatus?');
      expect(r.kidsAgesNeeded, isFalse);
      expect(r.text, 'Je server w is online.');
    });

    test('an answer without tools that names titles still gets the ages card', () async {
      for (final answer in ['Kijk «Saw».', 'Kijk Saw (2004), heel eng.', '- Saw (2004)\n- The Exorcist (1973)']) {
        final r = await _ask(_script([answer]).model, _ctx(ages: const []), prompt);
        expect(r.kidsAgesNeeded, isTrue, reason: answer);
        expect(r.text, isEmpty, reason: answer);
      }
    });
  });

  test('R3: split tasks on a children\'s profile get a neutral title, not the model\'s', () async {
    final m = _model((tools, _) {
      if (tools.contains('split_tasks')) {
        return {
          'name': 'split_tasks',
          'args': {
            'tasks': [
              {'title': 'Zoek «Saw» (2004)', 'intent': 'find', 'prompt': 'Zoek Saw'},
              {'title': 'Serverstatus', 'intent': 'status', 'prompt': 'Serverstatus'},
            ],
          },
        };
      }
      return 'Klaar.';
    });
    final c = _controller(m.model, _ctx());
    await c.submit('Zoek Saw en geef mijn serverstatus');
    expect(c.tasks.map((t) => t.title), [t.assistant.tasks.numbered(n: 1), t.assistant.tasks.numbered(n: 2)]);
  });
}
