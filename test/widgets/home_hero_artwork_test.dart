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
    await tester.pump(const Duration(milliseconds: 900)); // past the 800ms fade/zoom entrance
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
}
