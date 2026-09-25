import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover/seed_rows_loader.dart';
import 'package:pleya/services/recommendations/personalized_rows_builder.dart';
import 'package:pleya/services/recommendations/recommendation_service.dart';

class _Client implements MediaServerClient {
  _Client(this.id);

  final String id;
  Map<String, MediaItem> itemsById = {};
  List<MediaItem> recentlyWatched = const [];
  int recentlyWatchedCalls = 0;

  @override
  ServerId get serverId => ServerId(id);

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async => itemsById[id];

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async {
    recentlyWatchedCalls++;
    return recentlyWatched.take(limit).toList();
  }

  /// Every seed gets one unwatched related title, so each seed is one row.
  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => [
    MediaHub(
      id: 'rel-$id',
      title: 'rel',
      type: 'movie',
      items: [_movie('$id-related', server: this.id)],
      size: 1,
      serverId: this.id,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {String server = 'plex', int viewCount = 0, MediaKind kind = MediaKind.movie}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: kind,
  title: id,
  serverId: server,
  serverName: 'Server',
  viewCount: viewCount,
);

void main() {
  late AppDatabase db;
  final now = DateTime.now().millisecondsSinceEpoch;
  const day = Duration.millisecondsPerDay;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  RecommendationService service({Future<Set<String>> Function()? shared}) => RecommendationService(
    profileId: 'p1',
    database: db,
    titles: PersonalizedRowTitles(
      topPicks: 'Top Picks',
      becauseYouLike: (g) => 'Because you like $g',
      hiddenGems: 'Hidden Gems',
      moreWithActor: (n) => 'More with $n',
      moreFromDirector: (n) => 'More from $n',
    ),
    sharedHistoryServerIds: shared,
  );

  Future<void> play(String globalKey, {double weight = 1.0, required int at}) => db.insertMediaInteraction(
    MediaInteractionsCompanion.insert(
      profileId: 'p1',
      globalKey: globalKey,
      mediaKind: 'movie',
      eventType: weight >= 1.0 ? 'completed' : (weight < 0 ? 'skipped' : 'partial'),
      eventWeight: weight,
      occurredAt: at,
      seriesKey: const Value(null),
    ),
    profileId: 'p1',
  );

  Future<List<String?>> rowTitles(RecommendationService svc, List<_Client> clients) async {
    final byId = {for (final c in clients) c.serverId: c};
    final loaded = await SeedRowsLoader(
      recommendations: svc,
      clientFor: (id) => byId[id],
    ).load(clients: clients, alreadyShown: const {});
    return [for (final row in loaded.rows) row.title];
  }

  test('six seeds on a source that cannot seed do not starve the Plex seeds', () async {
    final plex = _Client('plex')
      ..itemsById = {
        for (final id in ['a', 'b', 'c']) id: _movie(id),
      };
    for (var i = 0; i < 6; i++) {
      await play('pleya:$i', at: now - i * 1000);
    }
    for (final (i, id) in ['a', 'b', 'c'].indexed) {
      await play('plex:$id', at: now - day - i * 1000);
    }

    expect(await rowTitles(service(), [plex]), [
      for (final id in ['a', 'b', 'c']) t.discover.becauseYouWatched(title: id),
    ]);
  });

  test('a partial that was then taken out of Continue Watching does not headline a row', () async {
    final plex = _Client('plex')..itemsById = {'film': _movie('film')};
    await play('plex:film', weight: 0.4, at: now - 2 * day);
    await play('plex:film', weight: -0.3, at: now - day);

    final titles = await rowTitles(service(), [plex]);

    expect(titles, isNot(contains(t.discover.becauseYouAreWatching(title: 'film'))));
    expect(titles, isEmpty);
  });

  test('a film whose newest row is a partial but that is watched elsewhere reads "watched"', () async {
    final plex = _Client('plex')..itemsById = {'film': _movie('film', viewCount: 1)};
    await play('plex:film', weight: 0.4, at: now - day);

    expect(await rowTitles(service(), [plex]), [t.discover.becauseYouWatched(title: 'film')]);
  });

  group('top-up from the servers', () {
    test('one log seed is topped up to three from the server list, without repeating the title', () async {
      final plex = _Client('plex')
        ..itemsById = {'log': _movie('log')}
        ..recentlyWatched = [
          _movie('log', viewCount: 1),
          _movie('s1', viewCount: 1),
          _movie('s2', viewCount: 1),
          _movie('s3', viewCount: 1),
        ];
      await play('plex:log', at: now - day);

      expect(await rowTitles(service(), [plex]), [
        for (final id in ['log', 's1', 's2']) t.discover.becauseYouWatched(title: id),
      ]);
    });

    test('three log seeds need no server call', () async {
      final plex = _Client('plex')
        ..itemsById = {
          for (final id in ['a', 'b', 'c']) id: _movie(id),
        };
      for (final (i, id) in ['a', 'b', 'c'].indexed) {
        await play('plex:$id', at: now - i * 1000);
      }

      await rowTitles(service(), [plex]);

      expect(plex.recentlyWatchedCalls, 0);
    });

    test('a Jellyfin connection shared with another profile never feeds the server path', () async {
      final plex = _Client('plex')..recentlyWatched = [_movie('mine', viewCount: 1)];
      final jf = _Client('jf')..recentlyWatched = [_movie('lenders', server: 'jf', viewCount: 1)];

      final titles = await rowTitles(service(shared: () async => {'jf'}), [plex, jf]);

      expect(titles, [t.discover.becauseYouWatched(title: 'mine')]);
      expect(jf.recentlyWatchedCalls, 0);
    });

    test('an own Jellyfin connection does feed the server path', () async {
      final jf = _Client('jf')..recentlyWatched = [_movie('own', server: 'jf', viewCount: 1)];

      expect(await rowTitles(service(shared: () async => const {}), [jf]), [
        t.discover.becauseYouWatched(title: 'own'),
      ]);
    });

    test('when the sharing check fails, the server path is left out entirely', () async {
      final plex = _Client('plex')..recentlyWatched = [_movie('mine', viewCount: 1)];

      final titles = await rowTitles(service(shared: () async => throw StateError('registry down')), [plex]);

      expect(titles, isEmpty);
      expect(plex.recentlyWatchedCalls, 0);
    });
  });
}
