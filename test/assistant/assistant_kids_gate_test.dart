import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
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
import 'package:pleya/widgets/big_p/assistant/big_p_results.dart';

import 'assistant_find_fakes.dart';

const _hp = 'Harry Potter and the Deathly Hallows: Part 2';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

/// Facts per title, as the chain would have found them.
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

/// The fake library server, healthy for the run's opening probe.
class _Server extends FakeServer {
  _Server(super.id, {super.libraries});
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
}

/// The run's context on a children's profile, or with [kidsProfile] false on
/// an adult one. A run reads the profile at the start of its ask; a tool
/// called directly gets [kidsMode] as the run would have set it.
AssistantToolContext _ctx({List<int> ages = const [8], FakeSeerr? seerr, bool kidsProfile = true}) {
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
    requests: seerr == null ? null : AssistantRequestServices(client: () => seerr.client),
    titleFacts: _Facts(),
    kidsAges: () async => ages,
    kidsProfile: () async => kidsProfile,
    region: () => 'NL',
  )..kidsMode = kidsProfile;
}

/// A model that answers from [script]: a string is a closing answer, a map a
/// tool call. Every request body is kept.
({AssistantModelClient model, List<List<Map<String, Object?>>> sent}) _model(List<Object> script) {
  final sent = <List<Map<String, Object?>>>[];
  final model = AssistantModelClient(
    const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      sent.add((body['messages'] as List).cast());
      final step = script[sent.length - 1];
      final message = step is String
          ? {'role': 'assistant', 'content': step}
          : {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c${sent.length}',
                  'type': 'function',
                  'function': {'name': (step as Map)['name'], 'arguments': jsonEncode(step['args'])},
                },
              ],
            };
      return jsonResponse({
        'choices': [
          {'message': message},
        ],
      });
    }),
  );
  return (model: model, sent: sent);
}

Future<AssistantRunResult> _ask(AssistantModelClient model, AssistantToolContext ctx, String prompt) =>
    AssistantRun(model: model, context: ctx, confirm: (_) async => null, entitlement: const _Entitled()).ask(prompt);

List<String> _cards(AssistantRunResult r) => [
  for (final d in r.displays.whereType<AssistantTitleMatches>())
    for (final m in d.matches) m.title,
];

Future<Map<String, Object?>> _tool(AssistantToolContext ctx, String name, Map<String, Object?> args) async =>
    ((await assistantTools.firstWhere((t) => t.name == name).run(ctx, null, args)) as AssistantToolResult).data;

