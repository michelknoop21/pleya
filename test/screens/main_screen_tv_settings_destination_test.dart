/// A-24c on the shipped shell: Instellingen is a destination of its own, and
/// the profile avatar opens the account menu (LEESMIJ-v4, A14). The ring on a
/// destination pill switches the page (DEC-XXX, which replaced A13's rule).
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
import 'package:pleya/navigation/tv/tv_ring_settle.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/screens/tv/sections/tv_servers_page.dart';
import 'package:pleya/screens/tv/tv_offline_home_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/services/companion_remote/companion_remote_receiver.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/tvos_system_navigation_service.dart';
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

  // DEC-XXX (besluit Michel 4 november 2026) reverses point 3 of DEC-167:
  // the ring on a destination pill is the page. Negative control: with the
  // A-24c host (`_tvNav.focusDestination` only) every `active` below stays
  // on Mijn Pleya and this test is red.
  testWidgets('DEC-XXX: the ring on a pill switches the page at once, for every destination', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onSelectDestination(TvDestinationId.myPleya);
    await h.settle();
    h.shell.onFocusNav();
    await h.settle();
    expect(h.shell.navNodes.isFocused(TvDestinationId.myPleya.focusKey), isTrue);

    // One press, no settle: the page is there in the frame the ring lands.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(h.shell.navNodes.isFocused(TvDestinationId.settings.focusKey), isTrue);
    expect(h.shell.coordinator.active, TvDestinationId.settings, reason: 'a single press has no visible delay');
    await h.settle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // Back left, one deliberate press at a time: each pill is the page.
    for (final d in [TvDestinationId.myPleya, TvDestinationId.movies, TvDestinationId.series, TvDestinationId.home]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.shell.coordinator.active, d, reason: d.name);
      await h.settle();
    }

    // Zoeken is a pill like any other; the avatar is not a destination, and
    // the ring on it leaves the page on screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.search);
    h.shell.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await h.settle();
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue);
    expect(h.shell.coordinator.active, TvDestinationId.search, reason: 'the avatar does not activate');

    await h.dispose(tester);
  });

  // The sweep is the complaint ("the app feels sluggish"): a held arrow
  // repeats every 80 ms in the engine. Negative control: with
  // `TvRingSettle.ringMoved` activating on every move, `switches` is
  // [series, movies, myPleya, settings] and this test is red.
  testWidgets('DEC-XXX: a sweep switches the page on the pill the ring rests on', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    expect(h.shell.navNodes.isFocused(TvDestinationId.home.focusKey), isTrue);

    final switches = <TvDestinationId>[];
    var last = h.shell.coordinator.active;
    void record() {
      final now = h.shell.coordinator.active;
      if (now != last) switches.add(last = now);
    }

    h.shell.coordinator.addListener(record);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(h.shell.navNodes.isFocused(TvDestinationId.settings.focusKey), isTrue);
    expect(switches, [TvDestinationId.series], reason: 'the first press switched at once, the rest are coalesced');

    await tester.pump(kTvRingSettle);
    expect(switches, [TvDestinationId.series, TvDestinationId.settings]);
    expect(h.shell.coordinator.active, TvDestinationId.settings);
    h.shell.coordinator.removeListener(record);
    await h.settle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await h.dispose(tester);
  });

  testWidgets('DEC-XXX: DOWN inside the settle window goes into the page under the ring', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(h.shell.navNodes.isFocused(TvDestinationId.myPleya.focusKey), isTrue);
    expect(h.shell.coordinator.active, isNot(TvDestinationId.myPleya), reason: 'still inside the window');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(h.shell.coordinator.active, TvDestinationId.myPleya);
    await h.settle();
    final focused = FocusManager.instance.primaryFocus!;
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => identical(e, focused.context)),
        matching: find.byType(TvMyPleyaScreen),
      ),
      findsOneWidget,
      reason: 'the remote is in Mijn Pleya, on ${focused.debugLabel}',
    );

    await h.dispose(tester);
  });

  // Review 593-I3: only a move between pills opens a settle window. The ring
  // arriving on the page's own pill (UP, Menu to Home, start-up focus) does
  // not, so the first arrow after it still switches at once. Negative control:
  // without the guard in `_focusTvDestination`, `active` is still Home here.
  testWidgets('DEC-XXX: the first arrow after UP or Menu switches at once', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    h.shell.onFocusContent(restorePreviousFocus: false);
    await h.settle();

    h.shell.onFocusNav();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(h.shell.coordinator.active, TvDestinationId.series, reason: 'UP opened no window');
    await h.settle();

    // Menu from Series goes Home and the ring with it; a quick RIGHT after it
    // is again a first press.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 60));
    expect(h.shell.navNodes.isFocused(TvDestinationId.home.focusKey), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(h.shell.coordinator.active, TvDestinationId.series, reason: 'Menu opened no window');

    await h.dispose(tester);
  });

  // Review 593-R2-M1 / M3: a page changed from outside the bar takes the ring
  // with it, also when the ring stands on the avatar. Negative control: with
  // the ring-follow check counting destination pills only, the avatar keeps
  // the focus and a second Menu would leave the app.
  testWidgets('DEC-XXX: Menu with the ring on the avatar goes Home and takes the ring along', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.search);
    h.shell.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await h.settle();
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.home);
    expect(h.shell.navNodes.isFocused(TvDestinationId.home.focusKey), isTrue, reason: 'the ring follows the page');
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isFalse);
    expect(TvosSystemNavigationService.automationState()['enabled'], isTrue, reason: 'on Home Menu is the system');

    await h.dispose(tester);
  });

  // Review 593-M3: the same for a page changed by the companion remote while
  // the ring stands on the avatar. Negative control: with the pill-only check
  // the page becomes Instellingen and the ring stays on the avatar.
  testWidgets('DEC-XXX: a companion-remote page change takes the ring off the avatar', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    h.shell.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await h.settle();
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue);

    final onTabSettings = CompanionRemoteReceiver.instance.onTabSettings;
    expect(onTabSettings, isNotNull, reason: 'MainScreen wires the companion remote on a TV host');
    onTabSettings!();
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.settings);
    expect(h.shell.navNodes.isFocused(TvDestinationId.settings.focusKey), isTrue, reason: 'the ring follows the page');
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isFalse);

    await h.dispose(tester);
  });

  // Review 593-M2: inside a settle window ring and page can differ, so Menu
  // is not handed to tvOS until the window closes.
  testWidgets('DEC-XXX: no Menu passthrough while a sweep is settling', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.series);

    // LEFT lands on Home (leading edge), LEFT again to Zoeken inside the window.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(h.shell.coordinator.active, TvDestinationId.home);
    expect(TvosSystemNavigationService.automationState()['enabled'], isFalse, reason: 'window open');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 40));
    expect(TvosSystemNavigationService.automationState()['enabled'], isFalse, reason: 'ring on Zoeken, page Home');
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.search);
    expect(TvosSystemNavigationService.automationState()['enabled'], isFalse, reason: 'Zoeken is not the root');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.home);
    expect(TvosSystemNavigationService.automationState()['enabled'], isTrue, reason: 'window closed on Home');

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

    // Review 557-I5: Menu from there lands in Instellingen, on something
    // that takes the remote, not on the content scope with no ring.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    await h.settle();
    expect(h.shell.coordinator.activeNestedRoute, isNull);
    expect(h.shell.coordinator.active, TvDestinationId.settings);
    final back = FocusManager.instance.primaryFocus!;
    expect(back is FocusScopeNode, isFalse, reason: 'the remote is on ${back.debugLabel}');
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => identical(e, back.context)),
        matching: find.byType(SettingsScreen),
      ),
      findsOneWidget,
      reason: 'the remote is in Instellingen, on ${back.debugLabel}',
    );
    expect(back.debugLabel, 'servers', reason: 'Menu returns to the Servers row');

    await h.dispose(tester);
  });

  // DEC-XXX: ring and page coincide, so Menu on the bar is the rule from
  // before A-24c again: on Home it is the system's (passthrough), on another
  // page it goes Home, and the ring goes with it.
  testWidgets('Menu on the bar: Home hands it to tvOS, another page goes Home with the ring', (tester) async {
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    expect(h.shell.navNodes.isFocused(TvDestinationId.home.focusKey), isTrue);
    expect(TvosSystemNavigationService.automationState()['enabled'], isTrue, reason: 'Home pill: Menu is the system');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.series);
    expect(TvosSystemNavigationService.automationState()['enabled'], isFalse, reason: 'Series is not the root');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.home);
    expect(h.shell.navNodes.isFocused(TvDestinationId.home.focusKey), isTrue, reason: 'the ring follows the page');
    expect(TvosSystemNavigationService.automationState()['enabled'], isTrue);

    await h.dispose(tester);
  });
}
