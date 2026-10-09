import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_recommend_constraints.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/recommendations/recommendation_service.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

import 'assistant_find_fakes.dart';

/// my_watching: "a tip for me" reads this profile's own log, not the
/// household's watch_stats (hardware feedback, 4 Oct 2026).
class _Server extends FakeServer {
  _Server(super.id, this.items);
  final Map<String, MediaItem> items;
  @override
  Future<MediaItem?> fetchItem(String id) async => items[id];
}

MediaItem _item(
  String id,
  String title,
  MediaKind kind, {
  int? year,
  String? series,
  List<String>? genres,
  int? viewCount,
}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: kind,
  title: title,
  year: year,
  grandparentTitle: series,
  genres: genres,
  viewCount: viewCount,
  serverId: 'nas',
);

AssistantTool _tool() => assistantTools.singleWhere((t) => t.name == 'my_watching');

AssistantToolContext _ctx({
  List<RecommendationSeed> seeds = const [],
  AffinityVector taste = AffinityVector.empty,
  List<MediaHub> hubs = const [],
  Map<String, MediaItem> items = const {},
  Set<String> everSeen = const {},
}) {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(
    _Server('nas', {
      'm1': _item('m1', 'Dune', MediaKind.movie, year: 2021),
      'e1': _item('e1', 'The Constant', MediaKind.episode, series: 'Lost'),
      ...items,
    }),
  );
  return AssistantToolContext(
    servers: m,
    personal: AssistantPersonalServices(
      userName: 'Michel',
      recent: () async => seeds,
      everSeen: () async => everSeen,
      taste: () async => taste,
      picks: (_) async => hubs,
    ),
  );
}

RecommendationSeed _seed(String key, {bool completed = true}) =>
    RecommendationSeed(globalKey: key, completed: completed, occurredAtMs: 0);

