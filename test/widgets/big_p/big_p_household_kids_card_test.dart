import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/household_kids_store.dart';
import 'package:pleya/screens/settings/household_kids/household_birth_picker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_household_kids_card.dart';

void main() {
  final h = t.assistant.household;

  Future<List<List<HouseholdKid>>> pump(WidgetTester tester) async {
    final saved = <List<HouseholdKid>>[];
    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: BigPHouseholdKidsCard(
              embedded: true,
              now: DateTime(2026, 10, 16),
              style: HouseholdPickerStyle.dropdown,
              onSave: saved.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return saved;
  }

  testWidgets('Bewaar en zoek verder stays off until there is a name', (tester) async {
    final saved = await pump(tester);
    await tester.tap(find.text(h.saveAndSearch));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('one child is handed over on save', (tester) async {
    final saved = await pump(tester);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.saveAndSearch));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.single.name, 'Sam');
    expect(saved.single.single.birthMonth, '2026-10');
  });

  testWidgets('Nog een kind toevoegen keeps the first as a line and saves both', (tester) async {
    final saved = await pump(tester);
    await tester.enterText(find.byType(TextField), 'Noor');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(h.addAnother));
    await tester.tap(find.text(h.addAnother));
    await tester.pumpAndSettle();
    expect(find.text('Noor'), findsOneWidget, reason: 'the first child stands above the fields');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);

    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.saveAndSearch));
    await tester.pumpAndSettle();
    expect(saved.single.map((k) => k.name), ['Noor', 'Sam']);
  });
}
