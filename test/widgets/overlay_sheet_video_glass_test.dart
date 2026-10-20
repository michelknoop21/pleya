/// Sheets of the player's host (A-23, Michel on 20 October 2026): with Liquid
/// Glass on they are a translucent plate over a light barrier, so the film
/// stays visible; on a phone in landscape they are 440 wide instead of the
/// 700 desktop box. Glass off, or any other host, keeps the flat sheet.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/overlay_sheet_surface.dart';
import 'package:pleya/widgets/video_controls/sheets/base_video_control_sheet.dart';

import '../test_helpers/contrast.dart';
import '../test_helpers/glass_phone.dart';
import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';

late final ui.Image _lightSceneImage;

const _kSceneKey = Key('scene');
const _kNameKey = Key('name');
const _kDetailKey = Key('detail');

/// iPhone 17 Pro in landscape, the way the player runs: 852x393 at 3x.
Future<void> _phoneLandscape(WidgetTester tester, {required bool glass}) async {
  tester.view.physicalSize = const Size(2556, 1179);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, glass);
  useFakeGlassTier();
}

/// Two handoff-style rows. [transparentInk] paints the text invisible with its
/// layout kept, for the contrast meter.
Widget _rows(BuildContext context, {bool transparentInk = false}) {
  final muted = Theme.of(context).extension<MonoTokens>()!.textMuted;
  Color ink(Color c) => transparentInk ? Colors.transparent : c;
  return BaseVideoControlSheet(
    title: 'Play on',
    icon: Icons.tv,
    shrinkWrap: true,
    child: ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          title: Text(
            'This iPhone',
            key: _kNameKey,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink(Colors.white)),
          ),
          subtitle: Text(
            'Playing here',
            key: _kDetailKey,
            style: TextStyle(fontSize: 12, color: ink(muted)),
          ),
        ),
        const ListTile(title: Text('Living room')),
      ],
    ),
  );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required bool glass,
  bool overVideo = true,
  ThemeData? theme,
  Widget? background,
  bool transparentInk = false,
}) async {
  await _phoneLandscape(tester, glass: glass);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? glassPhoneTheme(),
      home: RepaintBoundary(
        key: _kSceneKey,
        child: OverlaySheetHost(
          overVideo: overVideo,
          child: Builder(
            builder: (context) => Stack(
              fit: StackFit.expand,
              children: [
                background ?? const ColoredBox(color: Colors.black),
                Center(
                  child: TextButton(
                    onPressed: () => OverlaySheetController.of(
                      context,
                    ).show<void>(builder: (context) => _rows(context, transparentInk: transparentInk)),
                    child: const Text('Open'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// The black of the barrier at rest.
double _barrierAlpha(WidgetTester tester) => tester
    .widgetList<ColoredBox>(find.byType(ColoredBox))
    .map((b) => b.color)
    .firstWhere((c) => c.r == 0 && c.g == 0 && c.b == 0 && c.a > 0 && c.a < 1)
    .a;

/// Opacity of the host's own child (the player screen) while the sheet is open.
double _hostChildOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.ancestor(of: find.text('Open'), matching: find.byType(FadeTransition)).first)
    .opacity
    .value;

Rect _sheetRect(WidgetTester tester) => tester.getRect(find.byType(OverlaySheetSurface));

Color _sheetFill(WidgetTester tester) => tester
    .widget<Material>(find.descendant(of: find.byType(OverlaySheetSurface), matching: find.byType(Material)).first)
    .color!;

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    _lightSceneImage = (await codec.getNextFrame()).image;
  });
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  testWidgets('glas aan in de speler: een glazen plaat zonder backdrop, lichte barrier, 440 breed', (tester) async {
    await _pumpHost(tester, glass: true);

    final plate = tester.widget<GlassSurface>(
      find.descendant(of: find.byType(OverlaySheetSurface), matching: find.byType(GlassSurface)),
    );
    expect(plate.backdrop, isFalse, reason: 'mpv renders under the FlutterView; a backdrop paints black');
    expect(plate.tokens, kOverlaySheetVideoGlassTokens);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(_sheetFill(tester), Colors.transparent);
    expect(_barrierAlpha(tester), closeTo(0.2, 0.001));
    // The player's controls fade out under the plate; the film is native and stays.
    expect(_hostChildOpacity(tester), 0);

    final sheet = _sheetRect(tester);
    expect(sheet.width, 440);
    expect(sheet.center.dx, 852 / 2);
    expect(sheet.bottom, 393);
    // Shrink-wrapped to its rows, so the film shows above it.
    expect(sheet.height, lessThan(393 * 0.85));
  });

  testWidgets('glas uit in de speler: de vlakke sheet en de oude barrier, wel compact', (tester) async {
    await _pumpHost(tester, glass: false);

    expect(find.byType(GlassSurface), findsNothing);
    expect(_sheetFill(tester), monoTheme(dark: true).colorScheme.surface);
    expect(_barrierAlpha(tester), closeTo(0.5, 0.001));
    expect(_hostChildOpacity(tester), 1);
    expect(_sheetRect(tester).width, 440);
  });

  testWidgets('glas aan buiten de speler: ongewijzigd, vlak en de 700-box', (tester) async {
    await _pumpHost(tester, glass: true, overVideo: false);

    expect(find.byType(GlassSurface), findsNothing);
    expect(_sheetFill(tester), monoTheme(dark: true).colorScheme.surface);
    expect(_barrierAlpha(tester), closeTo(0.5, 0.001));
    expect(_sheetRect(tester).width, 700);
  });

  testWidgets('licht thema: de glazen plaat blijft donker en de inkt wordt licht', (tester) async {
    await _pumpHost(tester, glass: true, theme: monoTheme(dark: false).copyWith(platform: TargetPlatform.iOS));

    expect(find.byType(GlassSurface), findsOneWidget);
    final inner = Theme.of(tester.element(find.text('Living room')));
    expect(inner.brightness, Brightness.dark);
    expect(DefaultTextStyle.of(tester.element(find.text('Living room'))).style.color, isNot(const Color(0xFF111111)));
  });

  testWidgets('contrast over Big Buck Bunny: naam en detailregel halen 4,5:1', (tester) async {
    await _pumpHost(
      tester,
      glass: true,
      background: RawImage(image: _lightSceneImage, fit: BoxFit.cover),
      transparentInk: true,
    );
    final muted = monoTheme(dark: true).extension<MonoTokens>()!.textMuted;
    Future<double> m(Key k, Color c) =>
        textContrastOverBackground(tester, area: find.byKey(k), textColor: c, boundary: find.byKey(_kSceneKey));
    final ratios = {
      'name': await m(_kNameKey, Colors.white),
      // Muted ink composited over black: the darkest it can end up, so conservative.
      'detail': await m(_kDetailKey, Color.alphaBlend(muted, Colors.black)),
    };
    // ignore: avoid_print - the measured ratios belong in the test log
    print('player sheet glass contrast: $ratios');
    expect(ratios['name'], greaterThanOrEqualTo(4.5));
    expect(ratios['detail'], greaterThanOrEqualTo(4.5));
  });
}
