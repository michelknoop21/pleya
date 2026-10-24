/// A-24 (Apple TV+ Studio on iOS): the main Instellingen page on a phone.
///
/// The Studio header sits above the search field, the field is a filled bar
/// without an outline, values sit right-aligned before the chevron, and search
/// still finds the same destinations. The groups, their order and their
/// conditions are covered by `settings_screen_test.dart`.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

void main() {
  late AppDatabase db;
  setUpAll(() => db = AppDatabase.forTesting(NativeDatabase.memory()));

  Future<void> pumpSettings(WidgetTester tester, {double width = 375, double height = 2400}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
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
    await pumpSettings(tester);

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
  });

  testWidgets('values sit trailing: the theme on Weergave, the server line on Servers', (tester) async {
    await pumpSettings(tester);

    expect(
      find.ancestor(of: find.text(t.settings.oledTheme), matching: find.byType(SettingValueLabel)),
      findsOneWidget,
      reason: 'the theme (OLED by default) is the Weergave row value',
    );
    expect(
      find.ancestor(of: find.text(t.tvMyPleya.noServers), matching: find.byType(SettingValueLabel)),
      findsOneWidget,
    );
    expect(
      find.text('${t.settings.libraryDensity} ${SettingsService.instance.read(SettingsService.libraryDensity)}'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('search still finds the same destinations and hides the groups', (tester) async {
    await pumpSettings(tester);

    await tester.enterText(find.byType(TextField), 'trakt');
    await tester.pump();

    expect(find.text(t.settings.trackers), findsOneWidget);
    expect(find.text(t.settings.sectionLibrary.toUpperCase()), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz-geen-treffer');
    await tester.pump();
    expect(find.text(t.messages.noResultsFound), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('at 320 pt the header and every row lay out without overflow', (tester) async {
    await pumpSettings(tester, width: 320);
    expect(tester.takeException(), isNull);
    final title = tester.getRect(
      find.descendant(of: find.byType(SettingsStudioHeader), matching: find.text(t.settings.title)),
    );
    expect(title.right, lessThanOrEqualTo(320));
    await unmount(tester);
  });
}
