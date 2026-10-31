import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/models/plex/play_queue_response.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/episode_navigation_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/media_list_playback_launcher.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:provider/provider.dart';

import '../pleya_server/pleya_fake_server.dart';
import '../test_helpers/prefs.dart';

/// The launcher fills the queue, and `navigateToVideoPlayer` then swaps the item for
/// what the fresh read answers. The first frame of the player keeps the queue only
/// when that answer still counts as a member. These tests take the production route
/// from the press on Play to the route of the player, with a real client against a
/// fake server, and stop where mpv would start.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  const positionMs = 60000;
  final seen = {'position_ms': positionMs, 'watched': false, 'play_count': 0, 'updated_at': '2026-08-18T20:12:44Z'};

  group('Pleya Server', () {
    Future<(_Host, PleyaFakeServer)> connect(WidgetTester tester) async {
      final server = PleyaFakeServer(watchState: true)..listsCapability = true;
      for (final id in ['first', 'second', 'third']) {
        server.addItem(id: id, kind: 'movie', title: id, userState: seen);
      }
      final client = await tester.runAsync(() async {
        final client = server.client();
        await client.refreshCapabilities();
        return client;
      });
      addTearDown(client!.close);
      return (await _pumpHost(tester, client), server);
    }

    Future<void> play(
      WidgetTester tester,
      _Host host,
      Object list, {
      bool shuffle = false,
      MediaItem? startItem,
    }) async {
      await tester.runAsync(
        () => MediaListPlaybackLauncher.forItem(host.context, list).launchFromCollectionOrPlaylist(
          item: list,
          shuffle: shuffle,
          startItem: startItem,
          showLoadingIndicator: false,
        ),
      );
      await tester.pump();
    }

    MediaPlaylist playlist(_Host host, String id) => MediaPlaylist(
      id: id,
      backend: MediaBackend.pleyaServer,
      title: id,
      playlistType: 'video',
      serverId: host.client.serverId.toString(),
    );

    MediaItem collection(_Host host, String id) => MediaItem(
      id: id,
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.collection,
      serverId: host.client.serverId.toString(),
    );

    testWidgets('a playlist whose first title has watch state plays on', (tester) async {
      final (host, server) = await connect(tester);
      server.lists.playlists['p'] = FakeList(id: 'p', title: 'p', itemIds: ['first', 'second', 'third']);

      await play(tester, host, playlist(host, 'p'));

      final started = host.spy.playerScreen(host.context).metadata;
      expect(started.viewOffsetMs, positionMs);
      expect(identical(started, host.playback.loadedItems.first), isFalse, reason: 'the fresh read replaced it');
      host.enterPlayer(started);
      expect((await host.adjacent(tester, started)).next?.id, 'second');
    });

    testWidgets('a tapped row in a collection plays on from that row', (tester) async {
      final (host, server) = await connect(tester);
      server.lists.collections['c'] = FakeList(id: 'c', title: 'c', itemIds: ['first', 'second', 'third']);
      final tapped = MediaItem(id: 'second', backend: MediaBackend.pleyaServer, kind: MediaKind.movie);

      await play(tester, host, collection(host, 'c'), startItem: tapped);

      final started = host.spy.playerScreen(host.context).metadata;
      expect(started.id, 'second');
      host.enterPlayer(started);
      final adjacent = await host.adjacent(tester, started);
      expect(adjacent.next?.id, 'third');
      expect(adjacent.previous?.id, 'first');
    });

    testWidgets('shuffle keeps every row after the first title', (tester) async {
      final (host, server) = await connect(tester);
      server.lists.collections['c'] = FakeList(id: 'c', title: 'c', itemIds: ['first', 'second', 'third']);

      await play(tester, host, collection(host, 'c'), shuffle: true);

      final started = host.spy.playerScreen(host.context).metadata;
      host.enterPlayer(started);
      expect(host.playback.isShuffleActive, isTrue);
      expect(host.playback.loadedItems, hasLength(3));
      expect((await host.adjacent(tester, started)).next, isNotNull);
    });

    testWidgets('a later start of another title from the old list leaves that list behind', (tester) async {
      final (host, server) = await connect(tester);
      server.lists.playlists['p'] = FakeList(id: 'p', title: 'p', itemIds: ['first', 'second', 'third']);
      await play(tester, host, playlist(host, 'p'));
      host.enterPlayer(host.spy.playerScreen(host.context).metadata);

      // A press on a card elsewhere in the app: no launcher, so the cursor stays.
      final card = host.playback.loadedItems[2].copyWith();
      await tester.runAsync(() => navigateToVideoPlayer(host.context, metadata: card));
      await tester.pump();

      host.enterPlayer(host.spy.playerScreen(host.context).metadata);
      expect(host.playback.isQueueActive, isFalse);
    });
  });

  testWidgets('Jellyfin: a playlist plays on after a fresh read of every title', (tester) async {
    final server = _JellyfinServer(['first', 'second', 'third']);
    final client = _jellyfinClient(server, isEmby: false);
    final host = await _pumpHost(tester, client);
    final list = MediaPlaylist(
      id: 'pl',
      backend: MediaBackend.jellyfin,
      title: 'pl',
      playlistType: 'video',
      serverId: client.serverId.toString(),
    );

    await tester.runAsync(
      () => MediaListPlaybackLauncher.forItem(
        host.context,
        list,
      ).launchFromCollectionOrPlaylist(item: list, shuffle: false, showLoadingIndicator: false),
    );
    await tester.pump();

    final started = host.spy.playerScreen(host.context).metadata;
    expect(server.freshReads, ['first']);
    expect(identical(started, host.playback.loadedItems.first), isFalse);
    host.enterPlayer(started);
    expect((await host.adjacent(tester, started)).next?.id, 'second');
  });

  testWidgets('Plex: a server-side queue survives the fresh read of its first title', (tester) async {
    final server = _PlexServer();
    final client = _plexClient(server);
    final host = await _pumpHost(tester, client);
    final serverId = client.serverId.toString();
    final items = [
      for (final (index, id) in ['first', 'second'].indexed)
        PlexMediaItem(id: id, kind: MediaKind.movie, serverId: serverId, playQueueItemId: 500 + index),
    ];
    await host.playback.setPlaybackFromPlayQueue(
      PlayQueueResponse(
        playQueueID: 7,
        playQueueSelectedItemID: 500,
        playQueueShuffled: false,
        playQueueTotalCount: 2,
        playQueueVersion: 1,
        size: 2,
        items: items,
      ),
      'playlist-1',
    );

    await tester.runAsync(() => navigateToVideoPlayer(host.context, metadata: items.first));
    await tester.pump();

    final started = host.spy.playerScreen(host.context).metadata;
    expect(identical(started, items.first), isFalse, reason: 'the fresh read replaced it');
    host.enterPlayer(started);
    expect((await host.adjacent(tester, started)).next?.id, 'second');
  });
}

