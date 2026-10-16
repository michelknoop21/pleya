import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/household_kids_store.dart';
import 'package:pleya/screens/settings/household_kids/household_kids_screen.dart';
import 'package:pleya/theme/mono_theme.dart';

/// An in-memory store with the real store's rules (cap, kids profile).
class _Store implements HouseholdKidsStore {
  _Store(this.kids);
  List<HouseholdKid> kids;

  @override
  Future<List<HouseholdKid>> read() async => kids;

  @override
  Future<bool> save(List<HouseholdKid> next, {required bool kidsProfile}) async {
    if (kidsProfile || next.length > HouseholdKidsStore.maxKids) return false;
    kids = next;
    return true;
  }
}

final _now = DateTime(2026, 10, 16);
HouseholdKid _kid(String id, String name, String month) => HouseholdKid(id: id, name: name, birthMonth: month);

void main() {
  final h = t.assistant.household;

  Future<void> pump(WidgetTester tester, _Store store, {bool kids = false}) async {
    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: HouseholdKidsScreen(store: store, now: _now, isKidsProfile: () async => kids),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('add saves a child with the chosen month and shows the age', (tester) async {
    final store = _Store([]);
    await pump(tester, store);
    await tester.tap(find.text(h.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Sam ');
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.save));
    await tester.pumpAndSettle();
    expect(store.kids, hasLength(1));
    expect(store.kids.single.name, 'Sam');
    expect(store.kids.single.birthMonth, '2026-10');
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text(h.ageNewborn), findsOneWidget);
  });

  testWidgets('save stays off without a name', (tester) async {
    final store = _Store([]);
    await pump(tester, store);
    await tester.tap(find.text(h.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.save));
    await tester.pumpAndSettle();
    expect(store.kids, isEmpty);
    expect(find.text(h.save), findsOneWidget, reason: 'the sheet is still open');
  });

  testWidgets('edit changes the name of the child in place', (tester) async {
    final store = _Store([_kid('a', 'Noor', '2020-03')]);
    await pump(tester, store);
    expect(find.text(h.ageYears(n: 6)), findsOneWidget);
    await tester.tap(find.text('Noor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Noortje');
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.save));
    await tester.pumpAndSettle();
    expect(store.kids.single.id, 'a');
    expect(store.kids.single.name, 'Noortje');
    expect(store.kids.single.birthMonth, '2020-03');
  });

  testWidgets('delete asks for confirmation, and keeps the child on cancel', (tester) async {
    final store = _Store([_kid('a', 'Noor', '2020-03'), _kid('b', 'Sam', '2023-05')]);
    await pump(tester, store);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.delete));
    await tester.pumpAndSettle();
    expect(find.text(h.deleteTitle(name: 'Sam')), findsOneWidget);
    expect(find.textContaining(h.deleteLast), findsNothing, reason: 'not the last child');

    await tester.tap(find.text(t.common.cancel).last);
    await tester.pumpAndSettle();
    expect(store.kids, hasLength(2));

    await tester.tap(find.text(h.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.delete).last);
    await tester.pumpAndSettle();
    expect(store.kids.map((k) => k.name), ['Noor']);
    expect(find.text('Sam'), findsNothing);
  });

  testWidgets('deleting the last child warns that Big P asks again', (tester) async {
    final store = _Store([_kid('a', 'Noor', '2020-03')]);
    await pump(tester, store);
    await tester.tap(find.text('Noor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.delete));
    await tester.pumpAndSettle();
    expect(find.textContaining(h.deleteLast), findsOneWidget);
  });

  testWidgets('a swipe on the row asks before it deletes', (tester) async {
    final store = _Store([_kid('a', 'Noor', '2020-03'), _kid('b', 'Sam', '2023-05')]);
    await pump(tester, store);
    await tester.drag(find.text('Sam'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text(h.deleteTitle(name: 'Sam')), findsOneWidget);
    expect(store.kids, hasLength(2), reason: 'nothing is deleted before the yes');
    await tester.tap(find.text(h.delete).last);
    await tester.pumpAndSettle();
    expect(store.kids.map((k) => k.name), ['Noor']);
  });

  testWidgets('at 8 children there is no way to add a ninth', (tester) async {
    final store = _Store([for (var i = 0; i < 8; i++) _kid('k$i', 'Kind $i', '2022-0${i + 1}')]);
    await pump(tester, store);
    expect(find.text(h.add), findsNothing);
    expect(find.text(h.limit), findsOneWidget);
    // The store refuses it as well, whatever the screen shows.
    expect(await store.save([...store.kids, _kid('x', 'Negen', '2024-01')], kidsProfile: false), isFalse);
  });

  testWidgets('a child of 18 or older stays, with a line that says it no longer counts', (tester) async {
    final store = _Store([_kid('a', 'Oud', '2007-01')]);
    await pump(tester, store);
    expect(find.text('Oud'), findsOneWidget);
    expect(find.text(h.ageIgnored), findsOneWidget);
    expect(store.kids, hasLength(1));
  });

  testWidgets('a profile switched to a children\'s profile cannot write', (tester) async {
    final store = _Store([_kid('a', 'Noor', '2020-03')]);
    await pump(tester, store, kids: true);
    await tester.tap(find.text('Noor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Noortje');
    await tester.pumpAndSettle();
    await tester.tap(find.text(h.save));
    await tester.pumpAndSettle();
    expect(store.kids.single.name, 'Noor');
  });
}
