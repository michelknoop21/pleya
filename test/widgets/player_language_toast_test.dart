/// LANG1 / DEC-096, negatieve controle S: de toast van mockup 31 C en 31 D.
///
/// De tweede regel en de amberstip bestaan vóór deze bouwronde niet — de pil
/// had één regel en 1,2 seconde — dus dit bestand compileert niet op de code
/// van `eae19cb4`.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/widgets/video_controls/widgets/player_toast_indicator.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Stack(children: [Positioned.fill(child: child)]),
    ),
  ),
);

void main() {
  testWidgets('CONTROL S — de bevestiging toont beide regels', (tester) async {
    await _pump(
      tester,
      const PlayerToastIndicator(
        icon: Symbols.closed_caption_rounded,
        text: 'Subtitles: English · remembered for Severance',
        detail: 'The next episodes start this way. Your global preference stays Dutch.',
      ),
    );

    expect(find.text('Subtitles: English · remembered for Severance'), findsOneWidget);
    expect(find.text('The next episodes start this way. Your global preference stays Dutch.'), findsOneWidget);
  });

  testWidgets('CONTROL S — de terugvalmelding vervangt het glyph door de amberstip', (tester) async {
    await _pump(
      tester,
      const PlayerToastIndicator(
        icon: Symbols.closed_caption_rounded,
        text: 'No English subtitles in this episode · subtitles off',
        detail: 'Your preference for Severance stays English.',
        accent: true,
      ),
    );

    expect(find.byIcon(Symbols.closed_caption_rounded), findsNothing);
    final dot = tester.widget<Container>(
      find.descendant(of: find.byType(PlayerToastIndicator), matching: find.byType(Container)).last,
    );
    expect((dot.decoration! as BoxDecoration).color, const Color(0xFFF5A623));
  });

  testWidgets('CONTROL S — één regel blijft één regel', (tester) async {
    await _pump(tester, const PlayerToastIndicator(icon: Symbols.fast_forward_rounded, text: '2x'));

    expect(find.text('2x'), findsOneWidget);
    expect(find.byType(Column), findsWidgets);
  });

  test('CONTROL S — de controller draagt regel, detail en accent, en ruimt zichzelf op', () {
    fakeAsync((async) {
      final controller = PlayerToastController();
      addTearDown(controller.dispose);

      controller.show(
        Symbols.closed_caption_rounded,
        'Subtitles: English',
        detail: 'Remembered for Severance.',
        accent: true,
        duration: const Duration(seconds: 3),
      );

      expect(controller.current!.detail, 'Remembered for Severance.');
      expect(controller.current!.accent, isTrue);

      async.elapse(const Duration(seconds: 2));
      expect(controller.current, isNotNull);
      async.elapse(const Duration(seconds: 2));
      expect(controller.current, isNull);
    });
  });
}
