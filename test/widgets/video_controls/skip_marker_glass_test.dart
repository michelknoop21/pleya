/// LG-SKIP1: the skip button (Skip intro / Skip credits) follows Liquid Glass.
///
/// Glass off keeps the white pill. Glass on (iPhone and Apple TV) swaps only
/// the surface for the player's plate without backdrop: iPhone
/// [kPlayerGlassTokens] at black 60%, Apple TV `GlassTokens.tvFor(panel: true)`. The size
/// does not change. Contrast is read over a white frame, the worst case for a
/// plate without backdrop: the tint composites straight over the video.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/video_controls/mobile_video_controls_glass.dart';
import 'package:pleya/widgets/video_controls/widgets/skip_marker_button.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

const _kSceneKey = Key('scene');
const _kButtonKey = Key('skip');
const _kProbeKey = Key('probe');

enum _Device { phone, tv }

Future<void> _setUp(WidgetTester tester, _Device device, {required bool glass}) async {
  if (device == _Device.phone) {
    await glassPhone(tester, glass: glass);
  } else {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await tester.runAsync(() => SettingsService.getInstance());
    await SettingsService.instance.write(SettingsService.liquidGlass, glass);
  }
}

/// The button over [background]. [probe] adds an invisible box at that rect,
/// the area the contrast meter reads.
Future<void> _pump(
  WidgetTester tester,
  _Device device, {
  required bool glass,
  Color background = Colors.white,
  bool countdown = false,
  double progress = 0.4,
  Rect? probe,
}) async {
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  final theme = device == _Device.phone ? glassPhoneTheme() : monoTheme(dark: true);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: RepaintBoundary(
        key: _kSceneKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: background),
            Positioned(
              right: 24,
              bottom: 80,
              child: Material(
                type: MaterialType.transparency,
                child: SkipMarkerButton(
                  key: _kButtonKey,
                  marker: MediaMarker(id: 1, type: 'intro', startTimeOffset: 10000, endTimeOffset: 45000),
                  playerDuration: const Duration(minutes: 20),
                  hasNextEpisode: false,
                  isAutoSkipActive: countdown,
                  shouldShowAutoSkip: true,
                  autoSkipDelay: 5,
                  autoSkipProgress: progress,
                  focusNode: focusNode,
                  onActivate: () {},
                  onFocusDown: () {},
                  onFocusExit: () {},
                ),
              ),
            ),
            if (probe != null)
              Positioned.fromRect(
                rect: probe,
                child: const SizedBox(key: _kProbeKey),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// White ink against [plate] composited over white video.
double _whiteOn(Color plate) => 1.05 / (_luminance(Color.alphaBlend(plate, Colors.white)) + 0.05);

/// The glyph-free gap between label and icon, over the label's height: plate
/// pixels, the label's own shadow included, as `textContrastOverBackground`
/// counts it.
Rect _gapRect(WidgetTester tester) {
  final label = tester.getRect(find.descendant(of: find.byKey(_kButtonKey), matching: find.byType(Text)));
  return Rect.fromLTRB(label.right + 1, label.top, label.right + 7, label.bottom);
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  for (final device in _Device.values) {
    group(device.name, () {
      testWidgets('glas uit: de witte pil van vandaag', (tester) async {
        await _setUp(tester, device, glass: false);
        await _pump(tester, device, glass: false);
        expect(find.byType(GlassSurface), findsNothing);
        final decoration = tester
            .widgetList<Container>(find.descendant(of: find.byKey(_kButtonKey), matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.boxShadow != null);
        expect(decoration.color, Colors.white.withValues(alpha: 0.9));
        expect(decoration.boxShadow, hasLength(1));
        expect(tester.widget<Text>(find.text(t.videoControls.skipIntro)).style!.color, Colors.black);
      });

      testWidgets('glas aan: GlassSurface zonder backdrop, witte tekst, zelfde maat', (tester) async {
        await _setUp(tester, device, glass: false);
        await _pump(tester, device, glass: false);
        final offRect = tester.getRect(find.byKey(_kButtonKey));

        await SettingsService.instance.write(SettingsService.liquidGlass, true);
        await _pump(tester, device, glass: true);
        final surface = tester.widget<GlassSurface>(find.byType(GlassSurface));
        expect(surface.backdrop, isFalse);
        expect(surface.shape, isA<RoundedRectangleBorder>());
        expect(
          surface.tokens!.tint,
          device == _Device.phone ? const Color(0x99000000) : const GlassTokens.tvPanel().tint,
        );
        expect(tester.widget<Text>(find.text(t.videoControls.skipIntro)).style!.color, Colors.white);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.getRect(find.byKey(_kButtonKey)), offRect);
      });

      for (final countdown in [false, true]) {
        testWidgets('contrast wit label op de plaat over wit beeld (aftellen: $countdown)', (tester) async {
          await _setUp(tester, device, glass: true);
          await _pump(tester, device, glass: true, countdown: countdown, progress: 0.99);
          final gap = _gapRect(tester);
          await _pump(tester, device, glass: true, countdown: countdown, progress: 0.99, probe: gap);
          final ratio = await textContrastOverBackground(
            tester,
            area: find.byKey(_kProbeKey),
            textColor: Colors.white,
            boundary: find.byKey(_kSceneKey),
          );
          // ignore: avoid_print - the ratio goes into the register row
          print('LG-SKIP1 ${device.name} countdown=$countdown p95 ${ratio.toStringAsFixed(2)}');
          expect(ratio, greaterThanOrEqualTo(4.5));
        });
      }
    });
  }

  test('tint over wit beeld, zonder schaduw: iPhone en Apple TV halen 4,5:1', () {
    const red20 = Color(0x33E5140F);
    const phoneTint = Color(0x99000000);
    final phone = _whiteOn(phoneTint);
    final playerPlate = _whiteOn(kPlayerGlassTokens.tint);
    final tv = _whiteOn(const GlassTokens.tvPanel().tint);
    final phoneFill = 1.05 / (_luminance(Color.alphaBlend(red20, Color.alphaBlend(phoneTint, Colors.white))) + 0.05);
    // ignore: avoid_print - the ratios go into the register row
    print(
      'LG-SKIP1 flat: player plate ${playerPlate.toStringAsFixed(2)} phone ${phone.toStringAsFixed(2)} tv ${tv.toStringAsFixed(2)} phone+fill ${phoneFill.toStringAsFixed(2)}',
    );
    expect(phone, greaterThanOrEqualTo(4.5));
    expect(tv, greaterThanOrEqualTo(4.5));
    expect(phoneFill, greaterThanOrEqualTo(4.5));
    expect(kAccent.withValues(alpha: 0.2), red20);
  });
}
