/// SYS-4: `StateView` reads no viewport, no platform and no TV scale. Its
/// icon (48/32 compact), padding and text styles are fixed desktop/mobile
/// constants, which land at roughly half of what ten-foot viewing distance
/// needs (`docs/tvos-redesign-register.md`, "SYS-4, wat de audit vond").
///
/// These tests pin the TV-only scaling behavior. Off TV, `StateView` is
/// untouched: no test here exercises that path because the fix must not
/// change it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/libraries/state_messages.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/state_view.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  TranslationProvider(
    child: MaterialApp(
      theme: monoTheme(dark: true),
      home: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('SYS-4: the shared empty state scales on a TV viewport', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const StateView.empty(title: 'Nothing here'));

    final icon = tester.widget<Icon>(find.byType(Icon).first);
    // 48 was the fixed size; at the 1080 reference, ten-foot viewing asks for
    // more.
    expect(icon.size, greaterThan(48));
  });

  testWidgets('SYS-4: the 1080 reference produces a deterministic scale', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const StateView.empty(title: 'Nothing here'));

    final icon = tester.widget<Icon>(find.byType(Icon).first);
    // TvLayoutConstants.scaleForHeight(1080) == 1.0 exactly, so the TV
    // multiplier alone decides the size at the reference height.
    expect(icon.size, 96.0);
  });

  testWidgets('SYS-4: a low TV surface still scales, clamped at the floor', (tester) async {
    // Below the 1080 reference, TvLayoutConstants.scaleForHeight clamps at
    // 0.85 rather than shrinking further.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const StateView.empty(title: 'Nothing here'));

    final icon = tester.widget<Icon>(find.byType(Icon).first);
    expect(icon.size, closeTo(96.0 * 0.85, 0.01));
    // Still bigger than the old fixed constant even at the clamp floor.
    expect(icon.size, greaterThan(48));
  });

  testWidgets('SYS-4: the error state scales on a TV viewport', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const StateView.error(title: 'Something broke'));

    final icon = tester.widget<Icon>(find.byType(Icon).first);
    expect(icon.size, greaterThan(48));
  });

  testWidgets('SYS-4: a compact StateView also scales its smaller icon', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const StateView.empty(title: 'Nothing here', compact: true));

    final icon = tester.widget<Icon>(find.byType(Icon).first);
    // 32 was the fixed compact size.
    expect(icon.size, greaterThan(32));
  });

  testWidgets('SYS-4: the retry action stays reachable with a D-pad', (tester) async {
    // The audit named this explicitly working: this is a regression floor,
    // not a fix.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var retried = false;
    await _pump(tester, StateView.error(title: 'Something broke', onRetry: () => retried = true));

    final focusableFinder = find.byType(FocusableButton);
    expect(focusableFinder, findsOneWidget);
    final focusable = tester.widget<FocusableButton>(focusableFinder);
    expect(focusable.onPressed, isNotNull);

    focusable.onPressed!();
    expect(retried, isTrue);
  });

  testWidgets('SYS-4: EmptyStateWidget (state_messages.dart) also scales on TV', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const EmptyStateWidget(message: 'Nothing here', icon: Symbols.inbox_rounded));

    final icon = tester.widget<Icon>(find.byType(Icon).first);
    // 64 was the fixed default size.
    expect(icon.size, greaterThan(64));
  });
}
