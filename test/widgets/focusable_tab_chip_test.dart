import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/focusable_tab_chip.dart';

/// What a viewer sees marking the open tab.
///
/// The mockups of 2 and 3 September 2026 mark it with ink and weight on TV and
/// with nothing else: `libraries-d.png` draws the open tab as bold white text
/// over muted neighbours, and the approved set reserves the brand red for the
/// progress line and the recording marker. So these read the two signals a
/// viewer actually has (the colour of any rule under the label, and the state
/// of the label itself) rather than the widget's own flags.
void main() {
  /// Every bar colour the chip paints, transparent ones included.
  ///
  /// The rule is an [AnimatedContainer] in both treatments, once as a plain
  /// `color` and once inside a `BoxDecoration`; the constructor folds the first
  /// into the second, so one read covers both.
  List<Color> ruleColours(WidgetTester tester) => [
    for (final box in tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)))
      if (box.decoration case final BoxDecoration d) ...[if (d.color != null) d.color!],
  ];

  TextStyle labelStyle(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style!;

  Future<MonoTokens> pumpChip(
    WidgetTester tester, {
    required bool isSelected,
    TabChipStyle style = TabChipStyle.underline,
    bool light = false,
  }) async {
    late MonoTokens tk;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: !light),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              tk = tokens(context);
              return Center(
                child: FocusableTabChip(label: 'Browse', isSelected: isSelected, style: style, onSelect: () {}),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tk;
  }

  group('text tabs', () {
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('on TV the open tab carries no red rule, only ink and weight', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      final tk = await pumpChip(tester, isSelected: true);

      expect(ruleColours(tester), isNot(contains(tk.accent)));
      final style = labelStyle(tester, 'Browse');
      expect(style.color, tk.text);
      expect(style.fontWeight, FontWeight.w600);
    });

    testWidgets('on TV a closed tab stays muted, so the two are still apart', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      final tk = await pumpChip(tester, isSelected: false);

      expect(ruleColours(tester), isNot(contains(tk.accent)));
      final style = labelStyle(tester, 'Browse');
      expect(style.color, tk.textMuted);
      expect(style.fontWeight, FontWeight.w500);
    });

    testWidgets('on TV the light theme keeps the same two signals', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      final tk = await pumpChip(tester, isSelected: true, light: true);

      expect(ruleColours(tester), isNot(contains(tk.accent)));
      expect(labelStyle(tester, 'Browse').color, tk.text);
    });

    testWidgets('off TV the rule is unchanged: desktop and mobile keep it', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      final tk = await pumpChip(tester, isSelected: true);

      expect(ruleColours(tester), contains(tk.accent));
    });
  });

  testWidgets('the segmented treatment is untouched: it keeps its own rule on TV', (tester) async {
    // Not an endorsement, a boundary. The season tabs and the Seerr request
    // filters draw a short accent rule of their own, and that treatment was
    // designed after the red text rule this fix removes. Changing it is a
    // colour decision on the detail surface, which the redesign register makes
    // conditional on a regression image of Home, Films and Series that this
    // finding does not have. Recorded as TOK3 instead of quietly swept along.
    TvDetectionService.debugSetAppleTVOverride(true);
    final tk = await pumpChip(tester, isSelected: true, style: TabChipStyle.segmented);

    expect(ruleColours(tester), contains(tk.accent));
    TvDetectionService.debugSetAppleTVOverride(null);
  });
}