void main() {
  const prompt = 'Is er een film voor de kinderen?';

  test('an answer reaches the screen without em or en dashes', () async {
    final m = _model(['Kijk «Toy Story» (1995) \u2014 een klassieker.']);
    final result = await _ask(m.model, _ctx(), prompt);
    expect(result.text, 'Kijk «Toy Story» (1995), een klassieker.');
  });

  test('the iOS case: a title for 12+ named for an 8-year-old gets no card and one correction', () async {
    final m = _model(['Kijk «$_hp» (2011).', 'Kijk «Toy Story» (1995).']);
    final result = await _ask(m.model, _ctx(), prompt);

    expect(m.sent, hasLength(2), reason: 'exactly one correction round');
    final correction = m.sent[1].last;
    expect(correction['role'], 'system');
    expect(correction['content'], allOf(contains('«$_hp» (NL 12)'), contains('8 years')));
    expect(_cards(result), ['Toy Story']);
    expect(result.text, 'Kijk «Toy Story» (1995).');
    expect(result.ageFilterNotice, isFalse);
  });

  test('a model that keeps the title: no card, no second correction, Pleya\'s own line in place of the text', () async {
    final m = _model(['Kijk «$_hp» (2011).', 'Toch «$_hp» (2011).', 'nooit gevraagd']);
    final result = await _ask(m.model, _ctx(), prompt);
    expect(m.sent, hasLength(2));
    expect(_cards(result), isEmpty);
    expect(result.text, isEmpty, reason: 'the title appears nowhere');
    expect(result.ageFilterNotice, isTrue);
  });

  test('a title the gate never saw, named in prose with a year, gets the same correction', () async {
    final m = _model(['Kijk Shrek (2001), heel grappig.', 'Kijk «Toy Story» (1995).']);
    final result = await _ask(m.model, _ctx(), prompt);
    expect(m.sent, hasLength(2), reason: 'one correction round');
    expect(m.sent[1].last['content'], allOf(contains('Not checked by the age filter'), contains('Shrek (2001)')));
    expect(result.text, 'Kijk «Toy Story» (1995).');
    expect(result.ageFilterNotice, isFalse);
  });

  test('a title that passed the gate may be named in prose with its year', () async {
    final m = _model([
      {
        'name': 'find_title',
        'args': {
          'candidates': [
            {'title': 'Toy Story'},
          ],
          'variants': ['Toy Story'],
        },
      },
      'Kijk Toy Story (1995), heel leuk.',
    ]);
    final result = await _ask(m.model, _ctx(), prompt);
    expect(m.sent, hasLength(2), reason: 'no correction');
    expect(result.text, 'Kijk Toy Story (1995), heel leuk.');
  });

  test('the controller shows Pleya\'s own line and carries it as a flag', () async {
    final ctx = _ctx();
    final c = AssistantController(
      buildContext: (_) => ctx,
      entitlement: const _Entitled(),
      loadConfig: () async =>
          const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
      modelFor: (_) => _model(['Kijk «$_hp» (2011).', 'Toch «$_hp» (2011).']).model,
      languageName: () => 'Dutch',
    );
    addTearDown(c.dispose);
    await c.submit(prompt);
    expect(c.ageFilterNotice, isTrue);
    expect(c.answer, t.assistant.kids.noFit);
  });

  test('negative control: for a 13-year-old the Harry Potter card comes', () async {
    final m = _model(['Kijk «$_hp» (2011).']);
    final result = await _ask(m.model, _ctx(ages: [13]), prompt);
    expect(m.sent, hasLength(1));
    expect(_cards(result), [_hp]);
  });

  test('without known ages the tool says kids_ages_unknown and Pleya shows its ages card', () async {
    final m = _model([
      {
        'name': 'find_title',
        'args': {
          'variants': ['kids film', 'kinderfilm'],
        },
      },
      'Pleya vraagt eerst hun leeftijd.',
    ]);
    final result = await _ask(m.model, _ctx(ages: []), prompt);
    expect(jsonDecode(m.sent[1].last['content'] as String), {'error': 'kids_ages_unknown'});
    final card = result.displays.whereType<AssistantKidsAgesPrompt>().single;
    expect(card.prompt, prompt);
  });

  test('without ages a named title disappears: only the ages card, no model text', () async {
    final m = _model(['Kijk «Harry Potter», die is spannend.']);
    final result = await _ask(m.model, _ctx(ages: []), prompt);
    expect(result.text, isNot(contains('Harry')));
    expect(result.kidsAgesNeeded, isTrue);
    expect(result.displays, [isA<AssistantKidsAgesPrompt>()]);
  });

  test('without ages, after kids_ages_unknown the model text and its cards go', () async {
    final m = _model([
      {
        'name': 'find_title',
        'args': {
          'variants': ['kinderfilm'],
        },
      },
      'Kijk «$_hp» (2011).',
    ]);
    final result = await _ask(m.model, _ctx(ages: []), prompt);
    expect(result.text, isEmpty);
    expect(result.displays, [isA<AssistantKidsAgesPrompt>()]);
  });

  test('find_title rows carry facts; a children\'s profile filters them and says so', () async {
    final args = {
      'candidates': [
        {'title': _hp},
        {'title': 'Toy Story'},
      ],
      'variants': [_hp, 'Toy Story'],
    };
    final all = matchesOf(await _tool(_ctx(kidsProfile: false), 'find_title', args));
    final hp = all.firstWhere((r) => r['title'] == _hp);
    expect((hp['facts'] as Map)['age_min'], 12);
    expect((hp['facts'] as Map)['age'], {'NL': '12', 'US': 'PG-13'});

    final kids = await _tool(_ctx(), 'find_title', args);
    expect([for (final r in matchesOf(kids)) r['title']], ['Toy Story']);
    expect(kids['filtered_for_age'], 1);
    expect(kids['kids_age'], 8);
  });

  test('a PG-13 request suggestion falls away for an 8-year-old and cannot be requested', () async {
    final seerr = FakeSeerr()
      ..search['Harry'] = [
        {'id': 12445, 'mediaType': 'movie', 'title': _hp, 'releaseDate': '2011-07-07'},
        {'id': 862, 'mediaType': 'movie', 'title': 'Toy Story', 'releaseDate': '1995-11-22'},
      ];
    final ctx = _ctx(seerr: seerr);
    final data = await _tool(ctx, 'find_request_title', {
      'titles': [
        {'title': 'Harry'},
      ],
    });
    expect([for (final r in (data['titles'] as List).cast<Map>()) r['title']], ['Toy Story']);
    expect(data['filtered_for_age'], 1);
    final refused = await assistantRequestFromOption(ctx, 'movie:12445');
    expect((refused as AssistantToolResult).data, {'error': 'unknown_seerr_id'});
  });

  test('saveKidsAgesAndRetry saves the ages and asks the same question again', () async {
    var saved = <int>[];
    final pick = AssistantTool(
      name: 'pick',
      description: 'pick',
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (ctx, _, _) async {
        if ((await ctx.kidsAges!()).isEmpty) throw const AssistantToolError('kids_ages_unknown');
        return const AssistantToolResult({'ok': true});
      },
    );
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: MultiServerManager(), kidsAges: () async => saved),
      entitlement: const _Entitled(),
      loadConfig: () async =>
          const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
      modelFor: (_) => _model([
        {'name': 'pick', 'args': <String, Object?>{}},
        'klaar',
      ]).model,
      languageName: () => 'Dutch',
      tools: [pick],
      saveKidsAges: (ages) async => saved = ages,
    );
    addTearDown(c.dispose);

    await c.submit(prompt);
    expect(c.displays.whereType<AssistantKidsAgesPrompt>().single.prompt, prompt);

    await c.saveKidsAgesAndRetry([6, 9]);
    expect(saved, [6, 9]);
    expect(c.runs, 2);
    expect(c.prompt, prompt);
    expect(c.displays.whereType<AssistantKidsAgesPrompt>(), isEmpty);
  });

  group('an adult profile: the kids machinery is off', () {
    test('"film voor de kinderen" answers with normal results: no gate, no ages card, no notice', () async {
      final m = _model(['Kijk «$_hp» (2011).']);
      final result = await _ask(m.model, _ctx(kidsProfile: false, ages: []), prompt);
      expect(m.sent, hasLength(1), reason: 'no correction round');
      expect(_cards(result), [_hp]);
      expect(result.text, 'Kijk «$_hp» (2011).');
      expect(result.kidsAgesNeeded, isFalse);
      expect(result.displays.whereType<AssistantKidsAgesPrompt>(), isEmpty);
      expect(result.ageFilterNotice, isFalse);
    });

    test('a for_kids argument from the model filters nothing', () async {
      final ctx = _ctx(kidsProfile: false, ages: []);
      final data = await _tool(ctx, 'find_title', {
        'candidates': [
          {'title': _hp},
          {'title': 'Toy Story'},
        ],
        'variants': [_hp, 'Toy Story'],
        'for_kids': true,
      });
      expect([for (final r in matchesOf(data)) r['title']], containsAll([_hp, 'Toy Story']));
      expect(data.containsKey('filtered_for_age'), isFalse);
      expect(ctx.kidsMode, isFalse);
      expect(ctx.ageRejected, isEmpty);
    });

    test('the system prompt only mentions the filter on a children\'s profile', () async {
      final adult = _model(['Klaar.']);
      await _ask(adult.model, _ctx(kidsProfile: false), prompt);
      expect(adult.sent.first.first['content'], isNot(contains("children's profile")));
      final kids = _model(['Klaar.']);
      await _ask(kids.model, _ctx(), prompt);
      expect(kids.sent.first.first['content'], contains("This is a children's profile"));
    });
  });

  test('no title tool offers a for_kids parameter: the profile decides, not the model', () {
    for (final tool in assistantTools) {
      expect(tool.properties.containsKey('for_kids'), isFalse, reason: tool.name);
    }
  });

  test('the profile is read at the start of every ask', () async {
    var kids = false;
    final ctx = _ctx(kidsProfile: false);
    final perAsk = AssistantToolContext(
      servers: ctx.servers,
      catalog: ctx.catalog,
      titleFacts: ctx.titleFacts,
      kidsAges: ctx.kidsAges,
      kidsProfile: () async => kids,
      region: ctx.region,
    );
    final adult = await _ask(_model(['Kijk «$_hp» (2011).']).model, perAsk, prompt);
    expect(_cards(adult), [_hp]);
    kids = true;
    final m = _model(['Kijk «$_hp» (2011).', 'Kijk «Toy Story» (1995).']);
    final child = await _ask(m.model, perAsk, prompt);
    expect(m.sent, hasLength(2), reason: 'the correction round of a children\'s profile');
    expect(_cards(child), ['Toy Story']);
  });

  test('dismissKidsAges takes the card away and keeps the answer', () async {
    final pick = AssistantTool(
      name: 'pick',
      description: 'pick',
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (_, _, _) async => throw const AssistantToolError('kids_ages_unknown'),
    );
    final c = AssistantController(
      buildContext: (_) => AssistantToolContext(servers: MultiServerManager()),
      entitlement: const _Entitled(),
      loadConfig: () async =>
          const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
      modelFor: (_) => _model([
        {'name': 'pick', 'args': <String, Object?>{}},
        'klaar',
      ]).model,
      languageName: () => 'Dutch',
      tools: [pick],
    );
    addTearDown(c.dispose);
    await c.submit(prompt);
    expect(c.kidsAgesPrompt, isNotNull);
    // Pleya's own line, not the model's: its text was written without ages.
    expect(c.answer, t.assistant.kids.agesFirst);
    c.dismissKidsAges();
    expect(c.kidsAgesPrompt, isNull);
    expect(c.answer, t.assistant.kids.agesFirst);
  });

  test('every tool chose its place in kids mode: gated, neutral or blocked', () {
    final names = {
      for (final t in [...assistantTools, assistantSpoilerTool]) t.name,
    };
    expect(names.where((n) => !kidsToolPolicy.containsKey(n)), isEmpty, reason: 'add the tool to kidsToolPolicy');
    expect(kidsToolPolicy.keys.where((n) => !names.contains(n)), isEmpty, reason: 'no stale names');
    for (final blocked in const [
      'my_watching',
      'recommend_together',
      'create_home_row',
      'spoiler_context',
      'list_jobs',
    ]) {
      expect(kidsToolPolicy[blocked], KidsTool.blocked, reason: blocked);
    }
  });

  group('kids mode refuses tools whose titles skip the gate', () {
    var ran = 0;
    final watching = AssistantTool(
      name: 'my_watching',
      description: 'w',
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (_, _, _) async {
        ran++;
        return const AssistantToolResult({
          'titles': [_hp],
        });
      },
    );
    final find = AssistantTool(
      name: 'find_title',
      description: 'f',
      risk: AssistantToolRisk.read,
      properties: const {},
      needsServer: false,
      serves: (_, _) => true,
      run: (_, _, _) async => const AssistantToolResult({'titles': <Object>[]}),
    );
    setUp(() => ran = 0);

    Future<List<List<Map<String, Object?>>>> run(String prompt, List<Object> script, {bool kids = true}) async {
      final m = _model(script);
      await AssistantRun(
        model: m.model,
        context: _ctx(kidsProfile: kids),
        confirm: (_) async => null,
        entitlement: const _Entitled(),
        tools: [watching, find],
      ).ask(prompt);
      return m.sent;
    }

    test('a children\'s profile: my_watching is refused with a hint and never runs', () async {
      final sent = await run('Wat heb ik laatst gekeken?', [
        {'name': 'my_watching', 'args': <String, Object?>{}},
        'Klaar.',
      ]);
      expect(jsonDecode(sent[1].last['content'] as String), assistantKidsRefusal);
      expect(ran, 0);
    });

    test('an adult profile runs my_watching, also for a question about the kids', () async {
      final sent = await run(prompt, [
        {'name': 'my_watching', 'args': <String, Object?>{}},
        'Klaar.',
      ], kids: false);
      expect(jsonDecode(sent[1].last['content'] as String), {
        'titles': [_hp],
      });
      expect(ran, 1);
    });
  });

  test('the existing renderers take the ages card as a display without choices', () {
    const display = AssistantKidsAgesPrompt(prompt);
    expect(bigPChoiceCount(display), 0);
    expect(bigPTitleMatches(display), isEmpty);
    expect(bigPDisplayIsEmpty(display), isFalse);
  });
}
