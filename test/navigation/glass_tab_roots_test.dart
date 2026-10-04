/// Review Focus 3 on real tab roots: with Liquid Glass on, `MobileMainScaffold`
/// extends the body under the floating bar, and each root has to read the
/// bar's height back as `MediaQuery` bottom padding. Before fixronde 1,
/// Settings (fixed 24 pt tail) and the Downloads grid (no bottom padding)
/// ended behind the capsule.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/download_models.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/providers/trackers_provider.dart';
import 'package:pleya/providers/trakt_account_provider.dart';
import 'package:pleya/screens/downloads/downloads_screen.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:provider/provider.dart';

import '../test_helpers/glass_phone.dart';
import '../test_helpers/prefs.dart';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConnectionRegistry extends ConnectionRegistry {
  _FakeConnectionRegistry(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);
}

/// Scrolls [scrollable] to its end, then the bottom of [last] must sit on or
/// above the top of the glass capsule.
Future<void> _expectClearOfBar(WidgetTester tester, Finder scrollable, Finder last) async {
  for (var i = 0; i < 20; i++) {
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
  final barTop = tester.getTopLeft(find.byType(GlassSurface)).dy;
  expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(barTop));
}

void main() {
  setUp(() => resetSharedPreferencesForTest());

  testWidgets('Instellingen: About eindigt boven de zwevende balk', (tester) async {
    await glassPhone(tester, glass: true);
    final manager = MultiServerManager();
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    // Not closed: see settings_screen_test.dart, the Profiles tile keeps a
    // drift watch open until the explicit unmount below.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(servers.dispose);

    await tester.pumpWidget(
      glassMainShell(
        (_) => const SettingsScreen(),
        wrapApp: (app) => TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
              ChangeNotifierProvider<TraktAccountProvider>(create: (_) => TraktAccountProvider()),
              ChangeNotifierProvider<TrackersProvider>(create: (_) => TrackersProvider()),
              ChangeNotifierProvider<SeerrProvider>(create: (_) => SeerrProvider()),
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
              ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile()),
            ],
            child: app,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await _expectClearOfBar(tester, find.byType(CustomScrollView).first, find.text(t.settings.about));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  group('Downloads', () {
    late AppDatabase db;
    late DownloadProvider downloads;
    late MultiServerProvider servers;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      JellyfinApiCache.initialize(db);
      downloads = DownloadProvider.forTesting(
        downloadManager: DownloadManagerService(
          database: db,
          storageService: DownloadStorageService.instance,
          clientResolver: (serverId, {clientScopeId}) => null,
        ),
        database: db,
      );
      final manager = MultiServerManager();
      servers = MultiServerProvider(manager, DataAggregationService(manager));
    });

    tearDown(() async {
      downloads.dispose();
      servers.dispose();
      await db.close();
    });

    testWidgets('films-raster: de laatste kaart eindigt boven de zwevende balk', (tester) async {
      await glassPhone(tester, glass: true);
      await tester.runAsync(downloads.ensureInitialized);
      const count = 30;
      downloads.debugSeedState(
        downloads: {
          for (var i = 0; i < count; i++)
            'srv:$i': DownloadProgress(globalKey: 'srv:$i', status: DownloadStatus.completed),
        },
        metadata: {
          for (var i = 0; i < count; i++)
            'srv:$i': MediaItem(
              id: '$i',
              backend: MediaBackend.plex,
              kind: MediaKind.movie,
              title: 'Movie $i',
              serverId: ServerId('srv'),
            ),
        },
      );
      final screenKey = GlobalKey<DownloadsScreenState>();

      await tester.pumpWidget(
        glassMainShell(
          (_) => DownloadsScreen(key: screenKey),
          wrapApp: (app) => InputModeTracker(
            child: MultiProvider(
              providers: [
                Provider<ConnectionRegistry>.value(value: _FakeConnectionRegistry(db)),
                ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
                ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              ],
              child: app,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      screenKey.currentState!.tabController.index = 2;
      await tester.pumpAndSettle();

      final grid = find.byType(GridView);
      expect(grid, findsOneWidget);
      await _expectClearOfBar(tester, grid, find.text('Movie ${count - 1}'));
    });
  });
}