void main() {
  test('what this profile watched, liked and is offered, the picks as cards', () async {
    final pick = _item('p1', 'Arrival', MediaKind.movie, year: 2016);
    final ctx = _ctx(
      seeds: [_seed('nas:m1'), _seed('nas:e1', completed: false), _seed('elders:x1')],
      taste: const AffinityVector({
        'genre': {'science fiction': 1.0, 'drama': 0.6},
        'actor': {'amy adams': 0.8},
      }, eventCount: 3),
      hubs: [
        MediaHub(id: 'because.m1', title: 'Omdat je Dune keek', type: 'movie', items: [pick]),
      ],
    );

    final result = await _tool().run(ctx, null, const {}) as AssistantToolResult;

    expect(result.data['watched_recently'], [
      {'title': 'Dune', 'kind': 'movie', 'year': 2021, 'finished': true},
      // An episode counts as its series; a key on an unknown server is skipped.
      {'title': 'Lost', 'kind': 'show', 'finished': false},
    ]);
    expect(result.data['likes'], {
      'genres': ['science fiction', 'drama'],
      'actors': ['amy adams'],
      'directors': <String>[],
    });
    expect(result.data['picks'], [
      {
        'row': 'Omdat je Dune keek',
        'titles': [
          {'item_id': 'p1', 'server_id': 'nas', 'title': 'Arrival', 'year': 2016, 'kind': 'movie'},
        ],
      },
    ]);
    expect((result.display! as AssistantMediaGrid).entries.single.item.id, 'p1');
    expect(() => ctx.requireShownItem(ServerId('nas'), 'p1'), returnsNormally, reason: 'a pick can be opened');
  });

  test('no history: empty lists and no cards, so Big P can say so', () async {
    final result = await _tool().run(_ctx(), null, const {}) as AssistantToolResult;

    expect(result.data['watched_recently'], isEmpty);
    expect(result.data['picks'], isEmpty);
    expect(result.display, isNull);
  });

  test('without the profile services the tool is not offered', () {
    final m = MultiServerManager();
    addTearDown(m.dispose);
    expect(_tool().serves(AssistantToolContext(servers: m), ServerId('nas')), isFalse);
  });

  test('a shared account: only unseen films, no kids titles, in data and cards alike', () async {
    const crime = ['Crime'];
    const family = ['Animation', 'Family'];
    final watched = {
      'w1': _item('w1', 'MobLand', MediaKind.show, genres: crime),
      'w2': _item('w2', 'Reacher', MediaKind.show, genres: crime),
      'w3': _item('w3', 'The Gentlemen', MediaKind.movie, year: 2019, genres: crime),
      'w4': _item('w4', 'Ted Lasso', MediaKind.show, genres: ['Comedy']),
      'w5': _item('w5', 'Bluey', MediaKind.show, genres: ['Kids']),
      'w6': _item('w6', 'Puss in Boots', MediaKind.movie, year: 2022, genres: family),
    };
    final picks = [
      _item('p1', 'The Invite', MediaKind.movie, year: 2021, genres: crime, viewCount: 1),
      _item('p2', 'Code 3', MediaKind.movie, year: 2025, genres: crime),
      _item('p3', 'Den of Thieves', MediaKind.movie, year: 2018, genres: crime),
      // Another server's copy of a film in the history.
      _item('p4', 'The Gentlemen', MediaKind.movie, year: 2019, genres: crime),
      _item('p5', 'Bluey', MediaKind.show, genres: ['Kids']),
      _item('p6', 'Emily in Paris', MediaKind.show, genres: ['Comedy']),
      _item('p7', 'The Bear', MediaKind.show, genres: ['Drama']),
      _item('p8', 'Toy Story 5', MediaKind.movie, year: 2026, genres: family),
      _item('p9', 'Despicable Me 4', MediaKind.movie, year: 2024, genres: family),
    ];
    final ctx = _ctx(
      items: watched,
      seeds: [for (final id in watched.keys) _seed('nas:$id')],
      taste: const AffinityVector({
        'genre': {'crime': 1.0, 'family': 0.9, 'animation': 0.8, 'comedy': 0.5},
      }, eventCount: 6),
      hubs: [MediaHub(id: 'rows', title: 'Voor jou', type: 'movie', items: picks)],
    );
    ctx.recommend = const AssistantRecommendConstraints(excludeWatched: true);

    final result = await _tool().run(ctx, null, const {'kind': 'movie', 'exclude_kids': true}) as AssistantToolResult;

    final titles = [
      for (final row in result.data['picks']! as List)
        for (final t in (row as Map)['titles'] as List) (t as Map)['title'],
    ];
    expect(titles, ['Code 3', 'Den of Thieves']);
    expect([for (final e in (result.display! as AssistantMediaGrid).entries) e.item.title], titles);
    expect(
      [for (final w in result.data['watched_recently']! as List) (w as Map)['title']],
      ['MobLand', 'Reacher', 'The Gentlemen', 'Ted Lasso'],
    );
    expect((result.data['likes']! as Map)['genres'], ['crime', 'comedy']);
    expect(
      () => ctx.requireShownItem(ServerId('nas'), 'p5'),
      throwsA(anything),
      reason: 'a dropped pick cannot be opened',
    );
  });

  test(
    'seen is per title and per kind: a watched series keeps a film of that name, a watched clip drops its film',
    () async {
      const crime = ['Crime'];
      final watched = {
        'w1': _item('w1', 'Fargo', MediaKind.show, genres: crime),
        // Another server names the same film a clip.
        'w2': _item('w2', 'Heat', MediaKind.clip, year: 1995, genres: crime),
      };
      final picks = [
        _item('p1', 'Fargo', MediaKind.movie, year: 1996, genres: crime),
        _item('p2', 'Heat', MediaKind.movie, year: 1995, genres: crime),
      ];
      final ctx = _ctx(
        items: watched,
        seeds: [for (final id in watched.keys) _seed('nas:$id')],
        taste: const AffinityVector({
          'genre': {'crime': 1.0},
        }, eventCount: 2),
        hubs: [MediaHub(id: 'rows', title: 'Voor jou', type: 'movie', items: picks)],
      );
      ctx.recommend = const AssistantRecommendConstraints(excludeWatched: true);

      final result = await _tool().run(ctx, null, const {'kind': 'movie'}) as AssistantToolResult;

      expect(
        [
          for (final row in result.data['picks']! as List)
            for (final t in (row as Map)['titles'] as List) (t as Map)['title'],
        ],
        ['Fargo'],
      );
    },
  );

  test('the recent list names its window, so it is never taken for the whole history', () async {
    final result = await _tool().run(_ctx(), null, const {}) as AssistantToolResult;
    expect(result.data['watched_recently_window_days'], 30);
  });

  test('a title seen long ago is still seen: it leaves the picks although no recent seed names it', () async {
    final picks = [
      _item('p1', 'Arrival', MediaKind.movie, year: 2016),
      _item('p2', 'Sicario', MediaKind.movie, year: 2015),
    ];
    final ctx = _ctx(
      // Nothing recent: the watch of Arrival lies outside the seed window.
      everSeen: {'nas:p1'},
      hubs: [MediaHub(id: 'rows', title: 'Voor jou', type: 'movie', items: picks)],
    );
    ctx.recommend = const AssistantRecommendConstraints(excludeWatched: true);

    final result = await _tool().run(ctx, null, const {}) as AssistantToolResult;

    final titles = [
      for (final row in result.data['picks']! as List)
        for (final t in (row as Map)['titles'] as List) (t as Map)['title'],
    ];
    expect(titles, ['Sicario']);
  });

  test('without "nothing already seen" the long-ago watch does not filter', () async {
    final ctx = _ctx(
      everSeen: {'nas:p1'},
      hubs: [
        MediaHub(id: 'rows', title: 'Voor jou', type: 'movie', items: [_item('p1', 'Arrival', MediaKind.movie)]),
      ],
    );
    final result = await _tool().run(ctx, null, const {}) as AssistantToolResult;
    expect((result.data['picks']! as List), isNotEmpty);
  });
}
