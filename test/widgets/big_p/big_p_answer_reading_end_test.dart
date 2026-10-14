// The reading box scrolls by whole lines. Where the text engine's line is not
// the style's line (it rounds, and the system text scale changes it), a sliver
// is left under the last whole line. Scrolling that sliver took a press of its
// own that the eye could not see: on the tvOS simulator the first Down at the
// end of a lead above cards moved the text 2 pt and kept the focus (BP-09).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_answer.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';

Future<({List<double> moves, bool left})> _pressDown(
  WidgetTester tester, {
  required double fontSize,
  required double height,
  required double textScale,
}) async {
  final answer = FocusNode(debugLabel: 'answer');
  final below = FocusNode(debugLabel: 'below');
  addTearDown(answer.dispose);
  addTearDown(below.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), disableAnimations: true),
        child: Center(
          child: BigPScale(
            pt: 1,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BigPAnswer(
                    text: List.filled(21, 'woord').join(' '),
                    style: TextStyle(fontSize: fontSize, height: height),
                    lead: false,
                    bodyLines: 4,
                    focusNode: answer,
                  ),
                  Focus(focusNode: below, child: const SizedBox(height: 40, width: 100)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The box is a focus stop once it has measured that it overflows.
  await tester.pump();
  await tester.pump();
  answer.requestFocus();
  await tester.pump();
  final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!;
  final moves = <double>[];
  for (var i = 0; i < 8 && answer.hasFocus; i++) {
    final before = scroll.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 100));
    moves.add(scroll.offset - before);
  }
  return (moves: moves, left: below.hasFocus);
}

void main() {
  // A scroll that moves less than a line is the sliver: nothing to read in it.
  void expectNoSliverPress(List<double> moves, double line) {
    for (final m in moves.where((m) => m > 0)) {
      expect(m, greaterThanOrEqualTo(line - 0.5), reason: 'a press scrolled ${m}pt, less than a line ($line)');
    }
  }

  testWidgets('line metrics rounded up: the last scroll takes the sliver along, the next Down leaves', (tester) async {
    // 20.3 x 1.36 = 27.6 in the style, 28 as drawn.
    final r = await _pressDown(tester, fontSize: 20.3, height: 1.36, textScale: 1.0);
    expectNoSliverPress(r.moves, 27.6);
    expect(r.left, isTrue, reason: 'Down at the end must reach the control below; moves: ${r.moves}');
    expect(r.moves.last, 0, reason: 'the press that left scrolled nothing');
  });

  testWidgets('system text scale is part of the line: no sliver press either', (tester) async {
    final r = await _pressDown(tester, fontSize: 20, height: 1.2, textScale: 1.1);
    expectNoSliverPress(r.moves, 24 * 1.1);
    expect(r.left, isTrue, reason: 'moves: ${r.moves}');
  });
}
