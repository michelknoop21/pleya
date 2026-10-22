/// The phone alphabet scrubber mid-drag, in both themes: the machined gear at
/// the right edge and the letter bubble beside it, over a stand-in poster
/// grid at iPhone width; plus the edge at rest, where only the hint line shows.
///
/// The widget tests in `test/screens/libraries/alpha_scroll_handle_test.dart`
/// prove the jumps, the haptic ticks and reduce motion. They cannot see the
/// gear itself: teeth that lose their shading read as a flat grey pill, and
/// that is what this golden guards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_first_character.dart';
import 'package:pleya/screens/libraries/alpha_scroll_handle.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';

import '../test_helpers/golden.dart';

const _size = Size(402, 520);

const _chars = [
  LibraryFirstCharacter(key: '#', title: '#', size: 12),
  LibraryFirstCharacter(key: 'A', title: 'A', size: 40),
  LibraryFirstCharacter(key: 'B', title: 'B', size: 30),
  LibraryFirstCharacter(key: 'C', title: 'C', size: 30),
];

Widget _scene({required bool dark}) {
  final theme = monoTheme(dark: dark);
  final tk = theme.extension<MonoTokens>()!;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Scaffold(
      backgroundColor: tk.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: GridView.count(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2 / 3,
              children: [
                for (var i = 0; i < 9; i++)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.08 + (i % 3) * 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: AlphaScrollHandle(
              firstCharacters: _chars,
              onJump: (_) {},
              onScrub: (_) {},
              readScrollFraction: () => 0,
              currentLetter: 'B',
              onToothTick: () {},
              onLetterTick: () {},
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pumpMidDrag(WidgetTester tester, {required bool dark}) async {
  setGoldenSurfaceSize(tester, size: _size);
  await tester.pumpWidget(_scene(dark: dark));
  final rail = find.byKey(const ValueKey('alpha_scroll_rail'));
  final gesture = await tester.startGesture(tester.getTopLeft(rail) + const Offset(22, 120));
  for (var i = 0; i < 14; i++) {
    await gesture.moveBy(const Offset(0, 6));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
  addTearDown(gesture.removePointer);
}

void main() {
  setUpAll(loadAppFontsForGoldens);

  testWidgets('alphabet scrubber mid-drag, dark', (tester) async {
    await _pumpMidDrag(tester, dark: true);
    await expectMatchesGolden(find.byType(MaterialApp), 'alpha_scroll_crown_dark');
  });

  testWidgets('alphabet scrubber at rest, dark', (tester) async {
    setGoldenSurfaceSize(tester, size: _size);
    await tester.pumpWidget(_scene(dark: true));
    await expectMatchesGolden(find.byType(MaterialApp), 'alpha_scroll_crown_rest_dark');
  });

  testWidgets('alphabet scrubber mid-drag, light', (tester) async {
    await _pumpMidDrag(tester, dark: false);
    await expectMatchesGolden(find.byType(MaterialApp), 'alpha_scroll_crown_light');
  });
}
