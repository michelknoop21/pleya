/// Big P's face button in both stages (39 A parked, 39 B out) and the empty
/// balloon the conversation sits in, as pixels.
///
/// The widget tests in `test/screens/big_p/` prove which stage the button
/// is in and what it does on a tap. They cannot see the ring: a parked face
/// that loses its clip shows the whole portrait spilling over the header,
/// and an out ring with the wrong stroke reads as a disabled button. The
/// talking avatar stays out of this file on purpose: it moves, and a golden
/// of something that moves is a flaky golden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_face_button.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/big_p/big_p_balloon.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../widgets/big_p/fake_assistant_controller.dart';

/// One face button on its own session, so the two stages sit side by side.
Widget _face(BigPMobileSession session) =>
    ChangeNotifierProvider<BigPMobileSession>.value(value: session, child: const BigPFaceButton());

Widget _scene(BigPMobileSession parked, BigPMobileSession out) {
  final theme = monoTheme(dark: true);
  return TranslationProvider(
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: theme.extension<MonoTokens>()!.bg,
        body: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _face(parked),
              _face(out),
              const BigPBalloon(child: SizedBox(width: 180, height: 64)),
            ],
          ),
        ),
      ),
    ),
  );
}

FakeAssistantController _controller() {
  final c = FakeAssistantController()..availability = AssistantAvailability.needsSetup;
  addTearDown(c.dispose);
  return c;
}

BigPMobileSession _session(FakeAssistantController c) {
  final s = BigPMobileSession(c);
  addTearDown(s.dispose);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocale(AppLocale.nl);
  });

  testWidgets('the face button parked and out, beside an empty balloon', (tester) async {
    setGoldenSurfaceSize(tester, size: const Size(420, 140));
    final parked = _session(_controller());
    final out = _session(_controller())..summon();
    expect(out.stage, BigPStage.out);

    await tester.pumpWidget(_scene(parked, out));
    // The portrait layers decode through the engine codec, which the fake
    // clock never drives: precache every one of them for real.
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pumpAndSettle();

    await expectMatchesGolden(find.byType(Scaffold), 'big_p_face_button');
  });
}
