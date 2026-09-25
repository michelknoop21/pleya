/// Liquid Glass Task 9 (LG-05): the TV player panel's card on glass.
///
/// Glass off keeps today's card (24-sigma blur). Glass on swaps only the
/// surface: a [GlassSurface] with tvOS tokens and no backdrop, because mpv
/// draws under the FlutterView and a Flutter backdrop would sample nothing.
/// Contrast is read over the lightest real fixture (Big Buck Bunny).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/glass/glass_text.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/video_controls/models/track_controls_state.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

late final ui.Image _scene;
const _kSceneKey = Key('scene');
const _kTitle = 'Big Buck Bunny';

Future<void> _pumpPanel(
  WidgetTester tester, {
  required bool glass,
  bool scene = false,
  TvInfoPanelRequest initial = TvInfoPanelRequest.information,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, glass);
  final player = FakeSyncPlayer(duration: const Duration(minutes: 9), position: const Duration(minutes: 2));
  addTearDown(player.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: _kSceneKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (scene) RawImage(image: _scene, fit: BoxFit.cover) else const ColoredBox(color: Colors.black),
            Material(
              type: MaterialType.transparency,
              child: TvInfoPanel(
                player: player,
                metadata: MediaItem(id: '1', backend: MediaBackend.plex, kind: MediaKind.movie, title: _kTitle),
                trackControlsState: TrackControlsState(
                  // ignore: no-empty-block - the tab only needs the row to exist
                  onCycleBoxFitMode: () {},
                  audioSyncOffset: 0,
                  subtitleSyncOffset: 0,
                  canControl: true,
                ),
                chapters: const [],
                onSeekToChapter: null,
                isAmbientEnabled: false,
                ambientSupported: false,
                // ignore: no-empty-block - ambient is not exercised here
                onSetAmbientIntensity: (_) {},
                // ignore: no-empty-block - closing is not exercised here
                onClose: () {},
                initial: initial,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    _scene = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  });

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Finder informationPill() => find.text(t.videoControls.tvPanel.information);
  Finder videoPill() => find.text(t.videoControls.tvPanel.video);

  Color pillFill(WidgetTester tester, Finder label) =>
      (tester
                  .widget<AnimatedContainer>(find.ancestor(of: label, matching: find.byType(AnimatedContainer)).first)
                  .decoration!
              as BoxDecoration)
          .color!;

  testWidgets('glas uit: de kaart van vandaag met blur sigma 24', (tester) async {
    await _pumpPanel(tester, glass: false);
    final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(blur.filter, ui.ImageFilter.blur(sigmaX: kTvPanelBlurSigma, sigmaY: kTvPanelBlurSigma));
    expect(kTvPanelBlurSigma, 24);
    expect(
      find.byType(DecoratedBox).evaluate().where((e) {
        final d = (e.widget as DecoratedBox).decoration;
        return d is ShapeDecoration && d.shape is RoundedRectangleBorder;
      }),
      isEmpty,
    );
    expect(pillFill(tester, videoPill()), TvPanelTheme.inactivePill);
    expect(pillFill(tester, informationPill()), TvPanelTheme.activePill);
  });

  testWidgets('glas aan: GlassSurface zonder backdrop, tvOS-tokens, geen blur en geen LiquidGlass', (tester) async {
    await _pumpPanel(tester, glass: true);
    final surface = tester.widget<GlassSurface>(find.byType(GlassSurface));
    expect(surface.backdrop, isFalse);
    expect(surface.tokens?.blur, 30);
    expect(surface.tokens?.edge, 0.40);
    expect(surface.shape, isA<RoundedRectangleBorder>());
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(LiquidGlassLayer), findsNothing);
    expect(pillFill(tester, videoPill()), TvPanelTheme.glassInactivePill);
    expect(pillFill(tester, informationPill()), TvPanelTheme.activePill);
    expect(DefaultTextStyle.of(tester.element(videoPill())).style.shadows, kGlassTextShadows);
  });

  testWidgets('glas aan: het paneel houdt dezelfde breedte en de pillen dezelfde plek', (tester) async {
    await _pumpPanel(tester, glass: false);
    final off = [tester.getRect(informationPill()), tester.getRect(videoPill())];
    await _pumpPanel(tester, glass: true);
    // The legacy card draws a 1px border inside its box; the glass rim is a
    // shape side. Both leave the pill row where it was, to the pixel.
    expect(tester.getRect(informationPill()).center.dx, closeTo(off[0].center.dx, 1));
    expect(tester.getRect(videoPill()).center.dx, closeTo(off[1].center.dx, 1));
  });

  testWidgets('contrast over Big Buck Bunny: pillabel en rijtitel 4,5:1, rijwaarde niet slechter dan de oude kaart', (
    tester,
  ) async {
    await _pumpPanel(tester, glass: true, scene: true, initial: TvInfoPanelRequest.video);
    final card = tester.getRect(find.byType(GlassSurface));
    final cardSurface = tester.widget<GlassSurface>(find.byType(GlassSurface));
    // On the Video tab, Information is an inactive pill: white on glass.
    final pillLabel = informationPill();
    final pillText = tester.widget<Text>(pillLabel).data!;
    final pillRect = tester.getRect(pillLabel);
    final pillBox = tester.getRect(find.ancestor(of: pillLabel, matching: find.byType(AnimatedContainer)).first);
    final pillStyle = DefaultTextStyle.of(tester.element(pillLabel)).style.merge(tester.widget<Text>(pillLabel).style);
    final row = find.byType(TvPanelRow).first;
    final rowTitle = find.descendant(of: row, matching: find.byType(Text)).first;
    final rowRect = tester.getRect(rowTitle);
    final rowStyle = DefaultTextStyle.of(tester.element(rowTitle)).style.merge(tester.widget<Text>(rowTitle).style);
    final rowText = tester.widget<Text>(rowTitle).data!;
    // A row value (the current track, aspect, ...): the muted tier, unfocused.
    final value = find
        .descendant(
          of: find.byType(TvPanelRow),
          matching: find.byWidgetPredicate((w) => w is Text && w.style?.color == TvPanelTheme.textMuted),
        )
        .first;
    final valueRect = tester.getRect(value);
    final valueStyle = DefaultTextStyle.of(tester.element(value)).style.merge(tester.widget<Text>(value).style);
    final valueText = tester.widget<Text>(value).data!;

    final now = find.textContaining('$_kTitle · ');
    final nowRect = tester.getRect(now);
    final nowStyle = DefaultTextStyle.of(tester.element(now)).style.merge(tester.widget<Text>(now).style);
    final nowText = tester.widget<Text>(now).data!;

    const pillKey = Key('pill'), rowKey = Key('row'), nowKey = Key('now'), valueKey = Key('value');
    Widget at(Rect r, Widget child) => Positioned.fromRect(rect: r, child: child);
    Future<void> pumpScene(Widget cardWidget) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: _kSceneKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RawImage(image: _scene, fit: BoxFit.cover),
                at(card, cardWidget),
                at(
                  pillBox,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: TvPanelTheme.glassInactivePill,
                      borderRadius: BorderRadius.circular(pillBox.height / 2),
                    ),
                  ),
                ),
                at(rowRect.inflate(12), const ColoredBox(color: TvPanelTheme.group)),
                at(valueRect.inflate(12), const ColoredBox(color: TvPanelTheme.group)),
                for (final (rect, key, text, style) in [
                  (pillRect, pillKey, pillText, pillStyle),
                  (nowRect, nowKey, nowText, nowStyle),
                  (rowRect, rowKey, rowText, rowStyle),
                  (valueRect, valueKey, valueText, valueStyle),
                ])
                  at(
                    rect,
                    Text(
                      text,
                      key: key,
                      style: style.copyWith(color: Colors.transparent),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<double> m(Key k, Color c) =>
        textContrastOverBackground(tester, area: find.byKey(k), textColor: c, boundary: find.byKey(_kSceneKey));

    // The real card's own surface and tokens, not a copy of a constant.
    await pumpScene(
      GlassSurface(
        shape: cardSurface.shape,
        tokens: cardSurface.tokens,
        backdrop: cardSurface.backdrop,
        child: const SizedBox(),
      ),
    );
    final ratios = {
      'pillLabel': await m(pillKey, Color.alphaBlend(pillStyle.color!, Colors.black)),
      'rowTitle': await m(rowKey, Color.alphaBlend(rowStyle.color!, Colors.black)),
      'rowValue': await m(valueKey, Color.alphaBlend(valueStyle.color!, Colors.black)),
      // Informational: the secondary now-line (textFaint, white 50%) is a
      // panel-wide muted tier, not part of this surface swap.
      'nowLineFaint': await m(nowKey, Color.alphaBlend(nowStyle.color!, Colors.black)),
    };

    // The old card (glass off): 24-sigma blur under TvPanelTheme.card.
    final radius = (cardSurface.shape as RoundedRectangleBorder).borderRadius;
    await pumpScene(
      ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: kTvPanelBlurSigma, sigmaY: kTvPanelBlurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(color: TvPanelTheme.card, borderRadius: radius),
          ),
        ),
      ),
    );
    final legacyRowValue = await m(valueKey, Color.alphaBlend(valueStyle.color!, Colors.black));

    // ignore: avoid_print - the measured ratios belong in the test log
    print('tv player panel glass contrast: $ratios, legacy rowValue: $legacyRowValue');
    expect(ratios['pillLabel'], greaterThanOrEqualTo(4.5));
    expect(ratios['rowTitle'], greaterThanOrEqualTo(4.5));
    // B3 floor: the row value is muted text (textMuted, white 72%). The old
    // card reads 4.38 over this light fixture, under 4.5:1, so 4.5 is not a
    // requirement the panel ever met. The chosen floor is the old card itself,
    // measured here on the same scene with the same meter: glass may not be
    // worse than the card it replaces (70% tint: 4.66; the 50% tint of
    // GlassTokens.tv gave 2.70).
    expect(ratios['rowValue'], greaterThanOrEqualTo(legacyRowValue));
  });
}
