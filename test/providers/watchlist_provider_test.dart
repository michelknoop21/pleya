import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/providers/watchlist_store.dart';
import 'package:pleya/services/plex_account_auth.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/utils/global_key_utils.dart';
import 'package:pleya/utils/watchlist_notifier.dart';

import '../pleya_server/pleya_fake_server.dart';

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

const PlexAccountAuth plexAuth = (token: 't', profileId: 'p1', accountId: 'a', userId: 'u', isUserScoped: true);

/// The owner's token standing in for a Home user whose binder has not finished.
const PlexAccountAuth ownerOnlyAuth = (token: 't', profileId: 'p1', accountId: 'a', userId: 'u', isUserScoped: false);

/// A server the factory builds no source for, whatever its capabilities say.
class _PlainClient implements MediaServerClient {
  _PlainClient({bool favorites = false}) : capabilities = ServerCapabilities.plex.copyWith(serverFavorites: favorites);

  @override
  final ServerCapabilities capabilities;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _PendingSource extends _StubSource {
  _PendingSource() : super(scope: plexScope);
  final started = Completer<void>();
  final result = Completer<List<WatchlistEntry>>();
  @override
  Future<List<WatchlistEntry>> fetch() {
    started.complete();
    return result.future;
  }
}

class _PendingAddSource extends _StubSource {
  _PendingAddSource() : super(scope: plexScope);
  final started = Completer<void>();
  final result = Completer<WatchlistMembership>();
  @override
  bool accepts(MediaItem item) => true;
  @override
  Future<WatchlistMembership> add(MediaItem item) {
    started.complete();
    return result.future;
  }
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

  test('a response from a reset profile cannot repopulate the new watchlist', () async {
    final pending = _PendingSource();
    final provider = providerWith(sources: [pending]);
    addTearDown(provider.dispose);
    final loading = provider.load();
    await pending.started.future;
    provider.reset();
    provider.repository = WatchlistRepository(sources: []);
    pending.result.complete([entry()]);
    await loading;
    expect(provider.entries, isEmpty);
    expect(provider.hasLoaded, isFalse);
  });

  test('a load begun while a new profile binds cannot restore the old snapshot', () async {
    await snapshots.write(plexScope, [entry()]);
    final provider = providerWith(sources: [_StubSource(scope: plexScope)]);
    addTearDown(provider.dispose);
    final identifier = Completer<String>();
    provider.attach(
      profileId: 'p2',
      resolvePlexAuth: () async => null,
      clientIdentifier: () => identifier.future,
      clientsById: () => {},
      serversFor: () => [],
      cache: PlexApiCache.instance,
    );
    await provider.load(offline: true);
    final leaked = provider.entries.toList();
    identifier.complete('device');
    await Future<void>.delayed(Duration.zero);
    expect(leaked, isEmpty);
    expect(provider.hasLoaded, isFalse, reason: 'the newly bound sources must still load');
  });

  test('a late write cannot patch the next profile through the global notifier', () async {
    final store = WatchlistStore()..bindProfile('one');
    addTearDown(store.dispose);
    final pending = _PendingAddSource();
    final provider = providerWith(sources: [pending]);
    final adding = provider.addToWatchlist(entry().item, isOffline: false);
    await pending.started.future;
    await Future<void>.delayed(Duration.zero);
    store.bindProfile('two');
    provider.dispose();
    pending.result.complete(WatchlistMembership(scope: plexScope, remoteKey: 'abc'));
    await adding;
    await Future<void>.delayed(Duration.zero);
    expect(store.isOnWatchlistByKey('plex:abc'), isNull);
  });

  test('a source rebind also clears optimistic patches in the current profile', () {
    final store = WatchlistStore()..bindProfile('one');
    addTearDown(store.dispose);
    final provider = WatchlistProvider(snapshots: snapshots, onScopeChanged: store.clear);
    addTearDown(provider.dispose);
    store.patch('plex:abc', onList: true);
    provider.reset();
    expect(store.isOnWatchlistByKey('plex:abc'), isNull);
  });

