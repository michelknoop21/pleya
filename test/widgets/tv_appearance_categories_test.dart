import 'package:flutter/material.dart';
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
}
