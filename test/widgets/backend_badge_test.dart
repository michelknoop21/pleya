/// Register row J19: `BackendBadge` drew the Pleya P straight from
/// `pleya_mark.png` with no tint, while the Plex and Jellyfin neighbours in the
/// same `switch` took the ink through `SvgTheme(currentColor:)` and the local
/// folder through `Icon(color:)`. The P was the one branch that ignored the
/// `color` its own doc comment promises to honour, and five of the eighteen
/// callsites pass one — `MediaCard`'s metadata line passes a muted ink at 60%
/// alpha, the side rail passes `textMuted`.
///
/// [DEC-076] settled the product question that left the row open: a badge here
/// is a *source glyph*, not the app's identity, so all four take the ink of the
/// line they sit in. These tests assert that as a property of the widget tree
/// rather than of one branch, so a fifth backend added without a tint fails
/// here too.
///
/// The asset half of the fix — the badge now draws the generated, centred
/// `pleya_logo.png` instead of the off-centre hand-made source — is guarded in
/// `test/assets/brand_logo_asset_test.dart`, because no widget test can see
/// where a P sits inside its own PNG.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/widgets/backend_badge.dart';
import 'package:pleya/widgets/pleya_logo.dart';

/// The ink a badge actually renders with, read from whichever widget the branch
/// for [backend] built. One helper per test file rather than four copies: the
/// point of these tests is that the four branches agree, and that only reads as
/// a property if they are all asked the same question.
Color? renderedInk(WidgetTester tester, MediaBackend backend) {
  switch (backend) {
    case MediaBackend.plex:
    case MediaBackend.jellyfin:
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      return (picture.bytesLoader as SvgAssetLoader).theme?.currentColor;
    case MediaBackend.pleyaServer:
      return tester.widget<Image>(find.byType(Image)).color;
    case MediaBackend.local:
      return tester.widget<Icon>(find.byType(Icon)).color;
  }
}

Future<void> pumpBadge(
  WidgetTester tester,
  MediaBackend backend, {
  Color? color,
  Color? inheritedInk,
  double size = 24,
}) async {
  Widget badge = BackendBadge(backend: backend, size: size, color: color);
  if (inheritedInk != null) {
    badge = DefaultTextStyle(
      style: TextStyle(color: inheritedInk),
      child: badge,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: badge)),
    ),
  );
}

void main() {
  group('J19: every backend takes the ink of the line it sits in', () {
    for (final backend in MediaBackend.values) {
      testWidgets('${backend.id} honours an explicit colour', (tester) async {
        const ink = Color(0xFF3366CC);
        await pumpBadge(tester, backend, color: ink);

        expect(renderedInk(tester, backend), ink);
      });

      testWidgets('${backend.id} inherits the surrounding text colour when given none', (tester) async {
        const ink = Color(0xFF11AA22);
        await pumpBadge(tester, backend, inheritedInk: ink);

        expect(renderedInk(tester, backend), ink);
      });

      // The `MediaCard` case: the metadata line hands the badge a muted ink at
      // 60% so the glyph sits at the same weight as the server name beside it.
      // A branch that drops the alpha is as wrong as one that drops the colour.
      testWidgets('${backend.id} keeps the alpha of the ink it is given', (tester) async {
        final ink = const Color(0xFFDDDDDD).withValues(alpha: 0.6);
        await pumpBadge(tester, backend, color: ink);

        final rendered = renderedInk(tester, backend);
        expect(rendered, ink);
        expect(rendered!.a, closeTo(0.6, 0.001));
      });

      testWidgets('${backend.id} fills the same box as the other three', (tester) async {
        await pumpBadge(tester, backend, color: const Color(0xFF000000), size: 24);

        expect(tester.getSize(find.byType(BackendBadge)), const Size(24, 24));
      });
    }
  });

  group('J19: the Pleya branch specifically', () {
    testWidgets('tints through srcIn, so the P stays a silhouette instead of a filled square', (tester) async {
      await pumpBadge(tester, MediaBackend.pleyaServer, color: const Color(0xFF3366CC));

      expect(tester.widget<Image>(find.byType(Image)).colorBlendMode, BlendMode.srcIn);
    });

    testWidgets('draws the generated logo, not the off-centre hand-made source', (tester) async {
      await pumpBadge(tester, MediaBackend.pleyaServer, color: const Color(0xFF3366CC));

      final image = tester.widget<Image>(find.byType(Image)).image as AssetImage;
      expect(image.assetName, 'assets/branding/pleya_logo.png');
    });

    // The `size` box is only honoured while the glyph is allowed to fill it.
    // `Image`'s default fit is `scaleDown`, which shrinks but never enlarges:
    // beyond the asset's own 512px the P would sit small inside a large box
    // while the Plex and Jellyfin SVGs kept filling theirs. The box-size test
    // above stays green through that, because the box is not the glyph.
    testWidgets('fills its box at any size, not only below the asset resolution', (tester) async {
      await pumpBadge(tester, MediaBackend.pleyaServer, color: const Color(0xFF3366CC), size: 600);

      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      expect(tester.getSize(find.byType(BackendBadge)), const Size(600, 600));
    });

    // Not a restatement of the asset assertion above: `AssetImage` is the image
    // cache's key, so naming the same asset as `PleyaLogo` is exactly what
    // makes the badge free once any screen has drawn the mark. The old branch
    // named a different file and paid for its own 1024x1024 decode.
    testWidgets('shares one cache entry with PleyaLogo instead of decoding a second source', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PleyaLogo(size: 24),
                BackendBadge(backend: MediaBackend.pleyaServer, size: 24),
              ],
            ),
          ),
        ),
      );

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(2));
      expect((images[0].image as AssetImage).assetName, (images[1].image as AssetImage).assetName);
    });
  });

  /// The other half of the boundary [DEC-076] draws, asserted from this side so
  /// the two DECs cannot drift apart unnoticed: the badge takes ink, the brand
  /// authority does not. `PleyaWordmark`'s half of the same rule (mark never
  /// tinted, lettering takes the caller's ink) lives with that widget.
  group('J19: the brand authority is not made monochrome by this decision', () {
    testWidgets('PleyaLogo draws the mark with no tint at all', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: PleyaLogo(size: 24))),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      // `PleyaLogo` takes `size` and nothing else, so there is no colour a
      // callsite could pass; this asserts that the widget also does not tint
      // the mark on its own, which is the half a signature cannot state.
      expect(image.color, isNull, reason: 'the identity mark keeps its own colours');
      expect(image.colorBlendMode, isNull);
    });
  });
}
