import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_intent.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/memory/exclude_seen_store.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

import 'assistant_find_fakes.dart';
import 'assistant_memory_support.dart';
import '../services/memory/memory_test_support.dart';
import 'eval/big_p_eval_cases.dart';
import 'eval/big_p_eval_checks.dart';
import 'eval/big_p_eval_fixtures.dart';
import 'eval/big_p_eval_runner.dart';

// BP-11d: the standing "nothing I watched or started". Recognised by code,
// enforced in the title tools after the age gate, saved per profile only
// after a yes or a typed "onthoud dat".

const _standing =
    'ik wil niet dat je dingen aanraadt die ik in het verleden al gekeken heb of waar ik al aan begonnen ben';

Future<Map<String, Object?>> _tool(
  AssistantToolContext ctx,
  String name,
  Map<String, Object?> args, {
  String? server,
}) async =>
    ((await assistantTools.firstWhere((t) => t.name == name).run(ctx, server == null ? null : ServerId(server), args))
            as AssistantToolResult)
        .data;

List<String> _titles(Object? rows) => [for (final r in (rows as List).cast<Map>()) r['title'] as String];

AssistantToolContext _filtered({bool on = true, String prompt = ''}) =>
    evalContext(kids: false)..seenFilter = AssistantSeenFilter(on: on, prompt: prompt);

/// A profile whose log holds The Office from a server that is gone, and
/// whatever Seerr knows as The Bear.
AssistantPersonalServices _log() => AssistantPersonalServices(
  userName: 'M',
  recent: () async => const [],
  everSeen: () async => const {},
  everSeenIdentities: () async => [
    (key: 'oud:1', title: 'The Office', year: 2005, show: true, tokens: const <String>{}),
    (key: 'oud:2', title: 'The Bear', year: 2022, show: true, tokens: const <String>{}),
  ],
  taste: () async => const AffinityVector({}, eventCount: 0),
  picks: (_) async => const [],
);

Future<AssistantRunResult> _ask(
  AssistantToolContext ctx,
  String prompt,
  List<Object> script, {
  List<AssistantTurn> conversation = const [],
}) => AssistantRun(
  model: evalScriptedModel(script, EvalMeter()),
  context: ctx,
  confirm: (_) async => null,
  entitlement: const Entitled(),
  conversation: conversation,
  userTyped: true,
).ask(prompt);

const _bearScript = <Object>[
  EvalCall('find_title', {
    'candidates': [
      {'title': 'The Bear'},
      {'title': 'How I Met Your Mother'},
      {'title': 'The Office'},
    ],
    'variants': ['The Bear', 'The Office'],
  }),
  'Probeer «The Bear» (2022) of «The Office» (2005).',
];

