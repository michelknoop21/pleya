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
  List<String> calls = const ['my_watching'],
  List<AssistantTool> extraTools = const [],
  String languageName = 'Dutch',
}) async {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(_Server('nas', watched));
  var turn = 0;
  final model = AssistantModelClient(
    AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan:11434', model: 'm'),
    httpClient: MockClient((request) async {
      final at = turn++;
      final message = at < calls.length
          ? {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c$at',
                  'type': 'function',
                  'function': {'name': calls[at], 'arguments': '{}'},
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
    tools: [...assistantTools.where((t) => t.name == 'my_watching'), findTitle, ...extraTools],
    languageName: languageName,
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

  test('a year written inside the marks counts too: «Dune (2021)» is not the watched Dune 1984', () async {
    final (_, asked) = await _recommend(
      'Doe een voorstel voor vanavond',
      'Omdat je «Dune» (1984) keek: «Dune (2021)».',
      picks: picks,
      watched: {
        'w': _item('w', 'Dune', MediaKind.movie, genres: ['Drama'], year: 1984),
      },
    );
    expect(asked, ['Dune']);
  });

  test('a watched series does not hide a film of the same name: Fargo the series, Fargo (1996) the pick', () async {
    final (r, asked) = await _recommend(
      'Doe een voorstel voor vanavond',
      'Omdat je «Fargo» keek: «Fargo» (1996).',
      picks: [
        ...picks,
        _item('f', 'Fargo', MediaKind.movie, genres: ['Crime'], year: 1996),
      ],
      watched: {
        'w': _item('w', 'Fargo', MediaKind.show, genres: ['Crime']),
      },
    );
    expect(_cards(r), ['Fargo'], reason: 'the film is a pick; the series is the reason');
    expect(asked, isEmpty);
  });

  test('a watched title named with its year as the reason stays the reason, also when it sits in the picks', () async {
    final (r, _) = await _recommend(
      'Zoek een film voor vanavond',
      'Omdat je «Dune» (2021) keek: «The Order».',
      picks: [
        ...picks,
        _item('d', 'Dune', MediaKind.movie, genres: ['Crime'], year: 2021),
      ],
      watched: {
        'w': _item('w', 'Dune', MediaKind.movie, genres: ['Crime'], year: 2021),
      },
    );
    expect(_cards(r), ['The Order']);
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

  // Text and cards are one set (BP-10, decided by Michel on 16 Oct 2026): every
  // title a personal answer recommends has a card, within the asked number, and
  // a title without one is not left standing in the text. Only words go; the
  // cards stay what Pleya validated.
  group('the answer names exactly the cards', () {
    final neutral = anyOf(
      'Dit zijn de titels die ik kon controleren.',
      'These are the titles I could check.',
      'Ik kon hier geen titel voor controleren.',
      'I could not check a title for this.',
    );

    test('one film asked, two named: one card and one title in the text', () async {
      final (r, _) = await _recommend(
        'Zoek een film voor vanavond',
        'Ik raad «The Order» (2024) aan: spannend. Wil je iets anders, dan «Code 3» (2024).',
        picks: picks,
      );
      expect(_cards(r), ['The Order']);
      expect(r.text, contains('The Order'));
      expect(r.text, isNot(contains('Code 3')));
    });

    test('three asked, three named: all three stay, text untouched', () async {
      const answer = '«The Invite» (2024), «The Order» (2024) en «Code 3» (2024).';
      final (r, _) = await _recommend('Geef me drie films voor vanavond', answer, picks: picks);
      expect(_cards(r), ['The Invite', 'The Order', 'Code 3']);
      expect(r.text, answer);
    });

    test('a title past the asked number, with no validated card, is not left in the text', () async {
      final (r, asked) = await _recommend(
        'Zoek een film voor vanavond',
        'Kijk «The Order» (2024). Of «Heat» (1995), een klassieker.',
        picks: picks,
      );
      expect(asked, isEmpty, reason: 'past the asked number: not even looked up');
      expect(_cards(r), ['The Order']);
      expect(r.text, isNot(contains('Heat')));
    });

    test('the same title twice is one title: text untouched, one card', () async {
      const answer = 'Kijk «The Order» (2024). «The Order» is spannend.';
      final (r, _) = await _recommend('Zoek een film voor vanavond', answer, picks: picks);
      expect(_cards(r), ['The Order']);
      expect(r.text, answer);
    });

    test('an asked alternative is shown too: two cards, both in the text', () async {
      const answer = 'Eerst «The Order» (2024), en als alternatief «Code 3» (2024).';
      final (r, _) = await _recommend('Een film voor vanavond en een alternatief', answer, picks: picks);
      expect(_cards(r), ['The Order', 'Code 3']);
      expect(r.text, answer);
    });

    test('nothing validated is named: Pleya\'s short line, never a title without a card', () async {
      final (r, _) = await _recommend('Zoek een film voor vanavond', '«Heat» (1995) of «Dune» (2021).', picks: picks);
      expect(_cards(r), isEmpty);
      expect(r.text, neutral);
    });

    test('negative control: a title named as the reason stays in the text', () async {
      final (r, asked) = await _recommend(
        'Doe een voorstel voor vanavond',
        'Omdat je «Reacher» (2022) keek, raad ik «The Order» (2024) aan.',
        picks: picks,
        watched: {
          'w': _item('w', 'Reacher', MediaKind.show, genres: ['Crime'], year: 2022),
        },
      );
      expect(asked, isEmpty);
      expect(_cards(r), ['The Order']);
      expect(r.text, contains('Reacher'));
    });

    test('after an action the confirmation is the answer: nothing is cut', () async {
      final request = AssistantTool(
        name: 'request_title',
        description: 'fake',
        risk: AssistantToolRisk.read,
        properties: const {},
        needsServer: false,
        serves: (_, _) => true,
        run: (_, _, _) async => const AssistantToolResult({
          'status': 'requested',
        }, record: AssistantActionRecord(kind: AssistantActionKind.requestTitle, serverName: '', subject: 'Heat')),
      );
      const answer = 'Ik heb «Heat» (1995) aangevraagd.';
      final (r, _) = await _recommend(
        'Vraag Heat aan',
        answer,
        picks: picks,
        calls: const ['my_watching', 'request_title'],
        extraTools: [request],
      );
      expect(r.text, answer);
    });

    test('a list keeps its lines: the item without a card goes, the others and their intro stay', () async {
      final (r, _) = await _recommend(
        'Geef me twee films voor vanavond',
        'Mijn tips:\n1. «The Order» (2024)\n2. «Heat» (1995)\n3. «Code 3» (2024)',
        picks: picks,
      );
      expect(_cards(r), ['The Order', 'Code 3']);
      expect(r.text, 'Mijn tips:\n1. «The Order» (2024)\n3. «Code 3» (2024)');
    });

    test('a marked title with a dot is not cut in two', () async {
      final (r, _) = await _recommend(
        'Zoek een film voor vanavond',
        'Kijk «The Order» (2024). Of «Mr. Robot» (2015) als je iets anders wilt.',
        picks: picks,
      );
      expect(r.text, 'Kijk «The Order» (2024).');
    });

    test('a short common word is only a title when it is marked: "her" in prose stays', () async {
      final (r, _) = await _recommend(
        'Zoek een film voor vanavond',
        'Kijk «The Order» (2024), perfect voor her en der. Of «Her» (2013).',
        picks: picks,
      );
      expect(r.text, 'Kijk «The Order» (2024), perfect voor her en der.');
    });

    test('the short line speaks the run\'s language', () async {
      final (r, _) = await _recommend(
        'Find a movie for tonight',
        '«Heat» (1995) or «Dune» (2021).',
        picks: picks,
        languageName: 'English',
      );
      expect(r.text, 'I could not check a title for this.');
    });

    test('a subtitle title is matched whole', () async {
      final (r, _) = await _recommend(
        'Zoek een film voor vanavond',
        'Kijk «The Order» (2024). Of «Puss in Boots: The Last Wish» (2022), een leuke.',
        picks: picks,
      );
      expect(r.text, 'Kijk «The Order» (2024).');
    });

    test('a number or a letter at the end of a sentence is an ordinary end', () async {
      final (r, _) = await _recommend(
        'Zoek een film voor vanavond',
        'Ik raad «The Order» (2024) aan, uit plan A. Ook «Heat» (1995) is goed.',
        picks: picks,
      );
      expect(r.text, 'Ik raad «The Order» (2024) aan, uit plan A.');
    });

    test('paragraph breaks survive a cut', () async {
      final (r, _) = await _recommend(
        'Zoek een film voor vanavond',
        'Kijk «The Order» (2024).\n\nOf «Heat» (1995).\n\nVeel plezier.',
        picks: picks,
      );
      expect(r.text, 'Kijk «The Order» (2024).\n\nVeel plezier.');
    });
  });
}
