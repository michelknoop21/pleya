import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/device_performance.dart';
import 'package:pleya/utils/home_hero_layout.dart';
import 'package:pleya/widgets/home_hero_artwork.dart';

class _RecordingClient implements MediaServerClient {
  final List<(int? width, int? height)> requests = [];

  @override
  String thumbnailUrl(String? path, {int? width, int? height}) {
    requests.add((width, height));
    return '';
  }

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() => DevicePerformance.debugReset());

  Future<void> pumpArtwork(
    WidgetTester tester, {
    required _RecordingClient client,
    required BillboardArt art,
    required HomeHeroArtGeometry geometry,
    required double screenWidth,
    required double heroHeight,
    Duration settleAfter = const Duration(milliseconds: 900), // past the 800ms fade/zoom entrance
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: screenWidth,
            height: heroHeight,
            child: HomeHeroArtwork(client: client, art: art, geometry: geometry),
          ),
        ),
      ),
    );
    await tester.pump(settleAfter);
  }

  /// The sharp layer used to be top-anchored at `y = 0`, hiding its top edge
  /// under the Dynamic Island. On a phone it now starts at the bottom of the
  /// safe area and runs edge to edge.
  group('full-width sharp layer under the safe area', () {
    const inset = 62.0; // viewPadding.top, with nothing added

    HomeHeroArtGeometry fullWidth(double width, double height, BillboardArtKind kind) => homeHeroArtGeometry(
      screenWidth: width,
      heroHeight: height,
      kind: kind,
      requestedSharpTopInset: inset,
      presentation: HomeHeroSharpPresentation.fullWidth,
    );

    Future<void> pumpFullWidth(
      WidgetTester tester, {
      required double width,
      required double height,
      required BillboardArtKind kind,
    }) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpArtwork(
        tester,
        client: _RecordingClient(),
        art: BillboardArt(path: '/art', kind: kind),
        geometry: fullWidth(width, height, kind),
        screenWidth: width,
        heroHeight: height,
      );
    }

    testWidgets('402pt square: left 0, top 62, width 402, height 402', (tester) async {
      await pumpFullWidth(tester, width: 402, height: 572, kind: BillboardArtKind.square);

      final rect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
      expect(rect.left, closeTo(0, 0.5));
      expect(rect.top, closeTo(62, 0.5));
      expect(rect.width, closeTo(402, 0.5));
      expect(rect.height, closeTo(402, 0.5));
      expect(rect.right, closeTo(402, 0.5), reason: 'edge to edge');
      expect(tester.takeException(), isNull);
    });

    testWidgets('402pt widescreen: left 0, top 62, width 402, height 226.1', (tester) async {
      await pumpFullWidth(tester, width: 402, height: 572, kind: BillboardArtKind.widescreen);

      final rect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
      expect(rect.left, closeTo(0, 0.5));
      expect(rect.top, closeTo(62, 0.5));
      expect(rect.width, closeTo(402, 0.5));
      expect(rect.height, closeTo(402 * 9 / 16, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('353 and 430pt also run edge to edge, both kinds, no overflow', (tester) async {
      for (final (width, height) in [(353.0, 500.0), (430.0, 650.0)]) {
        for (final kind in [BillboardArtKind.square, BillboardArtKind.widescreen]) {
          await pumpFullWidth(tester, width: width, height: height, kind: kind);

          final rect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
          final label = 'w=$width kind=$kind';
          expect(rect.left, closeTo(0, 0.5), reason: label);
          expect(rect.width, closeTo(width, 0.5), reason: label);
          expect(rect.top, closeTo(inset, 0.5), reason: label);
          expect(tester.takeException(), isNull, reason: label);
        }
      }
    });

    testWidgets('a full-width square builds no horizontal side fade', (tester) async {
      await pumpFullWidth(tester, width: 402, height: 572, kind: BillboardArtKind.square);

      expect(
        find.byKey(HomeHeroArtwork.sideFadeKey),
        findsNothing,
        reason: 'its edges are the canvas edges — blending them fades the hero into its own margins',
      );
      // The vertical blend into the ambient layer stays.
      expect(find.byKey(HomeHeroArtwork.fadeKey), findsOneWidget);
    });

    testWidgets('an island square still keeps its side fade', (tester) async {
      tester.view.physicalSize = const Size(402, 572);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpArtwork(
        tester,
        client: _RecordingClient(),
        art: const BillboardArt(path: '/square', kind: BillboardArtKind.square),
        geometry: homeHeroArtGeometry(screenWidth: 402, heroHeight: 572, kind: BillboardArtKind.square),
        screenWidth: 402,
        heroHeight: 572,
      );

      expect(find.byKey(HomeHeroArtwork.sideFadeKey), findsOneWidget);
    });

    testWidgets('the ambient layer still covers the whole hero from y = 0', (tester) async {
      await pumpFullWidth(tester, width: 402, height: 572, kind: BillboardArtKind.square);

      final ambient = tester.getRect(find.byKey(HomeHeroArtwork.ambientKey));
      // It overscans past every edge so its own blur never shows a soft border
      // inside the hero; what matters is that it starts at or above y = 0.
      expect(ambient.top, lessThanOrEqualTo(0));
      expect(ambient.bottom, greaterThanOrEqualTo(572));
      expect(ambient.left, lessThanOrEqualTo(0));
      expect(ambient.right, greaterThanOrEqualTo(402));
    });

    testWidgets('ambient and sharp still share one URL and cache entry', (tester) async {
      tester.view.physicalSize = const Size(402, 572);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = _RecordingClient();
      await pumpArtwork(
        tester,
        client: client,
        art: const BillboardArt(path: '/square', kind: BillboardArtKind.square),
        geometry: fullWidth(402, 572, BillboardArtKind.square),
        screenWidth: 402,
        heroHeight: 572,
      );

      expect(client.requests.toSet().length, 1, reason: 'no second transcode for the ambient layer');
      final images = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
      expect(images.length, 2, reason: 'ambient + sharp');
      expect(images[0].imageUrl, images[1].imageUrl);
      expect(images[0].cacheKey, images[1].cacheKey);
    });

    testWidgets('the fade mask is driven by the sharp height, not height + inset', (tester) async {
      await pumpFullWidth(tester, width: 402, height: 572, kind: BillboardArtKind.widescreen);

      // The ShaderMask sits inside the Padding, so its box is exactly the sharp
      // rect. Had the Padding gone inside the mask, this would be `sharpHeight
      // + inset` tall and the 55% start would slide up the image.
      final maskRect = tester.getRect(find.byKey(HomeHeroArtwork.fadeKey));
      expect(maskRect.height, closeTo(402 * 9 / 16, 0.5));
      expect(maskRect.top, closeTo(inset, 0.5));
    });

    testWidgets('the image still draws crop-free with contain, and never zooms', (tester) async {
      await pumpFullWidth(tester, width: 402, height: 572, kind: BillboardArtKind.square);

      final images = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
      expect(images.last.fit, BoxFit.contain);

      final scales = tester
          .widgetList<Transform>(find.byType(Transform))
          .map((t) => t.transform.getMaxScaleOnAxis())
          .toList();
      expect(scales.every((s) => (s - 1.0).abs() < 0.001), isTrue, reason: 'no entrance zoom on a non-covering frame');
    });

    testWidgets('an inset taller than the hero keeps the ambient wash and drops the frame', (tester) async {
      tester.view.physicalSize = const Size(402, 572);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final geometry = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 572,
        kind: BillboardArtKind.square,
        requestedSharpTopInset: 573,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(geometry.hasSharpForeground, isFalse, reason: 'precondition');

      await pumpArtwork(
        tester,
        client: _RecordingClient(),
        art: const BillboardArt(path: '/square', kind: BillboardArtKind.square),
        geometry: geometry,
        screenWidth: 402,
        heroHeight: 572,
      );

      expect(find.byKey(HomeHeroArtwork.frameKey), findsNothing);
      expect(find.byKey(HomeHeroArtwork.ambientKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a collapsed canvas still draws nothing at all', (tester) async {
      await pumpArtwork(
        tester,
        client: _RecordingClient(),
        art: const BillboardArt(path: '/square', kind: BillboardArtKind.square),
        geometry: HomeHeroArtGeometry.zero,
        screenWidth: 402,
        heroHeight: 572,
      );

      expect(find.byKey(HomeHeroArtwork.artworkKey), findsNothing);
      expect(find.byKey(HomeHeroArtwork.ambientKey), findsNothing);
      expect(find.byKey(HomeHeroArtwork.frameKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  /// The full-width layer starts at `viewPadding.top`, so without a top blend
  /// its first pixel row jumps straight from ambient to fully sharp. Measured
  /// on a 402pt simulator screenshot, average row luminance went 20 -> 51 in a
  /// single row at y=62: a hard seam right under the Dynamic Island.
  group('top blend under the safe area', () {
    const inset = 62.0;

    HomeHeroArtGeometry fw(double width, double height, BillboardArtKind kind) => homeHeroArtGeometry(
      screenWidth: width,
      heroHeight: height,
      kind: kind,
      requestedSharpTopInset: inset,
      presentation: HomeHeroSharpPresentation.fullWidth,
    );

    /// Alpha the mask applies at [y] logical pixels down the sharp layer.
    double alphaAt(LinearGradient g, double y, double sharpHeight) {
      final t = (y / sharpHeight).clamp(0.0, 1.0);
      final stops = g.stops!;
      if (t <= stops.first) return g.colors.first.a;
      for (var i = 1; i < stops.length; i++) {
        if (t <= stops[i]) {
          final span = stops[i] - stops[i - 1];
          final f = span <= 0 ? 1.0 : (t - stops[i - 1]) / span;
          return g.colors[i - 1].a + ((g.colors[i].a - g.colors[i - 1].a) * f);
        }
      }
      return g.colors.last.a;
    }

    test('full width: the mask starts fully transparent and reaches opaque after the blend band', () {
      for (final (width, height) in [(353.0, 500.0), (402.0, 572.0), (430.0, 650.0)]) {
        for (final kind in [BillboardArtKind.square, BillboardArtKind.widescreen]) {
          final g = fw(width, height, kind);
          final band = g.sharpTopBlendHeight;
          final label = 'w=$width kind=$kind band=$band';

          expect(band, inInclusiveRange(36.0, 64.0), reason: label);

          final mask = HomeHeroArtwork.verticalFadeMask(
            sharpHeight: g.sharpHeight,
            fadeHeight: g.sharpFadeHeight,
            topBlendHeight: band,
          );
          expect(mask.colors.first.a, 0.0, reason: 'top edge is fully transparent: $label');
          expect(alphaAt(mask, 0, g.sharpHeight), closeTo(0.0, 0.001), reason: label);
          expect(alphaAt(mask, band / 2, g.sharpHeight), closeTo(0.5, 0.05), reason: 'ramps: $label');
          expect(alphaAt(mask, band, g.sharpHeight), closeTo(1.0, 0.001), reason: 'opaque after the band: $label');
          // Still opaque through the middle, all the way to the bottom fade.
          final bottomFadeStart = g.sharpHeight - g.sharpFadeHeight;
          expect(alphaAt(mask, bottomFadeStart, g.sharpHeight), closeTo(1.0, 0.001), reason: label);
          expect(
            alphaAt(mask, g.sharpHeight, g.sharpHeight),
            closeTo(0.0, 0.001),
            reason: 'bottom fade intact: $label',
          );
          expect(mask.stops!, orderedEquals(List.of(mask.stops!)..sort()), reason: 'stops ascend: $label');
        }
      }
    });

    test('the island gets no top blend, and its mask is byte-for-byte the old one', () {
      for (final (width, height) in [(402.0, 572.0), (834.0, 1034.0)]) {
        for (final kind in [BillboardArtKind.square, BillboardArtKind.widescreen]) {
          final island = homeHeroArtGeometry(screenWidth: width, heroHeight: height, kind: kind);
          expect(island.sharpTopBlendHeight, 0, reason: 'w=$width kind=$kind');

          final mask = HomeHeroArtwork.verticalFadeMask(
            sharpHeight: island.sharpHeight,
            fadeHeight: island.sharpFadeHeight,
            topBlendHeight: island.sharpTopBlendHeight,
          );
          final legacy = HomeHeroArtwork.verticalFadeMask(
            sharpHeight: island.sharpHeight,
            fadeHeight: island.sharpFadeHeight,
          );
          expect(mask.colors, legacy.colors, reason: 'w=$width kind=$kind');
          expect(mask.stops, legacy.stops, reason: 'w=$width kind=$kind');
          expect(mask.colors.first.a, 1.0, reason: 'island still starts opaque: w=$width kind=$kind');
        }
      }
    });

    test('a layer too short for both bands keeps its stops ascending', () {
      // Contrived: the top band would otherwise overlap the bottom fade.
      final mask = HomeHeroArtwork.verticalFadeMask(sharpHeight: 50, fadeHeight: 30, topBlendHeight: 40);
      final stops = mask.stops!;
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThanOrEqualTo(stops[i - 1]), reason: 'stops=$stops');
      }
    });

    test('the geometry never lets the top band run into the bottom fade', () {
      for (final h in [40.0, 60.0, 100.0, 226.125, 402.0]) {
        final g = HomeHeroArtGeometry(
          canvasWidth: 402,
          canvasHeight: 572,
          sharpWidth: 402,
          sharpHeight: h,
          requestWidth: 402,
          requestHeight: h,
          sharpFadeHeight: h * 0.45,
          sharpTopInset: inset,
          hasSharpForeground: true,
          useAmbientLayer: true,
          coversHero: false,
          presentation: HomeHeroSharpPresentation.fullWidth,
        );
        expect(
          g.sharpTopBlendHeight + g.sharpFadeHeight,
          lessThanOrEqualTo(h + 0.001),
          reason: 'sharpHeight=$h band=${g.sharpTopBlendHeight}',
        );
        expect(g.sharpTopBlendHeight, greaterThanOrEqualTo(0), reason: 'sharpHeight=$h');
      }
    });

    test('the ambient wash starts lighter at the top and lands on the existing darkness', () {
      const bg = Color(0xFF000000);
      final g = HomeHeroArtwork.ambientWashGradient(background: bg, canvasHeight: 572);

      expect(g.colors.first.a, closeTo(0.30, 0.001), reason: 'artwork must stay visible behind the Dynamic Island');
      expect(g.colors.last.a, closeTo(0.55, 0.001), reason: 'the rest of the hero keeps the darkness it had');
      expect(g.colors[1].a, closeTo(0.42, 0.001));
      // Ascending alpha, ascending stops.
      for (var i = 1; i < g.colors.length; i++) {
        expect(g.colors[i].a, greaterThan(g.colors[i - 1].a));
        expect(g.stops![i], greaterThan(g.stops![i - 1]));
      }
      // The stops are mapped through the 32pt overscan on each side, so the
      // ramp lands where the canvas-relative numbers say it does.
      const overscan = 32.0, canvas = 572.0;
      const box = canvas + (2 * overscan);
      expect(g.stops!.first, closeTo(overscan / box, 0.001), reason: 'stop 0 sits at canvas y = 0');
      expect(g.stops![2], closeTo((overscan + (0.32 * canvas)) / box, 0.001));
    });

    testWidgets('the rendered top band is not a flat dark bar: ambient shows through', (tester) async {
      tester.view.physicalSize = const Size(402, 572);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final geometry = fw(402, 572, BillboardArtKind.square);
      await pumpArtwork(
        tester,
        client: _RecordingClient(),
        art: const BillboardArt(path: '/square', kind: BillboardArtKind.square),
        geometry: geometry,
        screenWidth: 402,
        heroHeight: 572,
      );

      // The ambient layer owns everything from y = 0 down to the sharp layer,
      // and keeps owning it through the blend band.
      final ambient = tester.getRect(find.byKey(HomeHeroArtwork.ambientKey));
      expect(ambient.top, lessThanOrEqualTo(0));
      expect(ambient.bottom, greaterThanOrEqualTo(572));

      final sharp = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
      expect(sharp.top, closeTo(inset, 0.5));
      expect(sharp.left, closeTo(0, 0.5));
      expect(sharp.width, closeTo(402, 0.5));

      // The mask the ShaderMask actually installs, not a re-derived one.
      final shaderMask = tester.widget<ShaderMask>(find.byKey(HomeHeroArtwork.fadeKey));
      final shader = shaderMask.shaderCallback(Offset.zero & sharp.size);
      expect(shader, isNotNull, reason: 'the top band is masked, not painted flat');
      expect(shaderMask.blendMode, BlendMode.dstIn);
      expect(geometry.sharpTopBlendHeight, greaterThan(0));

      expect(find.byKey(HomeHeroArtwork.sideFadeKey), findsNothing, reason: 'still no side fade at full width');
      expect(tester.takeException(), isNull);
    });
  });

  /// `blurArtwork` is a no-op unless BLUR_ARTWORK is defined, so the reduced
  /// tier used to draw the ambient layer sharp: an upscaled cover crop of the
  /// same artwork sitting right behind the sharp layer, read as a duplicate
  /// rather than atmosphere.
  group('reduced visual-effects tier', () {
    tearDown(DevicePerformance.debugReset);

    test('the colour matrix desaturates and darkens instead of washing to grey', () {
      final m = HomeHeroArtwork.reducedAmbientColorMatrix();
      expect(m.length, 20);

      // Apply it to a few sample colours.
      ({double r, double g, double b}) apply(double r, double g, double b) => (
        r: (m[0] * r) + (m[1] * g) + (m[2] * b) + m[4],
        g: (m[5] * r) + (m[6] * g) + (m[7] * b) + m[9],
        b: (m[10] * r) + (m[11] * g) + (m[12] * b) + m[14],
      );

      double sat(({double r, double g, double b}) c) =>
          [c.r, c.g, c.b].reduce((a, b) => a > b ? a : b) - [c.r, c.g, c.b].reduce((a, b) => a < b ? a : b);

      // A saturated red loses most of its colour spread.
      const inR = 220.0, inG = 40.0, inB = 40.0;
      final out = apply(inR, inG, inB);
      expect(sat(out), lessThan(sat((r: inR, g: inG, b: inB)) * 0.4), reason: 'desaturated');

      // A bright pixel comes out much darker; the layer must not compete.
      final bright = apply(240, 240, 240);
      expect(bright.r, lessThan(180), reason: 'flattened and darkened');

      // Alpha is left alone.
      expect(m[18], 1);
      expect(m[19], 0);

      // Contrast is genuinely reduced: the gap between a dark and a bright
      // pixel shrinks.
      final dark = apply(20, 20, 20);
      expect(bright.r - dark.r, lessThan(240 - 20));
    });

    test('the reduced wash is darker at every stop than the full-effects one', () {
      const bg = Color(0xFF000000);
      final full = HomeHeroArtwork.ambientWashGradient(background: bg, canvasHeight: 572);
      final reduced = HomeHeroArtwork.ambientWashGradient(background: bg, canvasHeight: 572, reduced: true);

      for (var i = 0; i < full.colors.length; i++) {
        expect(reduced.colors[i].a, greaterThan(full.colors[i].a), reason: 'stop $i');
      }
      expect(reduced.stops, full.stops, reason: 'same ramp positions, only more darkness');
      // Still a ramp, not a flat bar: the top stays lighter than the bottom.
      expect(reduced.colors.first.a, lessThan(reduced.colors.last.a));
    });

    testWidgets('the reduced tier swaps the blur for a colour filter, and keeps the ambient layer', (tester) async {
      DevicePerformance.debugReset(override: VisualEffectsSetting.reduced);
      tester.view.physicalSize = const Size(402, 572);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final geometry = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 572,
        kind: BillboardArtKind.widescreen,
        requestedSharpTopInset: 62,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      await pumpArtwork(
        tester,
        client: _RecordingClient(),
        art: const BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen),
        geometry: geometry,
        screenWidth: 402,
        heroHeight: 572,
      );

      final ambient = find.byKey(HomeHeroArtwork.ambientKey);
      expect(ambient, findsOneWidget);
      expect(
        find.descendant(of: ambient, matching: find.byType(ColorFiltered)),
        findsWidgets,
        reason: 'flattened instead of left sharp',
      );
      expect(
        find.descendant(of: ambient, matching: find.byType(ImageFiltered)),
        findsNothing,
        reason: 'no gaussian blur on this tier',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the full tier keeps the blur and adds no colour filter', (tester) async {
      DevicePerformance.debugReset(override: VisualEffectsSetting.full);
      tester.view.physicalSize = const Size(402, 572);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final geometry = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 572,
        kind: BillboardArtKind.widescreen,
        requestedSharpTopInset: 62,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      await pumpArtwork(
        tester,
        client: _RecordingClient(),
        art: const BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen),
        geometry: geometry,
        screenWidth: 402,
        heroHeight: 572,
      );

      final ambient = find.byKey(HomeHeroArtwork.ambientKey);
      expect(find.descendant(of: ambient, matching: find.byType(ImageFiltered)), findsWidgets);
      expect(find.descendant(of: ambient, matching: find.byType(ColorFiltered)), findsNothing);
    });
  });
}