void main() {
  test('recognition: standing wishes, one-question overrides and history questions', () {
    const standing = [
      _standing,
      'raad nooit iets aan wat ik al gezien heb',
      'stel geen titels meer voor die ik al gezien of begonnen heb',
      'Never suggest anything I\'ve already watched or started',
      'don\'t recommend stuff I already saw',
      'stop suggesting things I have seen',
    ];
    const include = [
      'laat ook dingen zien die ik al gezien heb',
      'mag ook iets zijn wat ik al gekeken heb',
      'include what I watched',
      'maakt niet uit of ik het al gezien heb',
    ];
    const none = [
      'wat heb ik al gezien?',
      'heb ik The Bear al gezien?',
      'ik heb nog niet alles gezien, geef een tip',
      'waarom raad je dingen aan die ik al gezien heb?',
      'I watched it too, show me more',
      'geef me iets voor vanavond',
    ];
    for (final p in standing) {
      expect(assistantSeenWish(p), AssistantSeenWish.standing, reason: p);
    }
    for (final p in include) {
      expect(assistantSeenWish(p), AssistantSeenWish.include, reason: p);
    }
    for (final p in none) {
      expect(assistantSeenWish(p), AssistantSeenWish.none, reason: p);
    }
  });

  group('enforcement in the title tools', () {
    test('search_catalog drops watched and started titles only with the filter on', () async {
      const args = {'kind': 'show', 'limit': 50};
      final off = _titles((await _tool(_filtered(on: false), 'search_catalog', args))['results']);
      expect(off, containsAll(['The Bear', 'How I Met Your Mother', 'Breaking Bad']));
      final on = await _tool(_filtered(), 'search_catalog', args);
      expect(_titles(on['results']), isNot(anyOf(contains('The Bear'), contains('How I Met Your Mother'))));
      expect(_titles(on['results']), contains('The Office'));
      expect(on['filtered_seen'], greaterThanOrEqualTo(4));
    });

    test('find_media drops a started film by the server\'s own watch state', () async {
      final ctx = _filtered();
      final data = await _tool(ctx, 'find_media', {'query': 'In'}, server: 'zolder');
      expect(_titles(data['items']), isNot(contains('Interstellar')));
      expect(ctx.seenFilter.dropped.map((d) => d.title), contains('Interstellar'));
    });

    test('a copy on another server counts as seen through the log\'s identity', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);
      m.debugRegisterClientForTesting(
        FakeServer(
          'nieuw',
          libraries: {
            'series': [fakeItem('o', 'The Office', kind: MediaKind.show, year: 2005)],
          },
        ),
      );
      m.setVisibleServerIds(null);
      AssistantToolContext ctx(bool on) =>
          AssistantToolContext(servers: m, personal: _log(), region: () => 'NL')
            ..seenFilter = AssistantSeenFilter(on: on);
      expect(_titles((await _tool(ctx(false), 'find_media', {'query': 'Office'}, server: 'nieuw'))['items']), [
        'The Office',
      ]);
      expect((await _tool(ctx(true), 'find_media', {'query': 'Office'}, server: 'nieuw'))['items'], isEmpty);
    });

    test('a Seerr row without a library copy matches the log on title, year and kind', () async {
      final seerr = FakeSeerr()
        ..search['The'] = [
          {'id': 1, 'mediaType': 'tv', 'name': 'The Bear', 'firstAirDate': '2022-06-23'},
          {'id': 2, 'mediaType': 'tv', 'name': 'The Wire', 'firstAirDate': '2002-06-02'},
        ];
      final m = MultiServerManager();
      addTearDown(m.dispose);
      final ctx = AssistantToolContext(
        servers: m,
        personal: _log(),
        requests: AssistantRequestServices(client: () => seerr.client),
        region: () => 'NL',
      )..seenFilter = AssistantSeenFilter(on: true);
      final data = await _tool(ctx, 'find_request_title', {
        'titles': [
          {'title': 'The'},
        ],
      });
      expect(_titles(data['titles']), ['The Wire']);
      expect(data['filtered_seen'], 1);
    });

    test('a title the user names in the question is a lookup and stays', () async {
      final data = await _tool(_filtered(prompt: 'waar staat The Bear?'), 'search_catalog', {
        'kind': 'show',
        'limit': 50,
      });
      expect(_titles(data['results']), contains('The Bear'));
    });
  });

  group('in a conversation', () {
    late MemoryProfile profile;
    setUp(() async {
      await resetMemoryPrefs();
      final db = memoryTestDatabase();
      addTearDown(db.close);
      profile = MemoryProfile(db, 'p');
    });

    test('the standing wish filters at once, the answer names no dropped title, the card saves it on yes', () async {
      final ctx = evalContext(kids: false, memory: profile.services);
      final first = await _ask(ctx, _standing, _bearScript);
      expect(evalCards(first).map((c) => c.title), ['The Office']);
      expect(first.text, isNot(contains('The Bear')));
      final card = first.memoryProposals.single;
      expect(card.excludeSeen, isTrue);
      expect(card.value, 'Nooit titels voorstellen die je al gezien of begonnen hebt');
      expect(await profile.service.excludeSeen, isFalse, reason: 'nothing is saved before the yes');

      expect((await applyMemoryProposal(card)).ok, isTrue);
      expect(await profile.service.excludeSeen, isTrue);

      // A new conversation: no history, the saved preference holds.
      final later = await _ask(
        evalContext(kids: false, memory: profile.services),
        'geef me iets voor vanavond',
        _bearScript,
      );
      expect(evalCards(later).map((c) => c.title), ['The Office']);

      // A one-question override lets them through, for that question only.
      final include = await _ask(
        evalContext(kids: false, memory: profile.services),
        'laat ook dingen zien die ik al gezien heb',
        _bearScript,
      );
      expect(evalCards(include).map((c) => c.title), contains('The Bear'));

      // Forgetting the fact turns it off.
      final fact = (await profile.service.list()).single;
      await profile.service.delete(fact.id);
      expect(await profile.service.excludeSeen, isFalse);
    });

    test('a follow-up in the same conversation keeps the wish without a saved preference', () async {
      final ctx = evalContext(kids: false);
      final next = await _ask(
        ctx,
        'en voor vanavond?',
        _bearScript,
        conversation: [const AssistantTurn(question: _standing, answer: 'Begrepen.')],
      );
      expect(evalCards(next).map((c) => c.title), ['The Office']);
      final fresh = await _ask(evalContext(kids: false), 'en voor vanavond?', _bearScript);
      expect(
        evalCards(fresh).map((c) => c.title),
        contains('The Bear'),
        reason: 'negative control: no wish, no filter',
      );
    });

    test('a typed "onthoud dat" saves the wish at once with Pleya\'s own sentence', () async {
      final ctx = evalContext(kids: false, memory: profile.services);
      final result = await _ask(ctx, 'onthoud dat je nooit iets aanraadt wat ik al gezien heb', ['Goed.']);
      expect(result.memoryProposals, isEmpty);
      expect(await profile.service.excludeSeen, isTrue);
      expect(ExcludeSeenStore.isSentence((await profile.service.list()).single.value), isTrue);
    });

    test('a children\'s profile keeps its own rules: no filter and no card', () async {
      profile.kids = true;
      final ctx = evalContext(kids: true, kidsAges: const [17], memory: profile.services);
      final result = await _ask(ctx, _standing, _bearScript);
      expect(ctx.seenFilter.on, isFalse);
      expect(result.memoryProposals, isEmpty);
    });
  });
}
