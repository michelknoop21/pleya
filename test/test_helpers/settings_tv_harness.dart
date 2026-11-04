/// Mounts the TV Instellingen page with the providers it reads, for the
/// settings page tests and the A-24 density test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
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
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Profile? get active => null;

  @override
  bool get hasMultipleProfiles => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pumps [SettingsScreen] in keyboard mode on a [window] at DPR 1.
///
/// [wrap] puts something between the app and the page, such as the frame a
/// nested TV route gives it. [openLibraries] or [focusSidebar] mount a
/// `MainScreenFocusScope` that answers "Bekijk voorbeeld" and the way up to
/// the top bar.
Future<void> pumpTvSettings(
  WidgetTester tester, {
  required AppDatabase db,
  MultiServerManager? manager,
  VoidCallback? openLibraries,
  VoidCallback? focusSidebar,
  Size window = const Size(1920, 1080),
  Widget Function(Widget page)? wrap,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final serverManager = manager ?? MultiServerManager();
  if (manager == null) addTearDown(serverManager.dispose);
  final servers = MultiServerProvider(serverManager, DataAggregationService(serverManager));
  addTearDown(servers.dispose);
  Widget page = const SettingsScreen();
  if (openLibraries != null || focusSidebar != null) {
    page = MainScreenFocusScope(
      focusSidebar: focusSidebar ?? () {},
      focusContent: () {},
      isSidebarFocused: false,
      sideNavigationWidth: 0,
      openLibraries: openLibraries,
      child: page,
    );
  }
  if (wrap != null) page = wrap(page);
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
          Provider<ConnectionRegistry>.value(value: ConnectionRegistry(db)),
          ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _FakeActiveProfile()),
        ],
        // Keyboard mode, so `focusActiveTabIfReady` acts as it does on a remote.
        child: InputModeTracker(
          child: MaterialApp(theme: monoTheme(dark: true), home: page),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// See `settings_screen_test.dart`: providers with timers must go before the
/// test body ends.
Future<void> unmountTvSettings(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
