// Visual evidence: Big P on iPhone (39 A to D) at 402x874 with the app's
// fonts, over the 39 A mockup as Home. The header is the real one; the iOS
// keyboard is the mockup's, cut from 39 B. Skipped unless BIGP_SHOT_DIR is set:
//   BIGP_SHOT_DIR=/tmp/bigp flutter test test/screens/big_p/big_p_mobile_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/services/pleya_keychain.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/big_p_rig.dart';
import 'package:pleya/widgets/mobile/mobile_page_header.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../widgets/big_p/fake_assistant_controller.dart';

final _dir = Platform.environment['BIGP_SHOT_DIR'];
const _mockups = 'docs/assets/ios-unified/big-p-39';

Future<ui.Image> _image(String path) async {
  final bytes = File(path).readAsBytesSync();
  return (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
}

void main() {
  late ui.Image home;
  late ui.Image keys;

  setUpAll(() async {
    if (_dir == null) return;
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
    home = await _image('$_mockups/39-a-gezichtsknop.png');
    keys = await _image('$_mockups/39-b-opgeroepen.png');
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    FakeAssistantController c, {
    bool keyboard = false,
    Future<void> Function(BigPMobileSession session)? before,
  }) async {
    tester.view.physicalSize = const Size(804, 1748);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final session = BigPMobileSession(c);
    addTearDown(session.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: ChangeNotifierProvider<BigPMobileSession>.value(
            value: session,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    viewPadding: const EdgeInsets.only(top: 54, bottom: 34),
                    padding: const EdgeInsets.only(top: 54, bottom: 34),
                    viewInsets: EdgeInsets.only(bottom: keyboard ? 300 : 0),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RawImage(image: home, fit: BoxFit.fill),
                      // The real header over the mockup's.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 54,
                        height: 64,
                        child: ColoredBox(
                          color: Colors.black,
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            maxHeight: 200,
                            child: Material(
                              type: MaterialType.transparency,
                              child: MobilePageHeader(onSearchTap: () {}, activeProfile: null),
                            ),
                          ),
                        ),
                      ),
                      const BigPMobileHost(),
                      if (keyboard)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 300,
                          child: ClipRect(
                            child: RawImage(image: keys, fit: BoxFit.fitWidth, alignment: Alignment.bottomCenter),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final ctx = tester.element(find.byKey(boundary));
      for (final a in [
        for (final p in kBigPPoses) bigPPoseAsset(p),
        for (final m in kBigPMouths) bigPAsset('mouth-$m'),
        bigPAsset('brow-l'),
        bigPAsset('brow-r'),
        bigPAsset('aim-arm'),
        bigPAsset('wave-arm'),
        PleyaWordmark.markAsset,
      ]) {
        await precacheImage(AssetImage(a), ctx);
      }
    });
    await tester.pump(const Duration(milliseconds: 100));
    await before?.call(session);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('39-a face button', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(tester, '39-a-gezichtsknop', c);
  });

  testWidgets('39-b summoned', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(tester, '39-b-opgeroepen', c, before: (s) async => s.summon());
  });

  testWidgets('39-c no model', skip: _dir == null, (tester) async {
    final c = FakeAssistantController()..availability = AssistantAvailability.needsSetup;
    addTearDown(c.dispose);
    PleyaKeychain.debugForceSupported = true;
    addTearDown(() => PleyaKeychain.debugForceSupported = false);
    await shoot(tester, '39-c-geen-model', c, before: (s) async => s.summon());
  });

  testWidgets('39-d dictating', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(
      tester,
      '39-d-dicteren',
      c,
      keyboard: true,
      before: (s) async {
        s.summon();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'welke animatiefilms heb ik nog niet ge');
      },
    );
  });

  testWidgets('working', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(
      tester,
      'working',
      c,
      before: (s) async {
        s.summon();
        c
          ..prompt = 'Welke animatiefilms heb ik nog niet gezien?'
          ..state = AssistantSurfaceState.working
          ..steps = const [
            AssistantStep(index: 0, tool: 'search_catalog', serverName: 'Zolder', phase: AssistantStepPhase.done),
            AssistantStep(index: 1, tool: 'find_title', serverName: 'Zolder', phase: AssistantStepPhase.started),
          ]
          ..emit();
      },
    );
  });
}
