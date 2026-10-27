import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/profile_session_screen.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/profiles/active_profile_binder.dart';
import 'package:pleya/screens/downloads/downloads_screen.dart';
import 'package:pleya/screens/tv/tv_movies_landing_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/screens/tv/tv_offline_home_screen.dart';
import 'package:pleya/screens/watchlist_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/tv_main_screen_harness.dart';

/// OFF5: does an offline flip overwrite a Mijn Pleya section the viewer just
/// chose on the TV shell?
///
/// Pumps the real [ProfileSessionScreen] with its default shell, so the chain
/// under test is the shipped one: `MainScreen._handleOfflineStatusChanged` →
/// `_syncTvDestinations` → `TvNavigationCoordinator.updateConditions` →
/// `_selectTab`. Only the offline signal itself is faked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    LocaleSettings.setLocaleSync(AppLocale.en);
    // `MainScreen.initState` registers with window_manager on a desktop host.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => null,
    );
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
  });

  // Android TV: `isTV` without `isAppleTV`, so Downloads is a visible tab.
  Future<void> androidTv() async {
    TvDetectionService.debugSetAppleTVOverride(null);
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
  }

  void appleTv() => TvDetectionService.debugSetAppleTVOverride(true);

  /// The section is on screen, the bar lights Mijn Pleya, and the section is
  /// the route on top of Mijn Pleya's own stack.
  void expectSectionShown(TvMainScreenHarness h, TvMyPleyaSection section, Type screen, String phase) {
    expect(h.shell.coordinator.active, TvDestinationId.myPleya, reason: '$phase: bar active');
    expect(
      h.shell.coordinator.nestedRoutesFor(TvDestinationId.myPleya).map((r) => r.id).lastOrNull,
      'tvMyPleya_${section.name}',
      reason: '$phase: nested route on top of Mijn Pleya',
    );
    expect(find.byType(screen), findsOneWidget, reason: '$phase: $screen is what is on screen');
  }

  Future<void> chooseSection(TvMainScreenHarness h, TvMyPleyaSection section) async {
    // The viewer walks to Mijn Pleya in the bar, then opens the tile: the tile's
    // `onOpen` calls exactly this callback (`TvMyPleyaScreen` line ~368).
    h.shell.onSelectDestination(TvDestinationId.myPleya);
    await h.settle();
    h.tester.widget<TvMyPleyaScreen>(find.byType(TvMyPleyaScreen)).onOpenSection(section);
    await h.settle();
  }

  for (final (platform, section, screen) in [
    ('Android TV', TvMyPleyaSection.downloads, DownloadsScreen),
    ('Android TV', TvMyPleyaSection.watchlist, WatchlistScreen),
    ('Apple TV', TvMyPleyaSection.watchlist, WatchlistScreen),
  ]) {
    testWidgets('OFF5 $platform: a chosen ${section.name} section survives going offline and back online', (
      tester,
    ) async {
      platform == 'Apple TV' ? appleTv() : await androidTv();
      final h = await pumpTvMainScreen(tester);
      if (section == TvMyPleyaSection.watchlist) await h.enableWatchlist();

      await chooseSection(h, section);
      expectSectionShown(h, section, screen, 'online, just chosen');

      h.offline.set(true);
      await h.settle();
      expect(h.shell.coordinator.destinations, isNot(contains(TvDestinationId.movies)), reason: 'offline bar');
      expectSectionShown(h, section, screen, 'after going offline');

      h.offline.set(false);
      await h.settle();
      expect(h.shell.coordinator.destinations, contains(TvDestinationId.movies), reason: 'online bar');
      expectSectionShown(h, section, screen, 'after coming back online');

      await h.dispose(tester);
    });
  }

  // OFF6. A rebind of the profile that was already active (a reconnect, a
  // borrowed or removed connection) used to run the profile-switch cleanup and
  // drop the viewer on the bare hub. Same profile, same place.
  testWidgets('OFF6 Apple TV: a rebind of the same profile keeps the open section', (tester) async {
    appleTv();
    final h = await pumpTvMainScreen(tester);
    await h.enableWatchlist();

    await chooseSection(h, TvMyPleyaSection.watchlist);
    expectSectionShown(h, TvMyPleyaSection.watchlist, WatchlistScreen, 'before the rebind');

    final binder = Provider.of<ActiveProfileBinder>(tester.element(find.byType(TvRootShell)), listen: false);
    await tester.runAsync(binder.rebindActive);
    await h.settle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await h.settle();

    expectSectionShown(h, TvMyPleyaSection.watchlist, WatchlistScreen, 'after the rebind');

    await h.dispose(tester);
  });

  // The auto path. Offline, Films leaves the bar and the shell lands on the
  // offline Home (MOC-23). Back online, Android TV restores Films: its offline
  // normalisation picked Downloads first, which arms `_autoSwitchedToDownloads`,
  // and MOC-23a keeps that latch through the bar's own Home reselection. Apple
  // TV hides Downloads, so no latch is armed and Home stays. Either way the lit
  // pill and the page on screen have to agree.
  for (final (platform, restored) in [('Android TV', TvDestinationId.movies), ('Apple TV', TvDestinationId.home)]) {
    testWidgets('OFF5 $platform: Films going offline lands on the offline Home, and back online on ${restored.name}', (
      tester,
    ) async {
      platform == 'Apple TV' ? appleTv() : await androidTv();
      final h = await pumpTvMainScreen(tester);

      h.shell.onSelectDestination(TvDestinationId.movies);
      await h.settle();
      expect(h.shell.coordinator.active, TvDestinationId.movies);
      expect(find.byType(TvMoviesLandingScreen), findsOneWidget);

      h.offline.set(true);
      await h.settle();
      expect(h.shell.coordinator.active, TvDestinationId.home, reason: 'Films is gone offline; the bar falls to Home');
      expect(find.byType(TvOfflineHomeScreen), findsOneWidget, reason: 'MOC-23: offline Home is what is shown');
      expect(find.byType(DownloadsScreen), findsNothing, reason: 'the Downloads auto-pick does not survive on TV');

      // The remote on the bar when the connection returns: the ring the
      // coordinator draws and the node that holds the focus must move together.
      h.shell.onFocusNav();
      await h.settle();
      expect(h.shell.navNodes.isFocused(TvDestinationId.home.focusKey), isTrue, reason: 'offline: remote on Home');

      h.offline.set(false);
      await h.settle();
      expect(h.shell.coordinator.active, restored, reason: 'back online: the lit pill');
      expect(h.shell.navNodes.isFocused(restored.focusKey), isTrue, reason: 'back online: the focused pill');
      expect(
        find.byType(TvMoviesLandingScreen),
        restored == TvDestinationId.movies ? findsOneWidget : findsNothing,
        reason: 'back online: the page on screen must be the one the bar lights',
      );
      expect(find.byType(TvOfflineHomeScreen), findsNothing);

      await h.dispose(tester);
    });
  }
}
