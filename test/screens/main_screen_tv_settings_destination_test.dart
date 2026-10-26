/// A-24c on the shipped shell: Instellingen is a destination of its own, and
/// the profile avatar opens the account menu (LEESMIJ-v4, A13, A14).
///
/// Pumps the real [ProfileSessionScreen] through [pumpTvMainScreen], so the
/// chain under test is `MainScreen` itself: `_focusTvDestination`,
/// `_selectTvDestination`, `_selectTab` and `_openAccountMenuFromShell`.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/screens/profile/profile_switch_screen.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
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

  testWidgets('A13: the ring on Instellingen leaves Mijn Pleya on screen until Select', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onSelectDestination(TvDestinationId.myPleya);
    await h.settle();

    h.shell.onFocusDestination(TvDestinationId.settings);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.myPleya);
    expect(h.shell.coordinator.focusedDestination, TvDestinationId.settings);
    expect(find.byType(TvMyPleyaScreen), findsOneWidget);

    // Every other destination still follows the ring.
    h.shell.onFocusDestination(TvDestinationId.home);
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
}
