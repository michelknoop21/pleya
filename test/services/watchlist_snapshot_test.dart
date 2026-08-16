import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/utils/external_ids.dart';

final plexScope = WatchlistScopeId(
  profileId: 'profile-1',
  backend: MediaBackend.plex,
  accountId: 'account-1',
  userId: 'home-user-1',
);
final jellyfinScope = WatchlistScopeId(
  profileId: 'profile-1',
  backend: MediaBackend.jellyfin,
  accountId: 'jf-1',
  userId: 'jf-user',
);
final otherProfileScope = WatchlistScopeId(
  profileId: 'profile-2',
  backend: MediaBackend.plex,
  accountId: 'account-1',
  userId: 'home-user-1',
);

WatchlistEntry entry({
  String key = 'plex:abc',
  WatchlistScopeId? scope,
  String remoteKey = 'abc',
  int? addedAt = 1700000000,
  WatchlistAvailability availability = WatchlistAvailability.unknown,
  bool coverageComplete = false,
  MediaItem? lastKnownMatch,
}) {
  return WatchlistEntry(
    key: key,
    kind: MediaKind.movie,
    item: MediaItem(
      id: 'abc',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Sintel',
      year: 2010,
      thumbPath: 'https://metadata-static.plex.tv/poster.jpg',
    ),
    guid: 'plex://movie/abc',
    externalIds: const ExternalIds(imdb: 'tt1727587', tmdb: 45745),
    posterRef: 'https://metadata-static.plex.tv/poster.jpg',
    memberships: [WatchlistMembership(scope: scope ?? plexScope, remoteKey: remoteKey, addedAt: addedAt)],
    availability: availability,
    coverageComplete: coverageComplete,
    lastKnownMatch: lastKnownMatch,
  );
}

void main() {
  late AppDatabase db;
  late WatchlistSnapshotStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    store = WatchlistSnapshotStore(cache: PlexApiCache.instance);
  });

  tearDown(() async => db.close());

  group('round trip', () {
    test('an entry survives with its identity, memberships and poster intact', () async {
      final match = MediaItem(id: '4711', backend: MediaBackend.plex, kind: MediaKind.movie, serverId: 'machine-1');
      await store.write(plexScope, [
        entry(availability: WatchlistAvailability.available, coverageComplete: true, lastKnownMatch: match),
      ]);

      final read = (await store.read(plexScope))!.single;

      expect(read.key, 'plex:abc');
      expect(read.kind, MediaKind.movie);
      expect(read.guid, 'plex://movie/abc');
      expect(read.externalIds, const ExternalIds(imdb: 'tt1727587', tmdb: 45745));
      expect(read.posterRef, 'https://metadata-static.plex.tv/poster.jpg');
      expect(read.item.title, 'Sintel');
      expect(read.memberships.single.scope, plexScope);
      expect(read.memberships.single.remoteKey, 'abc');
      expect(read.memberships.single.addedAt, 1700000000);
      expect(read.availability, WatchlistAvailability.available);
      expect(read.coverageComplete, isTrue);
      expect(read.lastKnownMatch?.serverId, 'machine-1');
    });

    test('a merged entry keeps every membership', () async {
      final merged = entry().mergeWith(entry(scope: jellyfinScope, remoteKey: 'jf-1', addedAt: null));
      await store.write(plexScope, [merged]);

      final read = (await store.read(plexScope))!.single;

      expect(read.memberships, hasLength(2));
      expect(read.memberships.map((m) => m.scope), containsAll([plexScope, jellyfinScope]));
    });

    test('a membership without a timestamp reads back without one', () async {
      await store.write(plexScope, [entry(addedAt: null)]);

      expect((await store.read(plexScope))!.single.memberships.single.addedAt, isNull);
    });
  });

  group('scoping', () {
    test('two scopes do not read each other rows', () async {
      await store.write(plexScope, [entry(key: 'plex:abc')]);
      await store.write(jellyfinScope, [entry(key: 'imdb:tt1', scope: jellyfinScope, remoteKey: 'jf-1')]);

      expect((await store.read(plexScope))!.single.key, 'plex:abc');
      expect((await store.read(jellyfinScope))!.single.key, 'imdb:tt1');
    });

    test('the same account under another profile is a different snapshot', () async {
      await store.write(plexScope, [entry()]);

      expect(await store.read(otherProfileScope), isNull);
    });

    test('a write replaces rather than appends', () async {
      await store.write(plexScope, [entry(key: 'a'), entry(key: 'b')]);
      await store.write(plexScope, [entry(key: 'c')]);

      expect((await store.read(plexScope))!.map((e) => e.key), ['c']);
    });
  });

  group('offline semantics', () {
    test('no snapshot is null, an emptied watchlist is an empty list', () async {
      expect(await store.read(plexScope), isNull);

      await store.write(plexScope, []);

      expect(await store.read(plexScope), isEmpty);
    });

    test('the snapshot survives clearVolatile, which frees ordinary cache rows', () async {
      await store.write(plexScope, [entry()]);
      await PlexApiCache.instance.clearVolatile();

      expect(await store.read(plexScope), hasLength(1));
    });

    test('clear removes it, pin and all', () async {
      await store.write(plexScope, [entry()]);
      await store.clear(plexScope);

      expect(await store.read(plexScope), isNull);
    });
  });

  group('unreadable rows', () {
    test('an entry with no readable membership is dropped, not resurrected empty', () {
      final json = entry().toJson();
      json['memberships'] = [
        {'remoteKey': 'abc'},
      ];

      expect(WatchlistEntry.fromJson(json), isNull);
    });

    test('a membership with an unreadable scope is dropped', () {
      expect(WatchlistMembership.fromJson({'remoteKey': 'abc'}), isNull);
      expect(
        WatchlistMembership.fromJson({
          'scope': {'profileId': 'p', 'backend': 'martian', 'accountId': 'a', 'userId': 'u'},
          'remoteKey': 'abc',
        }),
        isNull,
      );
    });

    test('an entry without a key or an item is dropped', () {
      final noKey = entry().toJson()..['key'] = '';
      final noItem = entry().toJson()..remove('item');

      expect(WatchlistEntry.fromJson(noKey), isNull);
      expect(WatchlistEntry.fromJson(noItem), isNull);
    });

    test('one bad row does not sink the rest of the snapshot', () async {
      await store.write(plexScope, [entry(key: 'good-1'), entry(key: 'good-2')]);
      // Simulate a row written by an older schema by corrupting one entry.
      final row = await PlexApiCache.instance.get(
        WatchlistSnapshotStore.cacheServerId,
        WatchlistSnapshotStore.endpointFor(plexScope),
      );
      (row!['entries'] as List)[0] = {'key': 'broken'};
      await PlexApiCache.instance.put(
        WatchlistSnapshotStore.cacheServerId,
        WatchlistSnapshotStore.endpointFor(plexScope),
        row,
      );

      expect((await store.read(plexScope))!.map((e) => e.key), ['good-2']);
    });
  });
}
