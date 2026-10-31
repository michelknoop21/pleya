/// The filter row of the iPhone library look (A-06): the pencil and refresh of
/// the old toolbar now live behind its three dots, on every tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/libraries/mobile_library_filter_row.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:pleya/widgets/mobile/library_sort_glyph.dart';
import 'package:pleya/widgets/overlay_sheet.dart';

void main() {
  late List<String> calls;
  late FocusNode grouping;
  late FocusNode filters;
  late FocusNode sort;

  setUp(() {
    calls = [];
    grouping = FocusNode();
    filters = FocusNode();
    sort = FocusNode();
  });

  tearDown(() {
    grouping.dispose();
    filters.dispose();
    sort.dispose();
  });

  LibraryHeaderInfo browse() => LibraryHeaderInfo(
    itemCount: 485,
    actions: [
      LibraryHeaderAction(
        label: 'Groepering',
        value: 'Films',
        focusNode: grouping,
        onPressed: () => calls.add('grouping'),
      ),
      LibraryHeaderAction(
        label: 'Filters',
        pillLabel: 'Alles',
        icon: Symbols.filter_list_rounded,
        focusNode: filters,
        onPressed: () => calls.add('filters'),
      ),
      LibraryHeaderAction(
        label: 'Sorteren',
        value: 'Titel',
        sortDescending: false,
        focusNode: sort,
        onPressed: () => calls.add('sort'),
      ),
    ],
  );

  Future<void> pump(WidgetTester tester, LibraryHeaderInfo info, {bool canManage = true, bool dark = true}) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: dark),
          home: OverlaySheetHost(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: MobileLibraryFilterRow(
                  info: info,
                  onManage: canManage ? () => calls.add('manage') : null,
                  onRefresh: () => calls.add('refresh'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('pills open what they name, with the count on the right', (tester) async {
    await pump(tester, browse());

    await tester.tap(find.text('Films'));
    await tester.tap(find.text('Alles'));
    await tester.tap(find.text('Titel'));
    expect(calls, ['grouping', 'filters', 'sort']);

    expect(find.byType(LibrarySortGlyph), findsOneWidget);
    final count = tester.getRect(find.text('485'));
    expect(count.left, greaterThan(tester.getRect(find.text('Titel')).right));
  });

  testWidgets('the dots reach manage and refresh', (tester) async {
    await pump(tester, browse());

    await tester.tap(find.byIcon(Symbols.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text(t.libraries.manageLibraries), findsOneWidget);
    await tester.tap(find.text(t.common.refresh));
    await tester.pumpAndSettle();
    expect(calls, ['refresh']);
  });

  testWidgets('a tab without pills keeps the dots', (tester) async {
    await pump(tester, LibraryHeaderInfo.empty);

    expect(find.byIcon(Symbols.more_vert_rounded), findsOneWidget);
    expect(find.text('485'), findsNothing);
    await tester.tap(find.byIcon(Symbols.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.libraries.manageLibraries));
    await tester.pumpAndSettle();
    expect(calls, ['manage']);
  });

  testWidgets('without libraries there is nothing to manage', (tester) async {
    await pump(tester, LibraryHeaderInfo.empty, canManage: false);
    await tester.tap(find.byIcon(Symbols.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text(t.libraries.manageLibraries), findsNothing);
    expect(find.text(t.common.refresh), findsOneWidget);
  });

  testWidgets('pills and count stay readable on the light theme', (tester) async {
    await pump(tester, browse(), dark: false);

    double contrast(Color a, Color b) {
      final (light, dark) = a.computeLuminance() > b.computeLuminance() ? (a, b) : (b, a);
      return (light.computeLuminance() + 0.05) / (dark.computeLuminance() + 0.05);
    }

    final tk = tokens(tester.element(find.text('Titel')));
    final pillInk = tester.widget<Text>(find.text('Titel')).style!.color!;
    final countInk = tester.widget<Text>(find.text('485')).style!.color!;
    expect(contrast(pillInk, tk.surfaceElevated), greaterThanOrEqualTo(4.5));
    expect(contrast(countInk, tk.surface), greaterThanOrEqualTo(4.5));
  });

  testWidgets('every pill keeps a 44 pt tap target', (tester) async {
    await pump(tester, browse());
    expect(
      tester.getSize(find.ancestor(of: find.text('Titel'), matching: find.byType(GestureDetector)).first).height,
      greaterThanOrEqualTo(44),
    );
  });
}
