/// A-24 PR 2: the TV settings page as categories (left), rows (middle) and a
/// preview (right, library only). Mounted without the TV shell, so subpages
/// fall back to an ordinary push, which is enough to prove focus comes back.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
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
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/tv/tv_settings_categories.dart';
import 'package:pleya/widgets/tv/tv_settings_library_preview.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

late AppDatabase _db;

Future<void> _pumpTvSettings(WidgetTester tester, {MultiServerManager? manager}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final serverManager = manager ?? MultiServerManager();
  if (manager == null) addTearDown(serverManager.dispose);
  final servers = MultiServerProvider(serverManager, DataAggregationService(serverManager));
  addTearDown(servers.dispose);
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<TraktAccountProvider>(
            create: (_) => TraktAccountProvider(kidsProfileCheck: () async => false),
          ),
          ChangeNotifierProvider<TrackersProvider>(create: (_) => TrackersProvider()),
          ChangeNotifierProvider<SeerrProvider>(create: (_) => SeerrProvider()),
          ChangeNotifierProvider<TautulliProvider>(create: (_) => TautulliProvider()),
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          Provider<ProfileRegistry>.value(value: ProfileRegistry(_db)),
          ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile()),
        ],
        child: MaterialApp(theme: monoTheme(dark: true), home: const SettingsScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// See `settings_screen_test.dart`: providers with timers must go before the
/// test body ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

Finder _wrapper(String id, String instance) =>
    find.byWidgetPredicate((w) => w is FocusableWrapper && w.automationId == id && w.automationInstance == instance);

Finder _row(String key) => _wrapper(AutomationIds.myPleyaSectionTile, 'settings.$key');
Finder _category(int index) => _wrapper(AutomationIds.settingsCategory, '$index');

FocusNode _nodeOf(WidgetTester tester, Finder finder) => tester.widget<FocusableWrapper>(finder).focusNode!;

bool _hasFocus(WidgetTester tester, Finder finder) => _nodeOf(tester, finder).hasPrimaryFocus;

int _categoryIndex(WidgetTester tester, String title) {
  for (var i = 0; i < 20; i++) {
    final pill = _category(i);
    if (pill.evaluate().isEmpty) break;
    if (find.descendant(of: pill, matching: find.text(title)).evaluate().isNotEmpty) return i;
  }
  fail('no category "$title"');
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

Future<void> _focus(WidgetTester tester, Finder finder) async {
  _nodeOf(tester, finder).requestFocus();
  await tester.pump();
}

/// Choose a category the way the remote does: focus it, then SELECT.
Future<void> _choose(WidgetTester tester, String title) async {
  await _focus(tester, _category(_categoryIndex(tester, title)));
  await _press(tester, LogicalKeyboardKey.select);
}

MediaItem _poster(String id, {String? thumb}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id, thumbPath: thumb, serverId: 'nas');

void main() {
  setUpAll(() => PlexApiCache.initialize(_db = AppDatabase.forTesting(NativeDatabase.memory())));

  group('Apple TV', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      TvDetectionService.debugSetAppleTVOverride(true);
    });
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('RIGHT from a category enters its first row, LEFT from a row returns to it', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);

      await _focus(tester, _category(0));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_hasFocus(tester, _row('appearance')), isTrue);

      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_hasFocus(tester, _row('home_layout')), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_hasFocus(tester, _category(0)), isTrue);

      // A later category: RIGHT lands on its own first row, LEFT goes back
      // to it and not to the first category.
      final advanced = _categoryIndex(tester, t.settings.advanced);
      await _focus(tester, _category(advanced));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_hasFocus(tester, _row('watch_together_relay')), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_hasFocus(tester, _category(advanced)), isTrue);
      await _unmount(tester);
    });

    testWidgets('SELECT on a preference row toggles it', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      final settings = SettingsService.instance;
      final before = settings.read(SettingsService.enableDebugLogging);

      await _choose(tester, t.settings.advanced);
      await _focus(tester, _row('debug_logging'));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(settings.read(SettingsService.enableDebugLogging), !before);
      expect(_hasFocus(tester, _row('debug_logging')), isTrue);
      await _unmount(tester);
    });

    testWidgets('the chosen category carries the marker, focus carries the ring', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      final marker = find.byKey(TvStudioCategoryPill.markerKey);

      // Remote in the rows: the chosen category shows its mark and no focus.
      await _focus(tester, _row('appearance'));
      expect(marker, findsOneWidget);
      expect(find.descendant(of: _category(0), matching: marker), findsOneWidget);
      expect(_nodeOf(tester, _category(0)).hasFocus, isFalse);

      // Remote on another category: that one has focus but not the mark.
      await _focus(tester, _category(1));
      expect(find.descendant(of: _category(1), matching: marker), findsNothing);
      expect(find.descendant(of: _category(0), matching: marker), findsOneWidget);
      final focusedPill = tester.widget<TvStudioCategoryPill>(
        find.descendant(of: _category(1), matching: find.byType(TvStudioCategoryPill)),
      );
      expect(focusedPill.focused, isTrue);
      expect(focusedPill.selected, isFalse);
      await _unmount(tester);
    });

    testWidgets('only the library category has a preview', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      expect(find.byType(TvSettingsLibraryPreview), findsOneWidget);
      // No DiscoverProvider here: the card falls back to its summary line.
      expect(
        find.descendant(of: find.byType(TvSettingsLibraryPreview), matching: find.byType(OptimizedMediaImage)),
        findsNothing,
      );

      await _choose(tester, t.settings.advanced);
      expect(_row('view_logs'), findsOneWidget);
      expect(find.byType(TvSettingsLibraryPreview), findsNothing);
      await _choose(tester, t.connections.sectionTitle);
      expect(find.byType(TvSettingsLibraryPreview), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Downloads is not a category on Apple TV', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      expect(find.text(t.settings.advanced), findsOneWidget);
      expect(find.text(t.settings.downloads), findsNothing);
      await _unmount(tester);
    });

    testWidgets('returning from a subpage restores the row and its category', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      await _choose(tester, t.settings.advanced);
      await _focus(tester, _row('view_logs'));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(_row('view_logs'), findsNothing);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(_row('view_logs'), findsOneWidget);
      expect(_hasFocus(tester, _row('view_logs')), isTrue);
      await _unmount(tester);
    });

    testWidgets('Tautulli is a row only for a Plex owner', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      expect(_row('appearance'), findsOneWidget);
      expect(_row('tautulli'), findsNothing);
      await _unmount(tester);

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
      await _pumpTvSettings(tester, manager: manager);
      expect(_row('tautulli'), findsOneWidget);
      await _unmount(tester);
    });
  });

  testWidgets('Downloads is a category on a TV that is not an Apple TV', (tester) async {
    resetSharedPreferencesForTest();
    TvDetectionService.debugSetAppleTVOverride(false);
    TvDetectionService.debugSetTVOverride(true);
    addTearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      TvDetectionService.debugSetTVOverride(null);
    });
    await tester.runAsync(() => SettingsService.getInstance());
    await _pumpTvSettings(tester);
    expect(find.text(t.settings.downloads), findsOneWidget);
    await _unmount(tester);
  });

  group('library preview', () {
    test('picks three distinct posters and skips items without one', () {
      final picked = pickSettingsPreviewPosters([
        _poster('a', thumb: '/a'),
        _poster('none'),
        _poster('a2', thumb: '/a'),
        _poster('b', thumb: '/b'),
        _poster('c', thumb: '/c'),
        _poster('d', thumb: '/d'),
      ]);
      expect(picked.map((i) => i.id), ['a', 'b', 'c']);
    });

    Future<void> pumpCard(WidgetTester tester, List<MediaItem> items) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SizedBox(
              width: 520,
              child: TvSettingsPreviewCard(title: 'Weergave', summary: 'Donker · Dichtheid 3', items: items),
            ),
          ),
        ),
      );
    }

    testWidgets('shows posters when Home has items', (tester) async {
      await pumpCard(tester, [_poster('a', thumb: '/a'), _poster('b', thumb: '/b'), _poster('c', thumb: '/c')]);
      expect(find.byType(OptimizedMediaImage), findsNWidgets(3));
      expect(find.text('Donker · Dichtheid 3'), findsOneWidget);
    });

    testWidgets('falls back to the summary line without items', (tester) async {
      await pumpCard(tester, const []);
      expect(find.byType(OptimizedMediaImage), findsNothing);
      expect(find.text('Donker · Dichtheid 3'), findsOneWidget);
    });
  });
}
