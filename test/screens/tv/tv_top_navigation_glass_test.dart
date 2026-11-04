/// NAV-GLASS1: production Apple TV navbar, one selector, existing GlassSurface.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

const _sceneKey = Key('scene');
const _accessibility = MethodChannel('pleya/tvos_nav_accessibility');

void main() {
  late FocusMemoryTracker nodes;
  late ValueNotifier<TvDestinationId> active;
  late ValueNotifier<List<TvDestinationId>> destinations;
  late ui.Image scene;
  late List<TvDestinationId> selected;
  late bool reducedTransparency;

  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocaleSync(AppLocale.en);
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    scene = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  });
  tearDownAll(() => scene.dispose());

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    active = ValueNotifier(TvDestinationId.home);
    destinations = ValueNotifier(buildTvDestinations(const TvNavConditions(hasLiveTv: false)));
    selected = [];
    reducedTransparency = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _accessibility,
      (_) async => reducedTransparency,
    );
  });
  tearDown(() {
    nodes.dispose();
    active.dispose();
    destinations.dispose();
    TvDetectionService.debugSetAppleTVOverride(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_accessibility, null);
  });

  Widget background(Color? color) =>
      color == null ? RawImage(image: scene, fit: BoxFit.cover) : ColoredBox(color: color);

  Future<void> pumpBar(
    WidgetTester tester, {
    bool glass = true,
    bool dark = true,
    Color? color = Colors.black,
    bool reduceMotion = false,
    bool highContrast = false,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());
    await SettingsService.instance.write(SettingsService.liquidGlass, glass);
    await SettingsService.instance.write(SettingsService.tvReduceMotion, reduceMotion);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: dark),
          home: MediaQuery(
            data: MediaQueryData(size: const Size(1920, 1080), highContrast: highContrast),
            child: Directionality(
              textDirection: direction,
              child: InputModeTracker(
                child: RepaintBoundary(
                  key: _sceneKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      background(color),
                      Align(
                        alignment: Alignment.topCenter,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ValueListenableBuilder<List<TvDestinationId>>(
                            valueListenable: destinations,
                            builder: (context, ids, _) => ValueListenableBuilder<TvDestinationId>(
                              valueListenable: active,
                              builder: (context, current, _) => TvTopNavigation(
                                destinations: ids,
                                active: current,
                                nodes: nodes,
                                onSelect: (id) {
                                  selected.add(id);
                                  active.value = id;
                                },
                                onFocusDestination: (_) {},
                                onNavigateDown: () {},
                                onOpenProfiles: () {},
                              ),
                            ),
                          ),
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
    await tester.pumpAndSettle();
  }

  Finder item(TvDestinationId id) => find.byKey(ValueKey(id.focusKey));
  Finder getSelector() => find.byKey(const ValueKey('tv_nav_selector'));
  Future<void> focus(WidgetTester tester, TvDestinationId id) async {
    nodes.get(id.focusKey).requestFocus();
    await tester.pumpAndSettle();
  }

  void expectNoTabMarkings(WidgetTester tester) {
    for (final id in destinations.value) {
      final wrapper = tester.widget<FocusableWrapper>(
        find.descendant(of: item(id), matching: find.byType(FocusableWrapper)),
      );
      expect(wrapper.mode, FocusIndicatorMode.delegated, reason: id.name);
      for (final box in tester.widgetList<AnimatedContainer>(
        find.descendant(of: item(id), matching: find.byType(AnimatedContainer)),
      )) {
        final decoration = box.decoration;
        if (decoration is ShapeDecoration) expect(decoration.color, Colors.transparent, reason: id.name);
      }
      expect(find.descendant(of: item(id), matching: find.byType(AnimatedScale)), findsNothing);
    }
  }

  testWidgets('NAV-GLASS1 exactly one selector follows focus and rests on active Home', (tester) async {
    await pumpBar(tester);
    final homeRect = tester.getRect(getSelector());
    expect(getSelector(), findsOneWidget);
    await focus(tester, TvDestinationId.series);
    expect(tester.getCenter(getSelector()).dx, tester.getCenter(item(TvDestinationId.series)).dx);
    expect(active.value, TvDestinationId.home);
    expectNoTabMarkings(tester);
    nodes.get(TvDestinationId.series.focusKey).unfocus();
    await tester.pumpAndSettle();
    expect(tester.getRect(getSelector()), homeRect);
  });

  testWidgets('track and selector reuse GlassSurface, never liquid_glass_renderer on TV', (tester) async {
    await pumpBar(tester);
    expect(glassTierFor(tester.element(find.byType(TvTopNavigation))), GlassTier.fake);
    expect(find.byType(GlassSurface), findsNWidgets(2));
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(LiquidGlassLayer), findsNothing);
    final track = tester.getRect(find.byType(GlassSurface).first);
    for (final id in destinations.value) {
      expect(track.contains(tester.getCenter(item(id))), isTrue);
    }
    expect(track.contains(tester.getCenter(find.byType(ProfileAvatar))), isFalse);
  });

  testWidgets('profile focus does not leave a second selector on an active tab', (tester) async {
    await pumpBar(tester);
    nodes.get(tvNavProfileFocusKey).requestFocus();
    await tester.pumpAndSettle();
    expect(getSelector(), findsNothing, reason: 'profile owns the one visible focus indicator');
    await focus(tester, TvDestinationId.home);
    expect(getSelector(), findsOneWidget);
  });

  testWidgets('profile focus removes tab selector before its first focused frame', (tester) async {
    await pumpBar(tester, reduceMotion: true);
    nodes.get(tvNavProfileFocusKey).requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    await tester.pump();
    expect(getSelector(), findsNothing, reason: 'no transient double marker with reduced motion');
  });

  testWidgets('glass off is one opaque selector, without extra active background or ring', (tester) async {
    await pumpBar(tester, glass: false);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(getSelector(), findsOneWidget);
    await focus(tester, TvDestinationId.series);
    expectNoTabMarkings(tester);
  });

  testWidgets('glass toggle preserves selector and item geometry live', (tester) async {
    await pumpBar(tester, glass: false);
    final off = {for (final id in destinations.value) id: tester.getRect(item(id))};
    for (final value in [true, false, true]) {
      await SettingsService.instance.write(SettingsService.liquidGlass, value);
      await tester.pumpAndSettle();
      expect(getSelector(), findsOneWidget);
      for (final id in destinations.value) {
        expect(tester.getRect(item(id)), off[id]);
      }
    }
  });

  testWidgets('rapid reversals retarget the same capsule without selecting a page', (tester) async {
    await pumpBar(tester);
    await focus(tester, TvDestinationId.home);
    final element = tester.element(getSelector());
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 16));
      expect(getSelector(), findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(tester.element(getSelector()), same(element));
    expect(selected, isEmpty);
    expect(active.value, TvDestinationId.home);
    expect(tester.getCenter(getSelector()).dx, tester.getCenter(item(TvDestinationId.home)).dx);
  });

  testWidgets('Select activates focused Series; leaving focus rests on Series', (tester) async {
    await pumpBar(tester);
    await focus(tester, TvDestinationId.series);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, [TvDestinationId.series]);
    nodes.get(TvDestinationId.series.focusKey).unfocus();
    await tester.pumpAndSettle();
    expect(tester.getCenter(getSelector()).dx, tester.getCenter(item(TvDestinationId.series)).dx);
  });

  testWidgets('reduce motion snaps directly to focused tab', (tester) async {
    await pumpBar(tester, reduceMotion: true);
    await focus(tester, TvDestinationId.series);
    expect(tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).duration, Duration.zero);
    expect(tester.getCenter(getSelector()).dx, tester.getCenter(item(TvDestinationId.series)).dx);
  });

  testWidgets('OS Reduce Motion also snaps when the app toggle is off', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpBar(tester);
    await focus(tester, TvDestinationId.series);
    expect(tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).duration, Duration.zero);
  });

  testWidgets('capsule moves through intermediate positions and reverses without a second selector', (tester) async {
    await pumpBar(tester);
    await focus(tester, TvDestinationId.home);
    final homeX = tester.getCenter(getSelector()).dx;
    final seriesX = tester.getCenter(item(TvDestinationId.series)).dx;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getCenter(getSelector()).dx, greaterThan(homeX));
    expect(tester.getCenter(getSelector()).dx, lessThan(seriesX));
    expect(getSelector(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(tester.getCenter(getSelector()).dx, homeX);
    expect(selected, isEmpty);
  });

  testWidgets('UIKit reduce transparency disables blur live and keeps one clear selector', (tester) async {
    reducedTransparency = true;
    await pumpBar(tester);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(getSelector(), findsOneWidget);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      _accessibility.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('reduceTransparencyChanged', false)),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(getSelector(), findsOneWidget);
  });

  testWidgets('high contrast uses quiet opaque fallback', (tester) async {
    await pumpBar(tester, highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expectNoTabMarkings(tester);
  });

  testWidgets('missing native accessibility bridge keeps opaque fallback', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_accessibility, null);
    await pumpBar(tester);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(getSelector(), findsOneWidget);
  });

  testWidgets('RTL selector uses laid-out tab position', (tester) async {
    await pumpBar(tester, direction: TextDirection.rtl);
    await focus(tester, TvDestinationId.series);
    expect(tester.getCenter(getSelector()).dx, tester.getCenter(item(TvDestinationId.series)).dx);
    expectNoTabMarkings(tester);
  });

  testWidgets('removing a previewed Live TV tab rests on still-active Home', (tester) async {
    await pumpBar(tester);
    destinations.value = buildTvDestinations(const TvNavConditions(hasLiveTv: true));
    await tester.pumpAndSettle();
    await focus(tester, TvDestinationId.liveTv);
    destinations.value = buildTvDestinations(const TvNavConditions(hasLiveTv: false));
    await tester.pumpAndSettle();
    expect(getSelector(), findsOneWidget);
    expect(tester.getCenter(getSelector()).dx, tester.getCenter(item(TvDestinationId.home)).dx);
  });

  for (final dark in [true, false]) {
    for (final (name, color) in <(String, Color?)>[('white', Colors.white), ('black', Colors.black), ('Bunny', null)]) {
      testWidgets('contrast $name hero, ${dark ? 'Dark' : 'Light'}: labels >=4.5, search >=3', (tester) async {
        await pumpBar(tester, dark: dark, color: color);
        await focus(tester, TvDestinationId.home);
        final surfaces = tester.widgetList<GlassSurface>(find.byType(GlassSurface)).toList();
        final trackRect = tester.getRect(find.byType(GlassSurface).first);
        final selectorRect = tester.getRect(getSelector());
        final labels = <(TvDestinationId, Rect, Color)>[];
        for (final id in destinations.value) {
          if (id.isCompact) {
            final icon = find.descendant(of: item(id), matching: find.byType(Icon));
            labels.add((id, tester.getRect(icon), tester.widget<Icon>(icon).color!));
          } else {
            final text = find.descendant(of: item(id), matching: find.text(id.label));
            labels.add((id, tester.getRect(text), tester.widget<Text>(text).style!.color!));
          }
        }
        // Repaint the production surfaces at their measured positions, without
        // glyphs, so anti-aliased ink cannot contaminate the background reading.
        await tester.pumpWidget(
          TranslationProvider(
            child: MaterialApp(
              theme: monoTheme(dark: dark),
              home: RepaintBoundary(
                key: _sceneKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    background(color),
                    Positioned.fromRect(
                      rect: trackRect,
                      child: GlassSurface(
                        shape: surfaces.first.shape,
                        tokens: surfaces.first.tokens,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: selectorRect,
                      child: GlassSurface(
                        shape: surfaces.last.shape,
                        tokens: surfaces.last.tokens,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    for (final (id, rect, _) in labels)
                      Positioned.fromRect(
                        rect: rect,
                        child: SizedBox.expand(key: ValueKey('ink_${id.name}')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final (id, _, ink) in labels) {
          final ratio = await textContrastOverBackground(
            tester,
            area: find.byKey(ValueKey('ink_${id.name}')),
            textColor: ink,
            boundary: find.byKey(_sceneKey),
          );
          expect(ratio, greaterThanOrEqualTo(id.isCompact ? 3 : 4.5), reason: '$name ${id.name}: $ratio');
        }
      });
    }
  }
}
