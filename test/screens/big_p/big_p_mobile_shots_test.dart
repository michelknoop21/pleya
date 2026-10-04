// Visual evidence: Big P on iPhone (39 A to G) at 402x874 and on iPad (39 I)
// at 1180x820, with the app's fonts, over the 39 A mockup as Home. The header is the real one; the iOS
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
import 'big_p_mobile_fixtures.dart';

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
    _Phone phone = _iPhone17Pro,
    bool keyboard = false,
    Future<void> Function(BigPMobileSession session)? before,
    void Function(FakeAssistantController c)? answer,
  }) async {
    tester.view.physicalSize = phone.size * 2;
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
                    viewPadding: phone.safe,
                    padding: keyboard ? phone.safe.copyWith(bottom: 0) : phone.safe,
                    viewInsets: EdgeInsets.only(bottom: keyboard ? phone.keyboard : 0),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // No iPad Home without its balloon: black under the dim.
                      if (phone.size.width < 700)
                        RawImage(image: home, fit: BoxFit.cover, alignment: Alignment.topCenter),
                      if (phone.size.width >= 700) const ColoredBox(color: Colors.black),
                      // The real header over the mockup's.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: phone.safe.top,
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
                          height: phone.keyboard,
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
    if (answer != null) {
      answer(c);
      c.emit();
    }
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

  testWidgets('39-e answer with titles', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(tester, '39-e-antwoord-titels', c, before: (s) async => s.summon(), answer: answerTitles);
  });

  testWidgets('39-f watch stats', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(tester, '39-f-kijkcijfers', c, before: (s) async => s.summon(), answer: answerWatchStats);
  });

  testWidgets('39-g confirm', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(
      tester,
      '39-g-bevestigen',
      c,
      before: (s) async => s.summon(),
      answer: (c) => c
        ..prompt = 'Maak Sam aan en geef hem alleen Kids.'
        ..state = AssistantSurfaceState.working
        ..pending = createSam(),
    );
  });

  testWidgets('39-i iPad', skip: _dir == null, (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    await shoot(tester, '39-i-ipad', c, phone: _iPad, before: (s) async => s.summon(), answer: answerTitles);
  });

  for (final phone in _phones) {
    for (final keyboard in [false, true]) {
      final tag = '${phone.name}${keyboard ? '-kb' : ''}';
      testWidgets('sweep greet $tag', skip: _dir == null, (tester) async {
        final c = FakeAssistantController();
        addTearDown(c.dispose);
        await shoot(tester, 'sweep-$tag-greet', c, phone: phone, keyboard: keyboard, before: (s) async => s.summon());
      });
      testWidgets('sweep setup $tag', skip: _dir == null, (tester) async {
        final c = FakeAssistantController()..availability = AssistantAvailability.needsSetup;
        addTearDown(c.dispose);
        PleyaKeychain.debugForceSupported = true;
        addTearDown(() => PleyaKeychain.debugForceSupported = false);
        await shoot(tester, 'sweep-$tag-setup', c, phone: phone, keyboard: keyboard, before: (s) async => s.summon());
      });
    }
  }
}

typedef _Phone = ({String name, Size size, EdgeInsets safe, double keyboard});

/// The 402 one (iPhone 17 Pro) is what the 39 mockups are drawn at.
const _Phone _iPhone17Pro = (
  name: '402',
  size: Size(402, 874),
  safe: EdgeInsets.only(top: 54, bottom: 34),
  keyboard: 300,
);

/// 39 I: an 11-inch iPad in landscape.
const _Phone _iPad = (name: 'ipad', size: Size(1180, 820), safe: EdgeInsets.only(top: 24, bottom: 20), keyboard: 0);
const List<_Phone> _phones = [
  _iPhone17Pro,
  (name: 'se', size: Size(375, 667), safe: EdgeInsets.only(top: 20), keyboard: 260),
  (name: '440', size: Size(440, 956), safe: EdgeInsets.only(top: 62, bottom: 34), keyboard: 346),
];
