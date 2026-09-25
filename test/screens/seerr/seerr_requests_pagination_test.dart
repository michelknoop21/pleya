import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: InputModeTracker(child: Scaffold(body: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('the trailing request row loads automatically', (tester) async {
    var calls = 0;
    await _pump(tester, SeerrAutoLoadMoreListTile(loading: false, failed: false, onLoadMore: () => calls++));
    await tester.pump();

    expect(calls, 1);
    expect(find.text(t.seerr.loadMore), findsNothing);
  });

  testWidgets('a failed automatic request load waits for an explicit retry', (tester) async {
    var calls = 0;
    await _pump(tester, SeerrAutoLoadMoreListTile(loading: false, failed: true, onLoadMore: () => calls++));
    await tester.pump();

    expect(calls, 0);
    await tester.tap(find.text(t.common.retry));
    expect(calls, 1);
  });
}
