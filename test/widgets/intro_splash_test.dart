import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/intro_splash.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';

/// The ident's contract, not its picture — `test/goldens/intro_ident_golden_test.dart`
/// holds that. What is asserted here is what a picture cannot see: that it
/// plays once, that a remote can end it, that Reduce Motion is honoured where
/// it is honest, and that it leaves by dissolving into the page.
void main() {
  const pageKey = Key('page');

  setUp(() {
    IntroGate.debugResetForTesting();
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pump(WidgetTester tester, {bool dark = true, bool oled = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: dark, oled: oled),
        home: const IntroGate(
          child: ColoredBox(key: pageKey, color: Color(0xFF00FF00)),
        ),
      ),
    );
  }

  final Finder ident = find.byType(PleyaBrandLockup);

  double overlayOpacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.byKey(const ValueKey('introOverlay'))).opacity;

  /// A skip started from an input handler starts its ticker on the next frame,
  /// so one empty pump precedes the skip duration.
  Future<void> settleSkip(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(IntroGate.skip);
    await tester.pump();
  }

  testWidgets('it plays once per process, and the page is live underneath it the whole time', (tester) async {
    await pump(tester);
    expect(ident, findsOneWidget);
    expect(find.byKey(pageKey), findsOneWidget, reason: 'the ident is an overlay, not a gate on boot work');

    await tester.pump(IntroGate.duration);
    await tester.pump();
    expect(ident, findsNothing);

    // A second mount in the same process — a hot reload, a re-parent — must
    // not replay it.
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester);
    expect(ident, findsNothing);
  });

  testWidgets('the tagline follows the mark rather than arriving with it', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 150));
    final early = tester.widget<PleyaBrandLockup>(ident).taglineOpacity;
    await tester.pump(const Duration(milliseconds: 750));
    final later = tester.widget<PleyaBrandLockup>(ident).taglineOpacity;

    expect(early, 0.0, reason: 'nothing of the tagline before its delay has passed');
    expect(later, 1.0);
  });

  testWidgets('Select on a remote skips it, and the press does not fall through to the page', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ident, findsOneWidget);

    final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(handled, isTrue, reason: 'a skip press must be consumed, or the page under it acts on it too');

    await settleSkip(tester);
    expect(ident, findsNothing);
  });

  testWidgets('a tap skips it too', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(ident);
    await settleSkip(tester);
    expect(ident, findsNothing);
  });

  testWidgets('once it has ended, the remote is the page\'s again', (tester) async {
    await pump(tester);
    await tester.pump(IntroGate.duration);
    await tester.pump();

    final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(handled, isFalse, reason: 'the ident must not keep eating Select after it is gone');
  });

  testWidgets('it leaves by dissolving into the page, not by cutting', (tester) async {
    await pump(tester);
    await tester.pump(IntroGate.duration - const Duration(milliseconds: 230));
    final mid = overlayOpacity(tester);
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));
  });

  testWidgets('Reduce Motion skips it entirely — except on Apple TV, whose engine misreports the flag', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await pump(tester);
    expect(ident, findsNothing);

    IntroGate.debugResetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester);
    expect(ident, findsOneWidget, reason: 'tvOS reports reduceMotion before accessibility features are populated');
  });

  testWidgets('the ground is the page colour on every palette, and never light', (tester) async {
    for (final (dark, oled, expected) in const [
      (true, false, Color(0xFF141414)),
      (true, true, Color(0xFF000000)),
      (false, false, Color(0xFF141414)),
    ]) {
      IntroGate.debugResetForTesting();
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, dark: dark, oled: oled);
      final ground = tester.widget<ColoredBox>(find.ancestor(of: ident, matching: find.byType(ColoredBox)).first).color;
      expect(ground, expected, reason: 'dark=$dark oled=$oled');
    }
  });
}
