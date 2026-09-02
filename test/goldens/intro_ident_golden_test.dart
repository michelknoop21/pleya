import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/intro_splash.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';

import '../test_helpers/golden.dart';

/// The ident, and the hand-off it exists for. Two pictures:
///
///  * at rest — the lockup and its tagline on the page ground, which is the
///    whole composition;
///  * mid-dissolve over the boot splash's own lockup — the seam this design
///    closes: what shows through is the same picture, so only the ident's
///    copy is seen to go.
///
/// The page under the ident is [PleyaBrandLockup] on [identGround], which is
/// exactly what `SetupScreen` draws; the progress line is left out because it
/// is the one thing in that screen that is not the lockup.
void main() {
  setUpAll(loadAppFontsForGoldens);
  setUp(IntroGate.debugResetForTesting);

  Future<void> pump(WidgetTester tester, Widget page) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: true),
        home: IntroGate(child: page),
      ),
    );
    for (final asset in PleyaWordmark.assets) {
      await tester.runAsync(() => precacheImage(AssetImage(asset), tester.element(find.byType(IntroGate))));
    }
    await tester.pump();
  }

  Widget bootSplash() => Builder(
    builder: (context) => ColoredBox(
      color: identGround(context),
      child: const Center(child: PleyaBrandLockup(height: kIdentLockupHeight)),
    ),
  );

  testWidgets('the ident at rest', (tester) async {
    await pump(tester, const ColoredBox(color: Colors.black));
    await tester.pump(const Duration(milliseconds: 1000));
    await expectMatchesGolden(find.byType(MaterialApp), 'intro_ident_rest');
  });

  testWidgets('the ident dissolving into the boot splash', (tester) async {
    await pump(tester, bootSplash());
    await tester.pump(IntroGate.duration - const Duration(milliseconds: 230));
    await expectMatchesGolden(find.byType(MaterialApp), 'intro_ident_dissolve');
  });
}
