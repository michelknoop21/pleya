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
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/settings_service.dart' as settings_service show ThemeMode, ViewMode;
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/tv/tv_settings_categories.dart';
import 'package:pleya/widgets/tv/tv_settings_library_preview.dart';
import 'package:pleya/widgets/tv/tv_panel_primitives.dart';
import 'package:pleya/navigation/main_screen_scope.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/settings_tv_harness.dart';

late AppDatabase _db;

Future<void> _pumpTvSettings(WidgetTester tester, {MultiServerManager? manager, VoidCallback? openLibraries}) =>
    pumpTvSettings(tester, db: _db, manager: manager, openLibraries: openLibraries);

Future<void> _unmount(WidgetTester tester) => unmountTvSettings(tester);

Finder _wrapper(String id, String instance) =>
    find.byWidgetPredicate((w) => w is FocusableWrapper && w.automationId == id && w.automationInstance == instance);

Finder _row(String key) => _wrapper(AutomationIds.myPleyaSectionTile, 'settings.$key');

/// An inline preference row, under the id it has on its own page.
Finder _setting(String prefKey) => _wrapper(AutomationIds.myPleyaSectionTile, 'setting.$prefKey');
Finder _category(int index) => _wrapper(AutomationIds.settingsCategory, '$index');

/// The row's own node; a list row owns one inside its wrapper.
FocusNode _nodeOf(WidgetTester tester, Finder finder) =>
    tester.widget<FocusableWrapper>(finder).focusNode ??
    tester.widget<Focus>(find.descendant(of: finder, matching: find.byType(Focus)).first).focusNode!;

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

