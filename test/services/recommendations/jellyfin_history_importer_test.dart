import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/recommendations/jellyfin_history_importer.dart';

const _profile = 'profile-a';
const _server = 'jf-1';
final _now = DateTime.now().millisecondsSinceEpoch;
int _secondsAgo(int days) => (_now - days * Duration.millisecondsPerDay) ~/ 1000;

class _FakeSource implements JellyfinHistorySource {
  List<MediaItem> played;
  List<MediaItem> resumable;
  final Map<String, MediaItem> items;
  int pageCalls = 0;
  _FakeSource({this.played = const [], this.resumable = const [], this.items = const {}});

  @override
  ServerId get serverId => ServerId(_server);

  @override
  Future<List<MediaItem>> fetchPlayedHistoryPage({required int startIndex, int limit = 200}) async {
    pageCalls++;
    return played.skip(startIndex).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> fetchResumableItems({int limit = 100}) async => resumable.take(limit).toList();

  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async => items[id];
}

MediaItem _movie(String id, {required int lastViewedDaysAgo, int? viewOffsetMs, int? durationMs, int viewCount = 1}) =>
    MediaItem.jellyfin(
      id: id,
      kind: MediaKind.movie,
      serverId: _server,
      title: id,
      genres: const ['Drama'],
      year: 2019,
      viewCount: viewCount,
      lastViewedAt: _secondsAgo(lastViewedDaysAgo),
      viewOffsetMs: viewOffsetMs,
      durationMs: durationMs,
    );

MediaItem _episode(String id, {required String showId, required int lastViewedDaysAgo}) => MediaItem.jellyfin(
  id: id,
  kind: MediaKind.episode,
  serverId: _server,
  title: id,
  grandparentId: showId,
  viewCount: 1,
  lastViewedAt: _secondsAgo(lastViewedDaysAgo),
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  JellyfinHistoryImporter importer(_FakeSource source, {int maxPagesFirstRun = 5}) => JellyfinHistoryImporter(
    database: db,
    profileId: _profile,
    source: source,
    isCurrentProfile: () => true,
    clock: () => _now,
    maxPagesFirstRun: maxPagesFirstRun,
  );

  test('played films become completed rows with a stable event id', () async {
    final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1), _movie('m2', lastViewedDaysAgo: 2)]);
    final outcome = await importer(source).sync();
    expect(outcome!.imported, 2);
    final rows = await db.getMediaInteractions(_profile);
    expect(rows.map((r) => r.source).toSet(), {'jellyfin'});
    expect(rows.map((r) => r.eventWeight).toSet(), {1.0});
    expect(rows.map((r) => r.sourceEventId), everyElement(startsWith('jellyfin:$_server:')));
    expect(rows.map((r) => r.sourceServerId).toSet(), {_server});
  });

  test('a second sync imports nothing new and stops at the watermark', () async {
    final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1)]);
    await importer(source).sync();
    source.pageCalls = 0;
    final outcome = await importer(source).sync();
    expect(outcome!.imported, 0);
    expect(source.pageCalls, 1, reason: 'the first page already reaches the watermark');
  });

  test('an episode rolls up to its series for features and the series key', () async {
    final show = MediaItem.jellyfin(
      id: 'show',
      kind: MediaKind.show,
      serverId: _server,
      title: 'Show',
      genres: const ['Sci-Fi'],
    );
    final source = _FakeSource(
      played: [_episode('e1', showId: 'show', lastViewedDaysAgo: 1)],
      items: {'show': show},
    );
    await importer(source).sync();
    final row = (await db.getMediaInteractions(_profile)).single;
    expect(row.seriesKey, '$_server:show');
    expect(row.genresJson, '["Sci-Fi"]');
  });

  test('a resumable item between 50 and 90 percent is one partial row, also after three syncs', () async {
    final source = _FakeSource(
      resumable: [_movie('r1', lastViewedDaysAgo: 0, viewCount: 0, viewOffsetMs: 60 * 60000, durationMs: 100 * 60000)],
    );
    await importer(source).sync();
    source.resumable = [
      _movie('r1', lastViewedDaysAgo: 0, viewCount: 0, viewOffsetMs: 70 * 60000, durationMs: 100 * 60000),
    ];
    await importer(source).sync();
    await importer(source).sync();
    final rows = await db.getMediaInteractions(_profile);
    expect(rows, hasLength(1));
    expect(rows.single.eventType, 'partial');
    expect(rows.single.eventWeight, 0.4);
  });

  test('a resumable item under 50 percent is ignored', () async {
    final source = _FakeSource(
      resumable: [_movie('r1', lastViewedDaysAgo: 0, viewCount: 0, viewOffsetMs: 10 * 60000, durationMs: 100 * 60000)],
    );
    await importer(source).sync();
    expect(await db.getMediaInteractions(_profile), isEmpty);
  });

  test('a local completed view an hour earlier suppresses the import of the same title', () async {
    await db.insertMediaInteraction(
      MediaInteractionsCompanion.insert(
        profileId: _profile,
        globalKey: '$_server:m1',
        mediaKind: 'movie',
        eventType: 'completed',
        eventWeight: 1.0,
        occurredAt: _now - Duration.millisecondsPerHour,
      ),
      profileId: _profile,
    );
    final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 0)]);
    final outcome = await importer(source).sync();
    expect(outcome!.deduplicated, 1);
    expect(outcome.imported, 0);
  });

  test('the first run reads at most maxPagesFirstRun pages', () async {
    final source = _FakeSource(played: [for (var i = 0; i < 700; i++) _movie('m$i', lastViewedDaysAgo: i % 300)]);
    await importer(source, maxPagesFirstRun: 2).sync();
    expect(source.pageCalls, 2);
  });

  test('a local view of the same episode suppresses the import, keyed on the episode', () async {
    final show = MediaItem.jellyfin(id: 'show', kind: MediaKind.show, serverId: _server, title: 'Show');
    await db.insertMediaInteraction(
      MediaInteractionsCompanion.insert(
        profileId: _profile,
        globalKey: '$_server:e1',
        mediaKind: 'episode',
        eventType: 'completed',
        eventWeight: 1.0,
        occurredAt: _now - Duration.millisecondsPerHour,
      ),
      profileId: _profile,
    );
    final source = _FakeSource(
      played: [
        _episode('e1', showId: 'show', lastViewedDaysAgo: 0),
        _episode('e2', showId: 'show', lastViewedDaysAgo: 0),
      ],
      items: {'show': show},
    );
    final outcome = await importer(source).sync();
    expect(outcome!.deduplicated, 1);
    expect(outcome.imported, 1, reason: 'another episode of the same show is its own view');
  });
}
