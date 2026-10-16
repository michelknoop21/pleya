// A long answer above cards (IMG_8925, 13 Oct 2026): the lead is a headline
// only while it fits two lines; a longer sentence reads as running text in
// up to three lines, so it is no longer cut after two bold lines.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_answer.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';

// The test font is Ahem, one em per character: 38 pt gives 20 characters a line
// in 760 pt, 31 pt gives 24, so 58 characters need three lines at callout size
// and more than two at headline size.
const _headline = TextStyle(fontSize: 38, fontWeight: FontWeight.w700, height: 1.15);

Future<Text> _pump(WidgetTester tester, String text) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: Center(
        child: BigPScale(
          pt: 1,
          child: SizedBox(
            width: 760,
            child: BigPAnswer(text: text, style: _headline, bodyLines: 0),
          ),
        ),
      ),
    ),
  );
  final body = find.byKey(const ValueKey('assistant.answer.body'));
  return tester.widget<Text>(body.evaluate().isNotEmpty ? body : find.byKey(const ValueKey('assistant.answer')));
}

void main() {
  testWidgets('a long lead above cards moves into the reading box, whole', (tester) async {
    const sentence =
        'Right now the most popular are the film Dune: Part Two, the series Shogun and the series Carrie (2024), '
        'with Interstellar and Gravity close behind';
    final text = await _pump(tester, sentence);
    expect(text, isA<Text>());
    expect(text.data, sentence);
    expect(text.style!.fontSize, TvHig.callout);
    expect(text.style!.fontWeight, FontWeight.w400);
    // No cut: nothing is ellipsised and the rest scrolls into view.
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
    final box = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('assistant.answer.body')).last);
    expect(box.didExceedMaxLines, isFalse);
  });

  testWidgets('a lead that fits two headline lines stays a headline', (tester) async {
    final text = await _pump(tester, 'Dit zijn de beste kandidaten.');
    expect(text.style!.fontSize, 38);
    expect(text.style!.fontWeight, FontWeight.w700);
    expect(text.maxLines, 2);
  });
}
