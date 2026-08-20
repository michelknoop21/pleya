import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_server_client.dart';
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

  testWidgets('a narrow square frame sits at the top, never wider than the screen, DPR 2', (tester) async {
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
    expect(rect.width, lessThanOrEqualTo(screenWidth + 0.5));
    expect(rect.top, closeTo(0, 0.5));

    // The fade must blend the frame's own bottom edge, not the bottom of the
    // (taller) hero box it sits inside — otherwise it renders in the empty
    // space below the frame instead of over the frame itself.
    final fadeRect = tester.getRect(find.byKey(HomeHeroArtwork.fadeKey));
    expect(fadeRect.bottom, closeTo(rect.bottom, 0.5));
    expect(fadeRect.bottom, lessThan(heroHeight), reason: 'frame is shorter than the hero on this box');

    expect(client.requests, isNotEmpty);
    final (w, h) = client.requests.first;
    expect(w, isNotNull);
    expect(h, isNotNull);
    expect((w! / h!), closeTo(1.0, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow widescreen frame is 16:9, DPR 3 at 402pt', (tester) async {
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
    expect(rect.width, lessThanOrEqualTo(screenWidth + 0.5));
    expect(rect.height, closeTo(rect.width * 9 / 16, 0.5));
    expect(rect.top, closeTo(0, 0.5));

    final fadeRect = tester.getRect(find.byKey(HomeHeroArtwork.fadeKey));
    expect(fadeRect.bottom, closeTo(rect.bottom, 0.5));
    expect(fadeRect.bottom, lessThan(heroHeight), reason: 'frame is shorter than the hero on this box');

    final (w, h) = client.requests.first;
    expect((w! / h!), closeTo(16 / 9, 0.15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide hero keeps the old full-bleed frame with no fade band', (tester) async {
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
    expect(find.byKey(HomeHeroArtwork.fadeKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero geometry renders nothing and never calls the client', (tester) async {
    const art = BillboardArt(path: '/square', kind: BillboardArtKind.square);
    final geometry = homeHeroArtGeometry(screenWidth: 0, heroHeight: 500, kind: art.kind);
    final client = _RecordingClient();

    await pumpArtwork(tester, client: client, art: art, geometry: geometry, screenWidth: 0, heroHeight: 500);

    expect(find.byKey(HomeHeroArtwork.artworkKey), findsNothing);
    expect(client.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an island frame draws crop-free with fitWidth; a full-bleed frame keeps cover', (tester) async {
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

    final islandImage = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(islandImage.fit, BoxFit.fitWidth, reason: 'the island frame is already sized to its own source ratio');
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
    expect(midRect.width, closeTo(geometry.width, 0.5));
    expect(midRect.height, closeTo(geometry.height, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fade begins transparent and ends in the scaffold background, flush against the frame', (
    tester,
  ) async {
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

    final frameRect = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
    final fadeRect = tester.getRect(find.byKey(HomeHeroArtwork.fadeKey));

    // No gap and no overshoot: the fade's top sits exactly at the frame's own
    // bottom minus fadeHeight, and its bottom sits exactly at the frame's
    // bottom — never in the empty hero space below it.
    expect(fadeRect.top, closeTo(frameRect.bottom - geometry.fadeHeight, 0.5));
    expect(fadeRect.bottom, closeTo(frameRect.bottom, 0.5));

    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(of: find.byKey(HomeHeroArtwork.fadeKey), matching: find.byType(DecoratedBox)),
    );
    final gradient = (decoratedBox.decoration as BoxDecoration).gradient! as LinearGradient;
    final scaffoldBg = Theme.of(tester.element(find.byKey(HomeHeroArtwork.fadeKey))).scaffoldBackgroundColor;

    expect(gradient.colors.first, Colors.transparent, reason: 'the fade starts invisible, right over the artwork');
    expect(gradient.colors.last, scaffoldBg, reason: 'the fade ends exactly in the scaffold background, no hard edge');
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
}
