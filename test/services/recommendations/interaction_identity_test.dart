import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/recommendations/interaction_identity.dart';
import 'package:pleya/services/recommendations/interaction_recorder.dart';
import 'package:pleya/services/recommendations/personalized_rows_builder.dart' show PersonalizedRowTitles;
import 'package:pleya/services/recommendations/recommendation_service.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

MediaItem _movie(String id, {String? title, int? year, String? guid, Map<String, Object?>? raw}) => MediaItem(
  id: id,
  backend: raw == null ? MediaBackend.plex : MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: title ?? 'Dune',
  year: year,
  guid: guid,
  raw: raw,
);

MediaItem _show(String id, {String? title, int? year, String? guid}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.show,
  title: title ?? 'Severance',
  year: year,
  guid: guid,
);

MediaItem _episode(String id, {String? series, String? seriesGuid, int? year}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Pilot',
  year: year,
  guid: 'plex://episode/own',
  grandparentTitle: series,
  grandparentGuid: seriesGuid,
);

class _Client implements MediaServerClient {
  _Client(this.items, {this.ids = const {}, this.failing = const {}});

  final Map<String, MediaItem?> items;
  final Map<String, ExternalIds> ids;
  final Set<String> failing;
  final calls = <String>[];

  @override
  ServerId get serverId => ServerId('s1');
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;
  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async {
    calls.add('item:$id');
    if (failing.contains(id)) throw StateError('server error');
    return items[id];
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    calls.add('ids:$itemId');
    return ids[itemId] ?? const ExternalIds();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PleyaLike extends _Client {
  _PleyaLike(super.items);
  @override
  MediaBackend get backend => MediaBackend.pleyaServer;
}

class _JellyLike extends _Client {
  _JellyLike(super.items);
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
}

class _DeletingClient extends _Client {
  _DeletingClient(this.db, this.profile, MediaItem item) : super({item.id: item});
  final AppDatabase db;
  final String profile;

  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async {
    await db.deleteRecommendationDataForProfile(profile);
    return super.fetchItem(id, useCache: useCache);
  }
}

MediaInteractionsCompanion _row(
  String key, {
  String profile = 'p1',
  String? seriesKey,
  String kind = 'movie',
  int? year,
  int at = 1000,
  String? title,
  String? identityJson,
  int? tried,
  String? eventId,
  double weight = 1.0,
}) => MediaInteractionsCompanion.insert(
  profileId: profile,
  globalKey: key,
  mediaKind: kind,
  eventType: 'completed',
  eventWeight: weight,
  occurredAt: DateTime.now().millisecondsSinceEpoch - at,
  seriesKey: Value(seriesKey),
  year: Value(year),
  title: Value(title),
  identityJson: Value(identityJson),
  identityTriedAt: Value(tried),
  sourceEventId: Value(eventId),
);

void main() {
  group('interactionIdentityOf', () {
    test('a movie carries its catalogue guid and the ids it was given, at movie scope', () {
      final identity = interactionIdentityOf(
        _movie('1', guid: 'plex://movie/abc'),
        ids: const ExternalIds(imdb: 'tt1160419', tmdb: 438631),
      );
      expect(identity.title, 'Dune');
      expect(identity.tokens, {'movie:guid:plex://movie/abc', 'movie:imdb:tt1160419', 'movie:tmdb:438631'});
      expect(identity.tokensJson, contains('movie:tmdb:438631'));
    });

    test('a Jellyfin item gives its inline ProviderIds without a request', () {
      final identity = interactionIdentityOf(
        _movie(
          '1',
          raw: {
            'ProviderIds': {'Tmdb': '438631', 'Imdb': 'tt1160419'},
          },
        ),
      );
      expect(identity.tokens, {'movie:tmdb:438631', 'movie:imdb:tt1160419'});
    });

    test('an episode holds only its series guid and title, never an episode id', () {
      final identity = interactionIdentityOf(
        _episode('e1', series: 'Severance', seriesGuid: 'plex://show/sev', year: 2022),
        // Whatever a caller hands in is the episode's, and is not used.
        ids: const ExternalIds(tmdb: 999, tvdb: 888),
      );
      expect(identity.title, 'Severance');
      expect(identity.tokens, {'show:guid:plex://show/sev'});
    });

    test('an unusable guid and an unknown kind give nothing', () {
      expect(interactionIdentityOf(_movie('1', guid: 'local://1')).tokens, isEmpty);
      expect(interactionIdentityOf(_movie('1', guid: 'tv.plex.agents.none://x')).tokens, isEmpty);
      expect(interactionIdentityOf(_episode('e1')).title, isNull);
      expect(InteractionIdentity.none.tokensJson, isNull);
    });

    test('shared token proves, a different external id of the same scheme conflicts, a guid does not', () {
      expect(interactionIdentityProves({'movie:tmdb:1', 'movie:guid:a'}, {'movie:guid:a'}), isTrue);
      expect(interactionIdentityProves({'movie:tmdb:1'}, {'show:tmdb:1'}), isFalse, reason: 'scope is part of it');
      expect(interactionIdentityConflicts({'movie:tmdb:1'}, {'movie:tmdb:2'}), isTrue);
      expect(interactionIdentityConflicts({'movie:tmdb:1'}, {'show:tmdb:2'}), isFalse);
      expect(interactionIdentityConflicts({'movie:guid:a'}, {'movie:guid:b'}), isFalse);
    });
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> add(MediaInteractionsCompanion row) => db.insertMediaInteraction(row, profileId: 'p1');

    test('v21 migration keeps every row, re-runs as a no-op and keeps the import index', () async {
      await db.close();
      final dir = await Directory.systemTemp.createTemp('pleya_db_v21_migration_test_');
      final file = File('${dir.path}/pleya_downloads.db');
      AppDatabase? seeded;
      AppDatabase? reopened;
      try {
        seeded = AppDatabase.forTesting(NativeDatabase(file));
        await seeded.insertMediaInteraction(_row('s1:a', eventId: 'tautulli:m:1'), profileId: 'p1');
        await seeded.insertMediaInteraction(_row('s1:b', at: 2000), profileId: 'p1');
        // Looks like a v20 file, and one with an interrupted v21 run (one column back).
        for (final c in ['title', 'identity_json', 'identity_tried_at']) {
          await seeded.customStatement('ALTER TABLE media_interactions DROP COLUMN $c');
        }
        await seeded.customStatement('ALTER TABLE media_interactions ADD COLUMN title TEXT NULL');
        await seeded.customStatement('PRAGMA user_version = 20');
        await seeded.close();
        seeded = null;

        reopened = AppDatabase.forTesting(NativeDatabase(file));
        final rows = await reopened.getMediaInteractions('p1');
        expect(rows.map((r) => r.globalKey), containsAll(['s1:a', 's1:b']));
        expect(rows, hasLength(2));
        expect(rows.every((r) => r.title == null && r.identityJson == null && r.identityTriedAt == null), isTrue);
        final columns = (await reopened.customSelect('PRAGMA table_info(media_interactions)').get()).map(
          (c) => c.read<String>('name'),
        );
        expect(columns, containsAll(['title', 'identity_json', 'identity_tried_at']));
        // The partial unique index still refuses a second import of one event.
        await reopened.insertImportedInteractions([_row('s1:a', eventId: 'tautulli:m:1')], profileId: 'p1');
        expect(await reopened.getMediaInteractions('p1'), hasLength(2));
      } finally {
        await reopened?.close();
        await seeded?.close();
        await dir.delete(recursive: true);
        db = AppDatabase.forTesting(NativeDatabase.memory());
      }
    });

    test(
      'everWatchedIdentities: one title per key, the recorder\'s episode year is dropped, scoped to the profile',
      () async {
        await add(_row('s1:m1', title: 'Dune', year: 2021, identityJson: '["movie:tmdb:438631"]'));
        // The recorder keys an episode row on the episode and holds the series key apart.
        await add(_row('s1:e1', kind: 'episode', seriesKey: 's1:show', year: 2019, title: 'Severance', at: 500));
        await add(_row('s1:e2', kind: 'episode', seriesKey: 's1:show', year: 2019, title: 'Severance', at: 600));
        // An import keys on the series itself and holds the series' year.
        await add(_row('s2:show2', kind: 'episode', seriesKey: 's2:show2', year: 2008, title: 'Breaking Bad'));
        await add(_row('s1:blank'));
        await add(_row('s1:other', profile: 'p2', title: 'Secret'));
        final seen = await db.everWatchedIdentities('p1', minWeight: 0.4);
        final byKey = {for (final w in seen) w.key: w};
        expect(byKey.keys, {'s1:m1', 's1:show', 's2:show2'});
        expect(byKey['s1:m1']!.tokens, {'movie:tmdb:438631'});
        expect(byKey['s1:m1']!.year, 2021);
        expect(byKey['s1:show']!.year, isNull);
        expect(byKey['s1:show']!.show, isTrue);
        expect(byKey['s2:show2']!.year, 2008);
      },
    );

    test('writeIdentity fills nulls only, for every row of the title, for this profile only', () async {
      await add(_row('s1:e1', kind: 'episode', seriesKey: 's1:show'));
      await add(_row('s1:e2', kind: 'episode', seriesKey: 's1:show', at: 10));
      await add(_row('s1:m1', title: 'Kept', identityJson: '["movie:tmdb:1"]'));
      await db.insertMediaInteraction(
        _row('s1:e1', profile: 'p2', kind: 'episode', seriesKey: 's1:show'),
        profileId: 'p2',
      );
      await db.writeIdentity('p1', 's1:show', title: 'Severance', tokens: {'show:tvdb:371980'}, triedAt: 5);
      await db.writeIdentity('p1', 's1:m1', title: 'Overwritten', tokens: {'movie:tmdb:2'}, triedAt: 5);
      final p1 = {for (final r in await db.getMediaInteractions('p1')) r.globalKey: r};
      expect(p1['s1:e1']!.title, 'Severance');
      expect(p1['s1:e2']!.identityJson, '["show:tvdb:371980"]');
      expect(p1['s1:m1']!.title, 'Kept');
      expect(p1['s1:m1']!.identityJson, '["movie:tmdb:1","movie:tmdb:2"]', reason: 'tokens are added, none replaced');
      expect((await db.getMediaInteractions('p2')).single.title, isNull);
      expect(await db.getMediaInteractions('p1'), hasLength(3), reason: 'no row is added');
    });

    test(
      'identityGaps: untried first, then newest first; a recent attempt waits; a title with ids is complete',
      () async {
        await add(_row('s1:old', at: 9000));
        await add(_row('s1:new', at: 100));
        await add(_row('s1:done', title: 'x', identityJson: '["movie:tmdb:1"]'));
        await add(_row('s1:waiting', tried: 1000000, at: 5000));
        await add(_row('s1:retry', tried: 10, at: 4000));
        // A Plex row written at watch time: a catalogue guid, still no external id.
        await add(_row('s1:guidOnly', title: 'g', identityJson: '["movie:guid:plex://movie/a"]', at: 7000));
        final gaps = await db.identityGaps('p1', minWeight: 0.4, retryBeforeMs: 500000, limit: 10);
        expect(gaps.map((g) => g.key), ['s1:new', 's1:guidOnly', 's1:old', 's1:retry']);
        expect(gaps.singleWhere((g) => g.key == 's1:guidOnly').hasTitle, isTrue);
        expect(gaps.singleWhere((g) => g.key == 's1:old').hasTitle, isFalse);
      },
    );

    test(
      'identityGaps: a guid that spells a scheme is no external id, and a new play does not reopen a title just asked',
      () async {
        await add(_row('s1:odd', title: 'x', identityJson: '["movie:guid:tmdb://123"]'));
        // Asked a minute ago (marked on every row), then played again: the new row has no mark.
        await add(_row('s1:again', title: 'y', identityJson: '["movie:guid:plex://movie/a"]', tried: 900000, at: 5000));
        await add(_row('s1:again', title: 'y', identityJson: '["movie:guid:plex://movie/a"]', at: 10));
        final gaps = await db.identityGaps('p1', minWeight: 0.4, retryBeforeMs: 500000, limit: 10);
        expect(gaps.map((g) => g.key), ['s1:odd']);
      },
    );

    test('markIdentityTried marks every row of every given title in one call, this profile only', () async {
      for (var i = 0; i < 450; i++) {
        await add(_row('s1:t$i', at: 1000 + i));
      }
      await db.insertMediaInteraction(_row('s1:t0', profile: 'p2'), profileId: 'p2');
      await db.markIdentityTried('p1', [for (var i = 0; i < 450; i++) 's1:t$i'], triedAt: 77);
      expect((await db.getMediaInteractions('p1')).every((r) => r.identityTriedAt == 77), isTrue);
      expect((await db.getMediaInteractions('p2')).single.identityTriedAt, isNull);
    });

    test('everWatchedIdentities: kind and title come from the newest row of a key', () async {
      await add(_row('s1:old', kind: 'movie', seriesKey: 's1:k', title: 'Old', year: 1984, at: 9000));
      await add(
        _row('s1:new', kind: 'episode', seriesKey: 's1:k', title: 'New', identityJson: '["show:tvdb:1"]', at: 100),
      );
      final seen = (await db.everWatchedIdentities('p1', minWeight: 0.4)).single;
      expect(seen.title, 'New');
      expect(seen.show, isTrue);
    });

    test(
      'everWatchedIdentities: the ids of an older row of a key survive a newer row that holds the title alone',
      () async {
        await add(
          _row(
            's1:show',
            kind: 'episode',
            seriesKey: 's1:show',
            title: 'Sev',
            identityJson: '["show:tvdb:1"]',
            at: 9000,
          ),
        );
        await add(_row('s1:e9', kind: 'episode', seriesKey: 's1:show', title: 'Sev', at: 100));
        final seen = await db.everWatchedIdentities('p1', minWeight: 0.4);
        expect(seen.single.tokens, {'show:tvdb:1'});
      },
    );
  });

  group('recorder', () {
    late AppDatabase db;
    late InteractionRecorder recorder;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async {
      await recorder.dispose();
      await db.close();
    });

    Future<List<MediaInteractionRow>> record(
      MediaItem fetched, {
      String profile = 'p1',
      Future<void> Function()? during,
    }) async {
      final client = _Client({fetched.id: fetched, 'show': _show('show', guid: 'plex://show/sev', year: 2022)});
      recorder = InteractionRecorder(database: db, profileId: profile, clientResolver: (_) => client)..start();
      final event = MediaItem.plex(id: fetched.id, kind: fetched.kind, serverId: 's1', title: 'x');
      WatchStateNotifier().notifyWatched(item: event, isNowWatched: true);
      await pumpEventQueue();
      await during?.call();
      return db.getMediaInteractions(profile);
    }

    test('a watched movie is stored with its title and guid token', () async {
      final saved = await record(_movie('m1', guid: 'plex://movie/abc', year: 2021));
      expect(saved.single.title, 'Dune');
      expect(saved.single.identityJson, '["movie:guid:plex://movie/abc"]');
      expect(saved.single.identityTriedAt, isNull, reason: 'ids are still to be looked up');
    });

    test('a profile deleted while the metadata is fetched gets no row back', () async {
      final slow = _DeletingClient(db, 'p1', _movie('m1', guid: 'plex://movie/abc'));
      recorder = InteractionRecorder(database: db, profileId: 'p1', clientResolver: (_) => slow)..start();
      WatchStateNotifier().notifyWatched(
        item: MediaItem.plex(id: 'm1', kind: MediaKind.movie, serverId: 's1', title: 'x'),
      );
      await pumpEventQueue();
      expect(await db.getMediaInteractions('p1'), isEmpty);
    });

    test('a watched episode is stored under its series, with no episode id as a series id', () async {
      final saved = await record(_episode('e1', series: 'Severance', seriesGuid: 'plex://show/sev', year: 2022));
      expect(saved.single.title, 'Severance');
      expect(saved.single.identityJson, '["show:guid:plex://show/sev"]');
    });
  });

  group('RecommendationService backfill trigger', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    final titles = PersonalizedRowTitles(
      topPicks: 'a',
      becauseYouLike: (g) => g,
      hiddenGems: 'b',
      moreWithActor: (n) => n,
      moreFromDirector: (n) => n,
    );

    test('runs in the background on a sync, and not again within 15 minutes', () async {
      await db.insertMediaInteraction(_row('s1:m1'), profileId: 'p1');
      var lookups = 0;
      final client = _Client({'m1': _movie('m1')});
      final service = RecommendationService(
        profileId: 'p1',
        database: db,
        titles: titles,
        identityClientOf: (_) {
          lookups++;
          return client;
        },
      );
      await service.syncImportedHistory();
      await pumpEventQueue();
      expect(lookups, 1);
      expect((await db.getMediaInteractions('p1')).single.title, 'Dune');
      await db.insertMediaInteraction(_row('s1:m2', at: 5), profileId: 'p1');
      await service.syncImportedHistory();
      await pumpEventQueue();
      expect(lookups, 1, reason: 'the interval has not passed');
    });

    test('without a client source nothing is looked up', () async {
      await db.insertMediaInteraction(_row('s1:m1'), profileId: 'p1');
      await RecommendationService(profileId: 'p1', database: db, titles: titles).syncImportedHistory();
      await pumpEventQueue();
      expect((await db.getMediaInteractions('p1')).single.title, isNull);
    });
  });