  test('queued optimistic events cannot cross an immediate scope reset', () async {
    final store = WatchlistStore()..bindProfile('one');
    addTearDown(store.dispose);
    final pending = _PendingAddSource();
    final provider = WatchlistProvider(
      snapshots: snapshots,
      repository: WatchlistRepository(sources: [pending]),
      onScopeChanged: store.clear,
    );
    addTearDown(provider.dispose);
    final adding = provider.addToWatchlist(entry().item, isOffline: false);
    store.bindProfile('two');
    provider.reset();
    pending.result.complete(WatchlistMembership(scope: plexScope, remoteKey: 'abc'));
    await adding;
    await Future<void>.delayed(Duration.zero);
    expect(store.isOnWatchlistByKey('plex:abc'), isNull);
  });

  testWidgets('source-scope clearing during provider update is safe for listeners', (tester) async {
    final store = WatchlistStore()..patch('old', onList: true);
    final trigger = ValueNotifier<int>(0);
    addTearDown(store.dispose);
    addTearDown(trigger.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WatchlistStore>.value(value: store),
          ChangeNotifierProvider<ValueNotifier<int>>.value(value: trigger),
          ProxyProvider<ValueNotifier<int>, Object>(
            update: (context, value, previous) {
              if (value.value == 1) context.read<WatchlistStore>().clear();
              return Object();
            },
          ),
        ],
        child: Consumer2<WatchlistStore, Object>(
          builder: (context, value, object, child) =>
              Text('${value.debugPatches.length}', textDirection: TextDirection.ltr),
        ),
      ),
    );
    trigger.value = 1;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(store.debugPatches, isEmpty);
  });

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

  group('rebinding within one profile', () {
    late WatchlistProvider provider;
    late int scopeChanges;
    late List<bool> hasWatchlistSeen;

    Future<void> attach(
      Map<String, MediaServerClient> clients, {
      String profileId = 'p1',
      PlexAccountAuthResolver? auth,
    }) async {
      provider.attach(
        profileId: profileId,
        resolvePlexAuth: auth ?? () async => plexAuth,
        clientIdentifier: () async => 'device',
        clientsById: () => clients,
        serversFor: () => [],
        cache: PlexApiCache.instance,
      );
      await pumpEventQueue();
    }

    Future<PleyaServerClient> pleyaClient({bool favorites = true}) async {
      final client = (PleyaFakeServer()..personalCapability = favorites).client();
      addTearDown(client.close);
      await client.refreshCapabilities();
      return client;
    }

    /// Bound to [clients] with [entries] loaded, as a viewer on the tab would be.
    Future<void> bind(Map<String, MediaServerClient> clients, {List<WatchlistEntry>? entries}) async {
      await attach(clients);
      provider.repository = WatchlistRepository(
        sources: [
          _StubSource(scope: plexScope, entries: entries ?? [entry()]),
        ],
      );
      await provider.load();
      scopeChanges = 0;
      hasWatchlistSeen.clear();
    }

    setUp(() {
      scopeChanges = 0;
      hasWatchlistSeen = [];
      provider = WatchlistProvider(snapshots: snapshots, onScopeChanged: () => scopeChanges++);
      provider.addListener(() => hasWatchlistSeen.add(provider.hasWatchlist));
    });
    tearDown(() => provider.dispose());

    test('a second server dropping out leaves the kijklijst of a Plex viewer alone', () async {
      final plex = _PlainClient();
      await bind({'plex': plex, 'second': _PlainClient()});
      final repository = provider.repository;

      await attach({'plex': plex});

      expect(identical(provider.repository, repository), isTrue);
      expect(provider.entries.map((e) => e.key), ['plex:abc']);
      expect(hasWatchlistSeen, isNot(contains(false)), reason: 'one false sends the viewer away from the tab');
      expect(scopeChanges, 0, reason: 'clearing the store would drop the optimistic patches');
      expect(provider.hasLoaded, isTrue);
    });

    test('a client the factory builds no source for does not count, even with the flag set', () async {
      await bind({'plex': _PlainClient(favorites: true)});
      final repository = provider.repository;

      await attach({'plex': _PlainClient(favorites: true)});

      expect(identical(provider.repository, repository), isTrue);
    });

    test('a Pleya Server without favorites flipping offline does not rebind', () async {
      final pleya = await pleyaClient(favorites: false);
      await bind({'pleya': pleya});
      final repository = provider.repository;

      await attach({});
      await attach({'pleya': pleya});

      expect(identical(provider.repository, repository), isTrue);
      expect(scopeChanges, 0);
    });

    test('a replaced favorites source rebinds, and the list stays until the new repository is ready', () async {
      final first = await pleyaClient();
      await bind({'pleya': first});
      final repository = provider.repository;
      final auth = Completer<PlexAccountAuth?>();

      await attach({'pleya': await pleyaClient()}, auth: () => auth.future);

      expect(identical(provider.repository, repository), isTrue, reason: 'the old sources serve until the swap');
      expect(provider.entries.map((e) => e.key), ['plex:abc']);

      auth.complete(plexAuth);
      await pumpEventQueue();

      expect(identical(provider.repository, repository), isFalse);
      expect(provider.entries.map((e) => e.key), ['plex:abc']);
      expect(hasWatchlistSeen, isNot(contains(false)));
      expect(scopeChanges, 0);
      expect(provider.hasLoaded, isFalse, reason: 'the new sources still have to be asked');
    });

    test('an empty list keeps its tab while a favorites source rebinds', () async {
      final auth = Completer<PlexAccountAuth?>();
      await bind({'pleya': await pleyaClient()}, entries: const []);

      await attach({}, auth: () => auth.future);
      expect(provider.hasWatchlist, isTrue);

      auth.complete(plexAuth);
      await pumpEventQueue();

      expect(provider.hasWatchlist, isTrue);
      expect(hasWatchlistSeen, isNot(contains(false)));
    });

    test('titles only a removed source held go at the swap, the rest stays', () async {
      final auth = Completer<PlexAccountAuth?>();
      await bind(
        {'pleya': await pleyaClient()},
        entries: [
          entry(),
          entry(key: 'jellyfin:only', guid: null, scope: jellyfinScope),
        ],
      );

      await attach({}, auth: () => auth.future);
      expect(provider.entries.map((e) => e.key), ['plex:abc', 'jellyfin:only']);

      auth.complete(plexAuth);
      await pumpEventQueue();

      expect(provider.entries.map((e) => e.key), ['plex:abc']);
    });

    test('only the latest of two quick rebinds becomes the repository', () async {
      final slow = Completer<PlexAccountAuth?>();
      final pleya = await pleyaClient();
      await bind({'pleya': pleya});

      await attach({}, auth: () => slow.future);
      await attach({'pleya': pleya});
      final latest = provider.repository;

      slow.complete(plexAuth);
      await pumpEventQueue();

      expect(identical(provider.repository, latest), isTrue);
    });

    test('updates during the first bind do not start another build', () async {
      final auth = Completer<PlexAccountAuth?>();
      var builds = 0;
      Future<PlexAccountAuth?> resolve() {
        builds++;
        return auth.future;
      }

      await attach({}, auth: resolve);
      await attach({}, auth: resolve);
      await attach({}, auth: resolve);
      expect(builds, 1, reason: 'each one would replace the build before it, and the list would never arrive');

      auth.complete(plexAuth);
      await pumpEventQueue();
      expect(provider.repository, isNotNull);
    });

    test('a profile switch during the first bind still builds for the new profile', () async {
      final auth = Completer<PlexAccountAuth?>();

      await attach({}, auth: () => auth.future);
      await attach({}, profileId: 'p2');

      expect(provider.repository, isNotNull);
    });

    group('the Plex source', () {
      List<WatchlistScopeId> boundScopes() => provider.repository!.sources.map((s) => s.scope).toList();

      test('of an account added mid-session comes in with its client', () async {
        await attach({}, auth: () async => null);
        expect(boundScopes(), isEmpty);

        await attach({'plex': _PlainClient()}, auth: () async => plexAuth);

        expect(boundScopes(), [plexScope]);
      });

      test('of a Home profile built before its binder comes in once the binder is done', () async {
        await attach({'plex': _PlainClient()}, auth: () async => ownerOnlyAuth);
        expect(boundScopes(), isEmpty);

        await attach({'plex': _PlainClient()}, auth: () async => plexAuth);

        expect(boundScopes(), [plexScope]);
      });

      test('keeps its repository when a client change leaves the scope as it was', () async {
        final plex = _PlainClient();
        await attach({'plex': plex});
        final repository = provider.repository;
        hasWatchlistSeen.clear();

        await attach({'plex': plex, 'second': _PlainClient()});
        await attach({'plex': plex});

        expect(identical(provider.repository, repository), isTrue);
        expect(hasWatchlistSeen, isNot(contains(false)));
      });

      test('of another account replaces the old one, and its titles go at the swap', () async {
        await bind({'plex': _PlainClient()});

        await attach({
          'plex': _PlainClient(),
        }, auth: () async => (token: 't', profileId: 'p1', accountId: 'other', userId: 'u', isUserScoped: true));

        expect(boundScopes().single.accountId, 'other');
        expect(provider.entries, isEmpty);
        expect(scopeChanges, 0);
      });

      test('leaves with its account', () async {
        await bind({'plex': _PlainClient()});

        await attach({}, auth: () async => null);

        expect(boundScopes(), isEmpty);
      });

      test('is not rebound by a scope check a profile switch overtook', () async {
        final slow = Completer<PlexAccountAuth?>();
        await attach({'plex': _PlainClient()});

        await attach({'plex': _PlainClient()}, auth: () => slow.future);
        await attach({'plex': _PlainClient()}, profileId: 'p2');
        final current = provider.repository;
        slow.complete((token: 't', profileId: 'p1', accountId: 'other', userId: 'u', isUserScoped: true));
        await pumpEventQueue();

        expect(identical(provider.repository, current), isTrue);
      });

      test('follows the latest scope check, not the slowest', () async {
        final slow = Completer<PlexAccountAuth?>();
        await attach({'plex': _PlainClient()});
        final repository = provider.repository;

        await attach({'plex': _PlainClient()}, auth: () => slow.future);
        await attach({'plex': _PlainClient()});
        slow.complete(null);
        await pumpEventQueue();

        expect(identical(provider.repository, repository), isTrue);
      });

      test('is not lost when the clients change while a build is running', () async {
        final stale = Completer<PlexAccountAuth?>();

        await attach({}, auth: () => stale.future);
        await attach({'plex': _PlainClient()});
        stale.complete(ownerOnlyAuth);
        await pumpEventQueue();

        expect(boundScopes(), [plexScope]);
      });
    });

    test('a load still running on the replaced repository is dropped', () async {
      final pending = _PendingSource();
      await bind({'pleya': await pleyaClient()});
      provider.repository = WatchlistRepository(sources: [pending]);
      final loading = provider.load();
      await pending.started.future;

      await attach({});
      pending.result.complete([entry(key: 'plex:late')]);
      await loading;

      expect(provider.entries.map((e) => e.key), isNot(contains('plex:late')));
      expect(provider.isLoading, isFalse);
      expect(provider.hasLoaded, isFalse);
    });

    test('a profile switch still drops everything at once', () async {
      await bind({'pleya': await pleyaClient()});

      await attach({}, profileId: 'p2');

      expect(provider.entries, isEmpty);
      expect(scopeChanges, 1);
    });
  });
}
