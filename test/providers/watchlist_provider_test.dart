import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/providers/watchlist_store.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/utils/global_key_utils.dart';
import 'package:pleya/utils/watchlist_notifier.dart';

final plexScope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');
final jellyfinScope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.jellyfin, accountId: 'jf', userId: 'x');

MediaItem serverItem({String serverId = 'machine-1', String id = '4711'}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel', serverId: serverId);

WatchlistEntry entry({
  String key = 'plex:abc',
  String? guid = 'plex://movie/abc',
  WatchlistScopeId? scope,
  WatchlistAvailability availability = WatchlistAvailability.unknown,
  bool coverageComplete = false,
  MediaItem? lastKnownMatch,
}) {
  return WatchlistEntry(
    key: key,
    kind: MediaKind.movie,
    item: MediaItem(id: 'abc', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel', guid: guid),
    guid: guid,
    memberships: [WatchlistMembership(scope: scope ?? plexScope, remoteKey: 'abc')],
    availability: availability,
    coverageComplete: coverageComplete,
    lastKnownMatch: lastKnownMatch,
  );
}

class _StubSource implements WatchlistSource {
  _StubSource({required this.scope, this.entries = const [], this.fails = false});

  @override
  final WatchlistScopeId scope;
  final List<WatchlistEntry> entries;
  final bool fails;

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    if (fails) throw StateError('source down');
    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: item.id);

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

void main() {
  late AppDatabase db;
  late WatchlistSnapshotStore snapshots;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    snapshots = WatchlistSnapshotStore(cache: PlexApiCache.instance);
  });

  tearDown(() async => db.close());

  WatchlistProvider providerWith({
    List<WatchlistSource> sources = const [],
    bool Function(ServerId)? online,
    bool Function(String)? downloaded,
    bool seerr = false,
  }) {
    return WatchlistProvider(
      snapshots: snapshots,
      repository: WatchlistRepository(sources: sources),
      isServerOnline: online ?? (_) => false,
      hasDownload: downloaded ?? (_) => false,
      seerrConfigured: seerr,
    );
  }

  group('playability', () {
    test('an online server with a known match is playable', () {
      final provider = providerWith(online: (id) => id == 'machine-1');

      expect(provider.isPlayable(entry(lastKnownMatch: serverItem())), isTrue);
    });

    test('an offline server with a known match is not playable on its own', () {
      final provider = providerWith(online: (_) => false);

      expect(provider.isPlayable(entry(lastKnownMatch: serverItem())), isFalse);
    });

    test('a downloaded title stays playable while its server is unreachable', () {
      final match = serverItem();
      final key = buildGlobalKey(ServerId('machine-1'), match.id);
      final provider = providerWith(online: (_) => false, downloaded: (k) => k == key);

      expect(provider.isPlayable(entry(lastKnownMatch: match)), isTrue);
    });

    test('without a match there is nothing to play, downloads or not', () {
      final provider = providerWith(online: (_) => true, downloaded: (_) => true);

      expect(provider.isPlayable(entry()), isFalse);
    });
  });

  group('requestability', () {
    test('is unsupported without Seerr', () {
      final provider = providerWith(seerr: false);

      expect(
        provider.requestability(entry(availability: WatchlistAvailability.notFound, coverageComplete: true)),
        WatchlistRequestability.unsupported,
      );
    });

    test('is ready when nothing was found and every server answered', () {
      final provider = providerWith(seerr: true);

      expect(
        provider.requestability(entry(availability: WatchlistAvailability.notFound, coverageComplete: true)),
        WatchlistRequestability.ready,
      );
    });

    test('is not primary when a server could not be reached', () {
      final provider = providerWith(seerr: true);

      expect(
        provider.requestability(entry(availability: WatchlistAvailability.notFound, coverageComplete: false)),
        WatchlistRequestability.resolvable,
        reason: 'one offline server must not turn into duplicate requests for titles the user owns',
      );
    });

    test('an available or unchecked title is not a request candidate', () {
      final provider = providerWith(seerr: true);

      expect(
        provider.requestability(entry(availability: WatchlistAvailability.available, coverageComplete: true)),
        WatchlistRequestability.unsupported,
      );
      expect(provider.requestability(entry()), WatchlistRequestability.unsupported);
    });
  });

  group('load', () {
    test('merges the sources and writes a snapshot per scope', () async {
      final provider = providerWith(
        sources: [
          _StubSource(
            scope: plexScope,
            entries: [entry(key: 'plex:abc')],
          ),
          _StubSource(
            scope: jellyfinScope,
            entries: [entry(key: 'imdb:tt1', guid: null, scope: jellyfinScope)],
          ),
        ],
      );

      await provider.load();

      expect(provider.entries.map((e) => e.key), ['plex:abc', 'imdb:tt1']);
      expect(provider.isComplete, isTrue);
      expect((await snapshots.read(plexScope))!.single.key, 'plex:abc');
      expect((await snapshots.read(jellyfinScope))!.single.key, 'imdb:tt1');
    });

    test('a failed source keeps its last good snapshot instead of being emptied', () async {
      await providerWith(
        sources: [
          _StubSource(
            scope: plexScope,
            entries: [entry(key: 'plex:abc')],
          ),
        ],
      ).load();

      await providerWith(sources: [_StubSource(scope: plexScope, fails: true)]).load();

      expect((await snapshots.read(plexScope))!.single.key, 'plex:abc');
    });

    test('reports an incomplete fetch rather than passing it off as the whole list', () async {
      final provider = providerWith(
        sources: [
          _StubSource(scope: plexScope, fails: true),
          _StubSource(
            scope: jellyfinScope,
            entries: [entry(key: 'imdb:tt1', guid: null, scope: jellyfinScope)],
          ),
        ],
      );

      await provider.load();

      expect(provider.isComplete, isFalse);
      expect(provider.entries, hasLength(1));
    });

    test('offline reads the snapshot and never touches a source', () async {
      await providerWith(
        sources: [
          _StubSource(
            scope: plexScope,
            entries: [entry(key: 'plex:abc')],
          ),
        ],
      ).load();

      final offline = providerWith(sources: [_StubSource(scope: plexScope, fails: true)]);
      await offline.load(offline: true);

      expect(offline.entries.map((e) => e.key), ['plex:abc']);
      expect(offline.isFromSnapshot, isTrue);
    });

    test('a profile with no source and no snapshot has no kijklijst to show', () async {
      final provider = providerWith();
      await provider.load(offline: true);

      expect(provider.hasWatchlist, isFalse);
      expect(provider.entries, isEmpty);
    });
  });

  group('WatchlistStore', () {
    test('patches on a canonical key, not on a global key', () {
      final store = WatchlistStore();
      addTearDown(store.dispose);

      final discover = MediaItem(
        id: 'abc',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        guid: 'plex://movie/abc',
      );
      final onServer = MediaItem(
        id: '4711',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        guid: 'plex://movie/abc',
        serverId: 'machine-1',
      );

      store.patch('plex:abc', onList: true);

      expect(store.isOnWatchlist(discover), isTrue);
      expect(store.isOnWatchlist(onServer), isTrue, reason: 'the detail screen and the list describe one title');
      expect(store.debugPatches.keys, ['plex:abc']);
    });

    test('has no opinion about an item it never saw', () {
      final store = WatchlistStore();
      addTearDown(store.dispose);

      expect(store.isOnWatchlist(MediaItem(id: 'x', backend: MediaBackend.plex, kind: MediaKind.movie)), isNull);
    });

    test('revert drops the patch so the UI stops claiming a write that failed', () {
      final store = WatchlistStore();
      addTearDown(store.dispose);

      store.patch('plex:abc', onList: true);
      store.revert('plex:abc');

      expect(store.isOnWatchlistByKey('plex:abc'), isNull);
    });

    test('a profile switch drops every patch', () {
      final store = WatchlistStore();
      addTearDown(store.dispose);

      store.bindProfile('p1');
      store.patch('plex:abc', onList: true);
      store.bindProfile('p2');

      expect(store.debugPatches, isEmpty);
    });

    test('follows the notifier', () async {
      final store = WatchlistStore();
      addTearDown(store.dispose);

      WatchlistNotifier().notify(const WatchlistEvent(key: 'plex:abc', changeType: WatchlistChangeType.added));
      await Future<void>.delayed(Duration.zero);

      expect(store.isOnWatchlistByKey('plex:abc'), isTrue);
    });
  });
}
