/// A real [MediaContextMenu] on a fake server, off TV unless a test says so:
/// the download rows need their provider there, and the Watch row its player
/// route, which [MenuPlayerSpy] drops before mpv would spin up.
library;

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
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/widgets/media_context_menu.dart';
import 'package:pleya/widgets/mobile/library_phone_look.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

class MenuFakeClient implements MediaServerClient {
  MenuFakeClient({
    this.backend = MediaBackend.plex,
    this.capabilities = ServerCapabilities.plex,
    this.onDeck,
    this.children = const {},
  });

  @override
  final MediaBackend backend;

  @override
  final ServerCapabilities capabilities;

  final MediaItem? onDeck;
  final Map<String, List<MediaItem>> children;

  @override
  ServerId get serverId => ServerId('server-1');

  @override
  String? get serverName => 'Server';

  @override
  void close() {}

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: null, onDeckEpisode: onDeck);

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => children[parentId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MenuAuthorityManager extends MultiServerManager {
  bool canManage = false;

  @override
  bool canManageServerMetadata(ServerId serverId) => canManage;
}

/// Records every push and drops only the player route.
class MenuPlayerSpy extends NavigatorObserver {
  final playerRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != kVideoPlayerRouteName) return;
    playerRoutes.add(route);
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }
}

class MenuHarness {
  MenuHarness._(this.menuKey, this.spy);

  final GlobalKey<MediaContextMenuState> menuKey;
  final MenuPlayerSpy spy;

  /// Pumps the menu around a 120 x 80 'target' and opens it.
  static Future<MenuHarness> open(
    WidgetTester tester, {
    required Object item,
    required MediaServerClient client,
    bool canManage = false,
    bool phoneLook = false,
    String? collectionId,
    Size size = const Size(402, 874),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await SettingsService.getInstance();
    final manager = MenuAuthorityManager()
      ..canManage = canManage
      ..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    final downloads = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloads.ensureInitialized();
    final offlineSync = OfflineWatchSyncService(database: db, serverManager: manager);
    final watchState = WatchStateStore();
    final connections = ConnectionRegistry(db);
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: ProfileConnectionRegistry(db),
      plexHomeUserFetcher: (_) async => const [],
    );
    final profile = ActiveProfileProvider(registry: ProfileRegistry(db), plexHome: plexHome, connections: connections);
    addTearDown(() async {
      profile.dispose();
      await plexHome.dispose();
      watchState.dispose();
      offlineSync.dispose();
      downloads.dispose();
      multiServer.dispose();
      await db.close();
    });

    final spy = MenuPlayerSpy();
    final menuKey = GlobalKey<MediaContextMenuState>();
    final menu = MediaContextMenu(
      key: menuKey,
      item: item,
      collectionId: collectionId,
      child: const SizedBox(width: 120, height: 80, child: Text('target')),
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
            ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineSync),
            ChangeNotifierProvider<WatchStateStore>.value(value: watchState),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            navigatorObservers: [spy],
            home: OverlaySheetHost(
              child: Scaffold(
                body: Center(child: phoneLook ? LibraryPhoneLook(child: menu) : menu),
              ),
            ),
          ),
        ),
      ),
    );
    menuKey.currentState!.showContextMenu(tester.element(find.text('target')));
    await tester.pumpAndSettle();
    return MenuHarness._(menuKey, spy);
  }
}
