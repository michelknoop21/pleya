import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/screens/discover_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/watch_together/watch_together.dart';
import 'package:pleya/widgets/clickable_cursor.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// The discover billboard used to be one large hidden play button: a tap
/// anywhere on it called `navigateToMediaItem(playDirectly: true)`. Any stray
/// click — a menu label missed by a few pixels, a click that woke the window —
/// started a film. It opens the detail page now, and only the Afspelen pill
/// plays.
///
/// These tests drive the real [DiscoverScreen] in non-TV mode so they exercise
/// the shipped gesture and the real navigation call, not a stub.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(false);
    TvDetectionService.setForceTVSync(false);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// Pumps the screen and returns the observer that records pushed routes.
  Future<_RouteSpy> pumpDiscover(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final settings = await SettingsService.getInstance();
    // Pin the setting that used to turn the billboard tap into playback, so the
    // test cannot pass for the wrong reason.
    await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.play);

    // No artwork at all: `billboardArt` then returns null and the whole
    // CachedNetworkImage subtree is skipped, which keeps the fake client out of
    // image URL territory.
    final movie = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Movie 1',
      serverId: 'server_1',
      serverName: 'Server',
      durationMs: 7200000,
    );

    final client = _FakeHeroClient(movie);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    final librariesProvider = LibrariesProvider();
    final watchTogetherProvider = WatchTogetherProvider();
    final companionRemoteProvider = CompanionRemoteProvider();

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
    final offlineModeProvider = OfflineModeProvider(manager);
    final offlineWatchSync = OfflineWatchSyncService(database: db, serverManager: manager);
    final watchStateStore = WatchStateStore();
    final connectionRegistry = _FakeConnectionRegistry(db);
    final profileConnectionRegistry = _FakeProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connectionRegistry,
      profileConnections: profileConnectionRegistry,
      storage: storage,
      plexHomeUserFetcher: (_) async => const [],
    );
    final activeProfileProvider = ActiveProfileProvider(
      registry: _FakeProfileRegistry(db),
      plexHome: plexHome,
      connections: connectionRegistry,
      storage: storage,
    );
    final discoverProvider = DiscoverProvider(
      multiServerProvider,
      hiddenLibrariesProvider,
      librariesProvider,
      isProfileBinding: () => activeProfileProvider.isBinding,
    );

    addTearDown(() async {
      watchStateStore.dispose();
      offlineWatchSync.dispose();
      offlineModeProvider.dispose();
      downloadProvider.dispose();
      discoverProvider.dispose();
      activeProfileProvider.dispose();
      companionRemoteProvider.dispose();
      watchTogetherProvider.dispose();
      librariesProvider.dispose();
      hiddenLibrariesProvider.dispose();
      multiServerProvider.dispose();
      await plexHome.dispose();
      await db.close();
    });

    final spy = _RouteSpy();

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogetherProvider),
            ChangeNotifierProvider<CompanionRemoteProvider>.value(value: companionRemoteProvider),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discoverProvider),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineModeProvider),
            ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
            ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            navigatorObservers: [spy],
            home: MainScreenFocusScope(
              focusSidebar: () {},
              focusContent: () {},
              isSidebarFocused: false,
              sideNavigationWidth: 80,
              reservedSideNavigationWidth: 80,
              foregroundLeft: 80,
              foregroundWidth: 1200,
              viewportWidth: 1280,
              child: const DiscoverScreen(),
            ),
          ),
        ),
      ),
    );

    // Never pumpAndSettle: the hero carousel keeps rescheduling frames.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    return spy;
  }

  testWidgets('the hero play button still starts playback', (tester) async {
    final spy = await pumpDiscover(tester);
    expect(find.text('Movie 1'), findsOneWidget, reason: 'the hero rendered');
    spy.pushed.clear();

    final pill = find.ancestor(of: find.text(t.common.play), matching: find.byType(InkWell)).first;
    await tester.tapAt(tester.getCenter(pill));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(spy.names, contains(kVideoPlayerRouteName));
    expect(spy.pushed, hasLength(1), reason: 'the pill wins the arena; the billboard tap must not also fire');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping the billboard opens details instead of playing', (tester) async {
    final spy = await pumpDiscover(tester);
    expect(find.text('Movie 1'), findsOneWidget);
    spy.pushed.clear();

    final billboard = find.ancestor(of: find.text('Movie 1'), matching: find.byType(ClickableCursor)).first;
    final rect = tester.getRect(billboard);
    // Mid-height on the right: clear of the play pill bottom-left and of the
    // app bar actions in the top-right corner, both of which have their own tap.
    await tester.tapAt(Offset(rect.right - 60, rect.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      spy.names,
      isNot(contains(kVideoPlayerRouteName)),
      reason: 'the billboard opens the title; only the pill plays',
    );
    expect(spy.pushed, hasLength(1), reason: 'it does navigate somewhere: the detail page');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Records what the screen pushed, then drops it again.
///
/// The assertion is about which route the production code chose, not about the
/// destination rendering: a real [VideoPlayerScreen] would spin up mpv and a
/// real detail screen wants its own provider tree, neither of which says
/// anything about the gesture under test. The route is recorded before it is
/// removed, so nothing is hidden.
class _RouteSpy extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    if (previousRoute == null) return; // the home route itself
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }

  Iterable<String?> get names => pushed.map((route) => route.settings.name);
}

class _FakeHeroClient implements MediaServerClient {
  _FakeHeroClient(this.movie);

  final MediaItem movie;

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async => [movie];

  @override
  Future<List<MediaHub>> fetchGlobalHubs({int limit = defaultHubPreviewLimit, bool includePlaybackHubs = true}) async =>
      const [];

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRegistry extends ProfileRegistry {
  _FakeProfileRegistry(super.db);

  @override
  Stream<List<Profile>> watchProfiles() => Stream.value(const []);

  @override
  Future<List<Profile>> list() async => const [];
}

class _FakeConnectionRegistry extends ConnectionRegistry {
  _FakeConnectionRegistry(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);

  @override
  Future<List<Connection>> list() async => const [];
}

class _FakeProfileConnectionRegistry extends ProfileConnectionRegistry {
  _FakeProfileConnectionRegistry(super.db);

  @override
  Stream<List<ProfileConnection>> watchAll() => Stream.value(const []);
}
