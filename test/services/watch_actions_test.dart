import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/offline_watch_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/watch_actions.dart';
import 'package:provider/provider.dart';

/// Watch-state marks must survive their own server being unreachable, and that
/// question is per server.
///
/// [OfflineModeProvider.isOffline] answers a different one: it is false as soon
/// as *any* visible server is up. Routing on it alone meant a mark on a server
/// that was down took the online branch, hit a client that is registered
/// regardless of health, and was lost, while the identical mark with every
/// server down was queued and synced later. Same action, two durability
/// guarantees, decided by a server the item has nothing to do with.
class _UnreachableClient implements MediaServerClient {
  _UnreachableClient(this._id);

  final String _id;

  int markWatchedCalls = 0;

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<void> markWatched(MediaItem item) async {
    markWatchedCalls++;
    // What an unreachable server actually does: the transport gives up.
    throw Exception('connection refused');
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    throw Exception('connection refused');
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HealthyClient implements MediaServerClient {
  _HealthyClient(this._id);

  final String _id;

  final List<({String itemId, bool watched})> writes = [];

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<void> markWatched(MediaItem item) async => writes.add((itemId: item.id, watched: true));

  @override
  Future<void> markUnwatched(MediaItem item) async => writes.add((itemId: item.id, watched: false));

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _itemOn(String serverId, String id) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune', serverId: serverId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MultiServerManager serverManager;
  late OfflineWatchSyncService syncService;
  late DownloadManagerService downloadManager;
  late DownloadProvider downloadProvider;
  late OfflineWatchProvider offlineWatch;
  late MultiServerProvider multiServer;
  late OfflineModeProvider offlineMode;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    serverManager = MultiServerManager();
    syncService = OfflineWatchSyncService(database: db, serverManager: serverManager);

    downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();
    offlineWatch = OfflineWatchProvider(syncService: syncService, downloadProvider: downloadProvider);
  });

  tearDown(() async {
    offlineMode.dispose();
    multiServer.dispose();
    offlineWatch.dispose();
    downloadProvider.dispose();
    downloadManager.dispose();
    syncService.dispose();
    serverManager.dispose();
    await db.close();
  });

  /// Pumps the provider tree `WatchActions` reads from and hands back a context
  /// inside it.
  Future<BuildContext> pumpTree(WidgetTester tester) async {
    multiServer = MultiServerProvider(serverManager, DataAggregationService(serverManager));
    offlineMode = OfflineModeProvider(serverManager, multiServerProvider: multiServer);

    late BuildContext ctx;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
          ChangeNotifierProvider<OfflineWatchProvider>.value(value: offlineWatch),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  group('a mark on an unreachable server stays durable', () {
    testWidgets('one server down while another is up still queues the mark', (tester) async {
      final down = _UnreachableClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(down, online: false);

      final ctx = await pumpTree(tester);
      expect(offlineMode.isOffline, isFalse, reason: 'server a is up, so the app is not in offline mode');

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(
        await syncService.getPendingSyncCount(),
        1,
        reason: 'the mark belongs to server b, which is down, so it has to wait for server b',
      );
      expect(down.markWatchedCalls, 0, reason: 'no point spending a doomed request on a server known to be down');
    });

    testWidgets('unmarking on an unreachable server queues too', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(_UnreachableClient('b'), online: false);

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: false);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(await syncService.getPendingSyncCount(), 1);
    });

    testWidgets('a server with no client at all queues rather than doing nothing', (tester) async {
      // `skipped` used to be the answer here: the button reacted, nothing
      // happened, and nothing said so.
      serverManager.debugRegisterClientForTesting(_HealthyClient('a'));

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(await syncService.getPendingSyncCount(), 1);
    });
  });

  group('the reachable paths are untouched', () {
    testWidgets('a mark on a healthy server still goes straight to it', (tester) async {
      final healthy = _HealthyClient('a');
      serverManager.debugRegisterClientForTesting(healthy);

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('a', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.marked);
      expect(healthy.writes, [(itemId: 'i1', watched: true)]);
      expect(await syncService.getPendingSyncCount(), 0, reason: 'a write that landed has nothing to queue');
    });

    testWidgets('a server outside the profile filter is still written to directly', (tester) async {
      // Profile visibility scopes what a surface *shows*, not what a server can
      // accept. Reading the filtered answer here deferred a write to a server
      // that was up, while `tv_unified_context_actions` read the unfiltered one
      // and had already counted the same membership as written.
      final hidden = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(hidden);

      final ctx = await pumpTree(tester);
      multiServer.setVisibleServerIds({'a'});
      expect(multiServer.isServerOnline(ServerId('b')), isFalse, reason: 'invisible to the active profile');
      expect(serverManager.isServerOnline(ServerId('b')), isTrue, reason: 'but the server itself is up');

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.marked);
      expect(hidden.writes, [(itemId: 'i1', watched: true)]);
      expect(await syncService.getPendingSyncCount(), 0);
    });

    testWidgets('a rejected token reaches the caller instead of the queue', (tester) async {
      // An auth rejection reads as not-online, but no reconnect fixes it, so
      // queueing would swap the re-auth prompt for a silent "marked offline"
      // while the app is plainly online. `tv_unified_context_actions` refuses
      // to queue an auth error for the same reason.
      final rejected = _UnreachableClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(rejected)
        ..debugMarkAuthErrorForTesting(ServerId('b'));

      final ctx = await pumpTree(tester);

      await expectLater(WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true), throwsA(isA<Exception>()));
      expect(rejected.markWatchedCalls, 1, reason: 'the write is attempted so the 401 can surface');
      expect(await syncService.getPendingSyncCount(), 0, reason: 'nothing waits for a reconnect that cannot help');
    });

    testWidgets('an item with no server id is still skipped', (tester) async {
      serverManager.debugRegisterClientForTesting(_HealthyClient('a'));

      final ctx = await pumpTree(tester);
      final item = MediaItem(id: 'i1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune');

      expect(await WatchActions.setWatched(ctx, item, watched: true), WatchMarkOutcome.skipped);
      expect(await syncService.getPendingSyncCount(), 0, reason: 'the queue is keyed by server, so there is no row');
    });

    testWidgets('an explicit offline caller keeps queueing', (tester) async {
      serverManager.debugRegisterClientForTesting(_HealthyClient('a'));

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('a', 'i1'), watched: true, offline: true);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(await syncService.getPendingSyncCount(), 1);
    });
  });
}
