import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/profiles/profile_connection.dart';
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

  /// Runs between reading the pages and writing, to model a profile switch or
  /// a wipe landing mid-sync.
  void Function()? onResumable;
  _FakeSource({this.played = const [], this.resumable = const [], this.items = const {}});

  @override
  ServerId get serverId => ServerId(_server);

  @override
  Future<List<MediaItem>> fetchPlayedHistoryPage({required int startIndex, int limit = 200}) async {
    pageCalls++;
    return played.skip(startIndex).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> fetchResumableItems({int limit = 100}) async {
    onResumable?.call();
    return resumable.take(limit).toList();
  }

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
  late int nowMs;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    nowMs = _now;
  });
  // Past the sync interval, so the next sync is not throttled.
  void later() => nowMs += const Duration(minutes: 16).inMilliseconds;
  tearDown(() async => db.close());

  JellyfinHistoryImporter importer(_FakeSource source, {int maxPagesFirstRun = 5, bool Function()? isCurrentProfile}) =>
      JellyfinHistoryImporter(
        database: db,
        profileId: _profile,
        source: source,
        isCurrentProfile: isCurrentProfile ?? () => true,
        clock: () => nowMs,
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
    later();
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
    later();
    await importer(source).sync();
    later();
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

  group('play time, throttle, guards and resolution', () {
    MediaItem resumableAt(String id, int epochSeconds) => MediaItem.jellyfin(
      id: id,
      kind: MediaKind.movie,
      serverId: _server,
      title: id,
      viewCount: 0,
      lastViewedAt: epochSeconds,
      viewOffsetMs: 60 * 60000,
      durationMs: 100 * 60000,
    );

    test('a partial carries the play time, so a local partial eight hours ago dedups it', () async {
      final playedAt = _now - 8 * Duration.millisecondsPerHour;
      await db.insertMediaInteraction(
        MediaInteractionsCompanion.insert(
          profileId: _profile,
          globalKey: '$_server:r1',
          mediaKind: 'movie',
          eventType: 'partial',
          eventWeight: 0.4,
          occurredAt: playedAt,
        ),
        profileId: _profile,
      );
      final source = _FakeSource(resumable: [resumableAt('r1', playedAt ~/ 1000)]);
      final outcome = await importer(source).sync();
      expect(outcome!.deduplicated, 1);
      expect(await db.getMediaInteractions(_profile), hasLength(1), reason: 'one partial, not two');
    });

    test('a lastSyncAt in the future (clock set back) does not hold the sync', () async {
      final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1)]);
      await importer(source).sync();
      source.pageCalls = 0;
      nowMs -= const Duration(hours: 2).inMilliseconds;
      await importer(source).sync();
      expect(source.pageCalls, 1);
    });

    test('a second sync inside the interval makes no request at all', () async {
      final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1)]);
      await importer(source).sync();
      source.pageCalls = 0;
      nowMs += const Duration(minutes: 14).inMilliseconds;
      final outcome = await importer(source).sync();
      expect(outcome!.changedAnything, isFalse);
      expect(source.pageCalls, 0);
      later();
      await importer(source).sync();
      expect(source.pageCalls, 1, reason: 'the throttle is persisted in the cursor and lapses');
    });

    test('the watermark moves past a deduplicated play, so it is not handled again', () async {
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
      expect((await importer(source).sync())!.deduplicated, 1);
      later();
      final second = await importer(source).sync();
      expect(second!.fetched, 0);
      expect(second.deduplicated, 0);
    });

    test('a profile switch before the write stores no rows and no cursor', () async {
      var current = true;
      final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1)])..onResumable = () => current = false;
      expect(await importer(source, isCurrentProfile: () => current).sync(), isNull);
      expect(await db.getMediaInteractions(_profile), isEmpty);
      expect(await db.getHistorySyncCursor(_profile, _server, 'jellyfin'), isNull);
    });

    test('a wipe of the taste data mid-sync stores no rows and no cursor', () async {
      final source = _FakeSource(played: [_movie('m1', lastViewedDaysAgo: 1)])
        ..onResumable = () => db.deleteRecommendationDataForProfile(_profile);
      expect(await importer(source).sync(), isNull);
      expect(await db.getMediaInteractions(_profile), isEmpty);
      expect(await db.getHistorySyncCursor(_profile, _server, 'jellyfin'), isNull);
    });

    test('an episode whose series is gone is unresolvable, not a featureless row', () async {
      final source = _FakeSource(played: [_episode('e1', showId: 'gone', lastViewedDaysAgo: 1)]);
      final outcome = await importer(source).sync();
      expect(outcome!.unresolvable, 1);
      expect(await db.getMediaInteractions(_profile), isEmpty);
    });

    test('the same play on two pages counts once', () async {
      final movie = _movie('m1', lastViewedDaysAgo: 1);
      final source = _FakeSource(played: [for (var i = 0; i < 200; i++) movie, movie]);
      final outcome = await importer(source).sync();
      expect(outcome!.imported, 1);
    });
  });

  group('ownJellyfinHistoryImporters', () {
    ProfileConnection row(String profileId, String connectionId) =>
        ProfileConnection(profileId: profileId, connectionId: connectionId, userIdentifier: 'u');

    Future<List<JellyfinHistoryImporter>> build({
      required Map<String, List<String>> profilesByConnection,
      Set<String> online = const {'c1'},
      bool current = true,
      bool Function()? isCurrent,
      Future<void> Function()? whenBound,
    }) => ownJellyfinHistoryImporters(
      whenBound: whenBound,
      database: db,
      profileId: _profile,
      connectionsForProfile: (profileId) async => [
        for (final e in profilesByConnection.entries)
          if (e.value.contains(profileId)) row(profileId, e.key),
      ],
      profilesForConnection: (connectionId) async => [
        for (final p in profilesByConnection[connectionId] ?? const <String>[]) row(p, connectionId),
      ],
      onlineSource: (connectionId) => online.contains(connectionId) ? _FakeSource() : null,
      isCurrentProfile: isCurrent ?? () => current,
    );

    test('an own connection gets an importer', () async {
      expect(
        await build(
          profilesByConnection: {
            'c1': [_profile],
          },
        ),
        hasLength(1),
      );
    });

    test('a borrowed connection, shared with another profile, imports nothing', () async {
      expect(
        await build(
          profilesByConnection: {
            'c1': [_profile, 'profile-b'],
          },
        ),
        isEmpty,
      );
    });

    test('an offline connection or another profile\'s connection gets none', () async {
      expect(
        await build(
          profilesByConnection: {
            'c1': [_profile],
          },
          online: const {},
        ),
        isEmpty,
      );
      expect(
        await build(
          profilesByConnection: {
            'c1': ['profile-b'],
          },
        ),
        isEmpty,
      );
    });

    test('a build that starts during binding waits for it and then imports', () async {
      var binding = true;
      final settled = Completer<void>();
      final pending = build(
        profilesByConnection: {
          'c1': [_profile],
        },
        isCurrent: () => !binding,
        whenBound: () => settled.future,
      );
      binding = false;
      settled.complete();
      expect(await pending, hasLength(1));
    });

    test('nothing is built while the profile is not current or still binding', () async {
      expect(
        await build(
          profilesByConnection: {
            'c1': [_profile],
          },
          current: false,
        ),
        isEmpty,
      );
    });
  });
}
