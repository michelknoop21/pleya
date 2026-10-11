import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_single_title.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';

import 'assistant_find_fakes.dart';

// A question after one specific title ("die film met Tom Hanks over death
// row") whose answer names that one title: only its card stays, whatever else
// the search brought up on the way.

const _mile = 'The Green Mile';
const _gump = 'Forrest Gump';
const _toy = 'Toy Story';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Facts extends TitleFactsService {
  _Facts() : super(cache: TitleFactsCache());
  static const byTitle = {
    _mile: TitleFacts(certifications: {'NL': '16', 'US': 'R'}, genres: ['Drama']),
    _gump: TitleFacts(certifications: {'NL': '12', 'US': 'PG-13'}, genres: ['Drama']),
    'Cast Away': TitleFacts(certifications: {'NL': '12', 'US': 'PG-13'}, genres: ['Drama']),
    _toy: TitleFacts(certifications: {'NL': 'AL', 'US': 'G'}, genres: ['Animation']),
    'Toy Story 2': TitleFacts(certifications: {'NL': 'AL', 'US': 'G'}, genres: ['Animation']),
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

MediaItem _hanks(String id, String title, int year, String summary) =>
    fakeItem(id, title, year: year, summary: summary).copyWith(roles: const [MediaRole(tag: 'Tom Hanks')]);

/// A library with five Tom Hanks films and one without him.
AssistantToolContext _ctx({bool kids = false}) {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(
    _Server(
      'w',
      libraries: {
        'films': [
          _hanks('gm', _mile, 1999, 'Guards on death row meet an inmate with a gift.'),
          _hanks('fg', _gump, 1994, 'A man from Alabama witnesses history.'),
          _hanks('ca', 'Cast Away', 2000, 'A courier strands on an island.'),
          _hanks('ts', _toy, 1995, 'A cowboy doll and a space ranger.'),
          _hanks('t2', 'Toy Story 2', 1999, 'A cowboy doll is stolen by a collector.'),
          fakeItem('he', 'Heat', year: 1995, summary: 'A detective hunts a crew of robbers.'),
        ],
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
    kidsAges: () async => const [8],
    kidsProfile: () async => kids,
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

({AssistantModelClient model, List<List<Map<String, Object?>>> sent}) _script(List<Object> script) {
  final sent = <List<Map<String, Object?>>>[];
  final model = AssistantModelClient(
    const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan', model: 'm'),
    httpClient: MockClient((request) async {
      sent.add(((jsonDecode(request.body) as Map<String, Object?>)['messages'] as List).cast());
      return jsonResponse({
        'choices': [
          {'message': _reply(script[sent.length - 1], sent.length)},
        ],
      });
    }),
  );
  return (model: model, sent: sent);
}

Future<AssistantRunResult> _ask(
  List<Object> script,
  String prompt, {
  AssistantToolContext? ctx,
  List<AssistantTool>? tools,
}) => AssistantRun(
  model: _script(script).model,
  context: ctx ?? _ctx(),
  confirm: (_) async => null,
  entitlement: const _Entitled(),
  tools: tools,
).ask(prompt);

/// The model's search for an actor: no candidate title, the actor as phrase.
const _findHanks = {
  'name': 'find_title',
  'args': {
    'kind': 'movie',
    'variants': ['Tom Hanks', 'Tom Hanks film'],
  },
};

List<String> _cards(AssistantRunResult r) => [
  for (final d in r.displays)
    ...switch (d) {
      AssistantTitleMatches(:final matches) => [for (final m in matches) m.title],
      AssistantMediaGrid(:final entries) => [for (final e in entries) e.item.title ?? ''],
      _ => const <String>[],
    },
];

AssistantTitleMatch _match(String title, int year, {bool drawn = true}) => AssistantTitleMatch(
  matchId: title,
  title: title,
  year: year,
  kind: 'movie',
  confidence: 'high',
  targets: [
    if (drawn)
      (
        serverId: ServerId('w'),
        serverName: 'W',
        item: MediaItem(id: title, backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: title, year: year),
      ),
  ],
);

AssistantTool _tool(String name, AssistantDisplay? Function(AssistantToolContext) display) => AssistantTool(
  name: name,
  description: name,
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (ctx, _, _) async => AssistantToolResult(const {'ok': true}, display: display(ctx)),
);

MediaItem _item(String title, int year) => MediaItem(
  id: title,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: title,
  year: year,
  serverId: 'w',
);

void main() {
  const one = 'Hoe heet die film met Tom Hanks over death row?';
  const answer = 'Dat is «$_mile» (1999).';

  group('one title asked, one title named', () {
    test('NL: the search brings up his other films, only the named one keeps its card', () async {
      final r = await _ask([_findHanks, answer], one);
      expect(r.text, answer);
      expect(_cards(r), [_mile]);
    });

    test('EN question forms narrow the same way', () async {
      for (final prompt in [
        'What is that movie with Tom Hanks about death row?',
        'Which film has Tom Hanks as a prison guard?',
        'I am looking for the movie with Tom Hanks on death row',
      ]) {
        final r = await _ask([_findHanks, 'That is «$_mile» (1999).'], prompt);
        expect(_cards(r), [_mile], reason: prompt);
      }
    });

    test('NL question forms narrow the same way', () async {
      for (final prompt in [
        'Ik zoek die film met Tom Hanks over deathrow',
        'Welke film met Tom Hanks speelt in een dodencel?',
        'Ik weet niet meer hoe de film met Tom Hanks in de gevangenis heet',
      ]) {
        final r = await _ask([_findHanks, answer], prompt);
        expect(_cards(r), [_mile], reason: prompt);
      }
    });

    test('a grid of search results is narrowed too and keeps the facts of its title', () async {
      const facts = TitleFacts(genres: ['Drama']);
      final r = await _ask(
        [
          {'name': 'search_catalog', 'args': <String, Object?>{}},
          answer,
        ],
        one,
        tools: [
          _tool(
            'search_catalog',
            (_) => AssistantMediaGrid(
              [
                (item: _item(_gump, 1994), group: null),
                (item: _item(_mile, 1999), group: null),
                (item: _item('Cast Away', 2000), group: null),
              ],
              facts: {AssistantMediaGrid.keyOf((item: _item(_mile, 1999), group: null)): facts},
            ),
          ),
        ],
      );
      final grid = r.displays.single as AssistantMediaGrid;
      expect(_cards(r), [_mile]);
      expect(grid.facts.values.single, same(facts));
    });
    test('a named title the search missed gets its own card, and that is the one card', () async {
      final r = await _ask([_findHanks, 'Dat is «Heat» (1995).'], 'Hoe heet die film over een bankoverval?');
      expect(_cards(r), ['Heat']);
    });
  });

  group('everything else keeps its cards', () {
    test('a question for several titles keeps every card, also when the answer names one', () async {
      for (final prompt in [
        'Welke films met Tom Hanks heb ik?',
        'Films met Tom Hanks',
        'Iets spannends voor vanavond',
        'Which movies with Tom Hanks do I have?',
        'Geef me drie opties, bijvoorbeeld die film met Tom Hanks',
        'Iets zoals die film met Tom Hanks over death row',
      ]) {
        final r = await _ask([_findHanks, answer], prompt);
        expect(_cards(r).length, greaterThan(1), reason: prompt);
        expect(_cards(r), contains(_gump), reason: prompt);
      }
    });

    test('an answer that names no title leaves the found titles as they are', () async {
      final before = _cards(await _ask([_findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      final r = await _ask([_findHanks, 'Ik weet niet zeker welke je bedoelt.'], one);
      expect(_cards(r), before, reason: 'no card is picked for the user');
    });

    test('an answer that names a title outside the result keeps the result and picks none', () async {
      final before = _cards(await _ask([_findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      final r = await _ask([_findHanks, 'Dat is «Philadelphia» (1993).'], one);
      expect(_cards(r), before);
    });

    test('a named title whose only card cannot be opened or requested narrows nothing', () async {
      final r = await _ask(
        [
          {'name': 'trending_titles', 'args': <String, Object?>{}},
          answer,
        ],
        one,
        tools: [
          _tool(
            'trending_titles',
            (ctx) => AssistantTitleMatches(ctx, [_match(_gump, 1994), _match(_mile, 1999, drawn: false)]),
          ),
        ],
      );
      expect(_cards(r), [_gump, _mile]);
    });

    test('an answer that names two titles keeps every card', () async {
      final before = _cards(await _ask([_findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      final r = await _ask([_findHanks, 'Dat is «$_mile» (1999) of anders «$_gump» (1994).'], one);
      expect(_cards(r), before);
    });
  });

  group('a children\'s profile', () {
    const kidsOne = 'Hoe heet die film met Tom Hanks over speelgoed?';

    test('the age gate decides first, then the one named title keeps its card', () async {
      final r = await _ask([_findHanks, 'Dat is «$_toy» (1995).'], kidsOne, ctx: _ctx(kids: true));
      expect(_cards(r), [_toy]);
      expect(r.ageFilterNotice, isFalse);
    });

    test('a turned-down title gets no card, also as the one named title', () async {
      final m = [_findHanks, 'Dat is «$_mile» (1999).', 'Toch «$_mile» (1999).'];
      final r = await _ask(m, one, ctx: _ctx(kids: true));
      expect(r.ageFilterNotice, isTrue);
      expect(r.text, isEmpty);
      expect(_cards(r), isNot(contains(_mile)));
      expect(_cards(r), isNot(contains(_gump)), reason: 'the gate still holds for the rest');
    });
  });

  test('which questions are after one title', () {
    for (final prompt in [
      one,
      'Ik zoek die film met Tom Hanks over deathrow',
      'de film van Tom Hanks over de dodencel',
      'Welke serie gaat over een scheikundeleraar?',
      'Die ene docu over octopussen',
      'What is that movie with Tom Hanks about death row?',
      'the show about a chemistry teacher',
      'Een film met Tom Hanks in een dodencel, hoe heet die?',
      'What was the name of that Tom Hanks prison thing?',
    ]) {
      expect(assistantAsksOneTitle(prompt), isTrue, reason: prompt);
    }
    for (final prompt in [
      'Films met Tom Hanks',
      'Welke films met Tom Hanks heb ik?',
      'Iets spannends voor vanavond',
      'Een film met Tom Hanks',
      'Welke series zijn nieuw?',
      'What series do I have?',
      'Movies like that film with Tom Hanks',
      'Iets zoals die film met Tom Hanks',
      'Geef me twee opties voor de film van vanavond',
      'Tips voor de serie van dit weekend',
      'Wat is er deze week toegevoegd?',
    ]) {
      expect(assistantAsksOneTitle(prompt), isFalse, reason: prompt);
    }
  });
}
