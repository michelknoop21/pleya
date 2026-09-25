/// The floating glass tab bar (Liquid Glass Task 5, mockup LG-01).
///
/// All on [MobileMainScaffold], the shell `MainScreen` mounts. (a) Setting
/// off: the Task 4 bar, untouched, and the Scaffold does not extend its
/// body. (b) Setting on, iPhone-sized: one glass capsule, body extended.
/// (c) Review Focus 3 on a stub list; the real tab roots are in
/// `glass_tab_roots_test.dart`. (d) Contrast of labels and the active glyph
/// over the lightest real fixture (Big Buck Bunny), fake tier, i.e. the
/// floor. (e) The offline reconnect strip. (f) The header's search circle.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/screens/main/mobile_tab_bar_theme.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_discovery_shell.dart';

import '../test_helpers/contrast.dart';
import '../test_helpers/glass_phone.dart';
import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';

late final ui.Image _lightSceneImage;

const _kSceneKey = Key('scene');

Future<void> _phone(WidgetTester tester, {required bool glass}) => glassPhone(tester, glass: glass);

Widget _shell(WidgetBuilder body, {Widget? reconnectStrip, bool transparentForeground = false}) =>
    glassMainShell(body, reconnectStrip: reconnectStrip, transparentForeground: transparentForeground);

