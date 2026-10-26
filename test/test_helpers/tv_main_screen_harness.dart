/// `MainScreen` on a TV, as it ships: the real [ProfileSessionScreen] with
/// its default shell, so a test drives the chain the app runs
/// (`MainScreen` → `TvRootShell` → `TvTopNavigation` and the destinations).
/// Only the offline signal and the registries' database reads are faked.
///
/// Extracted from `main_screen_tv_offline_destination_test.dart` (OFF5/OFF6)
/// when A-24c needed the same shell for Instellingen and the account menu.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/navigation/profile_session_screen.dart';
import 'package:pleya/profiles/active_profile_binder.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/offline_watch_provider.dart';
import 'package:pleya/providers/shader_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/providers/user_profile_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

class TvMainScreenHarness {
  TvMainScreenHarness(this.tester, this.offline, this._teardown);

  final WidgetTester tester;
  final FakeTvOfflineMode offline;
  final Future<void> Function() _teardown;

  TvRootShell get shell => tester.widget<TvRootShell>(find.byType(TvRootShell));

  /// Never `pumpAndSettle`: the shell keeps timers (startup settle fallback,
  /// keyboard warm-up) that would make it spin.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Gives the profile a kijklijst source, so `hasWatchlist` is true and the
  /// Watchlist tab and tile exist. Waits out `WatchlistProvider.attach`'s own
  /// (empty) source build first, or it would overwrite this one.
  Future<void> enableWatchlist() async {
    final watchlist = Provider.of<WatchlistProvider>(tester.element(find.byType(TvRootShell)), listen: false);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      watchlist.repository = WatchlistRepository(sources: [_StubWatchlistSource()]);
      await watchlist.load();
    });
    await settle();
    expect(watchlist.hasWatchlist, isTrue);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _teardown();
  }
}

Future<TvMainScreenHarness> pumpTvMainScreen(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1920, 1080);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  late final TvMainScreenHarness harness;
  await tester.runAsync(() async {
    final settings = await SettingsService.getInstance();
    final storage = await StorageService.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);

    final connections = _FakeConnectionRegistry(db);
    final profileConnections = _FakeProfileConnectionRegistry(db);
    final profiles = ProfileRegistry(db);
    final owner = Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1));
    await profiles.upsert(owner);
    await storage.setActiveProfileId(owner.id);

    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => const [],
    );
    final activeProfile = ActiveProfileProvider(
      registry: profiles,
      plexHome: plexHome,
      connections: connections,
      storage: storage,
    );
    await activeProfile.initialize();

    final manager = MultiServerManager();
    final multiServer = FakeTvMultiServer(manager, DataAggregationService(manager));
    final offline = FakeTvOfflineMode(manager, multiServer);
    final binder = ActiveProfileBinder(
      activeProfile: activeProfile,
      connections: connections,
      profileConnections: profileConnections,
      serverManager: manager,
      multiServerProvider: multiServer,
      pinPrompt: (_, {String? errorMessage}) async => null,
      shouldDeferInitialBind: (_) async => false,
    );
    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    final downloads = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloads.ensureInitialized();
    final offlineSync = OfflineWatchSyncService(database: db, serverManager: manager);
    final offlineWatch = OfflineWatchProvider(syncService: offlineSync, downloadProvider: downloads);
    final userProfile = UserProfileProvider(storageService: storage);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            Provider<SettingsService>.value(value: settings),
            Provider<StorageService>.value(value: storage),
            Provider<AppDatabase>.value(value: db),
            Provider<ConnectionRegistry>.value(value: connections),
            Provider<ProfileRegistry>.value(value: profiles),
            Provider<ProfileConnectionRegistry>.value(value: profileConnections),
            Provider<PlexHomeService>.value(value: plexHome),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
            Provider<ActiveProfileBinder>.value(value: binder),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
            ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineSync),
            ChangeNotifierProvider<OfflineWatchProvider>.value(value: offlineWatch),
            ChangeNotifierProvider<UserProfileProvider>.value(value: userProfile),
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<ShaderProvider>(create: (_) => ShaderProvider()),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: const ProfileSessionScreen(initialPromptHandled: true),
          ),
        ),
      ),
    );

    harness = TvMainScreenHarness(tester, offline, () async {
      await tester.runAsync(() async {
        binder.dispose();
        offlineWatch.dispose();
        offlineSync.dispose();
        downloads.dispose();
        offline.dispose();
        activeProfile.dispose();
        multiServer.dispose();
        manager.dispose();
        await plexHome.dispose();
        await db.close();
      });
    });
  });
  // Let the startup profile bind settle before the viewer does anything: its
  // `_invalidateAllScreens` clears every nested route by design (profile
  // switch), and landing after a section was opened would read as OFF5.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await harness.settle();
  }
  return harness;
}

/// The offline signal, and nothing else. [MainScreen] listens to this provider
/// and reads [isOffline]; deriving it from real connectivity and server status
/// is `OfflineModeProvider`'s own test's job.
///
/// Going back online also marks a server as connected, because that is the
/// only way the real provider leaves offline mode (`noServerConnection` holds
/// until `hasConnectedServers`). Without it `MainScreen` takes its
/// "online but nothing connected" branch and forces a profile rebind, which is
/// a different path from the one OFF5 is about.
class FakeTvOfflineMode extends OfflineModeProvider {
  FakeTvOfflineMode(super.serverManager, this._servers) : super(multiServerProvider: _servers);

  final FakeTvMultiServer _servers;
  bool _offline = false;

  @override
  bool get isOffline => _offline;

  void set(bool value) {
    if (_offline == value) return;
    _offline = value;
    _servers.connected = !value;
    notifyListeners();
  }
}

class FakeTvMultiServer extends MultiServerProvider {
  FakeTvMultiServer(super.serverManager, super.aggregationService);

  bool connected = false;

  @override
  bool get hasConnectedServers => connected;
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

class _StubWatchlistSource implements WatchlistSource {
  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'local-owner', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async => const [];

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: item.id);

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}
