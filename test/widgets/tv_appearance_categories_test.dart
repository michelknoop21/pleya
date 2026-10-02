import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/settings_section.dart';
import 'package:pleya/widgets/tv/tv_appearance_categories.dart';

void main() {
  testWidgets('TV-categorie wisselt de zichtbare instellingen en houdt de paginamarge vrij', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: TvAppearanceCategories(
            title: 'Uiterlijk',
            children: const [
              SettingsSectionHeader('Weergave'),
              ListTile(title: Text('Thema')),
              SettingsSectionHeader('Home'),
              ListTile(title: Text('Automatisch wisselen')),
              SettingsSectionHeader('Navigatie'),
              ListTile(title: Text('Startpagina')),
              SettingsSectionHeader('Inhoud'),
              ListTile(title: Text('Spoilers verbergen')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Thema'), findsOneWidget);
    expect(find.text('Automatisch wisselen'), findsNothing);
    expect(tester.getRect(find.text('Uiterlijk')).left, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Home').first);
    await tester.pump();
    expect(find.text('Thema'), findsNothing);
    expect(find.text('Automatisch wisselen'), findsOneWidget);

    if (const bool.fromEnvironment('PLEYA_VERIFY')) {
      final declared = AutomationRegistry.instance.snapshot()['declared'] as List<dynamic>;
      expect(declared.where((node) => node['id'] == 'settings.appearance.category[1]'), hasLength(1));
    }
  });
  // APP1: LEFT from any row lands on the active category, RIGHT from a
  // category lands on that category's first row, wherever the rows sit.
  group('APP1', () {
    Future<void> pumpCategories(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvAppearanceCategories(
              title: 'Uiterlijk',
              children: [
                const SettingsSectionHeader('Weergave'),
                ListTile(title: const Text('Thema'), onTap: () {}),
                const SettingsSectionHeader('Home'),
                for (var i = 0; i < 7; i++) ListTile(title: Text('Home $i'), onTap: () {}),
                const SettingsSectionHeader('Navigatie'),
                ListTile(title: const Text('Startpagina'), onTap: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    bool focusedWithin(WidgetTester tester, String text) {
      final focus = FocusManager.instance.primaryFocus;
      final context = focus?.context;
      if (context == null) return false;
      return find.descendant(of: find.byWidget(context.widget), matching: find.text(text)).evaluate().isNotEmpty ||
          find.ancestor(of: find.text(text), matching: find.byWidget(context.widget)).evaluate().isNotEmpty;
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('RIGHT from a category enters it on its first row', (tester) async {
      await pumpCategories(tester);
      expect(focusedWithin(tester, 'Weergave'), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedWithin(tester, 'Home'), isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('Home 0'), findsOneWidget);
      expect(focusedWithin(tester, 'Home 0'), isTrue);
    });

    testWidgets('LEFT from a low row returns to the active category', (tester) async {
      await pumpCategories(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 6; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedWithin(tester, 'Home 6'), isTrue);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedWithin(tester, 'Home'), isTrue);
      expect(focusedWithin(tester, 'Home 6'), isFalse);
    });
  });

  // VIS-0925-B: selected, focused and idle must read apart in every palette.
  // Ratios are WCAG contrast of each fill composited on the page background.
  // Measured 25 Sep 2026 (selected/idle, label, focused/idle, idle/page):
  //   Light 15.75, 17.63, 1.18, 1.12
  //   Dark  16.12, 18.42, 1.27, 1.14
  //   OLED  19.30, 21.00, 1.20, 1.09
  // The idle pill on OLED is the faintest step on purpose: it replaces a 12%
  // white outline that made the rail read as a table.
  group('VIS-0925-B selected versus focused', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final (name, dark, oled) in [('Light', false, false), ('Dark', true, false), ('OLED', true, true)]) {
      test(name, () {
        final tk = monoTheme(dark: dark, oled: oled).extension<MonoTokens>()!;
        Color fill({required bool selected, required bool focused}) =>
            Color.alphaBlend(tvCategoryPillFill(tk, selected: selected, focused: focused), tk.bg);
        final idle = fill(selected: false, focused: false);
        final focused = fill(selected: false, focused: true);
        final selected = fill(selected: true, focused: false);

        // Selected is unmistakable: a full ink pill against the idle pill.
        expect(ratio(selected, idle), greaterThan(10));
        // Its label is the page color, readable on it.
        expect(ratio(tk.bg, selected), greaterThan(7));
        // Focused and idle differ by fill (the ring does the rest), and the
        // idle pill still separates from the page without a border.
        expect(ratio(focused, idle), greaterThan(1.1));
        expect(ratio(idle, tk.bg), greaterThan(1.08));
      });
    }
  });
}
