import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';

/// Which artwork source the home billboard picks, and why.
///
/// Split out of `media_item_test.dart`, which covers the neutral model
/// contract: this one is about a single decision that depends on how the home
/// screen lays the hero out, so it reads better next to the layout tests than
/// buried among equality and mapper checks.
void main() {
  /// Which source wins on a narrow box depends on how the layout renders the
  /// sharp layer there. An island (iPad) shows 82% of the box, so a square
  /// subject is the calmer choice. Edge to edge (iPhone) makes that same square
  /// a block as tall as the screen is wide with the clear-logo across it —
  /// exactly what commit "prefer 16:9 backdrop over square art on narrow
  /// iPhone hero" removed.
  group('billboardArt: narrowBoxIsFullWidth', () {
    const narrowRatio = 402 / 572; // 0.70, well under the 1.39 threshold
    const wideRatio = 1280 / 500;

    MediaItem item({String? art, String? square, MediaKind kind = MediaKind.movie, String? showArt}) => MediaItem(
      id: 'm',
      backend: MediaBackend.plex,
      kind: kind,
      title: 'T',
      serverId: 's',
      serverName: 'S',
      artPath: art,
      grandparentArtPath: showArt,
      backgroundSquarePath: square,
    );

    test('full width prefers the 16:9 backdrop over square art', () {
      final chosen = item(
        art: '/backdrop',
        square: '/square',
      ).billboardArt(containerAspectRatio: narrowRatio, narrowBoxIsFullWidth: true);
      expect(chosen?.kind, BillboardArtKind.widescreen);
      expect(chosen?.path, '/backdrop');
    });

    test('the island still prefers square art over the backdrop', () {
      final chosen = item(art: '/backdrop', square: '/square').billboardArt(containerAspectRatio: narrowRatio);
      expect(chosen?.kind, BillboardArtKind.square);
      expect(chosen?.path, '/square');
    });

    test('without a backdrop, full width falls back to square — sharp and crop-free, not blurred', () {
      final chosen = item(
        square: '/square',
      ).billboardArt(containerAspectRatio: narrowRatio, narrowBoxIsFullWidth: true);
      expect(chosen?.kind, BillboardArtKind.square);
      expect(chosen?.path, '/square');
      expect(chosen?.canRenderSharp, isTrue, reason: 'square carries no baked-in title');
    });

    test('an episode at full width prefers the show backdrop over square art', () {
      final chosen = item(
        kind: MediaKind.episode,
        showArt: '/showart',
        square: '/square',
      ).billboardArt(containerAspectRatio: narrowRatio, narrowBoxIsFullWidth: true);
      expect(chosen?.kind, BillboardArtKind.widescreen);
      expect(chosen?.path, '/showart');
    });

    test('with neither backdrop nor square, both compositions land on the blurred fallback', () {
      for (final fullWidth in [true, false]) {
        final chosen = item(
          square: null,
        ).billboardArt(containerAspectRatio: narrowRatio, narrowBoxIsFullWidth: fullWidth);
        expect(chosen?.kind ?? BillboardArtKind.fallback, BillboardArtKind.fallback, reason: 'fullWidth=$fullWidth');
      }
    });

    test('a wide box ignores the flag entirely — macOS and desktop are untouched', () {
      for (final fullWidth in [true, false]) {
        final chosen = item(
          art: '/backdrop',
          square: '/square',
        ).billboardArt(containerAspectRatio: wideRatio, narrowBoxIsFullWidth: fullWidth);
        expect(chosen?.kind, BillboardArtKind.widescreen, reason: 'fullWidth=$fullWidth');
      }
    });

    test('no ratio at all keeps backdrop-first, so the art-enrichment check never depends on layout', () {
      // `_hasBillboardArt` calls it this way.
      final chosen = item(art: '/backdrop', square: '/square').billboardArt();
      expect(chosen?.kind, BillboardArtKind.widescreen);
      expect(item(square: '/square').billboardArt()?.kind, BillboardArtKind.fallback);
    });

    test('the default is island behaviour, so no existing caller changed', () {
      final withFlag = item(
        art: '/backdrop',
        square: '/square',
      ).billboardArt(containerAspectRatio: narrowRatio, narrowBoxIsFullWidth: false);
      final withoutFlag = item(art: '/backdrop', square: '/square').billboardArt(containerAspectRatio: narrowRatio);
      expect(withFlag?.path, withoutFlag?.path);
      expect(withFlag?.kind, withoutFlag?.kind);
    });
  });
}
