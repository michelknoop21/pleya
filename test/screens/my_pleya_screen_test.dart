import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/screens/my_pleya_screen.dart';
import 'package:pleya/screens/profile/profile_switch_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';

/// My Pleya became the mobile home of Profiles, Settings and Sign out when the
/// avatar left the Home header. These check that all three arrived, that they
/// point at the flows that already existed, and that the identity on top is the
/// live one.
class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  _FakeActiveProfile(this._active);

  Profile? _active;

  @override
  Profile? get active => _active;

  set activeProfile(Profile? value) {
    _active = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineProvider extends ChangeNotifier implements OfflineModeProvider {
  @override
  bool get isOffline => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records pushes so a test can inspect where a row leads without mounting the
/// destination. [ProfileSwitchScreen] wants the whole profile/connection
/// provider stack; building it here would test that stack, not this screen.
class _RouteRecorder extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

Profile _profile(String name) => Profile.local(id: name, displayName: name, createdAt: DateTime.utc(2026, 8, 17));

void main() {
  late _FakeActiveProfile activeProfile;
  late List<NavigationTabId> opened;
  late _RouteRecorder routes;

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    opened = [];
    routes = _RouteRecorder();
  });

  Future<void> pumpScreen(WidgetTester tester, {Profile? profile, bool offline = false}) async {
    activeProfile = _FakeActiveProfile(profile ?? _profile('Gideuh'));
    addTearDown(activeProfile.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          navigatorObservers: [routes],
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
              if (offline) ChangeNotifierProvider<OfflineModeProvider>(create: (_) => _OfflineProvider()),
            ],
            child: MyPleyaScreen(onOpenTab: opened.add),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the header names whoever is signed in, with their own avatar', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Gideuh'), findsOneWidget);
    final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar).first);
    expect(avatar.profile?.displayName, 'Gideuh');
    expect(avatar.size, 40);
  });

  testWidgets('switching profile updates the header without a restart', (tester) async {
    await pumpScreen(tester);

    activeProfile.activeProfile = _profile('Michel');
    await tester.pump();

    expect(find.text('Michel'), findsOneWidget);
    expect(find.text('Gideuh'), findsNothing);
  });

  testWidgets('all three account actions from the old header menu are here', (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.profiles.sectionTitle), findsOneWidget);
    expect(find.text(t.common.settings), findsOneWidget);
    expect(find.text(t.common.logout), findsOneWidget);
  });

  /// The widget the last pushed route would build. Not pumped: see
  /// [_RouteRecorder].
  Widget pushedScreen(WidgetTester tester) {
    final route = routes.pushed.last as MaterialPageRoute<dynamic>;
    return route.builder(tester.element(find.byType(MyPleyaScreen)));
  }

  testWidgets('Profiles opens the existing profile screen, not a second switcher', (tester) async {
    await pumpScreen(tester);
    routes.pushed.clear();

    await tester.tap(find.text(t.profiles.sectionTitle));

    expect(pushedScreen(tester), isA<ProfileSwitchScreen>());
  });

  testWidgets('tapping the identity opens that same screen', (tester) async {
    await pumpScreen(tester);
    routes.pushed.clear();

    await tester.tap(find.text('Gideuh'));

    expect(pushedScreen(tester), isA<ProfileSwitchScreen>());
  });

  testWidgets('Settings goes through the tab the screen already used', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(t.common.settings));
    await tester.pump();

    // A tab switch, not a pushed route: the bar's projection lights My Pleya
    // while Settings is on screen, and a push would break that.
    expect(opened, [NavigationTabId.settings]);
  });

  testWidgets('Sign out asks first, and asking is the existing confirmation', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(t.common.logout));
    await tester.pumpAndSettle();

    expect(find.text(t.messages.logoutConfirm), findsOneWidget);

    // Backing out leaves the session alone.
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    expect(find.text(t.messages.logoutConfirm), findsNothing);
    expect(find.text('Gideuh'), findsOneWidget);
  });

  testWidgets('offline the account actions stay reachable', (tester) async {
    await pumpScreen(tester, offline: true);

    expect(find.text(t.profiles.sectionTitle), findsOneWidget);
    expect(find.text(t.common.settings), findsOneWidget);
    expect(find.text(t.common.logout), findsOneWidget);
    // Requests is the one section that needs a live server, so it goes.
    expect(find.text(t.seerr.title), findsNothing);
  });

  testWidgets('a profile without a picture still renders, so navigation never breaks', (tester) async {
    await pumpScreen(tester, profile: _profile('Zonder foto'));

    expect(find.byType(ProfileAvatar), findsWidgets);
    expect(find.text('Zonder foto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
