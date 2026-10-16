import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/household_kids_store.dart';
import 'package:pleya/screens/settings/household_kids/household_birth_picker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_household_kids_card.dart';

void main() {
  final h = t.assistant.household;

  Future<List<List<HouseholdKid>>> pump(WidgetTester tester, {int existing = 0, VoidCallback? onClose}) async {
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
              onClose: onClose,
              loadExisting: () async => [
                for (var i = 0; i < existing; i++) HouseholdKid(id: 'e$i', name: 'E$i', birthMonth: '2005-01'),
              ],
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

  testWidgets('a double tap on Bewaar hands the children over once', (tester) async {
    final saved = await pump(tester);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.saveAndSearch));
    await tester.tap(find.text(h.saveAndSearch));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
  });

  testWidgets('with 8 stored children the card says so and has a way out', (tester) async {
    var closed = 0;
    final saved = await pump(tester, existing: 8, onClose: () => closed++);
    expect(find.text(h.cardFull), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text(t.common.close));
    expect(closed, 1);
    expect(saved, isEmpty);
  });

  testWidgets('with 7 stored children only one more fits', (tester) async {
    final saved = await pump(tester, existing: 7);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(h.addAnother));
    await tester.tap(find.text(h.addAnother));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'the cap is reached');
    expect(find.text(h.limit), findsOneWidget);
    await tester.tap(find.text(h.saveAndSearch));
    await tester.pumpAndSettle();
    expect(saved.single.map((k) => k.name), ['Sam']);
  });
}
