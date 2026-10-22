import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_first_character.dart';
import 'package:pleya/screens/libraries/alpha_jump_helper.dart';
import 'package:pleya/screens/libraries/alpha_scroll_crown.dart';
import 'package:pleya/screens/libraries/alpha_scroll_handle.dart';

const _chars = [
  LibraryFirstCharacter(key: '#', title: '#', size: 10),
  LibraryFirstCharacter(key: 'A', title: 'A', size: 10),
  LibraryFirstCharacter(key: 'B', title: 'B', size: 10),
  LibraryFirstCharacter(key: 'C', title: 'C', size: 10),
];

Widget _host({required bool scrolling, required List<int> jumps, required List<int> ticks, bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: const Size(400, 700), disableAnimations: reduceMotion),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            height: 600,
            child: AlphaScrollHandle(
              firstCharacters: _chars,
              onJump: jumps.add,
              currentLetter: '#',
              isScrolling: scrolling,
              onLetterTick: () => ticks.add(1),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _showHandle(WidgetTester tester, List<int> jumps, List<int> ticks, {bool reduceMotion = false}) async {
  await tester.pumpWidget(_host(scrolling: false, jumps: jumps, ticks: ticks, reduceMotion: reduceMotion));
  await tester.pumpWidget(_host(scrolling: true, jumps: jumps, ticks: ticks, reduceMotion: reduceMotion));
  await tester.pumpAndSettle();
}

double _rotation(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.byKey(const ValueKey('alpha_scroll_crown')));
  return (paint.painter! as AlphaScrollCrownPainter).rotation;
}

void main() {
  test('every letter maps to the cumulative start offset of its titles', () {
    final helper = AlphaJumpHelper(_chars);
    expect([for (final l in helper.letters) helper.indexForLetter(l)], [0, 10, 20, 30]);
    expect(helper.letterAtFraction(0.0), '#');
    expect(helper.letterAtFraction(0.26), 'A');
    expect(helper.letterAtFraction(0.99), 'C');
  });

  testWidgets('dragging the roller jumps once and ticks once per letter change', (tester) async {
    final jumps = <int>[];
    final ticks = <int>[];
    await _showHandle(tester, jumps, ticks);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('alpha_scroll_crown'))));
    // Small steps: many drag updates land inside the same letter.
    for (var i = 0; i < 60; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
    }

    expect(find.byKey(const ValueKey('alpha_scroll_bubble')), findsOneWidget);
    expect(find.text('C'), findsOneWidget);

    await gesture.up();
    await tester.pump();

    expect(jumps, [10, 20, 30], reason: 'one jump to the start offset of each new letter');
    expect(ticks.length, 3, reason: 'one haptic tick per letter change, none within a letter');
    expect(find.byKey(const ValueKey('alpha_scroll_bubble')), findsNothing);
  });

  testWidgets('the roller turns with the drag', (tester) async {
    await _showHandle(tester, [], []);
    expect(_rotation(tester), 0);

    await tester.drag(find.byKey(const ValueKey('alpha_scroll_crown')), const Offset(0, 120));
    await tester.pump();

    expect(_rotation(tester), greaterThan(0));
  });

  testWidgets('reduce motion keeps the roller still but still scrubs', (tester) async {
    final jumps = <int>[];
    await _showHandle(tester, jumps, [], reduceMotion: true);

    await tester.drag(find.byKey(const ValueKey('alpha_scroll_crown')), const Offset(0, 300));
    await tester.pump();

    expect(_rotation(tester), 0);
    expect(jumps, isNotEmpty);
  });
}
