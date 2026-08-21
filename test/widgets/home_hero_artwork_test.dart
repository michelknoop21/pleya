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

  testWidgets('a square island sits centred at the top, 0.82x the box width', (tester) async {
    tester.view.physicalSize = const Size(706, 1000); // 353 x 500 logical @ DPR 2
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const screenWidth = 353.0, heroHeight = 500.0;
    const art = BillboardArt(path: '/square', kind: BillboardArtKind.square);
    final geometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: art.kind);
    final client = _RecordingClient();

    await pumpArtwork(
      tester,
      client: client,
      art: art,
      geometry: geometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );

    final rect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
    expect(rect.width, closeTo(rect.height, 0.5));
    expect(rect.width, closeTo(screenWidth * 0.82, 0.5));
    expect(rect.top, closeTo(0, 0.5));
    expect(rect.center.dx, closeTo(screenWidth / 2, 0.5), reason: 'horizontally centred');

    expect(client.requests, isNotEmpty);
    final (w, h) = client.requests.first;
    expect(w, isNotNull);
    expect(h, isNotNull);
    expect((w! / h!), closeTo(1.0, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a widescreen island is a screen-wide 16:9 strip', (tester) async {
    tester.view.physicalSize = const Size(1206, 1716); // 402 x 572 logical @ DPR 3
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const screenWidth = 402.0, heroHeight = 572.0;
    const art = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
    final geometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: art.kind);
    final client = _RecordingClient();

    await pumpArtwork(
      tester,
      client: client,
      art: art,
      geometry: geometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );

    final rect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
    expect(rect.width, closeTo(screenWidth, 0.5));
    expect(rect.height, closeTo(rect.width * 9 / 16, 0.5));
    expect(rect.top, closeTo(0, 0.5));

    final (w, h) = client.requests.first;
    expect((w! / h!), closeTo(16 / 9, 0.15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ambient layer fills the whole hero and uses BoxFit.cover', (tester) async {
    const screenWidth = 402.0, heroHeight = 572.0;
    const art = BillboardArt(path: '/square', kind: BillboardArtKind.square);
    final geometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: art.kind);
    final client = _RecordingClient();

    await pumpArtwork(
      tester,
      client: client,
      art: art,
      geometry: geometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );

    final ambientRect = tester.getRect(find.byKey(HomeHeroArtwork.ambientKey));
    // The overscan makes the ambient rect *bigger* than the hero on every
    // side, never smaller — the hero must never see a gap around it.
    expect(ambientRect.left, lessThanOrEqualTo(0), reason: 'covers the left edge');
    expect(ambientRect.top, lessThanOrEqualTo(0), reason: 'covers the top edge');
    expect(ambientRect.right, greaterThanOrEqualTo(screenWidth), reason: 'covers the right edge');
    expect(ambientRect.bottom, greaterThanOrEqualTo(heroHeight), reason: 'covers the bottom edge');

    final images = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
    // Ambient + sharp layer, both present on the island branch.
    expect(images, hasLength(2));
    final ambientImage = tester.widget<CachedNetworkImage>(
      find.descendant(of: find.byKey(HomeHeroArtwork.ambientKey), matching: find.byType(CachedNetworkImage)),
    );
    expect(ambientImage.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambient and sharp layers share the same URL and cache key — no second transcode', (tester) async {
    const screenWidth = 402.0, heroHeight = 572.0;
    const art = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
    final geometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: art.kind);
    final client = _RecordingClient();

    await pumpArtwork(
      tester,
      client: client,
      art: art,
      geometry: geometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );

    final images = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
    expect(images, hasLength(2));
    expect(images[0].imageUrl, images[1].imageUrl);
    expect(images[0].cacheKey, images[1].cacheKey);
    // One request to the client per layer's URL build call, but both must
    // have asked for the exact same dimensions — a single transcoder variant.
    expect(client.requests.toSet(), hasLength(1), reason: 'no separate ambient transcode ratio');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide hero keeps the old full-bleed frame: BoxFit.cover, no ambient layer, no fade', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const screenWidth = 1280.0, heroHeight = 720.0;
    const art = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
    final geometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: art.kind);
    final client = _RecordingClient();

    await pumpArtwork(
      tester,
      client: client,
      art: art,
      geometry: geometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );

    final rect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
    expect(rect.width, closeTo(screenWidth, 0.5));
    expect(rect.height, closeTo(heroHeight, 0.5));
    expect(find.byKey(HomeHeroArtwork.ambientKey), findsNothing);
    expect(find.byKey(HomeHeroArtwork.fadeKey), findsNothing);
    expect(find.byKey(HomeHeroArtwork.sideFadeKey), findsNothing);

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero geometry renders nothing and never calls the client', (tester) async {
    const art = BillboardArt(path: '/square', kind: BillboardArtKind.square);
    final geometry = homeHeroArtGeometry(screenWidth: 0, heroHeight: 500, kind: art.kind);
    final client = _RecordingClient();

    await pumpArtwork(tester, client: client, art: art, geometry: geometry, screenWidth: 0, heroHeight: 500);

    expect(find.byKey(HomeHeroArtwork.artworkKey), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(client.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an island frame draws crop-free with contain; a full-bleed frame keeps cover', (tester) async {
    const screenWidth = 402.0, heroHeight = 572.0;
    const island = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
    final islandGeometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: island.kind);
    final islandClient = _RecordingClient();

    await pumpArtwork(
      tester,
      client: islandClient,
      art: island,
      geometry: islandGeometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );

    final islandFrameImage = tester.widget<CachedNetworkImage>(
      find.descendant(of: find.byKey(HomeHeroArtwork.frameKey), matching: find.byType(CachedNetworkImage)),
    );
    expect(islandFrameImage.fit, BoxFit.contain, reason: 'the island frame is already sized to its own source ratio');
    expect(tester.takeException(), isNull);

    const fullBleed = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
    const wideWidth = 1280.0, wideHeight = 720.0;
    final fullBleedGeometry = homeHeroArtGeometry(screenWidth: wideWidth, heroHeight: wideHeight, kind: fullBleed.kind);
    final fullBleedClient = _RecordingClient();

    await pumpArtwork(
      tester,
      client: fullBleedClient,
      art: fullBleed,
      geometry: fullBleedGeometry,
      screenWidth: wideWidth,
      heroHeight: wideHeight,
    );

    final fullBleedImage = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(fullBleedImage.fit, BoxFit.cover, reason: 'the wide box still needs cover to fill a mismatched ratio');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an island frame never gets the 1.1 zoom, mid-animation or settled', (tester) async {
    const screenWidth = 402.0, heroHeight = 572.0;
    const art = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
    final geometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: art.kind);
    final client = _RecordingClient();

    // Mid-entrance (well before the 800ms fade/zoom finishes): a full-bleed
    // frame would still be scaled up here, so this is the moment a stray
    // zoom on the island frame would actually show up as an oversized rect.
    await pumpArtwork(
      tester,
      client: client,
      art: art,
      geometry: geometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
      settleAfter: const Duration(milliseconds: 200),
    );

    final midRect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
    expect(midRect.width, closeTo(geometry.sharpWidth, 0.5));
    expect(midRect.height, closeTo(geometry.sharpHeight, 0.5));
    expect(tester.takeException(), isNull);
  });

  group('HomeHeroArtwork.verticalFadeMask (pure)', () {
    test('starts at 55% of the sharp height and always ends fully transparent', () {
      final gradient = HomeHeroArtwork.verticalFadeMask(sharpHeight: 200, fadeHeight: 90);

      expect(gradient.colors.last, Colors.transparent, reason: 'no hard bottom edge');
      expect(gradient.colors.first, isNot(Colors.transparent), reason: 'opaque at the very top');
      expect(gradient.stops!.first, 0.0);
      expect(gradient.stops!.last, 1.0);
      // fadeStart = 1 - fadeHeight/sharpHeight = 1 - 90/200 = 0.55
      expect(gradient.stops![1], closeTo(0.55, 0.001));
    });

    test('clamps to a sane ramp when fadeHeight meets or exceeds sharpHeight', () {
      final gradient = HomeHeroArtwork.verticalFadeMask(sharpHeight: 100, fadeHeight: 150);
      expect(gradient.stops![1], greaterThanOrEqualTo(0.0));
      expect(gradient.stops![1], lessThanOrEqualTo(1.0));
    });

    test('zero sharpHeight never divides by zero', () {
      expect(() => HomeHeroArtwork.verticalFadeMask(sharpHeight: 0, fadeHeight: 0), returnsNormally);
    });
  });

  test('HomeHeroArtwork.horizontalFadeMask fades both edges, opaque through the middle', () {
    final gradient = HomeHeroArtwork.horizontalFadeMask;

    expect(gradient.colors.first, Colors.transparent, reason: 'left edge fully faded — no card shape');
    expect(gradient.colors.last, Colors.transparent, reason: 'right edge fully faded — no card shape');
    expect(gradient.colors[1], isNot(Colors.transparent));
    expect(gradient.colors[2], isNot(Colors.transparent));
  });

  testWidgets('the side fade only appears on the square island, never on widescreen or full-bleed', (tester) async {
    const screenWidth = 402.0, heroHeight = 572.0;

    const square = BillboardArt(path: '/square', kind: BillboardArtKind.square);
    final squareGeometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: square.kind);
    await pumpArtwork(
      tester,
      client: _RecordingClient(),
      art: square,
      geometry: squareGeometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );
    expect(find.byKey(HomeHeroArtwork.sideFadeKey), findsOneWidget);
    expect(find.byKey(HomeHeroArtwork.fadeKey), findsOneWidget);

    const wide = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
    final wideGeometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: wide.kind);
    await pumpArtwork(
      tester,
      client: _RecordingClient(),
      art: wide,
      geometry: wideGeometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );
    expect(find.byKey(HomeHeroArtwork.sideFadeKey), findsNothing, reason: 'already screen-wide, no side to blend');
    expect(find.byKey(HomeHeroArtwork.fadeKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reduced-performance tier skips the ambient blur but keeps the dark wash', (tester) async {
    DevicePerformance.debugReset(override: VisualEffectsSetting.reduced);

    const screenWidth = 402.0, heroHeight = 572.0;
    const art = BillboardArt(path: '/square', kind: BillboardArtKind.square);
    final geometry = homeHeroArtGeometry(screenWidth: screenWidth, heroHeight: heroHeight, kind: art.kind);

    await pumpArtwork(
      tester,
      client: _RecordingClient(),
      art: art,
      geometry: geometry,
      screenWidth: screenWidth,
      heroHeight: heroHeight,
    );

    final blurFilters = tester.widgetList<ImageFiltered>(
      find.descendant(of: find.byKey(HomeHeroArtwork.ambientKey), matching: find.byType(ImageFiltered)),
    );
    expect(blurFilters, isNotEmpty);
    expect(blurFilters.first.enabled, isFalse, reason: 'no costly blur on the reduced tier');
    // The ambient wash and the ambient image itself must still be present —
    // reduced performance must not mean a blank/black gap.
    expect(find.byKey(HomeHeroArtwork.ambientKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('353, 402, and 430pt wide island frames render without overflow', (tester) async {
    for (final (width, heroHeight) in [(353.0, 500.0), (402.0, 572.0), (430.0, 650.0)]) {
      const art = BillboardArt(path: '/backdrop', kind: BillboardArtKind.widescreen);
      final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: art.kind);
      final client = _RecordingClient();

      await pumpArtwork(
        tester,
        client: client,
        art: art,
        geometry: geometry,
        screenWidth: width,
        heroHeight: heroHeight,
      );

      expect(tester.takeException(), isNull, reason: 'w=$width h=$heroHeight');
    }
  });

  testWidgets('768, 834, and 1024pt wide iPad-portrait island frames render without overflow', (tester) async {
    for (final (width, heroHeight) in [(768.0, 968.0), (834.0, 1034.0), (1024.0, 1224.0)]) {
      for (final kind in [BillboardArtKind.square, BillboardArtKind.widescreen]) {
        final art = BillboardArt(path: '/backdrop', kind: kind);
        final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: art.kind);
        final client = _RecordingClient();

        await pumpArtwork(
          tester,
          client: client,
          art: art,
          geometry: geometry,
          screenWidth: width,
          heroHeight: heroHeight,
        );

        expect(tester.takeException(), isNull, reason: 'kind=$kind w=$width h=$heroHeight');
      }
    }
  });
}
