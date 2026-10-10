import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/widgets/notice/notice.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// `navigateToVideoPlayer` used to await the resume refetch before it took the
/// in-flight guard and before anything showed on screen. With a slow server
/// that left Select unanswered, and a second Select started a second
/// preparation. These tests hold the refetch open and look at what the shared
/// function does in that window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
    noticeController.debugReset();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    noticeController.debugReset();
  });

  final movie = MediaItem(
    id: 'movie_1',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Movie 1',
    serverId: 'server_1',
  );

  Future<(BuildContext, _BlockingClient, _RouteSpy)> pumpHost(WidgetTester tester) async {
    await SettingsService.getInstance();
    final client = _BlockingClient();
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
    final watchStateStore = WatchStateStore();
    addTearDown(() async {
      watchStateStore.dispose();
      offlineWatchSync.dispose();
      downloadProvider.dispose();
      multiServerProvider.dispose();
      await db.close();
    });

    final spy = _RouteSpy();
    late BuildContext hostContext;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
          ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
          ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
        ],
        child: MaterialApp(
          navigatorObservers: [spy],
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    spy.pushed.clear();
    return (hostContext, client, spy);
  }

  Iterable<String> startNotices() =>
      noticeController.visible.map((e) => e.notice.groupKey).where((key) => key.startsWith('playback-start:'));

  testWidgets('a blocked refetch shows the start notice until the player route is pushed', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();

    expect(client.fetchCalls, 1, reason: 'the refetch is in flight');
    expect(spy.names, isNot(contains(kVideoPlayerRouteName)), reason: 'still preparing');
    expect(startNotices(), hasLength(1), reason: 'Select is answered while the server is still thinking');
    final notice = noticeController.visible.single.notice;
    expect(notice.duration, isNull, reason: 'stays for as long as the preparation takes');
    expect(notice.body, 'Movie 1');

    client.release(movie);
    await tester.pump();
    await tester.pump();

    expect(spy.names, contains(kVideoPlayerRouteName));
    expect(startNotices(), isEmpty, reason: 'the player takes over from here');
  });

  testWidgets('a second start during the blocked refetch is dropped', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();
    final second = navigateToVideoPlayer(context, metadata: movie);
    await tester.pump();

    expect(client.fetchCalls, 1, reason: 'the duplicate never reaches the server');
    expect(await second, isNull);

    client.release(movie);
    await tester.pump();
    await tester.pump();

    expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(1));
  });

  testWidgets('the guard holds from the push until the frame that mounts the player', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();
    client.release(movie);
    // Microtasks only: the route is pushed, no frame has built it yet, so the
    // player state that owns `activeId` does not exist.
    await tester.idle();
    expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(1));

    final second = navigateToVideoPlayer(context, metadata: movie);
    await tester.idle();
    expect(client.fetchCalls, 1, reason: 'a press in that gap is still a duplicate');
    expect(await second, isNull);

    await tester.pump();
    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();
    expect(client.fetchCalls, 2, reason: 'after the handover frame the guard is free again');
    client.release(movie);
    await tester.pump();
  });

  testWidgets('the guard is released under the requested identity when the refetch returns another item', (
    tester,
  ) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();
    // A server may answer with a merged or re-keyed item. The guard was taken
    // for `movie_1`, so that is the key that has to be given back.
    client.release(movie.copyWith(id: 'movie_1_rekeyed'));
    await tester.pump();
    await tester.pump();
    expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(1));

    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();
    expect(client.fetchCalls, 2, reason: 'the first start no longer holds the guard');
    client.release(movie);
    await tester.pump();
    await tester.pump();
    expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(2));
  });

  testWidgets('a start whose screen went away releases the guard and clears the notice', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    final first = navigateToVideoPlayer(context, metadata: movie);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    client.release(movie);
    await tester.pump();

    expect(await first, isNull);
    expect(spy.names, isNot(contains(kVideoPlayerRouteName)));
    expect(startNotices(), isEmpty);

    final (context2, client2, spy2) = await pumpHost(tester);
    unawaited(navigateToVideoPlayer(context2, metadata: movie));
    await tester.pump();
    expect(client2.fetchCalls, 1, reason: 'the abandoned start did not keep the title locked');
    client2.release(movie);
    await tester.pump();
    await tester.pump();
    expect(spy2.names, contains(kVideoPlayerRouteName));
  });

  testWidgets('a failed refetch still starts playback and clears the notice', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();
    client.fail();
    await tester.pump();
    await tester.pump();

    expect(spy.names, contains(kVideoPlayerRouteName));
    expect(startNotices(), isEmpty);
  });

  testWidgets('the start notice shows over three standing errors, which all return afterwards', (tester) async {
    final (context, client, spy) = await pumpHost(tester);
    for (var i = 0; i < NoticeController.maxVisible; i++) {
      noticeController.show(Notice(level: NoticeLevel.error, title: 'e$i', groupKey: 'error-$i'));
    }

    unawaited(navigateToVideoPlayer(context, metadata: movie));
    await tester.pump();

    expect(startNotices(), hasLength(1), reason: 'standing errors must not hide the answer to Select');

    client.release(movie);
    await tester.pump();
    await tester.pump();

    expect(spy.names, contains(kVideoPlayerRouteName));
    expect(noticeController.visible.map((e) => e.notice.title), ['e0', 'e1', 'e2']);
  });

  testWidgets('two versions of one title each keep their notice until their own start ends', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(navigateToVideoPlayer(context, metadata: movie, selectedMediaIndex: 0));
    await tester.pump();
    unawaited(navigateToVideoPlayer(context, metadata: movie, selectedMediaIndex: 1));
    await tester.pump();

    expect(client.fetchCalls, 2, reason: 'a different version is a different start, the guard lets it through');
    expect(startNotices(), hasLength(2));

    client.release(movie);
    await tester.pump();
    await tester.pump();

    expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(1));
    expect(startNotices(), hasLength(1), reason: 'the second version is still preparing');

    client.release(movie);
    await tester.pump();
    await tester.pump();

    expect(startNotices(), isEmpty);
  });

  for (final savedFirst in [true, false]) {
    testWidgets(
      'the saved version and that same version by number are one start (${savedFirst ? 'saved' : 'numbered'} first)',
      (tester) async {
        final (context, client, spy) = await pumpHost(tester);

        // No preference is stored, so "saved" resolves to version 0.
        unawaited(navigateToVideoPlayer(context, metadata: movie, selectedMediaIndex: savedFirst ? null : 0));
        await tester.pump();
        unawaited(navigateToVideoPlayer(context, metadata: movie, selectedMediaIndex: savedFirst ? 0 : null));
        await tester.pump();

        // Both answers land before a frame is built. No player state exists
        // yet to answer for duplicates through `activeId`, so the guard is
        // all there is between these two starts.
        client.release(movie);
        client.release(movie);
        await tester.pump();
        await tester.pump();

        expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(1));
        expect(startNotices(), isEmpty);

        // Both keys are given back: the title can be started again.
        unawaited(navigateToVideoPlayer(context, metadata: movie));
        await tester.pump();
        client.release(movie);
        await tester.pump();
        await tester.pump();
        expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(2));
      },
    );
  }

  // The version menu of Jellyfin and Emby passes the number together with the
  // stable source id; a plain play passes neither. Nothing in the guard looks
  // at the backend, so every backend runs the same two orders.
  for (final backend in MediaBackend.values) {
    for (final plainFirst in [true, false]) {
      testWidgets('a plain start and version 0 by number and source id are one start '
          '(${backend.id}, ${plainFirst ? 'plain' : 'source id'} first)', (tester) async {
        final (context, client, spy) = await pumpHost(tester);
        final item = MediaItem(
          id: 'movie_1',
          backend: backend,
          kind: MediaKind.movie,
          title: 'Movie 1',
          serverId: 'server_1',
        );
        Future<bool?> start({required bool plain}) => plain
            ? navigateToVideoPlayer(context, metadata: item)
            : navigateToVideoPlayer(context, metadata: item, selectedMediaIndex: 0, selectedMediaSourceId: 'source_a');

        // No preference is stored, so the plain start resolves to version 0.
        unawaited(start(plain: plainFirst));
        await tester.pump();
        unawaited(start(plain: !plainFirst));
        await tester.pump();

        client.release(item);
        client.release(item);
        await tester.pump();
        await tester.pump();

        expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(1));
        expect(startNotices(), isEmpty);

        // Every key is given back: the title can be started again.
        unawaited(start(plain: false));
        await tester.pump();
        client.release(item);
        await tester.pump();
        await tester.pump();
        expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(2));
      });
    }
  }

  testWidgets('two versions picked by number and source id both start', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(
      navigateToVideoPlayer(context, metadata: movie, selectedMediaIndex: 0, selectedMediaSourceId: 'source_a'),
    );
    await tester.pump();
    unawaited(
      navigateToVideoPlayer(context, metadata: movie, selectedMediaIndex: 1, selectedMediaSourceId: 'source_b'),
    );
    await tester.pump();

    expect(client.fetchCalls, 2);

    client.release(movie);
    client.release(movie);
    await tester.pump();
    await tester.pump();

    expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(2));
    expect(startNotices(), isEmpty);
  });

  testWidgets('an explicit restart skips the refetch and still pushes once', (tester) async {
    final (context, client, spy) = await pumpHost(tester);

    unawaited(playFromBeginning(context, movie));
    unawaited(playFromBeginning(context, movie));
    await tester.pump();
    await tester.pump();

    expect(client.fetchCalls, 0);
    expect(spy.names.where((name) => name == kVideoPlayerRouteName), hasLength(1));
  });
}

/// Records what was pushed, then drops it again: a real [VideoPlayerScreen]
/// would spin up mpv. Same approach as `discover_hero_activation_test.dart`.
class _RouteSpy extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    if (previousRoute == null) return;
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }

  Iterable<String?> get names => pushed.map((route) => route.settings.name);
}

class _BlockingClient implements MediaServerClient {
  int fetchCalls = 0;
  final _pending = <Completer<MediaItem?>>[];

  /// Answers the oldest open fetch.
  void release(MediaItem? item) => _pending.removeAt(0).complete(item);
  void fail() => _pending.removeAt(0).completeError(StateError('server unreachable'));

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<MediaItem?> fetchItem(String id) {
    fetchCalls++;
    final pending = Completer<MediaItem?>();
    _pending.add(pending);
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
