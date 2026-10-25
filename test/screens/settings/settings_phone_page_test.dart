/// A-24 (Apple TV+ Studio on iOS): the main Instellingen page on a phone.
///
/// The Studio header sits above the search field, the field is a filled bar
/// without an outline, values sit right-aligned before the chevron, and search
/// still finds the same destinations. The groups, their order and their
/// conditions are covered by `settings_screen_test.dart`.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/focusable_text_field.dart';
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
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/settings/setting_value_label.dart';
import 'package:pleya/widgets/settings/settings_studio_header.dart';
import 'package:pleya/widgets/settings/settings_studio_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  _FakeActiveProfile(this._active);

  final Profile? _active;

  @override
  Profile? get active => _active;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _iPhone = TargetPlatformVariant.only(TargetPlatform.iOS);

void main() {
  late AppDatabase db;
  setUpAll(() => db = AppDatabase.forTesting(NativeDatabase.memory()));

  /// Points at 3x. An iPhone-sized view (812 or 568 high) reads as a phone to
  /// `PlatformDetector.isPhone`; the default 2400 high view, which builds every
  /// card at once, reads as a tablet and so shows the plain bar.
  Future<void> pumpSettings(WidgetTester tester, {double width = 375, double height = 2400}) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
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
            ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile(null)),
          ],
          child: MaterialApp(theme: monoTheme(dark: false), home: const SettingsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// See `settings_screen_test.dart`: the Profiles tile's drift `.watch()`
  /// leaves a zero-duration timer that must flush inside the test body.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the Studio header sits above a filled search bar without an outline', (tester) async {
    await pumpSettings(tester, height: 812);

    expect(find.byType(SettingsStudioHeader), findsOneWidget);
    final header = tester.getRect(find.byType(SettingsStudioHeader));
    final search = tester.getRect(find.byType(FocusableTextField));
    expect(header.bottom, lessThanOrEqualTo(search.top));

    final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(decoration.border, isNull, reason: 'no OutlineInputBorder; the theme fill draws the bar');
    final theme = Theme.of(tester.element(find.byType(TextField))).inputDecorationTheme;
    expect(theme.filled, isTrue);
    expect(theme.border, isA<OutlineInputBorder>().having((b) => b.borderSide, 'side', BorderSide.none));
    await unmount(tester);
  }, variant: _iPhone);

  testWidgets(
    'off the iPhone the page keeps the plain bar and the outlined search field',
    (tester) async {
      await pumpSettings(tester);

      expect(find.byType(SettingsStudioHeader), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(t.settings.title)), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.border, isA<OutlineInputBorder>());
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('A-24b: the page wears the Studio palette, the app around it keeps monoTheme', (tester) async {
    await pumpSettings(tester, height: 812);

    final page = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(page).scaffoldBackgroundColor, kStudioLightPage);
    expect(SettingsStudioTheme.isActive(page), isTrue);
    final app = tester.element(find.byType(SettingsScreen));
    expect(Theme.of(app).scaffoldBackgroundColor, const Color(0xFFF7F7F8), reason: 'only Instellingen is warm');
    await unmount(tester);
  }, variant: _iPhone);

  testWidgets('A-24b: the three Studio groups in order, one row per page, no values or lines', (tester) async {
    await pumpSettings(tester);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    final s = t.settingsStudio;
    expect(top(s.forYou.toUpperCase()), lessThan(top(s.connectionsAndProfiles.toUpperCase())));
    expect(top(s.connectionsAndProfiles.toUpperCase()), lessThan(top(s.system.toUpperCase())));
    final forYou = [
      t.settings.appearance,
      t.settings.videoPlayback,
      t.languageSettings.title,
      t.settings.subtitleStyling,
      s.libraries,
    ];
    for (var i = 1; i < forYou.length; i++) {
      expect(top(forYou[i - 1]), lessThan(top(forYou[i])), reason: '${forYou[i - 1]} before ${forYou[i]}');
    }
    expect(top(forYou.last), lessThan(top(s.connectionsAndProfiles.toUpperCase())));
    expect(top(s.integrations), greaterThan(top(s.connectionsAndProfiles.toUpperCase())));
    expect(top(s.serversAndSources), lessThan(top(s.system.toUpperCase())));
    expect(top(t.settings.advanced), greaterThan(top(s.system.toUpperCase())));
    expect(top(t.settings.about), greaterThan(top(t.settings.backup)));

    // The anchor's main page shows no values and no explanation lines.
    expect(find.byType(SettingValueLabel), findsNothing);
    expect(find.text(t.settings.oledTheme), findsNothing);
    expect(find.text(t.settings.videoPlaybackDescription), findsNothing);
    // The old groups are gone.
    expect(find.text(t.settings.sectionLibrary.toUpperCase()), findsNothing);
    await unmount(tester);
  });

  testWidgets('the explanation a row no longer shows is its VoiceOver hint', (tester) async {
    await pumpSettings(tester);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text(t.settings.videoPlayback)),
      containsSemantics(hint: t.settings.videoPlaybackDescription),
    );
    semantics.dispose();
    await unmount(tester);
  });

  testWidgets('search still finds the same destinations and hides the groups', (tester) async {
    await pumpSettings(tester);

    await tester.enterText(find.byType(TextField), 'trakt');
    await tester.pump();

    expect(find.text(t.settings.trackers), findsOneWidget);
    expect(find.text(t.settingsStudio.forYou.toUpperCase()), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz-geen-treffer');
    await tester.pump();
    expect(find.text(t.messages.noResultsFound), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('at 320 pt the header and every row lay out without overflow', (tester) async {
    await pumpSettings(tester, width: 320, height: 568);
    expect(tester.takeException(), isNull);
    final title = tester.getRect(
      find.descendant(of: find.byType(SettingsStudioHeader), matching: find.text(t.settings.title)),
    );
    expect(title.right, lessThanOrEqualTo(320));
    await unmount(tester);
  }, variant: _iPhone);
}
