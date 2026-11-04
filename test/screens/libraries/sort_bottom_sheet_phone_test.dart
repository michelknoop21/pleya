/// The sort sheet in the iPhone library look (A-06).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_sort.dart';
import 'package:pleya/screens/libraries/sort_bottom_sheet.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/mobile/library_sort_glyph.dart';
import 'package:pleya/widgets/overlay_sheet.dart';

const _title = MediaSort(key: 'titleSort', title: 'Titel');
const _added = MediaSort(key: 'addedAt', title: 'Toegevoegd', defaultDirection: 'desc');

void main() {
  late List<(String, bool)> changes;
  late int clears;
  late BuildContext screen;

  setUp(() {
    changes = [];
    clears = 0;
  });

  Future<void> open(WidgetTester tester, {required bool phoneStyle, bool dark = true}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: dark),
          home: OverlaySheetHost(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  screen = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(
      OverlaySheetController.of(screen).show(
        builder: (_) => SortBottomSheet(
          sortOptions: const [_title, _added],
          selectedSort: _title,
          isSortDescending: false,
          phoneStyle: phoneStyle,
          onSortChanged: (sort, descending) => changes.add((sort.key, descending)),
          onClear: () => clears++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('heading centred, no rules, no radio dots, no extra rows', (tester) async {
    await open(tester, phoneStyle: true);

    final heading = tester.getRect(find.text(t.libraries.sortBy));
    expect(heading.center.dx, closeTo(393 / 2, 1));
    expect(find.byType(Divider), findsNothing);
    expect(find.byIcon(Symbols.radio_button_checked_rounded), findsNothing);
    expect(find.byIcon(Symbols.radio_button_unchecked_rounded), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('the chosen row carries the direction on the right, in the accent colour', (tester) async {
    await open(tester, phoneStyle: true);

    final glyph = find.byType(LibrarySortGlyph);
    expect(glyph, findsOneWidget);
    final context = tester.element(glyph);
    expect(tester.widget<LibrarySortGlyph>(glyph).color, tokens(context).accent);
    expect(tester.getCenter(glyph).dy, closeTo(tester.getCenter(find.text('Titel')).dy, 2));
    expect(tester.getCenter(glyph).dx, greaterThan(393 - 60));
  });

  testWidgets('tapping another row chooses it with its own default direction', (tester) async {
    await open(tester, phoneStyle: true);
    await tester.tap(find.text('Toegevoegd'));
    await tester.pumpAndSettle();
    expect(changes, [('addedAt', true)]);
    expect(find.byType(LibrarySortGlyph), findsOneWidget);
  });

  testWidgets('tapping the chosen row flips its direction', (tester) async {
    await open(tester, phoneStyle: true);
    await tester.tap(find.text('Titel'));
    await tester.pumpAndSettle();
    expect(changes, [('titleSort', true)]);
  });

  testWidgets('clearing the sort stays available', (tester) async {
    await open(tester, phoneStyle: true);
    await tester.tap(find.text(t.common.clear));
    await tester.pumpAndSettle();
    expect(clears, 1);
  });

  testWidgets('the clear action sits at the right edge, clear of the heading', (tester) async {
    await open(tester, phoneStyle: true);
    final heading = tester.getRect(find.text(t.libraries.sortBy));
    final clear = tester.getRect(find.text(t.common.clear));
    expect(clear.left, greaterThan(heading.right));
    expect(clear.right, greaterThan(393 - 60));
  });

  testWidgets('the shared sheet keeps its radio rows', (tester) async {
    await open(tester, phoneStyle: false);
    expect(find.byIcon(Symbols.radio_button_checked_rounded), findsOneWidget);
    expect(find.byType(LibrarySortGlyph), findsNothing);
  });
}
