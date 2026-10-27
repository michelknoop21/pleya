/// A-24c on the shipped shell: Instellingen is a destination of its own, and
/// the profile avatar opens the account menu (LEESMIJ-v4, A13, A14).
///
/// Pumps the real [ProfileSessionScreen] through [pumpTvMainScreen], so the
/// chain under test is `MainScreen` itself: `_focusTvDestination`,
/// `_selectTvDestination`, `_selectTab` and `_openAccountMenuFromShell`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/screens/profile/profile_switch_screen.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/screens/tv/sections/tv_servers_page.dart';
import 'package:pleya/screens/tv/tv_offline_home_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_account_menu.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/tv_main_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    LocaleSettings.setLocaleSync(AppLocale.en);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => null,
    );
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('Instellingen sits right after Mijn Pleya and opens the settings page', (tester) async {
    final h = await pumpTvMainScreen(tester);
    final destinations = h.shell.coordinator.destinations;
    expect(destinations.last, TvDestinationId.settings);
    expect(destinations[destinations.length - 2], TvDestinationId.myPleya);

    h.shell.onSelectDestination(TvDestinationId.settings);
    await h.settle();

    expect(h.shell.coordinator.active, TvDestinationId.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
    // A destination of its own, not a section on top of Mijn Pleya.
    expect(h.shell.coordinator.nestedRoutesFor(TvDestinationId.myPleya), isEmpty);

    await h.dispose(tester);
  });

  testWidgets('Instellingen keeps the collapsible bar of A-24 as a destination of its own', (tester) async {
    expect(tvRootTopNavFor(TvDestinationId.settings), TvTopNavPresentation.collapsible);
    for (final other in TvDestinationId.values.where((d) => d != TvDestinationId.settings)) {
      expect(tvRootTopNavFor(other), TvTopNavPresentation.persistent, reason: other.name);
    }

    final h = await pumpTvMainScreen(tester);
    h.shell.onSelectDestination(TvDestinationId.settings);
    await h.settle();
    final settingsTop = tester.getRect(find.byType(SettingsScreen)).top;
    expect(settingsTop, lessThanOrEqualTo(0), reason: 'the page runs up behind the bar');

    // Into the page: the bar slides away.
    h.shell.onFocusContent(restorePreviousFocus: false);
    await h.settle();
    await h.settle();
    expect(tester.getRect(find.byType(TvTopNavigation)).bottom, lessThanOrEqualTo(1));

    // Back to the bar: it is there again, on Instellingen.
    h.shell.onFocusNav();
    await h.settle();
    await h.settle();
    expect(tester.getRect(find.byType(TvTopNavigation)).top, greaterThanOrEqualTo(0));

    await h.dispose(tester);
  });

  testWidgets('A13: the ring moves and the page stays until Select, for every destination', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onSelectDestination(TvDestinationId.myPleya);
    await h.settle();

    h.shell.onFocusDestination(TvDestinationId.settings);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.myPleya);
    expect(h.shell.coordinator.focusedDestination, TvDestinationId.settings);
    expect(find.byType(TvMyPleyaScreen), findsOneWidget);

    // Review 557-I4: LEESMIJ-v4 holds for all destinations, not only for
    // Instellingen. The walk to the avatar passes Zoeken and Home and leaves
    // Mijn Pleya on screen, so the account menu opens over it (A14).
    for (final d in [TvDestinationId.home, TvDestinationId.search]) {
      h.shell.onFocusDestination(d);
      await h.settle();
      expect(h.shell.coordinator.active, TvDestinationId.myPleya, reason: d.name);
      expect(find.byType(TvMyPleyaScreen), findsOneWidget, reason: d.name);
    }

    // DOWN goes into the page on screen, and the way back up is its pill.
    // The ring walks right to Instellingen on real key presses, so the bar
    // scope remembers Instellingen; then down, then up.
    h.shell.onFocusNav();
    await h.settle();
    for (var i = 0; i < 8 && !h.shell.navNodes.isFocused(TvDestinationId.settings.focusKey); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await h.settle();
    }
    expect(h.shell.navNodes.isFocused(TvDestinationId.settings.focusKey), isTrue);
    expect(h.shell.coordinator.active, TvDestinationId.myPleya);
    h.shell.onFocusContent(restorePreviousFocus: true);
    await h.settle();
    expect(h.shell.coordinator.focusedDestination, TvDestinationId.myPleya);
    h.shell.onFocusNav();
    await h.settle();
    expect(
      h.shell.navNodes.isFocused(TvDestinationId.myPleya.focusKey),
      isTrue,
      reason: 'UP returns to the pill on screen',
    );

    // Select changes the page.
    h.shell.onSelectDestination(TvDestinationId.home);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.home);

    await h.dispose(tester);
  });

  testWidgets('A14: Wissel profiel goes through the same gate picker the avatar always opened', (tester) async {
    final h = await pumpTvMainScreen(tester);

    h.shell.onOpenProfiles();
    await h.settle();
    expect(find.byType(TvAccountMenu), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await h.settle();

    expect(find.byType(TvAccountMenu), findsNothing);
    final picker = tester.widget<ProfileSwitchScreen>(find.byType(ProfileSwitchScreen));
    expect(picker.presentAsGate, isTrue, reason: 'AccountUiActions.openProfiles(asGate: true)');

    await h.dispose(tester);
  });

  testWidgets('A14: Uitloggen asks the existing confirmation, and cancelling returns to the avatar', (tester) async {
    final h = await pumpTvMainScreen(tester);

    h.shell.onOpenProfiles();
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await h.settle();

    expect(find.text(t.messages.logoutConfirm), findsOneWidget);
    // Cancel holds the focus in `showConfirmDialog`.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await h.settle();

    expect(find.text(t.messages.logoutConfirm), findsNothing);
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue);

    await h.dispose(tester);
  });

  testWidgets('A14: Back closes the menu and the remote is on the avatar again', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await h.settle();

    h.shell.onOpenProfiles();
    await h.settle();
    expect(find.byType(TvAccountMenu), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    expect(find.byType(TvAccountMenu), findsNothing);
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue);

    await h.dispose(tester);
  });

  // Review 557-I2: "Servers beheren" used to select Instellingen and leave
  // the remote on the offstage button, with the bar collapsed and no ring.
  testWidgets('Servers beheren on the offline Home opens Koppelingen > Servers with the remote in it', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.offline.set(true);
    await h.settle();
    expect(find.byType(TvOfflineHomeScreen), findsOneWidget);

    final button = find.text(t.tvOfflineHome.manageServers);
    expect(button, findsOneWidget);
    Focus.of(tester.element(button)).requestFocus();
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await h.settle();
    await h.settle();

    expect(h.shell.coordinator.active, TvDestinationId.settings);
    expect(h.shell.coordinator.activeNestedRoute?.id, 'tvSettings_servers');
    expect(h.shell.coordinator.activeNestedRoute?.topNav, TvTopNavPresentation.collapsible);
    final focused = FocusManager.instance.primaryFocus!;
    expect(focused.context, isNotNull);
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => identical(e, focused.context)),
        matching: find.byType(TvServersPage),
      ),
      findsOneWidget,
      reason: 'the remote is inside the Servers page, on ${focused.debugLabel}',
    );

    await h.dispose(tester);
  });
}