Widget _longList(BuildContext context, {bool tail = true}) => CustomScrollView(
  slivers: [
    SliverList.builder(
      itemCount: 40,
      itemBuilder: (_, i) => SizedBox(key: ValueKey('row-$i'), height: 120, child: Text('row $i')),
    ),
    if (tail) mobileDiscoveryTailSliver(context),
  ],
);

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    _lightSceneImage = (await codec.getNextFrame()).image;
  });
  setUp(() => resetSharedPreferencesForTest());

  testWidgets('(a) glas uit: de balk van vandaag, full-width, body niet eronder', (tester) async {
    await _phone(tester, glass: false);
    await tester.pumpWidget(_shell((_) => const SizedBox.expand()));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsNothing);
    final blurs = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).toList();
    expect(blurs, hasLength(1));
    expect(blurs.single.filter, ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isFalse);

    // Edge to edge and flush with the bottom, the theme's own bar color.
    final bar = tester.getRect(find.byType(NavigationBar));
    expect(bar.left, 0);
    expect(bar.width, 393);
    expect(bar.bottom, 852);
    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(theme.backgroundColor, const Color(0xE60F0F0F));
  });

  testWidgets('(b) glas aan: één glazen capsule, zwevend, body eronder', (tester) async {
    await _phone(tester, glass: true);
    await tester.pumpWidget(_shell((_) => const SizedBox.expand()));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);

    final plate = tester.getRect(find.byType(GlassSurface));
    expect(plate.left, 16);
    expect(plate.right, 393 - 16);
    expect(plate.height, 64);
    expect(plate.bottom, 852 - 34 - 10);
    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(theme.backgroundColor, Colors.transparent);
  });

  testWidgets('(c) Review Focus 3: de laatste rij scrollt vrij boven de zwevende balk', (tester) async {
    await _phone(tester, glass: true);
    await tester.pumpWidget(_shell((context) => _longList(context)));
    await tester.pumpAndSettle();

    final last = find.byKey(const ValueKey('row-39'));
    await tester.scrollUntilVisible(last, 300);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(GlassSurface)).dy;
    expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(barTop));
  });

  testWidgets('(c) controle: zonder staart-padding verdwijnt de laatste rij achter de balk', (tester) async {
    await _phone(tester, glass: true);
    await tester.pumpWidget(_shell((context) => _longList(context, tail: false)));
    await tester.pumpAndSettle();

    final last = find.byKey(const ValueKey('row-39'));
    await tester.scrollUntilVisible(last, 300);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(GlassSurface)).dy;
    expect(tester.getBottomLeft(last).dy, greaterThan(barTop));
  });

  group('(d) contrast over Big Buck Bunny (nepglas = ondergrens)', () {
    // The real bar over the scene's lightest band (fur, sunlit bark), labels
    // painted transparent with their shadows kept and glyphs hidden, as the
    // meter requires.
    Future<void> pumpBarOverScene(WidgetTester tester) async {
      await _phone(tester, glass: true);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _kSceneKey,
          child: _shell(
            (_) => Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 180,
                  child: RawImage(image: _lightSceneImage, fit: BoxFit.cover),
                ),
              ],
            ),
            transparentForeground: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<double> measure(WidgetTester tester, Finder area, Color color) =>
        textContrastOverBackground(tester, area: area, textColor: color, boundary: find.byKey(_kSceneKey));

    testWidgets('elk label, ook het actieve, is wit en haalt 4,5:1', (tester) async {
      await pumpBarOverScene(tester);
      final ratios = <String, double>{};
      for (final tab in glassPhoneTabs()) {
        ratios[tab.getLabel()] = await measure(tester, find.text(tab.getLabel()), Colors.white);
      }
      // ignore: avoid_print - the measured ratios belong in the test log
      print('glass tab bar contrast, labels (white): $ratios');
      for (final ratio in ratios.values) {
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });

    // The active glyph stays kAccent (#E5140F): a graphic needs 3:1 (WCAG
    // 1.4.11), the red tops out at 4.36:1 on pure black.
    testWidgets('actief rood icoon haalt 3:1', (tester) async {
      await pumpBarOverScene(tester);
      final glyph = find.byWidgetPredicate((w) => w is AutomationNode && w.id == 'nav.discover').first;
      final ratio = await measure(tester, glyph, kAccent);
      // ignore: avoid_print - the measured ratios belong in the test log
      print('glass tab bar contrast, active red glyph: $ratio');
      expect(ratio, greaterThanOrEqualTo(3.0));
    });
  });

  test('verborgen labels houden hun compacte hoogte op glas', () {
    const base = NavigationBarThemeData(height: 56);
    expect(mobileGlassTabBarTheme(base).height, 56);
    expect(mobileGlassTabBarTheme(const NavigationBarThemeData()).height, 64);
  });

  group('(e) offline-reconnectstrook', () {
    const strip = Material(
      key: Key('reconnect'),
      color: Color(0xFF2A2A2A),
      child: SizedBox(height: 40, child: Center(child: Text('Reconnect'))),
    );

    testWidgets('glas uit: volle breedte, direct op de balk', (tester) async {
      await _phone(tester, glass: false);
      await tester.pumpWidget(_shell((_) => const SizedBox.expand(), reconnectStrip: strip));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const Key('reconnect')));
      expect(rect.left, 0);
      expect(rect.width, 393);
      expect(rect.bottom, tester.getTopLeft(find.byType(NavigationBar)).dy);
    });

    testWidgets('glas aan: zwevende pil met de marges van de capsule', (tester) async {
      await _phone(tester, glass: true);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _kSceneKey,
          child: _shell(
            (_) => Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 260,
                  child: RawImage(image: _lightSceneImage, fit: BoxFit.cover),
                ),
              ],
            ),
            reconnectStrip: strip,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const Key('reconnect')));
      final plate = tester.getRect(find.byType(GlassSurface));
      expect(rect.left, plate.left);
      expect(rect.right, plate.right);
      expect(plate.top - rect.bottom, 8);
      expect(find.byType(ClipPath), findsWidgets);

      // PLEYA_GLASS_CAPTURE_DIR=<dir> writes the frame for a visual check.
      final dir = Platform.environment['PLEYA_GLASS_CAPTURE_DIR'];
      if (dir != null) {
        await tester.runAsync(() async {
          final image = await captureImage(tester.element(find.byKey(_kSceneKey)));
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/offline-strip-glass.png').writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  });

  // (f) Over the black header the phone plate would vanish; the control
  // tokens give a grey circle with a rim. White glyph on it: 3:1 minimum.
  testWidgets('(f) zoekcirkel: wit icoon op de controleplaat boven zwart haalt 3:1', (tester) async {
    await _phone(tester, glass: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: glassPhoneTheme(),
        home: const RepaintBoundary(
          key: _kSceneKey,
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: GlassLayer(
                tokens: GlassTokens.control(),
                child: GlassSurface(
                  shape: CircleBorder(),
                  tokens: GlassTokens.control(),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Icon(Icons.search, key: Key('glyph'), size: 24, color: Colors.transparent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ratio = await textContrastOverBackground(
      tester,
      area: find.byKey(const Key('glyph')),
      textColor: Colors.white,
      boundary: find.byKey(_kSceneKey),
    );
    // ignore: avoid_print - the measured ratios belong in the test log
    print('header search circle contrast, white glyph: $ratio');
    expect(ratio, greaterThanOrEqualTo(3.0));
    // And it is visible as a button: the plate is clearly lighter than black.
    expect(ratio, lessThan(21));
  });
}
