import 'package:flutter_test/flutter_test.dart';
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

MediaItem _item(String id, String title, MediaKind kind, {int? year, String? series}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: kind,
  title: title,
  year: year,
  grandparentTitle: series,
  serverId: 'nas',
);

AssistantTool _tool() => assistantTools.singleWhere((t) => t.name == 'my_watching');

AssistantToolContext _ctx({
  List<RecommendationSeed> seeds = const [],
  AffinityVector taste = AffinityVector.empty,
  List<MediaHub> hubs = const [],
}) {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  m.debugRegisterClientForTesting(
    _Server('nas', {
      'm1': _item('m1', 'Dune', MediaKind.movie, year: 2021),
      'e1': _item('e1', 'The Constant', MediaKind.episode, series: 'Lost'),
    }),
  );
  return AssistantToolContext(
    servers: m,
    personal: AssistantPersonalServices(
      userName: 'Michel',
      recent: () async => seeds,
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
}
