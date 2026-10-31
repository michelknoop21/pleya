/// The floating sheets of the iPhone library look, measured against the
/// reference at 402 pt wide and on a small iPhone (375 x 667).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_sort.dart';
import 'package:pleya/screens/libraries/sort_bottom_sheet.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/mobile/library_phone_look.dart';
import 'package:pleya/widgets/mobile/library_phone_sheet.dart';
import 'package:pleya/widgets/mobile/library_sort_glyph.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';

const _sizes = [Size(402, 874), Size(375, 667)];

List<MediaSort> _sorts(int n) => [for (var i = 0; i < n; i++) MediaSort(key: 'k$i', title: 'Sort $i')];

void main() {
  late BuildContext screen;

  Future<void> open(WidgetTester tester, Size size, Widget Function(BuildContext) builder) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
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
        presentation: OverlaySheetPresentation.floating,
        showDragHandle: true,
        backgroundColor: Colors.black,
        builder: builder,
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget sortSheet(int n) => SortBottomSheet(
    sortOptions: _sorts(n),
    selectedSort: _sorts(n).first,
    isSortDescending: false,
    phoneStyle: true,
    onSortChanged: (_, _) {},
  );

  Widget groupingSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const LibraryPhoneSheetHeading(title: 'Weergave'),
      LibraryPhoneSheetRow(title: 'Films', selected: true, onTap: () {}),
      LibraryPhoneSheetRow(title: 'Mappen', selected: false, onTap: () {}),
    ],
  );

  Widget filterSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const LibraryPhoneSheetHeading(title: 'Filteren op'),
      Flexible(
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (var i = 0; i < 12; i++) LibraryPhoneSheetRow(title: 'Filter $i', selected: i == 0, onTap: () {}),
            ],
          ),
        ),
      ),
    ],
  );

  Material surface(WidgetTester tester, Finder inside) =>
      tester.widget<Material>(find.ancestor(of: inside, matching: find.byType(Material)).first);

  Rect surfaceRect(WidgetTester tester, Finder inside) =>
      tester.getRect(find.ancestor(of: inside, matching: find.byType(Material)).first);

  for (final size in _sizes) {
    group('${size.width.toInt()} x ${size.height.toInt()}', () {
      testWidgets('floats 8 pt off the left, right and bottom with 37 pt corners', (tester) async {
        await open(tester, size, (_) => sortSheet(6));
        final rect = surfaceRect(tester, find.byType(SortBottomSheet));
        expect(rect.left, 8);
        expect(rect.right, size.width - 8);
        expect(rect.bottom, size.height - 8);
        expect(surface(tester, find.byType(SortBottomSheet)).borderRadius, BorderRadius.circular(37));
      });

      final sheets = <String, Widget Function(BuildContext)>{
        'filter': (_) => filterSheet(),
        'sort': (_) => sortSheet(12),
        'view': (_) => groupingSheet(),
      };
      for (final entry in sheets.entries) {
        testWidgets('the ${entry.key} sheet has exactly the shared edges and corners', (tester) async {
          await open(tester, size, entry.value);
          final material = tester.widget<Material>(find.byType(Material).last);
          final rect = tester.getRect(find.byType(Material).last);
          expect(
            (rect.left, rect.right, rect.bottom, material.borderRadius),
            (8.0, size.width - 8, size.height - 8, BorderRadius.circular(37)),
          );
        });
      }

      testWidgets('height follows the content, up to the maximum', (tester) async {
        await open(tester, size, (_) => groupingSheet());
        final low = surfaceRect(tester, find.byType(LibraryPhoneSheetHeading));
        expect(low.height, lessThan(size.height * 0.4));
      });

      testWidgets('a long list stops at 85 percent of the screen', (tester) async {
        await open(tester, size, (_) => sortSheet(40));
        final tall = surfaceRect(tester, find.byType(SortBottomSheet));
        expect(tall.height, closeTo(size.height * 0.85, 1));
      });

      testWidgets('grip is centred, the heading is centred and bold, rows are 46 pt apart', (tester) async {
        await open(tester, size, (_) => sortSheet(6));
        final rect = surfaceRect(tester, find.byType(SortBottomSheet));
        final grip = tester.getRect(
          find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == floatingSheetHandleWidth),
        );
        expect(grip.center.dx, closeTo(rect.center.dx, 0.5));
        final heading = find.text(t.libraries.sortBy);
        expect(tester.getCenter(heading).dx, closeTo(rect.center.dx, 0.5));
        expect(tester.widget<Text>(heading).style!.fontWeight, FontWeight.w700);
        final y0 = tester.getCenter(find.text('Sort 0')).dy;
        final y1 = tester.getCenter(find.text('Sort 1')).dy;
        expect(y1 - y0, closeTo(46, 0.5));
        expect(tester.getRect(find.text('Sort 0')).left - rect.left, closeTo(16, 0.5));
      });

      testWidgets('the first row hangs 46 pt under the heading, text in the middle of the row', (tester) async {
        await open(tester, size, (_) => sortSheet(6));
        final heading = tester.getCenter(find.text(t.libraries.sortBy)).dy;
        expect(tester.getCenter(find.text('Sort 0')).dy - heading, closeTo(LibraryPhoneMetrics.sheetRowHeight, 1));
        final rowBox = tester.getRect(find.ancestor(of: find.text('Sort 0'), matching: find.byType(SizedBox)).first);
        expect(tester.getCenter(find.text('Sort 0')).dy, closeTo(rowBox.center.dy, 0.5));
      });

      testWidgets('the active row carries the direction in the accent colour, no other row does', (tester) async {
        await open(tester, size, (_) => sortSheet(6));
        final glyph = tester.widget<LibrarySortGlyph>(find.byType(LibrarySortGlyph));
        expect(glyph.color, tokens(tester.element(find.text('Sort 0'))).accent);
        expect(glyph.descending, isFalse);
        expect(find.byType(LibrarySortGlyph), findsOneWidget);
      });
    });
  }
}
