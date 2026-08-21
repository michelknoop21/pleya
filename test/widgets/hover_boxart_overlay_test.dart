import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/navigation/profile_navigation_scope.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/media_card.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// Records which navigator each route was pushed onto.
class _PushSpy extends NavigatorObserver {
  _PushSpy(this.name, this.pushes);

  final String name;
  final List<String> pushes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes.add(name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(false);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  /// Mirrors the app's navigator shape: a root navigator (MaterialApp) whose
  /// current route is the profile shell, and a *nested* profile navigator
  /// inside [ProfileNavigationScope]. Everything the browse UI opens belongs on
  /// the nested one — the scope only exists below the root navigator, and the
  /// hover preview is inserted into the root overlay, above both.
  ///
  /// Returns the list the observers append to.
  Future<List<String>> pumpHoveredCard(WidgetTester tester, {bool waitForPreview = true}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);
    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();

    final manager = MultiServerManager();
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    final offlineModeProvider = OfflineModeProvider(manager);
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
      watchStateStore.dispose();
      activeProfileProvider.dispose();
      await plexHome.dispose();
      offlineWatchSync.dispose();
      offlineModeProvider.dispose();
      downloadProvider.dispose();
      downloadManager.dispose();
      multiServerProvider.dispose();
      manager.dispose();
      await db.close();
    });

    final item = MediaItem(
      id: 'episode-1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Vuur',
      grandparentId: 'show-1',
      grandparentTitle: 'Amsterdam Empire',
      parentIndex: 1,
      index: 7,
      viewOffsetMs: 300000,
      durationMs: 2700000,
      serverId: 'server-1',
    );

    final pushes = <String>[];
    final profileNavigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineModeProvider),
            ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
            ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.macOS),
            navigatorObservers: [_PushSpy('root', pushes)],
            home: ProfileNavigationScope(
              navigatorKey: profileNavigatorKey,
              routeObserver: RouteObserver<PageRoute<dynamic>>(),
              mainScaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
              child: Navigator(
                key: profileNavigatorKey,
                observers: [_PushSpy('profile', pushes)],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 220,
                        height: 160,
                        child: MediaCard(item: item, forceGridMode: true, isInContinueWatching: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    pushes.clear();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(MediaCard)));
    await tester.pump();
    if (!waitForPreview) {
      // Still inside the hover dwell: the show timer is armed, nothing drawn yet.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Symbols.play_arrow_rounded), findsNothing);
      return pushes;
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    // The preview is up: its own copy of the title plus the three quick actions.
    expect(find.byIcon(Symbols.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.add_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.expand_more_rounded), findsOneWidget);

    return pushes;
  }

  Finder quickAction(IconData icon) => find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell)).first;

  testWidgets('the "more" quick action opens the detail route inside the profile navigator', (tester) async {
    final pushes = await pumpHoveredCard(tester);

    await tester.tap(quickAction(Symbols.expand_more_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Pushing with the preview's own context lands on the root navigator, and
    // the detail screen then throws in didChangeDependencies because
    // ProfileNavigationScope only exists below it — an error widget over the
    // whole window, which is what the black screen was.
    expect(tester.takeException(), isNull);
    expect(pushes, ['profile']);
  });

  testWidgets('the play quick action opens the player inside the profile navigator', (tester) async {
    final pushes = await pumpHoveredCard(tester);

    await tester.tap(quickAction(Symbols.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(pushes, ['profile']);
  });

  testWidgets('the "+" quick action takes the preview down before opening the menu', (tester) async {
    await pumpHoveredCard(tester);

    await tester.tap(quickAction(Symbols.add_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text(t.mediaMenu.markAsWatched), findsOneWidget);

    // The preview is gone, so nothing floats above the menu. Navigator.rearrange
    // hoists hand-inserted overlay entries above every route entry, so a preview
    // left standing would swallow the clicks on the entries it covers.
    expect(find.byIcon(Symbols.play_arrow_rounded), findsNothing);

    // And it must not grow back while the menu is open: the pointer is still
    // over the card, so removing the preview re-enters the card's hover region.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byIcon(Symbols.play_arrow_rounded), findsNothing);

    final buried = find.text(t.externalPlayer.playInExternalPlayer);
    expect(buried, findsOneWidget);
    await tester.tapAt(tester.getCenter(buried));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(t.mediaMenu.markAsWatched), findsNothing, reason: 'the menu entry must be clickable');
  });

  testWidgets('no preview grows on top of a menu opened during the hover dwell', (tester) async {
    await pumpHoveredCard(tester, waitForPreview: false);

    final click = await tester.startGesture(
      tester.getCenter(find.byType(MediaCard)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await click.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(t.mediaMenu.markAsWatched), findsOneWidget);

    // The armed show timer must not fire behind the menu's back: a preview
    // appearing now would sit on top of the menu and eat its clicks.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byIcon(Symbols.play_arrow_rounded), findsNothing);
  });
}