  group('backfillInteractionIdentity', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> run(
      MediaServerClient? Function(ServerId) clientOf, {
      bool Function()? current,
      int now = 10000000,
      Duration timeout = const Duration(seconds: 5),
    }) => backfillInteractionIdentity(
      database: db,
      profileId: 'p1',
      clientOf: clientOf,
      enabledImportServerIds: () => const {},
      isCurrentProfile: current ?? () => true,
      minWeight: 0.4,
      nowMs: now,
      timeout: timeout,
    );

    Future<void> add(MediaInteractionsCompanion row) => db.insertMediaInteraction(row, profileId: 'p1');

    test(
      'fills the movie\'s title and ids, and an episode row from its series, in one request pair per title',
      () async {
        await add(_row('s1:m1', year: 2021));
        await add(_row('s1:e1', kind: 'episode', seriesKey: 's1:show', at: 10));
        await add(_row('s1:e2', kind: 'episode', seriesKey: 's1:show', at: 20));
        final client = _Client(
          {'m1': _movie('m1', year: 2021), 'show': _show('show', year: 2022, guid: 'plex://show/sev')},
          ids: {'m1': const ExternalIds(tmdb: 438631), 'show': const ExternalIds(tvdb: 371980)},
        );
        expect(await run((_) => client), 2);
        final rows = {for (final r in await db.getMediaInteractions('p1')) r.globalKey: r};
        expect(rows['s1:m1']!.title, 'Dune');
        expect(rows['s1:m1']!.identityJson, '["movie:tmdb:438631"]');
        expect(rows['s1:e1']!.title, 'Severance');
        expect(rows['s1:e2']!.identityJson, '["show:guid:plex://show/sev","show:tvdb:371980"]');
        expect(client.calls.where((c) => c == 'item:show'), hasLength(1), reason: 'one lookup per series');
        expect(await db.getMediaInteractions('p1'), hasLength(3));
      },
    );

    test('a server key that now names another year is not linked, only marked tried', () async {
      await add(_row('s1:m1', year: 1984));
      final client = _Client({'m1': _movie('m1', year: 2021)}, ids: {'m1': const ExternalIds(tmdb: 438631)});
      expect(await run((_) => client), 0);
      final row = (await db.getMediaInteractions('p1')).single;
      expect(row.title, isNull);
      expect(row.identityJson, isNull);
      expect(row.identityTriedAt, 10000000);
    });

    test('a title the server answers nothing for is tried again after a day, one that threw after an hour', () async {
      await add(_row('s1:gone'));
      await add(_row('s1:flaky', at: 10));
      final client = _Client({'gone': null, 'flaky': _movie('flaky')}, failing: {'flaky'});
      await run((_) => client);
      final marks = {for (final r in await db.getMediaInteractions('p1')) r.globalKey: r.identityTriedAt};
      const week = 7 * 24 * 3600000;
      expect(marks['s1:flaky'], 10000000 - week + 3600000, reason: 'due again after an hour');
      expect(marks['s1:gone'], 10000000 - week + 24 * 3600000, reason: 'due again after a day');
      client.calls.clear();
      await run((_) => client, now: 10000000 + 30 * 60000);
      expect(client.calls, isEmpty, reason: 'neither is due yet');
      await run((_) => client, now: 10000000 + 2 * 3600000);
      expect(client.calls, ['item:flaky'], reason: 'the thrown one is due after an hour, the empty one after a day');
      client.calls.clear();
      await run((_) => client, now: 10000000 + 26 * 3600000);
      expect(client.calls, containsAll(['item:gone', 'item:flaky']));
    });

    test(
      '25 titles that keep failing do not hold the queue: the title behind them is filled in on the next pass',
      () async {
        for (var i = 0; i < 25; i++) {
          await add(_row('s1:bad$i', at: 100000 + i));
        }
        await add(_row('s1:ok', at: 500000));
        final client = _Client({'ok': _movie('ok', title: 'Fine')}, failing: {for (var i = 0; i < 25; i++) 'bad$i'});
        expect(await run((_) => client), 0);
        expect(await run((_) => client, now: 10000000 + 1000), 1);
        expect((await db.getMediaInteractions('p1')).where((r) => r.title != null).single.globalKey, 's1:ok');
      },
    );

    test('a row written at watch time with only its guid gets the external ids later', () async {
      await add(_row('s1:m1', title: 'Dune', identityJson: '["movie:guid:plex://movie/abc"]', year: 2021));
      final client = _Client(
        {'m1': _movie('m1', guid: 'plex://movie/abc', year: 2021)},
        ids: {'m1': const ExternalIds(tmdb: 438631)},
      );
      expect(await run((_) => client), 1);
      final row = (await db.getMediaInteractions('p1')).single;
      expect(row.identityJson, contains('movie:tmdb:438631'));
      expect(row.identityJson, contains('movie:guid:plex://movie/abc'), reason: 'filled, not overwritten');
    });

    test('a profile that left before the marks were written gets none', () async {
      await add(_row('ps:m1', title: 'Known', identityJson: '["movie:guid:x://1"]'));
      final ps = _PleyaLike({'m1': _movie('m1')});
      await run((_) => ps, current: () => false);
      expect((await db.getMediaInteractions('p1')).single.identityTriedAt, isNull);
    });

    test('Jellyfin and Emby ids are inline: no second request for them', () async {
      await add(_row('jf:m1'));
      final client = _JellyLike({
        'm1': _movie(
          'm1',
          raw: {
            'ProviderIds': {'Tmdb': '438631'},
          },
        ),
      });
      expect(await run((_) => client), 1);
      expect(client.calls, ['item:m1']);
      expect((await db.getMediaInteractions('p1')).single.identityJson, '["movie:tmdb:438631"]');
    });

    test('a backend that holds no external ids is marked without a request and without a slot', () async {
      await add(_row('ps:m1', title: 'Known', identityJson: '["movie:guid:x://1"]'));
      final psClient = _PleyaLike({'m1': _movie('m1')});
      expect(await run((_) => psClient), 0);
      expect(psClient.calls, isEmpty);
      expect((await db.getMediaInteractions('p1')).single.identityTriedAt, 10000000, reason: 'a full week');
    });

    test(
      'titles on a server without an online client do not take a slot: 26 of them ahead of one that resolves',
      () async {
        for (var i = 0; i < 26; i++) {
          await add(_row('off:o$i', at: 100000 + i));
        }
        await add(_row('s1:ok', at: 500000));
        final client = _Client({'ok': _movie('ok')});
        expect(await run((id) => id == ServerId('s1') ? client : null), 1);
        expect((await db.getMediaInteractions('p1')).where((r) => r.title != null).single.globalKey, 's1:ok');
      },
    );

    test('at most 25 titles per pass', () async {
      for (var i = 0; i < 30; i++) {
        await add(_row('s1:t$i', at: 1000 + i));
      }
      final client = _Client({for (var i = 0; i < 30; i++) 't$i': _movie('t$i', title: 'T$i')});
      expect(await run((_) => client), kIdentityBackfillBatch);
      expect((await db.getMediaInteractions('p1')).where((r) => r.title == null), hasLength(5));
    });

    test('a profile switched away, or deleted, mid-pass writes nothing', () async {
      await add(_row('s1:m1'));
      final client = _Client({'m1': _movie('m1')});
      expect(await run((_) => client, current: () => false), 0);
      expect((await db.getMediaInteractions('p1')).single.title, isNull);
      await add(_row('s1:m2', at: 5));
      var deleted = false;
      final slow = _Client({'m1': _movie('m1'), 'm2': _movie('m2')});
      final result = await backfillInteractionIdentity(
        database: db,
        profileId: 'p1',
        clientOf: (_) {
          if (!deleted) {
            deleted = true;
            // The profile's data is removed while the pass is being set up.
            db.deleteRecommendationDataForProfile('p1');
          }
          return slow;
        },
        enabledImportServerIds: () => const {},
        isCurrentProfile: () => true,
        minWeight: 0.4,
      );
      expect(result, 0);
      expect(await db.getMediaInteractions('p1'), isEmpty);
    });
  });
}
