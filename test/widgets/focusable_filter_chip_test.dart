import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/focusable_filter_chip.dart';

/// `filled` is the northstar control pill (Sources/Filters/Sort), `scope` is
/// the northstar toggle chip (All/Movies/Shows) — see DEC-103 for why they
/// are separate from `outlined`, which stays byte-for-byte for shared
/// TV/desktop/iPad surfaces.
void main() {
  Future<MonoTokens> pumpChip(WidgetTester tester, {required Widget chip, double textScale = 1.0}) async {
    late MonoTokens tk;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                tk = tokens(context);
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: chip,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tk;
  }

  AnimatedContainer shapedContainer(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .singleWhere((c) => c.decoration is ShapeDecoration);

  ShapeDecoration shapeDecoration(WidgetTester tester) => shapedContainer(tester).decoration as ShapeDecoration;

  group('filled', () {
    testWidgets('draws exactly 32pt, badge exactly 18x18', (tester) async {
      await pumpChip(
        tester,
        chip: FocusableFilterChip(variant: FilterChipVariant.filled, label: 'Filters', badgeCount: 2, onPressed: () {}),
      );

      expect(tester.getSize(find.byWidget(shapedContainer(tester))).height, 32.0);

      final badge = find.ancestor(of: find.text('2'), matching: find.byType(SizedBox)).first;
      expect(tester.getSize(badge), const Size(18, 18));
    });

    testWidgets('height is independent of typography', (tester) async {
      await pumpChip(
        tester,
        textScale: 2.0,
        chip: FocusableFilterChip(
          variant: FilterChipVariant.filled,
          label: 'Filters',
          badgeCount: 12,
          onPressed: () {},
        ),
      );

      expect(tester.getSize(find.byWidget(shapedContainer(tester))).height, 32.0);

      final badge = find.ancestor(of: find.text('12'), matching: find.byType(SizedBox)).first;
      expect(tester.getSize(badge), const Size(18, 18));
    });

    testWidgets('44pt tap target wraps the 32pt surface without enlarging it', (tester) async {
      var taps = 0;
      await pumpChip(
        tester,
        chip: FocusableFilterChip(variant: FilterChipVariant.filled, label: 'Filters', onPressed: () => taps++),
      );

      final chipRect = tester.getRect(find.byType(FocusableFilterChip));
      expect(chipRect.height, greaterThanOrEqualTo(44));

      final pillRect = tester.getRect(find.byWidget(shapedContainer(tester)));
      expect(pillRect.height, 32.0);

      // Above the drawn pill, inside the tap target: still activates.
      expect(chipRect.top, lessThan(pillRect.top));
      await tester.tapAt(Offset(chipRect.center.dx, (chipRect.top + pillRect.top) / 2));
      expect(taps, 1);
    });

    testWidgets('selected does not change the fill', (tester) async {
      final tkSelected = await pumpChip(
        tester,
        chip: FocusableFilterChip(variant: FilterChipVariant.filled, label: 'X', selected: true, onPressed: () {}),
      );
      final selectedColor = shapeDecoration(tester).color;

      final tkUnselected = await pumpChip(
        tester,
        chip: FocusableFilterChip(variant: FilterChipVariant.filled, label: 'X', selected: false, onPressed: () {}),
      );
      final unselectedColor = shapeDecoration(tester).color;

      expect(selectedColor, unselectedColor);
      expect(selectedColor, tkSelected.surfaceElevated);
      expect(unselectedColor, tkUnselected.surfaceElevated);
    });

    testWidgets('no border, gray surfaceElevated fill', (tester) async {
      final tk = await pumpChip(
        tester,
        chip: FocusableFilterChip(variant: FilterChipVariant.filled, label: 'X', onPressed: () {}),
      );

      final decoration = shapeDecoration(tester);
      expect(decoration.color, tk.surfaceElevated);
      final shape = decoration.shape as StadiumBorder;
      expect(shape.side, BorderSide.none);
    });
  });

  group('scope', () {
    testWidgets('keeps the accent tint on selected, stadium shape', (tester) async {
      final tk = await pumpChip(
        tester,
        chip: FocusableFilterChip(variant: FilterChipVariant.scope, label: 'Movies', selected: true, onPressed: () {}),
      );

      final decoration = shapeDecoration(tester);
      expect(decoration.color, tk.accent.withValues(alpha: 0.14));
      final shape = decoration.shape as StadiumBorder;
      expect(shape.side.color, tk.accent.withValues(alpha: 0.55));
    });
  });

  group('outlined (unchanged)', () {
    testWidgets('still radius 10, still the default deferToChild hit behavior', (tester) async {
      await pumpChip(
        tester,
        chip: FocusableFilterChip(label: 'X', onPressed: () {}),
      );

      final container = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .singleWhere((c) => c.decoration is BoxDecoration);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(10));

      final detector = tester.widget<GestureDetector>(find.byType(GestureDetector));
      expect(detector.behavior, HitTestBehavior.deferToChild);
    });
  });
}
