import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// `assets/branding/pleya_logo.png` used to be the old opaque tile — 650x650,
/// no alpha channel, with a black square baked directly into the bitmap. Any
/// widget that dropped its `ClipRRect` would have shown that square, not a
/// floating mark. This decodes the real asset bytes off disk (not through
/// `rootBundle`, so it also catches a regenerate that silently regresses back
/// to an opaque file) and asserts on the raw RGBA buffer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image image;
  late Uint8List rgba;
  late int width;
  late int height;

  setUpAll(() async {
    final bytes = File('assets/branding/pleya_logo.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    image = frame.image;
    width = image.width;
    height = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    rgba = byteData!.buffer.asUint8List();
  });

  tearDownAll(() => image.dispose());

  int offsetOf(int x, int y) => (y * width + x) * 4;
  int alphaAt(int x, int y) => rgba[offsetOf(x, y) + 3];
  (int, int, int, int) pixelAt(int x, int y) {
    final o = offsetOf(x, y);
    return (rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]);
  }

  test('alpha channel is actually in use, not a fully-opaque image', () {
    final hasTransparent = List.generate(rgba.length ~/ 4, (i) => rgba[i * 4 + 3]).any((a) => a == 0);
    final hasOpaque = List.generate(rgba.length ~/ 4, (i) => rgba[i * 4 + 3]).any((a) => a == 255);
    expect(hasTransparent, isTrue, reason: 'expected at least one fully-transparent pixel');
    expect(hasOpaque, isTrue, reason: 'expected at least one fully-opaque pixel');
  });

  test('all four corner pixels are transparent', () {
    expect(alphaAt(0, 0), 0, reason: 'top-left');
    expect(alphaAt(width - 1, 0), 0, reason: 'top-right');
    expect(alphaAt(0, height - 1), 0, reason: 'bottom-left');
    expect(alphaAt(width - 1, height - 1), 0, reason: 'bottom-right');
  });

  test('the outer 2px border is fully transparent all the way around', () {
    for (var x = 0; x < width; x++) {
      expect(alphaAt(x, 0), 0, reason: 'top row, x=$x');
      expect(alphaAt(x, 1), 0, reason: 'top row+1, x=$x');
      expect(alphaAt(x, height - 1), 0, reason: 'bottom row, x=$x');
      expect(alphaAt(x, height - 2), 0, reason: 'bottom row-1, x=$x');
    }
    for (var y = 0; y < height; y++) {
      expect(alphaAt(0, y), 0, reason: 'left column, y=$y');
      expect(alphaAt(1, y), 0, reason: 'left column+1, y=$y');
      expect(alphaAt(width - 1, y), 0, reason: 'right column, y=$y');
      expect(alphaAt(width - 2, y), 0, reason: 'right column-1, y=$y');
    }
  });

  test('the mark still has intact dark detail, not a globally lightened image', () {
    var darkOpaquePixels = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final (r, g, b, a) = pixelAt(x, y);
        if (a > 200 && r < 70 && g < 70 && b < 70) darkOpaquePixels++;
      }
    }
    expect(darkOpaquePixels, greaterThan(0), reason: 'expected at least one opaque dark pixel inside the mark');
  });

  test('a transparent border composites cleanly over any background, no baked-in fill', () {
    // Straight alpha-over compositing, done by hand rather than via a canvas:
    // out = src.rgb*src.a + bg*(1-src.a). At a==0 (the border, per the test
    // above), that reduces to `out == bg` for any background colour.
    const white = (255, 255, 255);
    const saturated = (10, 200, 30);

    (int, int, int) compositeOver((int, int, int) bg, (int, int, int, int) src) {
      final (sr, sg, sb, sa) = src;
      final a = sa / 255.0;
      final (br, bg_, bb) = bg;
      return ((sr * a + br * (1 - a)).round(), (sg * a + bg_ * (1 - a)).round(), (sb * a + bb * (1 - a)).round());
    }

    for (final (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1), (width ~/ 2, 0)]) {
      final src = pixelAt(x, y);
      expect(compositeOver(white, src), white, reason: 'over white at ($x,$y)');
      expect(compositeOver(saturated, src), saturated, reason: 'over a saturated colour at ($x,$y)');
    }
  });

  /// The badge half of [DEC-076]. `BackendBadge` draws this asset in a fixed
  /// `size x size` box beside the Plex chevron and the Jellyfin mark, both of
  /// which fill their own viewBox edge to edge. It used to draw the hand-made
  /// `pleya_mark.png` source instead, whose P sits at an alpha bbox of
  /// (39, 128, 931, 938) on a 1024x1024 canvas: it fills 87% of the width and
  /// 79% of the height, and its centre sits 27px left of and 22px below the
  /// canvas centre. In a row of glyphs that reads as a Pleya badge drawn
  /// smaller and off-centre next to its neighbours, and no widget test can see
  /// it — the `Image` still reports the box it was given, whatever it paints
  /// inside.
  ///
  /// So the invariants live here, on the bytes `gen_brand_assets.py` writes.
  group('the mark is badge-shaped: centred on its own canvas and filling it', () {
    late int left;
    late int right;
    late int top;
    late int bottom;

    setUpAll(() {
      left = width;
      right = -1;
      top = height;
      bottom = -1;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          if (alphaAt(x, y) <= 8) continue;
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    });

    test('the canvas is square, so a square badge box crops nothing', () {
      expect(width, height, reason: 'a non-square canvas letterboxes under BoxFit.contain');
    });

    test('the mark is centred within a pixel or two on both axes', () {
      // Not "equal": `mark_canvas` centres with integer division, so one side
      // may carry a single pixel more than the other. Two is the honest bound;
      // the hand-made source's margins differ by 53px horizontally and 43px
      // vertically.
      expect(
        (left - (width - 1 - right)).abs(),
        lessThanOrEqualTo(2),
        reason: 'horizontal padding, l=$left r=${width - 1 - right}',
      );
      expect(
        (top - (height - 1 - bottom)).abs(),
        lessThanOrEqualTo(2),
        reason: 'vertical padding, t=$top b=${height - 1 - bottom}',
      );
    });

    test('the mark fills at least 90% of its canvas on the axis it is widest in', () {
      final fill = ((right - left + 1) / width).clamp(0.0, 1.0);
      final fillY = ((bottom - top + 1) / height).clamp(0.0, 1.0);
      expect(
        fill > fillY ? fill : fillY,
        greaterThanOrEqualTo(0.90),
        reason: 'a badge that fills $fill x $fillY of its box reads as smaller than its neighbours',
      );
    });
  });
}
