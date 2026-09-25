/// The main mobile/desktop `SettingsScreen` list (northstar 14) never had a
/// widget test of its own: every existing `test/screens/settings/*_test.dart`
/// covers a destination it pushes to, not the list itself. This is the
/// minimal harness that mounts it and proves the automation ids the
/// northstar-14 Verify scenario needs actually resolve, the same shape
/// `my_pleya_screen_test.dart` and `mobile_libraries_screen_test.dart` use
/// for their own screens.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/automation/automation_screen.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/providers/trackers_provider.dart';
import 'package:pleya/providers/trakt_account_provider.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const bool _verifyOn = bool.fromEnvironment('PLEYA_VERIFY');
const String _skipReason = 'run with --dart-define=PLEYA_VERIFY=true';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  _FakeActiveProfile(this._active);

  final Profile? _active;

  @override
  Profile? get active => _active;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Tautulli tile: owner rights on a Plex server', () {
    late AppDatabase db;
    setUpAll(() => PlexApiCache.initialize(db = AppDatabase.forTesting(NativeDatabase.memory())));

    Future<void> pumpSettings(WidgetTester tester, MultiServerManager manager) async {
      tester.view.physicalSize = const Size(393, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final servers = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(servers.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
              ChangeNotifierProvider<TraktAccountProvider>(create: (_) => TraktAccountProvider()),
              ChangeNotifierProvider<TrackersProvider>(create: (_) => TrackersProvider()),
              ChangeNotifierProvider<SeerrProvider>(create: (_) => SeerrProvider()),
              ChangeNotifierProvider<TautulliProvider>(create: (_) => TautulliProvider()),
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
              ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile(null)),
            ],
            child: MaterialApp(theme: monoTheme(dark: true), home: const SettingsScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// See the Verify test below for why the unmount happens in the body.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('a Jellyfin-only administrator does not see the tile', (tester) async {
      resetSharedPreferencesForTest();
      await tester.runAsync(() => SettingsService.getInstance());
      final manager = MultiServerManager();
      manager.debugRegisterJellyfinClientForTesting(
        JellyfinClient.forTesting(
          connection: JellyfinConnection(
            id: 'jf-machine/admin',
            baseUrl: 'https://jellyfin.local',
            serverName: 'Jellyfin',
            serverMachineId: 'jf-machine',
            userId: 'admin',
            userName: 'admin',
            accessToken: 'token',
            deviceId: 'device-1',
            isAdministrator: true,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      addTearDown(manager.dispose);
      expect(manager.canManageServerMetadata(ServerId('jf-machine')), isTrue);

      await pumpSettings(tester, manager);
      expect(find.text(t.tautulli.title), findsNothing);
      await unmount(tester);
    });

    testWidgets('the Plex owner sees the tile', (tester) async {
      resetSharedPreferencesForTest();
      await tester.runAsync(() => SettingsService.getInstance());
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(
        PlexClient.forTesting(
          config: PlexConfig(
            baseUrl: 'https://plex.example',
            token: 'token',
            clientIdentifier: 'client-id',
            product: 'Pleya',
            version: '1.0.0',
          ),
          serverId: ServerId('server-1'),
          serverName: 'Plex',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      await tester.runAsync(
        () => manager.refreshTokensForProfile(
          PlexAccountConnection(
            id: 'account-1',
            accountToken: 'account-token',
            clientIdentifier: 'account-client',
            accountLabel: 'Account',
            servers: [
              PlexServer(
                name: 'Plex',
                clientIdentifier: 'server-1',
                accessToken: 'token',
                connections: const [],
                owned: true,
              ),
            ],
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ),
      );
      expect(manager.managesAPlexServer, isTrue);

      await pumpSettings(tester, manager);
      expect(find.text(t.tautulli.title), findsOneWidget);
      await unmount(tester);
    });
  });

  group(
    'screen.settings en zijn tegels registreren de ids het northstar-scenario nodig heeft',
    () {
      testWidgets('screen.settings wordt ready, en elke top-level tegel is als node te vinden', (tester) async {
        // Tall enough that every tile in all three cards builds in one pass:
        // `CustomScrollView`'s `SliverList` only builds what is near the
        // viewport, so the default test surface leaves Servers (the last
        // card) unbuilt and absent from the declared snapshot.
        tester.view.physicalSize = const Size(393, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        resetSharedPreferencesForTest();
        await tester.runAsync(() => SettingsService.getInstance());

        final manager = MultiServerManager();
        final aggregation = DataAggregationService(manager);
        final servers = MultiServerProvider(manager, aggregation);
        // Not closed in tearDown: the Profiles tile's `StreamBuilder` is
        // still subscribed to this in-memory db's `.watch()` query at that
        // point, and closing it there schedules a zero-duration drift
        // cancellation timer with no further `pump()` left to flush it,
        // which fails flutter_test's pending-timer check. An unclosed
        // in-memory database has nothing to leak once the test process exits.
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(servers.dispose);

        await tester.pumpWidget(
          TranslationProvider(
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
                ChangeNotifierProvider<TraktAccountProvider>(create: (_) => TraktAccountProvider()),
                ChangeNotifierProvider<TrackersProvider>(create: (_) => TrackersProvider()),
                ChangeNotifierProvider<SeerrProvider>(create: (_) => SeerrProvider()),
                ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
                Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
                ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile(null)),
              ],
              child: MaterialApp(theme: monoTheme(dark: true), home: const SettingsScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final screens = AutomationScreenRegistry.instance.snapshot();
        final screen = screens.firstWhere(
          (s) => s['id'] == AutomationIds.screenSettings,
          orElse: () => throw StateError('screen.settings ontbreekt op de mobiele Instellingen'),
        );
        expect(screen['ready'], isTrue);

        final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
        const expectedTiles = [
          'appearance',
          'home_layout',
          'playback',
          'language',
          'subtitle_styling',
          'downloads',
          'trackers',
          'requests',
          'profiles',
          'servers',
        ];
        for (final instance in expectedTiles) {
          declared.firstWhere(
            (n) => n['id'] == '${AutomationIds.settingsTile}[$instance]',
            orElse: () => throw StateError('settings.tile[$instance] ontbreekt op Instellingen'),
          );
        }

        // Unmount deliberately, inside the test body: the Profiles tile's
        // `StreamBuilder` sits on a drift `.watch()` query, whose cancel
        // schedules a zero-duration timer on dispose. Leaving that to the
        // framework's own automatic teardown fires the timer after the last
        // `pump()`, which flutter_test's pending-timer check then fails on.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1));
      });
    },
    skip: _verifyOn ? false : _skipReason,
  );
}
