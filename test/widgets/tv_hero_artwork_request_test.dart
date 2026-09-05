/// HERO1 (docs/tvos-fysieke-correctieronde.md): the hero card must ask the
/// server for artwork in the *source's* ratio, never in the card's.
///
/// Why this is the claim that matters: Plex's `/photo/:/transcode` fills the
/// requested box with `minSize=1` and crops the overshoot from the centre
/// before Flutter sees a pixel, while Jellyfin's `maxWidth`/`maxHeight` fit
/// inside and crop nothing. A request in the card's 2.465:1 therefore lands
/// as two different crops on two backends, and neither is the crop the widget
/// says it makes with `alignment`. A request in the source's own 16:9 makes
/// the server-side crop a no-op everywhere, and hands the crop to one owner.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/device_performance.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_hero_artwork.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

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

MediaItem _film({String? art, String? square}) => MediaItem(
  id: 'f1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'A Film',
  artPath: art,
  backgroundSquarePath: square,
  serverId: 'server_1',
);

void main() {
  tearDown(() => DevicePerformance.debugReset());

  // The Apple TV hero card: 3538x1365 physical, DEC-028's scale 1.85, so
  // 1912x738 logical. The ratio is what the test is about; the numbers only
  // have to be the real ones.
  const card = Size(1912, 738);
  const ratioTolerance = 0.06; // `roundDimensions` buckets width to 40 and height to 60.

  Future<_RecordingClient> pumpHero(WidgetTester tester, MediaItem item) async {
    tester.view.physicalSize = const Size(3538, 1365);
    tester.view.devicePixelRatio = 1.85;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _RecordingClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SizedBox(
            width: card.width,
            height: card.height,
            child: TvHeroArtwork(item: item, size: card, client: client),
          ),
        ),
      ),
    );
    await tester.pump();
    return client;
  }

  testWidgets('a widescreen backdrop is requested in 16:9, not in the card ratio', (tester) async {
    final client = await pumpHero(tester, _film(art: '/art/backdrop'));
    expect(client.requests, isNotEmpty, reason: 'the sharp layer must ask the server for the backdrop');
    final (w, h) = client.requests.single;
    expect(w, isNotNull);
    expect(h, isNotNull);
    final ratio = w! / h!;
    expect(
      ratio,
      closeTo(16 / 9, ratioTolerance),
      reason:
          'requested $w x $h is ${ratio.toStringAsFixed(3)}; the card is ${(card.width / card.height).toStringAsFixed(3)} '
          'and a request in that ratio makes Plex crop the source before the widget can choose',
    );
    // And the request is at least the card's width, so the cover-fit does not upscale.
    expect(w, greaterThanOrEqualTo(card.width * 1.85 * 0.99));
  });

  testWidgets('square-only art takes the poster-fill path, and neither of its requests has the card ratio', (
    tester,
  ) async {
    // On the wide card `billboardArt` resolves square-only art to `fallback`,
    // so the hero draws a blurred fill plus a sharp island (hoofdstuk 9.4).
    // Both are poster requests at their own boxes; what must not happen is a
    // request shaped like the card, which is the HERO1 double-owner crop.
    final client = await pumpHero(tester, _film(square: '/art/square'));
    expect(client.requests, hasLength(2));
    const cardRatio = 1912 / 738;
    for (final (w, h) in client.requests) {
      expect(w! / h!, isNot(closeTo(cardRatio, ratioTolerance)));
    }
  });

  test('the request box has the source ratio and covers the card', () {
    const card = Size(1912, 738);
    final wide = tvHeroRequestBox(card, 16 / 9);
    expect(wide.width / wide.height, closeTo(16 / 9, 1e-9));
    expect(wide.width, card.width);
    expect(wide.height, greaterThanOrEqualTo(card.height));
    final square = tvHeroRequestBox(card, 1);
    expect(square.width, card.width);
    expect(square.height, card.width);
    final ultraWide = tvHeroRequestBox(card, 3);
    expect(ultraWide.height, card.height);
    expect(ultraWide.width / ultraWide.height, closeTo(3, 1e-9));
  });

  test('the hero art alignment is a named token, not a literal in the widget', () {
    // A literal `Alignment.topCenter` is what the old widget carried, and it
    // was dead on Plex because the server had already cropped. Once the widget
    // owns the crop the anchor is a design decision, and it lives in the layout
    // tokens next to the card ratio it is a function of.
    expect(TvHomeLayout.heroArtAlignment.y, lessThan(0));
    expect(TvHomeLayout.heroArtAlignment.x, 0);
  });
}
