import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_entitlement.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_recommend_constraints.dart';
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

void main() {
  group('fromPrompt', () {
    const shared =
        'Vergeet even de kinderfilms die gekeken zijn, want ik deel mijn account met mijn kinderen. '
        'Doe een voorstel op basis van de films die ik gekeken heb.';

    test('Dutch: films, kids dropped, a proposal', () {
      final c = AssistantRecommendConstraints.fromPrompt(shared);
      expect(c.kind, MediaKind.movie);
      expect(c.excludeKids, isTrue);
      expect(c.excludeWatched, isTrue);
    });

    test('English', () {
      final c = AssistantRecommendConstraints.fromPrompt(
        'Ignore the kids stuff, I share my account. Recommend a movie',
      );
      expect(c.excludeKids, isTrue);
      expect(c.excludeWatched, isTrue);
      expect(c.kind, MediaKind.movie);
    });

    test('negative control: a question about series is not films, a plain one is not constrained', () {
      expect(AssistantRecommendConstraints.fromPrompt('Een tip voor een serie of film?').kind, isNull);
      expect(AssistantRecommendConstraints.fromPrompt('Welke series zijn er?').kind, isNull);
      expect(AssistantRecommendConstraints.fromPrompt('Scan mijn bibliotheek').active, isFalse);
      // Kids named without dropping them is no constraint.
      expect(AssistantRecommendConstraints.fromPrompt('Welke kinderfilms heb ik?').excludeKids, isFalse);
    });
  });

  test('isKids: family genres and kids ratings, not grown-up animation', () {
    bool kids(List<String>? genres, [String? rating]) =>
        AssistantRecommendConstraints.isKids(_item('x', 'X', MediaKind.movie, genres: genres, rating: rating));
    expect(kids(['Animation', 'Family']), isTrue);
    expect(kids(['KIDS']), isTrue);
    expect(kids(null, 'TV-Y7'), isTrue);
    expect(kids(null, ' g '), isTrue);
    expect(kids(['Animation', 'Comedy'], 'TV-MA'), isFalse);
    expect(kids(null), isFalse);
  });

  test('admit: drops what does not fit, passes other displays and untouched grids', () {
    const c = AssistantRecommendConstraints(kind: MediaKind.movie, excludeKids: true, excludeWatched: true);
    final good = _item('1', 'Code 3', MediaKind.movie);
    final grid = AssistantMediaGrid([(item: good, group: null)]);
    expect(c.admit(grid), same(grid));

    final mixed = AssistantMediaGrid([
      (item: good, group: null),
      (item: _item('2', 'Bluey', MediaKind.show, genres: ['Kids']), group: null),
      (item: _item('3', 'The Invite', MediaKind.movie, viewCount: 1), group: null),
    ]);
    expect(((c.admit(mixed)!) as AssistantMediaGrid).entries.map((e) => e.item.title), ['Code 3']);
    expect(
      c.admit(AssistantMediaGrid([(item: _item('2', 'Bluey', MediaKind.show), group: null)])),
      isNull,
      reason: 'a show is not a film',
    );
    expect(const AssistantRecommendConstraints().admit(mixed), same(mixed));
  });

  test('a request-only match proves nothing about kids and goes when kids are excluded', () {
    final ctx = AssistantToolContext(servers: MultiServerManager());
    const match = AssistantTitleMatch(matchId: 'a', title: 'Bluey', kind: 'show', confidence: 'high', targets: []);
    expect(const AssistantRecommendConstraints(excludeKids: true).admit(AssistantTitleMatches(ctx, [match])), isNull);
    expect(const AssistantRecommendConstraints().admit(AssistantTitleMatches(ctx, [match])), isNotNull);
  });

  test('acceptance: my_watching without arguments still shows only unseen, non-kids films', () async {
    const crime = ['Crime'];
    final m = MultiServerManager();
    addTearDown(m.dispose);
    final watchedItems = {
      'w1': _item('w1', 'Bluey', MediaKind.show, genres: ['Kids']),
      'w2': _item('w2', 'The Gentlemen', MediaKind.movie, year: 2019, genres: crime),
    };
    m.debugRegisterClientForTesting(_Server('nas', watchedItems));
    final picks = [
      _item('p1', 'Bluey', MediaKind.show, genres: ['Kids']),
      for (final (i, t) in ['Emily in Paris', 'The Bear', 'Reacher', 'MobLand', 'Ted Lasso'].indexed)
        _item('s$i', t, MediaKind.show, genres: ['Drama']),
      _item('p2', 'Toy Story 5', MediaKind.movie, genres: ['Family'], rating: 'G'),
      _item('p3', 'Despicable Me 4', MediaKind.movie, genres: ['Animation', 'Family']),
      _item('p4', 'The Invite', MediaKind.movie, viewCount: 1, genres: crime),
      _item('p5', 'Code 3', MediaKind.movie, genres: crime),
    ];
    var turn = 0;
    final system = <String>[];
    final model = AssistantModelClient(
      AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o.lan:11434', model: 'm'),
      httpClient: MockClient((request) async {
        system.addAll([
          for (final msg in (jsonDecode(request.body)['messages'] as List))
            if ((msg as Map)['role'] == 'system') msg['content'] as String,
        ]);
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
            : {'role': 'assistant', 'content': 'Probeer «Code 3» (2025). «Bluey» laat ik weg.'};
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

    final result =
        await AssistantRun(
          model: model,
          context: AssistantToolContext(
            servers: m,
            personal: AssistantPersonalServices(
              userName: 'Michel',
              recent: () async => [
                const RecommendationSeed(globalKey: 'nas:w1', completed: true, occurredAtMs: 0),
                const RecommendationSeed(globalKey: 'nas:w2', completed: true, occurredAtMs: 0),
              ],
              taste: () async => AffinityVector.empty,
              picks: (_) async => [MediaHub(id: 'r', title: 'Voor jou', type: 'movie', items: picks)],
            ),
          ),
          confirm: (_) async => null,
          entitlement: const _Entitled(),
          tools: assistantTools.where((t) => t.name == 'my_watching').toList(),
        ).ask(
          'Vergeet even de kinderfilms die gekeken zijn, want ik deel mijn account met mijn kinderen. '
          'Doe een voorstel op basis van de films die ik gekeken heb.',
        );

    final cards = [
      for (final d in result.displays)
        if (d is AssistantMediaGrid) ...d.entries.map((e) => e.item),
    ];
    expect(cards.map((i) => i.title), ['Code 3']);
    expect(
      cards.every((i) => i.kind == MediaKind.movie && !AssistantRecommendConstraints.isKids(i) && !i.isWatched),
      isTrue,
    );
    expect(system.any((s) => s.contains('films only, no kids titles')), isTrue);
  });
}
