import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/media_detail/mobile/light_ink_plate.dart';

void main() {
  testWidgets('light plate is translucent blurred glass, not an opaque fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: const Scaffold(body: LightInkPlate(child: Text('Kijklijst'))),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(BackdropFilter), matching: find.byType(DecoratedBox)),
    );
    final color = (box.decoration as BoxDecoration).color!;
    expect(color.a, lessThan(0.7));
    expect(color.a, greaterThan(0.2));
  });

  testWidgets('dark theme gets the child untouched', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: LightInkPlate(child: Text('Kijklijst'))),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
