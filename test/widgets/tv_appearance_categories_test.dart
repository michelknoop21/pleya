import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/theme/mono_theme.dart';
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
}
