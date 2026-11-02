/// CAT-SCROLL429, Roadmap A-06c: full-bleed navigation during scrolling.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../test_helpers/tv_full_bleed_catalog_harness.dart';

void main() {
  FullBleedHarness.setUpAllTv();
  setUpAll(() => initializeDateFormatting('en'));
  testWidgets('450 titles preserve row and column during interrupted directional scrolling', (tester) async {
    final h = await FullBleedHarness.create([for (var i = 0; i < 450; i++) fakeMovie(i, year: 2020)]);
    await h.pump(tester, canvas: const Size(1038, 584));
    await h.open(tester);
    expect(h.catalog.snapshot.groups.length, 450);
    final pitch = h.posterRect(tester, 7).top - h.posterRect(tester, 1).top;
    var expected = 0;
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 30));
      expected += 6;
      expect(h.focused, h.cardLabel(expected), reason: 'DOWN $i');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 30));
      expected++;
      expect(h.focused, h.cardLabel(expected), reason: 'RIGHT $i');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 30));
      expected--;
      expect(h.focused, h.cardLabel(expected), reason: 'LEFT $i');
    }
    await tester.pumpAndSettle();
    final top = h.posterRect(tester, 1).top;
    debugPrint('continuity row=$expected pitch=$pitch top=$top');
    expect(h.posterRect(tester, expected + 1).top, closeTo(h.posterRect(tester, expected - 5).top + pitch, 0.01));
    expect(tester.takeException(), isNull);
  });
}
