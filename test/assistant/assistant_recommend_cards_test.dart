import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart' show HealthStatus;
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/recommendations/recommendation_service.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

import 'assistant_find_fakes.dart';

class _Entitled extends AssistantEntitlement {
  const _Entitled();
  @override
  Future<AssistantEntitlementState> check() async => AssistantEntitlementState.entitled;
}

MediaItem _item(
  String id,
  String title,
  MediaKind kind, {
  List<String>? genres,
  String? rating,
  int? viewCount,
  int? year,
}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: kind,
  title: title,
  year: year,
  genres: genres,
  contentRating: rating,
  viewCount: viewCount,
  serverId: 'nas',
);

class _Server extends FakeServer {
  _Server(super.id, this.items);
  final Map<String, MediaItem> items;
  @override
  Future<MediaItem?> fetchItem(String id) async => items[id];
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
}

/// A run where the model calls my_watching, then answers [answer]. Returns the
/// run result and the titles the find_title fallback was asked for.
Future<(AssistantRunResult, List<String>)> _recommend(
  String prompt,
  String answer, {
  required List<MediaItem> picks,
  Map<String, MediaItem> watched = const {},
  int? maxSteps,
}) async {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(_Server('nas', watched));
  var turn = 0;
  final model = AssistantModelClient(
    AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan:11434', model: 'm'),
    httpClient: MockClient((request) async {
      final message = turn++ == 0
          ? {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c0',
                  'type': 'function',
                  'function': {'name': 'my_watching', 'arguments': '{}'},
                },
              ],
            }
          : {'role': 'assistant', 'content': answer};
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
  final asked = <String>[];
  final findTitle = AssistantTool(
    name: 'find_title',
    description: 'fake',
    risk: AssistantToolRisk.read,
    properties: const {},
    needsServer: false,
    serves: (_, _) => true,
    run: (ctx, _, args) async {
      asked.addAll([for (final c in args['candidates'] as List) (c as Map)['title'] as String]);
      return const AssistantToolResult({});
    },
  );
  final result = await AssistantRun(
    model: model,
    context: AssistantToolContext(
      servers: m,
      personal: AssistantPersonalServices(
        userName: 'Michel',
        recent: () async => [
          for (final id in watched.keys) RecommendationSeed(globalKey: 'nas:$id', completed: true, occurredAtMs: 0),
        ],
        everSeen: () async => const {},
        taste: () async => AffinityVector.empty,
        picks: (_) async => [MediaHub(id: 'r', title: 'Voor jou', type: 'movie', items: picks)],
      ),
    ),
    confirm: (_) async => null,
    entitlement: const _Entitled(),
    maxSteps: maxSteps ?? 8,
    tools: [...assistantTools.where((t) => t.name == 'my_watching'), findTitle],
  ).ask(prompt);
  return (result, asked);
}

List<String> _cards(AssistantRunResult r) => [
  for (final d in r.displays)
    if (d is AssistantMediaGrid) ...d.entries.map((e) => e.item.title ?? ''),
];

void main() {
  final picks = [
    _item('1', 'The Invite', MediaKind.movie, genres: ['Crime']),
    _item('2', 'The Order', MediaKind.movie, genres: ['Crime']),
    _item('3', 'Code 3', MediaKind.movie, genres: ['Crime']),
    _item('4', 'Den of Thieves', MediaKind.movie, genres: ['Crime']),
    _item('5', 'Bluey', MediaKind.show, genres: ['Drama']),
  ];

  test('one proposal: the card is the title the answer names, not the whole pick list', () async {
    final (r, _) = await _recommend('Zoek een film voor vanavond', 'Kijk «The Order» (2024).', picks: picks);
    expect(_cards(r), ['The Order']);
  });

  test('a few options: the three named cards, in the order of the answer', () async {
    final (r, _) = await _recommend(
      'Geef me een paar opties',
      'Probeer «Code 3», «The Invite» of «The Order».',
      picks: picks,
    );
    expect(_cards(r), ['Code 3', 'The Invite', 'The Order']);
  });

  test('an asked number caps the cards even when the answer names more', () async {
    final (r, _) = await _recommend(
      'Noem twee films die ik kan kijken',
      '«Code 3», «The Invite» en «The Order».',
      picks: picks,
    );
    expect(_cards(r), ['Code 3', 'The Invite']);
  });

  test('a film question gets films: a named series does not stay as a card', () async {
    final (r, _) = await _recommend('Een film voor vanavond graag', '«Bluey» of «Code 3»', picks: picks);
    expect(_cards(r), ['Code 3']);
  });

  test('a title named only as the reason gets no card', () async {
    final (r, asked) = await _recommend(
      'Doe een voorstel voor vanavond',
      'Omdat je «Reacher» keek: «The Order».',
      picks: picks,
      watched: {
        'w': _item('w', 'Reacher', MediaKind.show, genres: ['Drama']),
      },
    );
    expect(_cards(r), ['The Order']);
    expect(asked, isEmpty, reason: 'Reacher is history, not a pick');
  });

  test('a title named only as the reason is history for that year alone: Dune 2021 is not Dune 1984', () async {
    final (_, asked) = await _recommend(
      'Doe een voorstel voor vanavond',
      'Omdat je «Dune» (1984) keek: «Dune» (2021).',
      picks: picks,
      watched: {
        'w': _item('w', 'Dune', MediaKind.movie, genres: ['Drama'], year: 1984),
      },
    );
    expect(asked, ['Dune'], reason: 'the 2021 film is a pick; only the 1984 one is history');
  });

  test('an answer that names no pick shows no pick cards, whatever the question was', () async {
    final (r, _) = await _recommend('Wat zal ik kijken?', 'Zie hieronder.', picks: picks);
    expect(_cards(r), isEmpty);
  });

  test('a recommendation outside the picks still gets its card while another grid is on screen', () async {
    final (r, asked) = await _recommend('Geef me drie films voor vanavond', 'Kijk «Heat» (1995).', picks: picks);
    expect(_cards(r), isEmpty);
    expect(asked, ['Heat'], reason: 'find_title is asked for it, whatever else was shown');
  });

  test('a run that ends before the answer (step limit) ships no pick grid', () async {
    final (r, _) = await _recommend('Zoek een film voor vanavond', 'Kijk «The Order».', picks: picks, maxSteps: 1);
    expect(_cards(r), isEmpty);
  });
}
