import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/metadata_edit/metadata_edit_adapters.dart';
import 'package:pleya/models/plex/plex_home_user.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/providers/watchlist_store.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/media_context_menu.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isAdminActionAllowedForMediaItem', () {
    test('blocks non-admin Plex Home users on Plex items', () {
      final profile = Profile.virtualPlexHome(connectionId: 'plex-1', homeUser: _homeUser(admin: false));

      expect(
        isAdminActionAllowedForMediaItem(isOwnerOrAdmin: true, itemBackend: MediaBackend.plex, activeProfile: profile),
        isFalse,
      );
    });

    test('does not apply Plex Home role to Jellyfin items', () {
      final profile = Profile.virtualPlexHome(connectionId: 'plex-1', homeUser: _homeUser(admin: false));

      expect(
        isAdminActionAllowedForMediaItem(
          isOwnerOrAdmin: true,
          itemBackend: MediaBackend.jellyfin,
          activeProfile: profile,
        ),
        isTrue,
      );
    });

    test('allows Plex admin Home users on Plex items', () {
      final profile = Profile.virtualPlexHome(connectionId: 'plex-1', homeUser: _homeUser(admin: true));

      expect(
        isAdminActionAllowedForMediaItem(isOwnerOrAdmin: true, itemBackend: MediaBackend.plex, activeProfile: profile),
        isTrue,
      );
    });
  });

  group('supportsMetadataEdit', () {
    test('allows Jellyfin video metadata edit through capability gate', () {
      final client = JellyfinClient.forTesting(
        connection: _jellyfinConnection(),
        httpClient: MockClient((_) async => http.Response('', 204)),
      );
      addTearDown(client.close);

      expect(supportsMetadataEdit(client, MediaKind.movie), isTrue);
      expect(supportsMetadataEdit(client, MediaKind.show), isTrue);
      expect(supportsMetadataEdit(client, MediaKind.track), isFalse);
    });
  });

  group('MediaContextMenu actions', () {
    testWidgets('file info client resolution failure shows an error without popping another route', (tester) async {
      LocaleSettings.setLocaleSync(AppLocale.en);
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final manager = MultiServerManager();
      final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
      final connections = ConnectionRegistry(db);
      final profileConnections = ProfileConnectionRegistry(db);
      final plexHome = PlexHomeService(
        connections: connections,
        profileConnections: profileConnections,
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
        multiServerProvider.dispose();
        manager.dispose();
        await db.close();
      });

      final menuKey = GlobalKey<MediaContextMenuState>();
      final item = MediaItem(
        id: 'movie-1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Movie',
        serverId: 'missing-server',
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: Center(
                  child: MediaContextMenu(
                    key: menuKey,
                    item: item,
                    child: const SizedBox(width: 120, height: 80, child: Text('target')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      menuKey.currentState!.showContextMenu(tester.element(find.text('target')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.mediaMenu.fileInfo));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // No NoticeHost is mounted in this widget tree, so the failure surfaces
      // on the global controller's model rather than as a widget in the tree.
      expect(noticeController.visible, isNotEmpty);
      addTearDown(() {
        for (final entry in noticeController.visible.toList()) {
          noticeController.dismiss(entry.id);
        }
      });
      expect(find.text('target'), findsOneWidget);
    });
  });

  group('MediaContextMenu watchlist action', () {
    late AppDatabase db;
    late MultiServerManager manager;
    late MultiServerProvider multiServerProvider;
    late ActiveProfileProvider activeProfileProvider;
    late PlexHomeService plexHome;
    late WatchlistProvider watchlistProvider;
    late WatchlistStore watchlistStore;

    setUp(() {
      LocaleSettings.setLocaleSync(AppLocale.en);
      // Apple TV keeps the download entries out of the menu, so what is left is
      // the neutral set this test is about.
      TvDetectionService.debugSetAppleTVOverride(true);

      db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      manager = MultiServerManager();
      multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
      final connections = ConnectionRegistry(db);
      plexHome = PlexHomeService(
        connections: connections,
        profileConnections: ProfileConnectionRegistry(db),
        plexHomeUserFetcher: (_) async => const [],
      );
      activeProfileProvider = ActiveProfileProvider(
        registry: ProfileRegistry(db),
        plexHome: plexHome,
        connections: connections,
      );
      watchlistProvider = WatchlistProvider(
        snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
        repository: WatchlistRepository(sources: [_AcceptingSource()]),
      );
      watchlistStore = WatchlistStore();
    });

    tearDown(() async {
      TvDetectionService.debugSetAppleTVOverride(null);
      watchlistStore.dispose();
      watchlistProvider.dispose();
      activeProfileProvider.dispose();
      await plexHome.dispose();
      multiServerProvider.dispose();
      manager.dispose();
      await db.close();
    });

    MediaItem plexItem(MediaKind kind) => MediaItem(
      id: 'item-1',
      backend: MediaBackend.plex,
      kind: kind,
      title: 'Sintel',
      guid: 'plex://movie/abc',
      serverId: 'server-1',
    );

    Future<void> openMenu(WidgetTester tester, MediaItem item, {OfflineModeProvider? offline}) async {
      final menuKey = GlobalKey<MediaContextMenuState>();
      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
              ChangeNotifierProvider<WatchlistProvider>.value(value: watchlistProvider),
              ChangeNotifierProvider<WatchlistStore>.value(value: watchlistStore),
              if (offline != null) ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: Center(
                  child: MediaContextMenu(
                    key: menuKey,
                    item: item,
                    child: const SizedBox(width: 120, height: 80, child: Text('target')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      menuKey.currentState!.showContextMenu(tester.element(find.text('target')));
      await tester.pumpAndSettle();
    }

    testWidgets('offers Add for a movie', (tester) async {
      await openMenu(tester, plexItem(MediaKind.movie));
      expect(find.text(t.watchlist.add), findsOneWidget);
    });

    testWidgets('offers Add for a show', (tester) async {
      await openMenu(tester, plexItem(MediaKind.show));
      expect(find.text(t.watchlist.add), findsOneWidget);
    });

    testWidgets('leaves episodes alone', (tester) async {
      await openMenu(tester, plexItem(MediaKind.episode));
      expect(find.text(t.watchlist.add), findsNothing);
      expect(find.text(t.watchlist.remove), findsNothing);
    });

    testWidgets('leaves seasons alone', (tester) async {
      await openMenu(tester, plexItem(MediaKind.season));
      expect(find.text(t.watchlist.add), findsNothing);
      expect(find.text(t.watchlist.remove), findsNothing);
    });

    testWidgets('says Remove once the title is on the list', (tester) async {
      watchlistStore.patch('plex:abc', onList: true);
      await watchlistProvider.addToWatchlist(plexItem(MediaKind.movie), isOffline: false);

      await openMenu(tester, plexItem(MediaKind.movie));

      expect(find.text(t.watchlist.remove), findsOneWidget);
      expect(find.text(t.watchlist.add), findsNothing);
    });

    testWidgets('hides the action offline instead of letting it fail', (tester) async {
      final offline = OfflineModeProvider(manager, multiServerProvider: multiServerProvider);
      addTearDown(offline.dispose);
      multiServerProvider.setExpectedVisibleServerIds({'server-1'});
      multiServerProvider.setVisibleServerIds(<String>{});
      expect(offline.isOffline, isTrue, reason: 'the offline state under test has to be real');

      await openMenu(tester, plexItem(MediaKind.movie), offline: offline);

      // A watchlist write is refused offline rather than queued, so the menu
      // does not offer one.
      expect(find.text(t.watchlist.add), findsNothing);
      expect(find.text(t.watchlist.remove), findsNothing);
    });
  });
}

/// Takes every title, so the menu's own gates are what the tests measure.
class _AcceptingSource implements WatchlistSource {
  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'acc', userId: 'usr');

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async => const [];

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: 'abc');

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

PlexHomeUser _homeUser({required bool admin}) {
  return PlexHomeUser(
    id: 0,
    uuid: 'home-user',
    title: 'Home User',
    username: null,
    email: null,
    friendlyName: null,
    thumb: 'https://plex.tv/users/home-user/avatar',
    hasPassword: false,
    restricted: false,
    updatedAt: null,
    admin: admin,
    guest: false,
    protected: false,
  );
}

JellyfinConnection _jellyfinConnection() {
  return JellyfinConnection(
    id: 'srv-1/user-1',
    baseUrl: 'https://jf.example.com',
    serverName: 'Home',
    serverMachineId: 'srv-1',
    userId: 'user-1',
    userName: 'edde',
    accessToken: 'tok',
    deviceId: 'dev',
    isAdministrator: true,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
