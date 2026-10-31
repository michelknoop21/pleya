/// Geavanceerd ▸ Privacy on TV: the switch for Discussies, where the section can
/// show and nowhere else.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
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
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/trakt/trakt_comments_client.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_settings_categories.dart';
import 'package:pleya/widgets/tv/tv_settings_rows.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => null;

  @override
  bool get hasMultipleProfiles => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  setUpAll(() => db = AppDatabase.forTesting(NativeDatabase.memory()));

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    TraktCommentsClient.shared = TraktCommentsClient(
      clientId: 'app-key',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TraktCommentsClient.shared = TraktCommentsClient();
  });

  Future<void> pumpAdvanced(WidgetTester tester, {bool kids = false}) async {
    const canvas = Size(1038, 584);
    tester.view.physicalSize = canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await tester.runAsync(() => SettingsService.getInstance());
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    final account = TraktAccountProvider(kidsProfileCheck: () async => kids);
    addTearDown(account.dispose);
    // Not for an adult: that goes on to the keychain, which a test does not have.
    if (kids) await tester.runAsync(() => account.reevaluateKidsGate());
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<TraktAccountProvider>.value(value: account),
            ChangeNotifierProvider<TrackersProvider>(create: (_) => TrackersProvider()),
            ChangeNotifierProvider<SeerrProvider>(create: (_) => SeerrProvider()),
            ChangeNotifierProvider<TautulliProvider>(create: (_) => TautulliProvider()),
            ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
            Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
            ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile()),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: TvDisplayMetrics(size: canvas, child: const SettingsScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    tester.state<TvSettingsCategoriesState>(find.byType(TvSettingsCategories)).choose('advanced');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the switch stands under Privacy, is on, and Select turns it off', (tester) async {
    await pumpAdvanced(tester);

    expect(find.text(t.settings.privacy.toUpperCase(), skipOffstage: false), findsOneWidget);
    final row = find.text(t.settings.showTraktDiscussions, skipOffstage: false);
    expect(row, findsOneWidget);
    expect(SettingsService.instance.read(SettingsService.showTraktDiscussions), isTrue);

    final item = tester
        .widgetList<TvSettingsRowList>(find.byType(TvSettingsRowList))
        .expand((list) => list.items)
        .firstWhere((item) => item.title == t.settings.showTraktDiscussions);
    await tester.runAsync(() async => item.onSelect!());
    await tester.pump();

    expect(SettingsService.instance.read(SettingsService.showTraktDiscussions), isFalse);
    await unmount(tester);
  });

  testWidgets('a children\'s profile has no such switch', (tester) async {
    await pumpAdvanced(tester, kids: true);

    expect(find.text(t.settings.showTraktDiscussions), findsNothing);
    await unmount(tester);
  });

  testWidgets('a build without an app key has no such switch', (tester) async {
    TraktCommentsClient.shared = TraktCommentsClient(clientId: '');
    await pumpAdvanced(tester);

    expect(find.text(t.settings.showTraktDiscussions), findsNothing);
    await unmount(tester);
  });
}
