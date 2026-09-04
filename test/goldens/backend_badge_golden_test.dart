/// [DEC-076] in pixels: the four backend badges are one ink set.
///
/// The widget tests in `test/widgets/backend_badge_test.dart` prove that every
/// branch is *handed* the same ink. They cannot prove it arrives: a tint on an
/// `Image` with the wrong blend mode paints a filled square, and one with the
/// right blend mode on the wrong asset paints a P that sits low and small in
/// its box. Both of those are green there and obvious here.
///
/// Rendered on both palettes because that is the whole point of an ink set —
/// on light the row has to go dark with the text around it, and the Pleya P
/// used to be the one glyph that stayed brand red on both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/backend_badge.dart';

import '../test_helpers/golden.dart';

/// The four badges beside the label they would carry in a real row, at the
/// muted ink `MediaCard`'s metadata line uses. Deliberately the muted ink and
/// not full-strength text: a glyph that ignores its colour is most visible
/// against neighbours that took a *weaker* one.
Widget _scene({required bool dark}) {
  final theme = monoTheme(dark: dark);
  final tokens = theme.extension<MonoTokens>()!;
  final ink = tokens.textMuted.withValues(alpha: 0.6);
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      backgroundColor: tokens.bg,
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final backend in MediaBackend.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BackendBadge(backend: backend, size: 24, color: ink),
                  const SizedBox(width: 6),
                  Text(backend.id, style: TextStyle(fontSize: 14, color: ink)),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFontsForGoldens);

  /// Both the PNG and the two SVGs decode asynchronously, and a golden taken
  /// before they land is a row of blanks that still passes on the next run.
  /// `precacheImage` covers the PNG; the SVGs have no equivalent hook, so the
  /// real elapsed pause inside `runAsync` is what lets their loaders finish.
  Future<void> settleAssets(WidgetTester tester) async {
    await tester.runAsync(() async {
      await precacheImage(const AssetImage('assets/branding/pleya_logo.png'), tester.element(find.byType(Scaffold)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the four badges read as one ink set on the dark palette', (tester) async {
    setGoldenSurfaceSize(tester, size: const Size(640, 120));

    await tester.pumpWidget(_scene(dark: true));
    await settleAssets(tester);

    await expectMatchesGolden(find.byType(Scaffold), 'backend_badge_set_dark');
  });

  testWidgets('and go dark with the text around them on the light palette', (tester) async {
    setGoldenSurfaceSize(tester, size: const Size(640, 120));

    await tester.pumpWidget(_scene(dark: false));
    await settleAssets(tester);

    await expectMatchesGolden(find.byType(Scaffold), 'backend_badge_set_light');
  });
}
