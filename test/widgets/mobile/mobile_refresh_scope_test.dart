import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_refresh_scope.dart';

void main() {
  testWidgets('a pull down calls onRefresh', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobileRefreshScope(
            onRefresh: () async => calls++,
            child: ListView(children: const [SizedBox(height: 2000)]),
          ),
        ),
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });
}
