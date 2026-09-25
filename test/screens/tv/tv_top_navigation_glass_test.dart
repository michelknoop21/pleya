/// Liquid Glass Task 8 (LG-04): the TV top bar as one capsule of fake glass.
///
/// Against the production [TvTopNavigation] on an Apple TV override. Glass off
/// must be today's bar; glass on puts search and the destinations in one
/// [GlassSurface], never a `liquid_glass_renderer` widget, and swaps the ring
/// on the white active pill for a 1.08 scale plus a shadow. Contrast is read
/// over the lightest real fixture (Big Buck Bunny).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_top_nav_item.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

late final ui.Image _scene;
const _kSceneKey = Key('scene');

void main() {
  late FocusMemoryTracker nodes;

  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocaleSync(AppLocale.en);
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    _scene = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  });

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    nodes.dispose();
  });

  final destinations = buildTvDestinations(const TvNavConditions(hasLiveTv: false));

  Future<void> pumpBar(WidgetTester tester, {required bool glass, bool scene = false}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());
    await SettingsService.instance.write(SettingsService.liquidGlass, glass);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: RepaintBoundary(
              key: _kSceneKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (scene) RawImage(image: _scene, fit: BoxFit.cover) else const ColoredBox(color: Colors.black),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Material(
                      type: MaterialType.transparency,
                      child: TvTopNavigation(
                        destinations: destinations,
                        active: TvDestinationId.home,
                        nodes: nodes,
                        onSelect: (_) {},
                        onFocusDestination: (_) {},
                        onNavigateDown: () {},
                        onOpenProfiles: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Focus [id] with a D-pad key first, so the input mode is keyboard and the
  /// wrapper draws focus at all.
  Future<void> focus(WidgetTester tester, TvDestinationId id) async {
    nodes.get(id.focusKey).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    nodes.get(id.focusKey).requestFocus();
    await tester.pumpAndSettle();
  }

  Finder item(TvDestinationId id) => find.byKey(ValueKey(id.focusKey));

  /// Whether the wrapper's white ring is painted around [id].
  bool ringShown(WidgetTester tester, TvDestinationId id) => tester
      .widgetList<AnimatedContainer>(find.descendant(of: item(id), matching: find.byType(AnimatedContainer)))
      .map((c) => c.foregroundDecoration)
      .whereType<ShapeDecoration>()
      .any((d) => (d.shape as OutlinedBorder).side.color != Colors.transparent);

  double pillScale(WidgetTester tester, TvDestinationId id) {
    final scales = find.descendant(of: item(id), matching: find.byType(AnimatedScale));
    if (scales.evaluate().isEmpty) return 1;
    return tester.widget<AnimatedScale>(scales).scale;
  }

  testWidgets('glas uit: geen GlassSurface, ring op de actieve pil zoals vandaag', (tester) async {
    await pumpBar(tester, glass: false);
    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);

    await focus(tester, TvDestinationId.home);
    expect(ringShown(tester, TvDestinationId.home), isTrue);
    expect(pillScale(tester, TvDestinationId.home), 1);
  });

  testWidgets('glas aan: één capsule van nepglas met tvOS-tokens, geen liquid_glass_renderer', (tester) async {
    await pumpBar(tester, glass: true);
    expect(glassTierFor(tester.element(find.byType(TvTopNavigation))), GlassTier.fake);
    final surfaces = tester.widgetList<GlassSurface>(find.byType(GlassSurface));
    expect(surfaces, hasLength(1));
    expect(surfaces.single.shape, const StadiumBorder());
    expect(surfaces.single.tokens?.blur, const GlassTokens.tv().blur);
    expect(surfaces.single.tokens?.edge, const GlassTokens.tv().edge);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(LiquidGlassLayer), findsNothing);

    // Every destination sits inside the capsule; the profile chip does not.
    final capsule = tester.getRect(find.byType(GlassSurface));
    for (final id in destinations) {
      expect(capsule.contains(tester.getCenter(item(id))), isTrue, reason: id.name);
    }
    final chip = tester.getCenter(find.byType(ProfileAvatar));
    expect(capsule.contains(chip), isFalse);
  });

  testWidgets('de schakelaar werkt live: capsule verschijnt en verdwijnt zonder herstart', (tester) async {
    await pumpBar(tester, glass: false);
    expect(find.byType(GlassSurface), findsNothing);
    await SettingsService.instance.write(SettingsService.liquidGlass, true);
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsOneWidget);
    await SettingsService.instance.write(SettingsService.liquidGlass, false);
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsNothing);
  });

  testWidgets('glas aan: actieve pil zonder ring maar 1.08 en schaduw; inactieve pil met ring', (tester) async {
    await pumpBar(tester, glass: true);

    await focus(tester, TvDestinationId.home);
    expect(ringShown(tester, TvDestinationId.home), isFalse);
    expect(pillScale(tester, TvDestinationId.home), kTvNavGlassActiveFocusScale);
    final pill = tester
        .widgetList<AnimatedContainer>(
          find.descendant(of: item(TvDestinationId.home), matching: find.byType(AnimatedContainer)),
        )
        .map((c) => c.decoration)
        .whereType<ShapeDecoration>()
        .single;
    expect(pill.shadows, const [kTvNavGlassActiveFocusShadow]);

    final movies = destinations.firstWhere((d) => d != TvDestinationId.home && !d.isCompact);
    await focus(tester, movies);
    expect(ringShown(tester, movies), isTrue);
    expect(pillScale(tester, TvDestinationId.home), 1);
  });

  testWidgets('glas aan: de geometrie van de pillen verschuift niet tussen actief en inactief', (tester) async {
    await pumpBar(tester, glass: false);
    final off = {for (final id in destinations) id: tester.getSize(item(id))};
    await pumpBar(tester, glass: true);
    for (final id in destinations) {
      expect(tester.getSize(item(id)), off[id], reason: id.name);
    }
  });

  testWidgets('contrast over Big Buck Bunny: labels 4,5:1, zoekicoon 3:1', (tester) async {
    await pumpBar(tester, glass: true, scene: true);
    final idle = destinations.firstWhere((d) => d != TvDestinationId.home && !d.isCompact);
    final search = destinations.firstWhere((d) => d.isCompact);
    final idleLabel = find.descendant(of: item(idle), matching: find.text(idle.label));
    final homeLabel = find.descendant(of: item(TvDestinationId.home), matching: find.text(TvDestinationId.home.label));
    final icon = find.descendant(of: item(search), matching: find.byType(Icon));
    final idleRect = tester.getRect(idleLabel), homeRect = tester.getRect(homeLabel), iconRect = tester.getRect(icon);
    final idleStyle = tester.widget<Text>(idleLabel).style!;
    final homeStyle = tester.widget<Text>(homeLabel).style!;
    final idleColor = idleStyle.color!;
    final iconWidget = tester.widget<Icon>(icon);
    final capsuleRect = tester.getRect(find.byType(GlassSurface));

    // Same scene and bar; the measured glyphs are painted transparent with
    // their shadows kept, on top of the real capsule at the same rects.
    const idleKey = Key('idle'), homeKey = Key('home'), iconKey = Key('icon');
    Widget at(Rect r, Widget child) => Positioned.fromRect(rect: r, child: child);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: RepaintBoundary(
              key: _kSceneKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RawImage(image: _scene, fit: BoxFit.cover),
                  at(
                    capsuleRect,
                    const GlassSurface(shape: StadiumBorder(), tokens: GlassTokens.tv(), child: SizedBox.expand()),
                  ),
                  at(
                    homeRect.inflate(8),
                    const DecoratedBox(
                      decoration: ShapeDecoration(shape: StadiumBorder(), color: Colors.white),
                    ),
                  ),
                  at(
                    idleRect,
                    Text(
                      idle.label,
                      key: idleKey,
                      style: idleStyle.copyWith(color: Colors.transparent),
                    ),
                  ),
                  at(
                    homeRect,
                    Text(
                      TvDestinationId.home.label,
                      key: homeKey,
                      style: homeStyle.copyWith(color: Colors.transparent),
                    ),
                  ),
                  at(
                    iconRect,
                    Icon(
                      iconWidget.icon,
                      key: iconKey,
                      size: iconWidget.size,
                      color: Colors.transparent,
                      shadows: iconWidget.shadows,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The idle ink is white at 88%; composited over pure black it is at its
    // darkest, so that is the conservative text colour to measure with.
    final idleInk = Color.alphaBlend(idleColor, Colors.black);
    Future<double> m(Key k, Color c) =>
        textContrastOverBackground(tester, area: find.byKey(k), textColor: c, boundary: find.byKey(_kSceneKey));
    final ratios = {
      'idleLabel': await m(idleKey, idleInk),
      'activeLabel': await m(homeKey, homeStyle.color!),
      'searchIcon': await m(iconKey, idleInk),
    };
    // ignore: avoid_print - the measured ratios belong in the test log
    print('tv top bar glass contrast: $ratios');
    expect(ratios['idleLabel'], greaterThanOrEqualTo(4.5));
    expect(ratios['activeLabel'], greaterThanOrEqualTo(4.5));
    expect(ratios['searchIcon'], greaterThanOrEqualTo(3.0));
  });
}
