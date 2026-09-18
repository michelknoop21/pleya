/// SYS-4: `StateView` and `StateMessageWidget`/`EmptyStateWidget` never read
/// the TV panel scale (`docs/tvos-redesign-register.md`, "SYS-4, wat de
/// audit vond"): their icon, padding and text stayed fixed regardless of
/// viewport, platform or TV surface size.
///
/// Fix-round 1's review rejected the first version of these tests: they
/// pinned an invented flat multiplier (`icon.size == 96.0` at the 1080
/// reference) instead of a property that holds for whatever base size the
/// implementation actually uses. These tests check the property that
/// matters: on TV, the icon follows `TvLayoutConstants.scaleForHeight` the
/// same way `TvCatalogEmptyState` does, and off TV nothing about viewport
/// height affects it at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/libraries/state_messages.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/state_view.dart';

Future<double> _iconSizeAt(WidgetTester tester, Widget Function() build, Size viewport) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: Center(child: build())),
      ),
    ),
  );

  return tester.widget<Icon>(find.byType(Icon).first).size!;
}

void main() {
  // 1080 is TvLayoutConstants.scaleForHeight's reference (scale == 1.0).
  // 1350 sits inside the unclamped 0.85..1.35 range (scale == 1.25), so the
  // ratio between the two isolates the scale formula from whatever base
  // icon size the widget under test picks.
  const reference = Size(1920, 1080);
  const taller = Size(1920, 1350);
  // Below the reference, TvLayoutConstants.scaleForHeight clamps at 0.85
  // rather than shrinking further.
  const clampedLow = Size(1280, 700);

  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('SYS-4: the shared empty state scales with the TV panel height', (tester) async {
    final atReference = await _iconSizeAt(tester, () => const StateView.empty(title: 'Nothing here'), reference);
    final atTaller = await _iconSizeAt(tester, () => const StateView.empty(title: 'Nothing here'), taller);

    expect(
      atTaller / atReference,
      closeTo(
        TvLayoutConstants.scaleForHeight(taller.height) / TvLayoutConstants.scaleForHeight(reference.height),
        0.001,
      ),
    );
  });

  testWidgets('SYS-4: a low TV surface clamps at the scaleForHeight floor', (tester) async {
    final atReference = await _iconSizeAt(tester, () => const StateView.empty(title: 'Nothing here'), reference);
    final atLow = await _iconSizeAt(tester, () => const StateView.empty(title: 'Nothing here'), clampedLow);

    // scaleForHeight(1080) == 1.0 and scaleForHeight(700) clamps at 0.85.
    expect(atLow / atReference, closeTo(0.85, 0.001));
  });

  testWidgets('SYS-4: off TV, viewport height has no effect on the icon size', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);

    final atReference = await _iconSizeAt(tester, () => const StateView.empty(title: 'Nothing here'), reference);
    final atTaller = await _iconSizeAt(tester, () => const StateView.empty(title: 'Nothing here'), taller);

    expect(atTaller, equals(atReference));
  });

  testWidgets('SYS-4: the error state also scales with the TV panel height', (tester) async {
    final atReference = await _iconSizeAt(tester, () => const StateView.error(title: 'Something broke'), reference);
    final atTaller = await _iconSizeAt(tester, () => const StateView.error(title: 'Something broke'), taller);

    expect(
      atTaller / atReference,
      closeTo(
        TvLayoutConstants.scaleForHeight(taller.height) / TvLayoutConstants.scaleForHeight(reference.height),
        0.001,
      ),
    );
  });

  testWidgets('SYS-4: a compact StateView also scales with the TV panel height', (tester) async {
    final atReference = await _iconSizeAt(
      tester,
      () => const StateView.empty(title: 'Nothing here', compact: true),
      reference,
    );
    final atTaller = await _iconSizeAt(
      tester,
      () => const StateView.empty(title: 'Nothing here', compact: true),
      taller,
    );

    expect(
      atTaller / atReference,
      closeTo(
        TvLayoutConstants.scaleForHeight(taller.height) / TvLayoutConstants.scaleForHeight(reference.height),
        0.001,
      ),
    );
  });

  testWidgets('SYS-4: the retry action stays reachable with a D-pad', (tester) async {
    // The audit named this explicitly working: this is a regression floor,
    // not a fix.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var retried = false;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Center(
              child: StateView.error(title: 'Something broke', onRetry: () => retried = true),
            ),
          ),
        ),
      ),
    );

    final focusableFinder = find.byType(FocusableButton);
    expect(focusableFinder, findsOneWidget);
    final focusable = tester.widget<FocusableButton>(focusableFinder);
    expect(focusable.onPressed, isNotNull);

    focusable.onPressed!();
    expect(retried, isTrue);
  });

  testWidgets('SYS-4: EmptyStateWidget (state_messages.dart) also scales with the TV panel height', (tester) async {
    final atReference = await _iconSizeAt(
      tester,
      () => const EmptyStateWidget(message: 'Nothing here', icon: Symbols.inbox_rounded),
      reference,
    );
    final atTaller = await _iconSizeAt(
      tester,
      () => const EmptyStateWidget(message: 'Nothing here', icon: Symbols.inbox_rounded),
      taller,
    );

    expect(
      atTaller / atReference,
      closeTo(
        TvLayoutConstants.scaleForHeight(taller.height) / TvLayoutConstants.scaleForHeight(reference.height),
        0.001,
      ),
    );
  });

  testWidgets('SYS-4: EmptyStateWidget scales the caller\'s own iconSize, not a fixed reference', (tester) async {
    // sync_rules_screen.dart passes 80 instead of the 64 default for a more
    // prominent glyph; that relative choice must survive on TV too.
    final defaultSize = await _iconSizeAt(
      tester,
      () => const EmptyStateWidget(message: 'Nothing here', icon: Symbols.inbox_rounded),
      reference,
    );
    final overriddenSize = await _iconSizeAt(
      tester,
      () => const EmptyStateWidget(message: 'Nothing here', icon: Symbols.inbox_rounded, iconSize: 80),
      reference,
    );

    expect(overriddenSize / defaultSize, closeTo(80 / 64, 0.001));
  });
}
