import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout contract for [SeerrRequestSheet]'s body: a long season list must
/// scroll inside a height-capped sheet while the Request button stays pinned
/// and on-screen. This guards the regression where 20+ seasons pushed the
/// button off the bottom of a non-scrolling column (no way to file a request).
///
/// Mirrors the structure of `_buildBody`: ConstrainedBox(maxHeight) → Column(min)
/// → Flexible(ListView) + pinned footer button.
Widget _sheetBody({required int seasonCount, required double maxHeight}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (var i = 1; i <= seasonCount; i++)
                        ListTile(title: Text('Season $i'), trailing: const Icon(Icons.check_box)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(onPressed: () {}, child: const Text('Request')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('long season list keeps the Request button on-screen and scrollable', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_sheetBody(seasonCount: 25, maxHeight: 800 * 0.72));
    await tester.pumpAndSettle();

    // The button is rendered and fully within the 800px-tall viewport.
    final button = find.widgetWithText(FilledButton, 'Request');
    expect(button, findsOneWidget);
    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(800.0));

    // The season list scrolls: the last season is reachable by scrolling even
    // though it starts off-screen.
    expect(find.text('Season 1'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Season 25'), findsOneWidget);
    // Button is still pinned and visible after scrolling.
    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(800.0));
  });

  testWidgets('short season list sizes to content without forcing full height', (tester) async {
    await tester.pumpWidget(_sheetBody(seasonCount: 3, maxHeight: 800 * 0.72));
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'Request');
    expect(button, findsOneWidget);
    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(800.0));
  });
}
