import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
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

const mile = 'The Green Mile';
const gump = 'Forrest Gump';
const toy = 'Toy Story';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

class _Facts extends TitleFactsService {
  _Facts() : super(cache: TitleFactsCache());
  static const byTitle = {
    mile: TitleFacts(certifications: {'NL': '16', 'US': 'R'}, genres: ['Drama']),
    gump: TitleFacts(certifications: {'NL': '12', 'US': 'PG-13'}, genres: ['Drama']),
    'Cast Away': TitleFacts(certifications: {'NL': '12', 'US': 'PG-13'}, genres: ['Drama']),
    toy: TitleFacts(certifications: {'NL': 'AL', 'US': 'G'}, genres: ['Animation']),
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
AssistantToolContext singleCtx({bool kids = false}) {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(
    _Server(
      'w',
      libraries: {
        'films': [
          _hanks('gm', mile, 1999, 'Guards on death row meet an inmate with a gift.'),
          _hanks('fg', gump, 1994, 'A man from Alabama witnesses history.'),
          _hanks('ca', 'Cast Away', 2000, 'A courier strands on an island.'),
          _hanks('ts', toy, 1995, 'A cowboy doll and a space ranger.'),
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

Future<AssistantRunResult> singleAsk(
  List<Object> script,
  String prompt, {
  AssistantToolContext? ctx,
  List<AssistantTool>? tools,
}) => AssistantRun(
  model: _script(script).model,
  context: ctx ?? singleCtx(),
  confirm: (_) async => null,
  entitlement: const _Entitled(),
  tools: tools,
).ask(prompt);

/// The model's search for an actor: no candidate title, the actor as phrase.
const findHanks = {
  'name': 'find_title',
  'args': {
    'kind': 'movie',
    'variants': ['Tom Hanks', 'Tom Hanks film'],
  },
};

List<String> cardsOf(AssistantRunResult r) => [
  for (final d in r.displays)
    ...switch (d) {
      AssistantTitleMatches(:final matches) => [for (final m in matches) m.title],
      AssistantMediaGrid(:final entries) => [for (final e in entries) e.item.title ?? ''],
      _ => const <String>[],
    },
];

AssistantTitleMatch titleMatch(String title, int year, {bool drawn = true}) => AssistantTitleMatch(
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

AssistantTool displayTool(String name, AssistantDisplay? Function(AssistantToolContext) display) => AssistantTool(
  name: name,
  description: name,
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (ctx, _, _) async => AssistantToolResult(const {'ok': true}, display: display(ctx)),
);

MediaItem movieItem(String title, int year) => MediaItem(
  id: title,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: title,
  year: year,
  serverId: 'w',
);
