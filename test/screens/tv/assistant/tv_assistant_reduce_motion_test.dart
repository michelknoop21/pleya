import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_answer.dart';

void main() {
  for (final answer in [true, false]) {
    for (final reduced in [true, false]) {
      testWidgets('${answer ? 'answer' : 'list'} scroll respects Reduce Motion=$reduced and reaches the end', (
        tester,
      ) async {
        final node = FocusNode();
        final scroll = ScrollController();
        addTearDown(node.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Center(
                child: SizedBox(
                  width: 400,
                  height: 160,
                  child: answer
                      ? BigPAnswer(
                          text: List.generate(40, (i) => 'Regel $i: voldoende tekst om te lezen.').join('\n'),
                          lead: false,
                          focusNode: node,
                          style: const TextStyle(fontSize: 20, height: 1.2),
                        )
                      : BigPReadableList(
                          controller: scroll,
                          focusNode: node,
                          child: Column(
                            children: [for (var i = 0; i < 40; i++) SizedBox(height: 24, child: Text('Regel $i'))],
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final controller = answer
            ? tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!
            : scroll;
        node.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final target = answer ? 120.0 : controller.position.viewportDimension * .6;
        if (reduced) {
          expect(controller.offset, closeTo(target, .01));
        } else {
          expect(controller.offset, lessThan(target));
          await tester.pump(const Duration(milliseconds: 240));
          expect(controller.offset, closeTo(target, .01));
        }
        for (var i = 0; i < 30; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 240));
        }
        expect(controller.offset, controller.position.maxScrollExtent);
        expect(node.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        expect(controller.offset, lessThan(controller.position.maxScrollExtent));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
