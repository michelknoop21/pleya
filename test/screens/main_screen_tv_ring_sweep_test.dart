import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_ring_settle.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/tv_main_screen_harness.dart';

/// The ring's own delayed page switch must not pull the ring back to that page
/// once it has moved on (review 593 I-1), while a page changed from outside the
/// bar still takes the ring along (593-R2-M1).
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
  });
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
  });

  Future<void> androidTv() async {
    TvDetectionService.debugSetAppleTVOverride(null);
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
  }

  // Held LEFT from Series at the 80 ms engine repeat: Home (leading edge),
  // Zoeken (inside the window), avatar. The trailing switch to Zoeken fires
  // after the ring already reached the avatar.
  testWidgets('Apple TV: a fast sweep that ends on the avatar leaves the ring on the avatar', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final h = await pumpTvMainScreen(tester);
    h.shell.onFocusNav();
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle();
    await tester.pump(kTvRingSettle);
    expect(h.shell.coordinator.active, TvDestinationId.series);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 10));
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue, reason: 'the third LEFT reached the avatar');

    await h.settle();
    await tester.pump(kTvRingSettle);
    await h.settle();
    expect(
      h.shell.navNodes.isFocused(tvNavProfileFocusKey),
      isTrue,
      reason: 'the trailing switch must not pull the ring off the avatar',
    );
    expect(h.shell.coordinator.active, TvDestinationId.search);
    await h.dispose(tester);
  });

  // Android TV, driven by focus requests: the harness's key events do not
  // reach the Android TV bar handlers.
  testWidgets('Android TV: a fast sweep that ends on the avatar leaves the ring on the avatar', (tester) async {
    await androidTv();
    final h = await pumpTvMainScreen(tester);
    h.shell.navNodes.get(TvDestinationId.home.focusKey).requestFocus();
    await h.settle();
    h.shell.navNodes.get(TvDestinationId.series.focusKey).requestFocus();
    await h.settle();
    await tester.pump(kTvRingSettle);
    expect(h.shell.coordinator.active, TvDestinationId.series);

    h.shell.navNodes.get(TvDestinationId.home.focusKey).requestFocus();
    await tester.pump(const Duration(milliseconds: 80));
    h.shell.navNodes.get(TvDestinationId.search.focusKey).requestFocus();
    await tester.pump(const Duration(milliseconds: 80));
    h.shell.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await tester.pump(const Duration(milliseconds: 10));
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue);

    await h.settle();
    await tester.pump(kTvRingSettle);
    await h.settle();
    expect(h.shell.navNodes.isFocused(tvNavProfileFocusKey), isTrue);
    await h.dispose(tester);
  });

  testWidgets('Android TV: back with the ring on the avatar goes Home and takes the ring along', (tester) async {
    await androidTv();
    final h = await pumpTvMainScreen(tester);
    h.shell.navNodes.get(TvDestinationId.home.focusKey).requestFocus();
    await h.settle();
    h.shell.navNodes.get(TvDestinationId.search.focusKey).requestFocus();
    await h.settle();
    await tester.pump(kTvRingSettle);
    expect(h.shell.coordinator.active, TvDestinationId.search);

    h.shell.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(h.shell.coordinator.active, TvDestinationId.home);
    expect(h.shell.navNodes.isFocused(TvDestinationId.home.focusKey), isTrue);
    await h.dispose(tester);
  });
}
