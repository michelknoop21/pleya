import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/tv_search_pill.dart';
import 'package:pleya/theme/mono_theme.dart';

void main() {
  Future<void> pumpPill(WidgetTester tester, {String? count, String text = 'as', double width = 1000}) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: TvSearchPill(
                  controller: TextEditingController(text: text),
                  countLabel: count,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // VIS1: 36 B draws the pill at half the content column, starting on its left
  // edge, with the count on the pill's midline.
  testWidgets('takes half the row from its left edge', (tester) async {
    await pumpPill(tester, count: '2 resultaten');
    final row = tester.getRect(find.byType(TvSearchPill));
    final pill = tester.getRect(find.byType(InputDecorator));
    expect(pill.left, row.left);
    expect(pill.width, row.width * TvSearchPill.widthFactor);
  });

  // This harness centers the count with or without the Center in the pill, so
  // it guards the result rather than reproducing the TV bug; the evidence for
  // the fix is `tvos.search.results`, screenshot 02-results.
  testWidgets('puts the count on the midline of the pill', (tester) async {
    await pumpPill(tester, count: '2 resultaten');
    final pill = tester.getRect(find.byType(InputDecorator));
    final count = tester.getRect(find.text('2 resultaten'));
    expect(count.center.dy, moreOrLessEquals(pill.center.dy, epsilon: 0.5));
    expect(count.right, lessThan(pill.right));
  });

  testWidgets('keeps a long hint on one line', (tester) async {
    // Two lines of the test font still fit the decorator's 48-point minimum,
    // so the pill's height cannot show a wrap; the hint's own height can.
    await pumpPill(tester, text: '');
    final wide = tester.getSize(find.text(t.search.hint)).height;
    await pumpPill(tester, text: '', width: 200);
    expect(tester.getSize(find.text(t.search.hint)).height, wide);
  });

  testWidgets('shows no count while there is nothing to count', (tester) async {
    await pumpPill(tester);
    expect(find.text('2 resultaten'), findsNothing);
  });
}
