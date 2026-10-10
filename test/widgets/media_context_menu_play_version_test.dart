import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/models/transcode_quality_preset.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/quality_preset_labels.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/widgets/media_context_menu.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// The start that `_handlePlayVersion` makes itself, reached the way a viewer
/// reaches it: context menu, "Play version", the version picker, the quality
/// picker. A plain start of the same title runs while the refetch of the
/// menu start is still open, so the in-flight guard is all that stands
/// between the two.
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

  const versions = [
    MediaVersion(id: 'source_a', videoResolution: '1080', videoCodec: 'h264', container: 'mkv'),
    MediaVersion(id: 'source_b', videoResolution: '480', videoCodec: 'h264', container: 'mp4'),
  ];
  final movie = MediaItem(
    id: 'movie_1',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Movie 1',
    serverId: 'server_1',
    mediaVersions: versions,
  );
  const quality = TranscodeQualityPreset.p720_4mbps;

  Future<(GlobalKey<MediaContextMenuState>, _BlockingClient, _PlayerRouteSpy)> pumpMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
    final connections = ConnectionRegistry(db);
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: ProfileConnectionRegistry(db),
      plexHomeUserFetcher: (_) async => const [],
    );
    final activeProfileProvider = ActiveProfileProvider(
      registry: ProfileRegistry(db),
      plexHome: plexHome,
      connections: connections,
    );
    addTearDown(() async {
      activeProfileProvider.dispose();
      await plexHome.dispose();
      watchStateStore.dispose();
      offlineWatchSync.dispose();
      downloadProvider.dispose();
      multiServerProvider.dispose();
      await db.close();
    });

    final spy = _PlayerRouteSpy();
    final menuKey = GlobalKey<MediaContextMenuState>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
            ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
            ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            navigatorObservers: [spy],
            home: Scaffold(
              body: Center(
                child: MediaContextMenu(
                  key: menuKey,
                  item: movie,
                  child: const SizedBox(width: 120, height: 80, child: Text('target')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return (menuKey, client, spy);
  }

  /// Walks the real menu up to the tap on the quality row. That tap closes
  /// the quality picker, and `_handlePlayVersion` then starts playback.
  Future<void> playVersionFromMenu(WidgetTester tester, GlobalKey<MediaContextMenuState> menuKey) async {
    menuKey.currentState!.showContextMenu(tester.element(find.text('target')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.mediaMenu.playVersion));
    await tester.pumpAndSettle();

    // Two versions, so the version picker opens first.
    await tester.tap(find.text(versions.first.displayLabel));
    await tester.pumpAndSettle();

    // The backend can transcode, so the quality picker follows.
    final qualityRow = find.text(qualityPresetLabel(quality));
    await tester.ensureVisible(qualityRow);
    await tester.pumpAndSettle();
    await tester.tap(qualityRow);
    await tester.pumpAndSettle();
  }

  for (final plainFirst in [true, false]) {
    testWidgets('Play version from the context menu with a lower quality and a plain start are one start '
        '(${plainFirst ? 'plain' : 'menu'} first)', (tester) async {
      final (menuKey, client, spy) = await pumpMenu(tester);
      final hostContext = tester.element(find.text('target'));
      Future<bool?> plainStart() => navigateToVideoPlayer(hostContext, metadata: movie);

      Future<bool?>? plain;
      if (plainFirst) {
        plain = plainStart();
        await tester.pump();
        expect(client.fetchCalls, 1, reason: 'the plain start is waiting on the server');
      }

      await playVersionFromMenu(tester, menuKey);
      expect(client.fetchCalls, plainFirst ? 2 : 1, reason: 'the menu start reached the refetch');
      expect(spy.playerRoutes, isEmpty, reason: 'still preparing, so no player state answers for duplicates');

      if (!plainFirst) {
        plain = plainStart();
        await tester.pump();
      }

      while (client.hasPending) {
        client.release(movie);
      }
      await tester.pump();
      await tester.pump();

      expect(await plain, isNull, reason: 'the plain start is the duplicate in both orders');
      expect(spy.playerRoutes, hasLength(1));
      expect(tester.takeException(), isNull);

      // The one player that opens is the one the viewer configured in the menu.
      final screen = spy.playerScreen(hostContext);
      expect(screen.selectedMediaIndex, 0);
      expect(screen.selectedMediaSourceId, 'source_a');
      expect(screen.selectedQualityPreset, quality);
    });
  }
}

/// Records every push and drops only the player route: a real
/// [VideoPlayerScreen] would spin up mpv. The menu and its pickers stay.
class _PlayerRouteSpy extends NavigatorObserver {
  final playerRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != kVideoPlayerRouteName) return;
    playerRoutes.add(route);
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }

  /// The widget the only player route would have built, read without
  /// mounting it.
  VideoPlayerScreen playerScreen(BuildContext context) {
    final route = playerRoutes.single as PageRouteBuilder<bool>;
    return route.pageBuilder(context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation) as VideoPlayerScreen;
  }
}

class _BlockingClient implements MediaServerClient {
  int fetchCalls = 0;
  final _pending = <Completer<MediaItem?>>[];

  bool get hasPending => _pending.isNotEmpty;

  /// Answers the oldest open fetch.
  void release(MediaItem? item) => _pending.removeAt(0).complete(item);

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