/// The shell handing the remote back to the page (DOWN from the top bar):
/// `TvNestedSurface.focusEntry` calls the screen's `focusActiveTabIfReady`.
Future<void> _restore(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  (tester.state(find.byType(SettingsScreen)) as FocusableTab).focusActiveTabIfReady();
  await tester.pump();
  await tester.pump();
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

    testWidgets('A-24b: the rail carries the series\' categories, each with its glyph', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      final titles = [
        for (var i = 0; _category(i).evaluate().isNotEmpty; i++)
          tester.widget<TvStudioCategoryPill>(
            find.descendant(of: _category(i), matching: find.byType(TvStudioCategoryPill)),
          ),
      ];
      expect(titles.map((p) => p.title), [
        t.settings.appearance,
        t.settings.videoPlayback,
        t.languageSettings.title,
        t.settingsStudio.libraries,
        t.settings.homeLayout,
        t.settingsStudio.integrations,
        t.settings.advanced,
      ]);
      expect(titles.every((p) => p.icon != null), isTrue);
      // Anchor 02: the tagline, Weergave's heading and the remote's key hint.
      expect(find.text(t.settingsStudio.tvTagline), findsOneWidget);
      expect(find.text(t.settingsStudio.appearanceHeadline), findsOneWidget);
      expect(find.text(t.settingsStudio.tvFooterHint), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Weergave shows its rows in place; RIGHT enters, DOWN crosses groups, LEFT returns', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);

      await _focus(tester, _category(0));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_hasFocus(tester, _setting('theme_mode')), isTrue);

      // From the last row of Scherm into the first row of Home.
      await _focus(tester, _setting('show_episode_number_on_cards'));
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_hasFocus(tester, _setting('tv_hero_clear_logo')), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_hasFocus(tester, _setting('show_episode_number_on_cards')), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_hasFocus(tester, _category(0)), isTrue);
      await _unmount(tester);
    });

    testWidgets('SELECT on a switch row flips it in place, one stop per row', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      final settings = SettingsService.instance;
      final glow = settings.read(SettingsService.focusGlow);

      await _focus(tester, _setting('focus_glow'));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(settings.read(SettingsService.focusGlow), !glow);
      expect(_hasFocus(tester, _setting('focus_glow')), isTrue);
      // The switch inside the row is not a stop of its own.
      final row = _nodeOf(tester, _setting('focus_glow'));
      expect(row.traversalDescendants.where((n) => n.canRequestFocus), isEmpty);

      final logging = settings.read(SettingsService.enableDebugLogging);
      await _choose(tester, t.settings.advanced);
      await _focus(tester, _row('debug_logging'));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(settings.read(SettingsService.enableDebugLogging), !logging);
      expect(_hasFocus(tester, _row('debug_logging')), isTrue);
      await _unmount(tester);
    });

    testWidgets('A-24b: RIGHT from a Weergave row reaches Bekijk voorbeeld, which opens Bibliotheken', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      var libraries = 0;
      await _pumpTvSettings(tester, openLibraries: () => libraries++);
      final button = find.widgetWithText(TvPanelButton, t.settingsStudio.viewPreview);
      expect(button, findsOneWidget);

      await _focus(tester, _setting('theme_mode'));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(Focus.of(tester.element(find.text(t.settingsStudio.viewPreview))).hasFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.select);
      expect(libraries, 1);
      await _unmount(tester);
    });

    testWidgets('the chosen category carries the marker, focus carries the ring', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      final marker = find.byKey(TvStudioCategoryPill.markerKey);

      await _focus(tester, _setting('theme_mode'));
      expect(find.descendant(of: _category(0), matching: marker), findsOneWidget);
      expect(_nodeOf(tester, _category(0)).hasFocus, isFalse);

      await _focus(tester, _category(1));
      expect(find.descendant(of: _category(1), matching: marker), findsNothing);
      final focusedPill = tester.widget<TvStudioCategoryPill>(
        find.descendant(of: _category(1), matching: find.byType(TvStudioCategoryPill)),
      );
      expect(focusedPill.focused, isTrue);
      expect(focusedPill.selected, isFalse);
      await _unmount(tester);
    });

    testWidgets('previews: Live voorbeeld on Weergave, Afspeelervaring on Afspelen, none on Geavanceerd', (
      tester,
    ) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      expect(
        find.descendant(
          of: find.byType(TvSettingsLibraryPreview),
          matching: find.text('${t.settingsStudio.oledMode} · ${t.settingsStudio.posterView}'),
        ),
        findsOneWidget,
      );
      // No DiscoverProvider here: the card falls back to its text.
      expect(
        find.descendant(of: find.byType(TvSettingsLibraryPreview), matching: find.byType(OptimizedMediaImage)),
        findsNothing,
      );
      await _choose(tester, t.settings.videoPlayback);
      expect(find.byType(TvSettingsPlaybackPreview), findsOneWidget);
      await _choose(tester, t.settings.advanced);
      expect(find.byType(TvSettingsLibraryPreview), findsNothing);
      expect(find.byType(TvSettingsPlaybackPreview), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Downloads has no row on Apple TV', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      await _choose(tester, t.settingsStudio.libraries);
      expect(find.text(t.settings.libraryVisibility), findsOneWidget);
      expect(find.text(t.settings.downloads), findsNothing);
      await _unmount(tester);
    });

    testWidgets('returning from a subpage restores the row', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      await _choose(tester, t.settings.advanced);
      await _focus(tester, _row('view_logs'));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(_row('view_logs'), findsNothing);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(_hasFocus(tester, _row('view_logs')), isTrue);
      await _unmount(tester);
    });

    testWidgets('a restore returns to the row the remote left from', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      await _choose(tester, t.settings.advanced);
      await _focus(tester, _row('debug_logging'));

      await _restore(tester);
      expect(_hasFocus(tester, _row('debug_logging')), isTrue);
      await _unmount(tester);
    });

    // Re-review m-1: the remote left from the rail after choosing another
    // category. The restore used to pull it back to the last row and flip the
    // chosen category back with it.
    testWidgets('a restore after a later rail choice returns to that category\'s pill', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      final advanced = _categoryIndex(tester, t.settings.advanced);
      final integrations = _categoryIndex(tester, t.settingsStudio.integrations);
      final marker = find.byKey(TvStudioCategoryPill.markerKey);

      await _choose(tester, t.settings.advanced);
      await _focus(tester, _row('debug_logging'));
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await _focus(tester, _category(integrations));
      await _press(tester, LogicalKeyboardKey.select);

      await _restore(tester);
      expect(_hasFocus(tester, _category(integrations)), isTrue);
      expect(find.descendant(of: _category(integrations), matching: marker), findsOneWidget);
      expect(find.descendant(of: _category(advanced), matching: marker), findsNothing);

      // Re-review m-2: SELECT on the category that holds the remembered row,
      // the one whose rows a stale request could pull the remote into. The
      // rail keeps it.
      await _focus(tester, _category(advanced));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump();
      expect(_row('debug_logging'), findsOneWidget);
      expect(_hasFocus(tester, _category(advanced)), isTrue);
      await _unmount(tester);
    });

    testWidgets('Tautulli is a row only for a Plex owner', (tester) async {
      await tester.runAsync(() => SettingsService.getInstance());
      await _pumpTvSettings(tester);
      await _choose(tester, t.settingsStudio.integrations);
      expect(find.text(t.settings.requests), findsWidgets);
      expect(find.text(t.tautulli.title), findsNothing);
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
      await _choose(tester, t.settingsStudio.integrations);
      expect(find.text(t.tautulli.title), findsWidgets);
      await _unmount(tester);
    });
  });

  testWidgets('Downloads is a row on a TV that is not an Apple TV', (tester) async {
    resetSharedPreferencesForTest();
    TvDetectionService.debugSetAppleTVOverride(false);
    TvDetectionService.debugSetTVOverride(true);
    addTearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      TvDetectionService.debugSetTVOverride(null);
    });
    await tester.runAsync(() => SettingsService.getInstance());
    await _pumpTvSettings(tester);
    await _choose(tester, t.settingsStudio.libraries);
    expect(find.text(t.settings.downloads), findsWidgets);
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

    Future<void> pumpCard(WidgetTester tester, List<MediaItem> items, {SettingsPreviewAction? action}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SizedBox(
              width: 520,
              child: TvSettingsPreviewCard(
                eyebrow: 'Live voorbeeld',
                title: 'Jouw bibliotheek',
                modeLine: 'Donkere modus · Posterweergave',
                items: items,
                action: action,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows posters, the title and the mode line when Home has items', (tester) async {
      await pumpCard(tester, [_poster('a', thumb: '/a'), _poster('b', thumb: '/b'), _poster('c', thumb: '/c')]);
      expect(find.byType(OptimizedMediaImage), findsNWidgets(3));
      expect(find.text('Jouw bibliotheek'), findsOneWidget);
      expect(find.text('Donkere modus · Posterweergave'), findsOneWidget);
    });

    testWidgets('without items it keeps its text and offers no button (the empty path)', (tester) async {
      await pumpCard(tester, const []);
      expect(find.byType(OptimizedMediaImage), findsNothing);
      expect(find.text('Jouw bibliotheek'), findsOneWidget);
      expect(find.text('Donkere modus · Posterweergave'), findsOneWidget);
      expect(find.byType(TvPanelButton), findsNothing);
    });

    testWidgets('an action is a button on the card that runs on SELECT', (tester) async {
      var opened = 0;
      await pumpCard(tester, const [], action: (label: 'Bekijk voorbeeld', onSelect: () => opened++));
      expect(find.widgetWithText(TvPanelButton, 'Bekijk voorbeeld'), findsOneWidget);
      // The remote's path: focus on the button, then SELECT.
      Focus.of(tester.element(find.text('Bekijk voorbeeld'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(opened, 1);
    });

    test('the mode line names the theme as a mode and the library view', () {
      expect(
        settingsPreviewModeLine(settings_service.ThemeMode.dark, settings_service.ViewMode.grid),
        '${t.settingsStudio.darkMode} · ${t.settingsStudio.posterView}',
      );
      expect(
        settingsPreviewModeLine(settings_service.ThemeMode.light, settings_service.ViewMode.list),
        '${t.settingsStudio.lightMode} · ${t.settingsStudio.listView}',
      );
    });

    testWidgets('"Bekijk voorbeeld" opens Bibliotheken through the shell, and is absent without one', (tester) async {
      var libraries = 0;
      SettingsPreviewAction? withShell;
      SettingsPreviewAction? withoutShell;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              MainScreenFocusScope(
                focusSidebar: () {},
                focusContent: () {},
                isSidebarFocused: false,
                sideNavigationWidth: 0,
                openLibraries: () => libraries++,
                child: Builder(
                  builder: (context) {
                    withShell = settingsViewPreviewAction(context);
                    return const SizedBox();
                  },
                ),
              ),
              Builder(
                builder: (context) {
                  withoutShell = settingsViewPreviewAction(context);
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );
      expect(withShell?.label, t.settingsStudio.viewPreview);
      withShell!.onSelect();
      expect(libraries, 1);
      expect(withoutShell, isNull);
    });
  });
}