class _Host {
  _Host(this.client);

  final MediaServerClient client;
  final playback = PlaybackStateProvider();
  final spy = _PlayerRouteSpy();
  late BuildContext context;

  /// What the post-frame callback in [VideoPlayerScreenState.initState] decides.
  void enterPlayer(MediaItem started) {
    if (playback.isItemInActiveQueue(started)) {
      playback.setCurrentItem(started);
    } else {
      playback.clearShuffle();
    }
  }

  Future<AdjacentEpisodes> adjacent(WidgetTester tester, MediaItem started) async {
    final adjacent = await tester.runAsync(
      () => EpisodeNavigationService().loadAdjacentEpisodes(context: context, metadata: started),
    );
    return adjacent!;
  }
}

Future<_Host> _pumpHost(WidgetTester tester, MediaServerClient client) async {
  await SettingsService.getInstance();
  final host = _Host(client);
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final downloadManager = DownloadManagerService(
    database: db,
    storageService: DownloadStorageService.instance,
    clientResolver: (serverId, {clientScopeId}) => null,
  );
  downloadManager.recoveryFuture = Future<void>.value();
  final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
  await downloadProvider.ensureInitialized();
  final offlineWatchSync = OfflineWatchSyncService(database: db, serverManager: manager);
  final store = WatchStateStore();
  addTearDown(() async {
    host.playback.dispose();
    store.dispose();
    offlineWatchSync.dispose();
    downloadProvider.dispose();
    multiServerProvider.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
        ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
        ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
        ChangeNotifierProvider<WatchStateStore>.value(value: store),
        ChangeNotifierProvider<PlaybackStateProvider>.value(value: host.playback),
      ],
      child: MaterialApp(
        navigatorObservers: [host.spy],
        home: Builder(
          builder: (context) {
            host.context = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return host;
}

/// Captures the real route and removes it before its state would mount mpv.
class _PlayerRouteSpy extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != kVideoPlayerRouteName) return;
    _routes.add(route);
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }

  VideoPlayerScreen playerScreen(BuildContext context) {
    final route = _routes.last as PageRouteBuilder<bool>;
    return route.pageBuilder(context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation) as VideoPlayerScreen;
  }
}

JellyfinClient _jellyfinClient(_JellyfinServer server, {required bool isEmby}) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  JellyfinApiCache.initialize(db);
  final client = JellyfinClient.forTesting(
    connection: JellyfinConnection(
      id: 'server_1/user_1',
      baseUrl: 'https://jellyfin.example.test',
      serverName: 'Server',
      serverMachineId: 'server_1',
      userId: 'user_1',
      userName: 'Test viewer',
      accessToken: 'test-token',
      deviceId: 'test-client',
      isEmby: isEmby,
      createdAt: DateTime.utc(2026, 10, 18),
    ),
    httpClient: server.httpClient,
  );
  addTearDown(client.close);
  return client;
}

PlexClient _plexClient(_PlexServer server) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  PlexApiCache.initialize(db);
  final client = PlexClient.forTesting(
    config: PlexConfig(
      baseUrl: 'https://plex.example.test',
      token: 'test-token',
      clientIdentifier: 'test-client',
      product: 'Pleya',
      version: 'test',
    ),
    serverId: ServerId('server_1'),
    httpClient: server.httpClient,
  );
  addTearDown(client.close);
  return client;
}

class _JellyfinServer {
  _JellyfinServer(this.ids);

  final List<String> ids;
  final freshReads = <String>[];

  Map<String, Object?> _row(String id) => {
    'Id': id,
    'Type': 'Movie',
    'Name': id,
    'RunTimeTicks': 2 * 60 * 60 * 1000 * 10000,
    'UserData': {'PlaybackPositionTicks': 60000 * 10000, 'Played': false},
  };

  late final httpClient = MockClient((request) async {
    final path = request.url.path;
    if (path == '/Playlists/pl/Items') {
      return _json({
        'Items': [for (final id in ids) _row(id)],
        'TotalRecordCount': ids.length,
      });
    }
    if (path.startsWith('/Users/user_1/Items/')) {
      final id = path.split('/').last;
      freshReads.add(id);
      return _json(_row(id));
    }
    return http.Response('not found: $path', 404);
  });
}

class _PlexServer {
  late final httpClient = MockClient((request) async {
    final id = request.url.pathSegments.last;
    return _json({
      'MediaContainer': {
        'Metadata': [
          {'ratingKey': id, 'type': 'movie', 'title': id, 'duration': 7200000, 'viewOffset': 60000},
        ],
      },
    });
  });
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
