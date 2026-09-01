/// J10: white stays the one TV focus identity (hoofdstuk 8), including on a
/// light/white surface — proven visually here, not just asserted on the
/// decoration objects `focus_theme_contrast_separator_test.dart` covers.
/// Mandatory per fase 9's J10 resolution: "Regression/golden op de light
/// surface verplicht."
///
/// Deliberately painted straight from [FocusTheme.focusDecoration] rather
/// than through a live [FocusableWrapper]: the wrapper's own scale/opacity/
/// glow-overlay pipeline is a much bigger surface than this golden needs to
/// judge, and would make a failure here ambiguous about which layer changed.
/// This paints exactly the decoration object J10 touched, nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../test_helpers/golden.dart';

/// A white pill in one of three states a real TV row shows side by side:
/// - [active]: selected, not focused — plain white fill, no ring.
/// - focused (the default when neither flag is set... see [focused]):
///   the same white fill, plus [FocusTheme.focusDecoration]'s ring — and,
///   on a light surface, J10's separator.
/// - idle: neither, just the label with no pill at all — the baseline a
///   reader compares the other two against.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.focused = false, this.active = false});

  final String label;
  final bool focused;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!focused && !active) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: focused ? FocusTheme.contrastSeparatorShadows(context) : null,
        border: focused
            ? Border.all(color: FocusTheme.getFocusBorderColor(context), width: FocusTheme.focusBorderWidth)
            : null,
      ),
      child: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
    );
  }
}

Widget _scene({required bool dark}) => MaterialApp(
  theme: monoTheme(dark: dark),
  home: Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            _Pill(label: 'Active', active: true),
            _Pill(label: 'Focused', focused: true),
            _Pill(label: 'Idle'),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFontsForGoldens);

  testWidgets('a focused white pill stays visually distinct on a light/white surface', (tester) async {
    setGoldenSurfaceSize(tester, size: const Size(700, 220));

    await tester.pumpWidget(_scene(dark: false));
    await tester.pumpAndSettle();

    expect(FocusTheme.needsContrastSeparator(tester.element(find.byType(Scaffold))), isTrue);
    await expectMatchesGolden(find.byType(Scaffold), 'focus_contrast_separator_light');
  });

  testWidgets('the same scene on the dark palette needs no separator, and gets none', (tester) async {
    setGoldenSurfaceSize(tester, size: const Size(700, 220));

    await tester.pumpWidget(_scene(dark: true));
    await tester.pumpAndSettle();

    expect(FocusTheme.needsContrastSeparator(tester.element(find.byType(Scaffold))), isFalse);
    await expectMatchesGolden(find.byType(Scaffold), 'focus_contrast_separator_dark');
  });
}
