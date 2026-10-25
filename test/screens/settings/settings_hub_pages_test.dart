/// A-24b: the main Instellingen page opens one page per row (anchor `01`,
/// series `ios/01`, `03`, `08`-`09`, `13`-`14`). Every row that left the main
/// page is on the page its new row opens, the destructive rows ask first, and
/// search still finds each page and each moved destination.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/providers/trackers_provider.dart';
import 'package:pleya/providers/trakt_account_provider.dart';
import 'package:pleya/screens/settings/library_home_settings_screen.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/settings_section.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  setUpAll(() => db = AppDatabase.forTesting(NativeDatabase.memory()));

  Future<void> pump(WidgetTester tester, {Widget home = const SettingsScreen()}) async {
    tester.view.physicalSize = const Size(393, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    resetSharedPreferencesForTest();
    await tester.runAsync(() => SettingsService.getInstance());
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
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
            Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
            ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile()),
          ],
          child: MaterialApp(theme: monoTheme(dark: true), home: home),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String row) async {
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  /// The row keeps the `settings.tile[...]` id it had on the main page.
  bool hasTile(String instance) => find
      .byWidgetPredicate((w) => w is AutomationNode && w.id == AutomationIds.settingsTile && w.instance == instance)
      .evaluate()
      .isNotEmpty;

  testWidgets('Bibliotheken opens Bibliotheek & Home with its rows inline, Studio and all', (tester) async {
    await pump(tester);
    await open(tester, t.settingsStudio.libraries);

    expect(find.text(t.settingsStudio.libraryAndHome), findsWidgets);
    final s = t.settingsStudio;
    // Series 03-02: the Home aanpassen actions; removing an own row and the
    // hidden Verder kijken titles only appear when there are some.
    for (final row in [
      t.settings.libraryVisibility,
      s.reorderRows,
      s.rowVisibility,
      s.addOwnRow,
      t.settings.downloads,
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text(s.removeOwnRow), findsNothing);
    expect(find.text(s.hiddenContinueWatching), findsNothing);
    expect(find.text(t.settings.homeLayout.toUpperCase()), findsOneWidget, reason: 'the group heading');
    expect(SettingsStudioTheme.isActive(tester.element(find.text(s.reorderRows))), isTrue);
    expect(hasTile('home_layout') && hasTile('downloads'), isTrue);

    await back(tester);
    expect(find.text(t.settingsStudio.forYou.toUpperCase()), findsOneWidget, reason: 'back on the main page');
  });

  testWidgets('on an Apple TV the hub has no Downloads, as the main page never had', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await pump(tester, home: const SettingsStudioTheme(child: LibraryHomeSettingsScreen()));
    // The TV rows are tall and built lazily, so read the cards from the list.
    final list = tester.widget<SliverList>(find.byType(SliverList).first).delegate as SliverChildListDelegate;
    final titles = [
      for (final child in list.children)
        if (child is SettingsWidthLimit && child.child is SettingsGroup) (child.child as SettingsGroup).title,
    ];
    expect(titles, [t.settingsStudio.libraries, t.settings.homeLayout]);
  });

  testWidgets('Koppelingen opens Trackers and Aanvragen; Tautulli only for a Plex owner', (tester) async {
    await pump(tester);
    await open(tester, t.settingsStudio.integrations);

    expect(find.text(t.settings.trackers), findsWidgets);
    expect(find.text(t.settings.requests), findsWidgets);
    expect(find.text(t.tautulli.title), findsNothing);
    expect(hasTile('trackers') && hasTile('requests'), isTrue);
  });

  testWidgets('Geavanceerd holds Onderhoud; Cache wissen asks before it clears', (tester) async {
    await pump(tester);
    await open(tester, t.settings.advanced);

    expect(find.text(t.settingsStudio.maintenance.toUpperCase()), findsOneWidget);
    for (final row in [
      t.settings.watchTogetherRelay,
      t.settings.crashReporting,
      t.settings.debugLogging,
      t.settings.viewLogs,
      t.settings.clearCache,
      t.settings.resetSettings,
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }

    await tester.tap(find.text(t.settings.clearCache));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'the confirmation comes before the clear');
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    final crashBefore = SettingsService.instance.read(SettingsService.crashReporting);
    await tester.tap(find.text(t.settings.crashReporting));
    await tester.pump();
    expect(SettingsService.instance.read(SettingsService.crashReporting), !crashBefore, reason: 'the switch writes');
  });

  testWidgets('Back-up holds export, import and the iCloud switch; import asks first', (tester) async {
    await pump(tester);
    await open(tester, t.settings.backup);

    expect(find.text(t.settings.exportSettings), findsOneWidget);
    expect(find.text(t.settings.importSettings), findsOneWidget);
    expect(find.text(t.settings.icloudSync), findsOneWidget, reason: 'the test host is Apple');

    await tester.tap(find.text(t.settings.importSettings));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
  });

  group('search finds each page and each moved destination', () {
    // The pages this harness can build are opened from the result too; the
    // others need providers of their own and are only found.
    for (final (query, title, opens) in [
      ('advanced', () => t.settings.advanced, true),
      ('crash', () => t.settings.advanced, true),
      ('icloud', () => t.settings.backup, true),
      ('library & home', () => t.settingsStudio.libraryAndHome, true),
      ('integrations', () => t.settingsStudio.integrations, true),
      ('offline', () => t.localLibrary.title, false),
      ('trakt', () => t.settings.trackers, false),
      ('seerr', () => t.settings.requests, false),
      ('sources', () => t.settingsStudio.serversAndSources, false),
      ('home', () => t.settings.homeLayout, false),
      ('download', () => t.settings.downloads, false),
    ]) {
      testWidgets('"$query"', (tester) async {
        await pump(tester);
        await tester.enterText(find.byType(TextField), query);
        await tester.pump();
        expect(find.text(title()), findsWidgets);
        if (!opens) return;

        await tester.tap(find.text(title()).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsNothing, reason: 'the result opened its page');
      });
    }
  });
}
